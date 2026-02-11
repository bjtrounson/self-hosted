#!/bin/bash
set -e

echo "Starting Revolt Mono-App Entrypoint..."

# Path to the shared configuration
CONFIG_FILE="/data/Revolt.toml"

# 1. Generate Revolt.toml if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No configuration found. Generating Revolt.toml..."
    DOMAIN=${RAILWAY_PUBLIC_DOMAIN:-localhost}
    PROTO="https"
    if [ "$DOMAIN" = "localhost" ]; then PROTO="http"; fi
    
    # Handle VAPID keys
    VAPID_PRIV=${VAPID_PRIVATE_KEY}
    VAPID_PUB=${VAPID_PUBLIC_KEY}
    if [ -z "$VAPID_PRIV" ] || [ -z "$VAPID_PUB" ]; then
        echo "Generating VAPID keys..."
        openssl ecparam -name prime256v1 -genkey -noout -out /tmp/priv.pem
        VAPID_PRIV=$(cat /tmp/priv.pem | base64 | tr -d '\n')
        VAPID_PUB=$(openssl ec -in /tmp/priv.pem -pubout -outform DER 2>/dev/null | tail -c 65 | base64 | tr -d '\n')
        rm /tmp/priv.pem
    fi
    
    # Handle encryption key
    FILES_KEY=${FILES_ENCRYPTION_KEY}
    if [ -z "$FILES_KEY" ]; then
        echo "Generating file encryption key..."
        FILES_KEY=$(openssl rand -base64 32)
    fi

    cat <<EOF > "$CONFIG_FILE"
production = true

[database]
mongodb = "mongodb://database"
redis = "redis://redis/"

[hosts]
app = "$PROTO://$DOMAIN"
api = "$PROTO://$DOMAIN/api"
events = "ws${PROTO#http}://$DOMAIN/ws"
autumn = "$PROTO://$DOMAIN/autumn"
january = "$PROTO://$DOMAIN/january"

[rabbit]
host = "rabbit"
port = 5672
username = "${RABBIT_USER:-rabbituser}"
password = "${RABBIT_PASS:-rabbitpass}"

[pushd.vapid]
private_key = "$VAPID_PRIV"
public_key = "$VAPID_PUB"

[files]
encryption_key = "$FILES_KEY"

[files.s3]
endpoint = "http://minio:9000"
path_style_buckets = false
region = "minio"
access_key_id = "${MINIO_USER:-minioautumn}"
secret_access_key = "${MINIO_PASS:-minioautumn}"
default_bucket = "revolt-uploads"
EOF
    echo "Revolt.toml generated successfully."
fi

# 2. Generate Caddyfile
echo "Configuring Caddy..."
cat <<EOF > /etc/caddy/Caddyfile
:{\$PORT} {
    route /api* {
        uri strip_prefix /api
        reverse_proxy localhost:14702 {
            header_down Location "^/" "/api/"
        }
    }

    route /ws {
        uri strip_prefix /ws
        reverse_proxy localhost:14703 {
            header_down Location "^/" "/ws/"
        }
    }

    route /autumn* {
        uri strip_prefix /autumn
        reverse_proxy localhost:14704 {
            header_down Location "^/" "/autumn/"
        }
    }

    route /january* {
        uri strip_prefix /january
        reverse_proxy localhost:14705 {
            header_down Location "^/" "/january/"
        }
    }

    route /gifbox* {
        uri strip_prefix /gifbox
        reverse_proxy localhost:14706 {
            header_down Location "^/" "/gifbox/"
        }
    }

    handle {
        root * /www/client
        file_server
        try_files {path} /index.html
    }
}
EOF

# 3. Create MinIO Buckets
echo "Waiting for MinIO..."
(
    while ! mc alias set minio http://minio:9000 "${MINIO_USER:-minioautumn}" "${MINIO_PASS:-minioautumn}" > /dev/null 2>&1; do
        sleep 2
    done
    echo "Creating revolt-uploads bucket..."
    mc mb minio/revolt-uploads || true
) &

# 4. Start Supervisord
echo "Handing over to Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/revolt.conf
