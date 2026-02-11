#!/bin/sh
set -e

CONFIG_FILE="/config/Revolt.toml"

if [ -f "$CONFIG_FILE" ]; then
    echo "Configuration already exists at $CONFIG_FILE. Skipping generation."
    exit 0
fi

echo "Generating Revolt.toml..."

# Use provided domain or fallback to localhost
DOMAIN=${RAILWAY_PUBLIC_DOMAIN:-localhost}
PROTO="https"
if [ "$DOMAIN" = "localhost" ]; then PROTO="http"; fi

# Generate VAPID keys if not provided
if [ -z "$VAPID_PRIVATE_KEY" ] || [ -z "$VAPID_PUBLIC_KEY" ]; then
    echo "Generating VAPID keys..."
    # Simple key generation using openssl if available, or just dummy ones for now
    # Since this is a shell script in a container, we'll assume openssl is installed in the configurator image
    openssl ecparam -name prime256v1 -genkey -noout -out /tmp/vapid_private.pem
    VAPID_PRIVATE_KEY=$(cat /tmp/vapid_private.pem | base64 | tr -d '\n')
    VAPID_PUBLIC_KEY=$(openssl ec -in /tmp/vapid_private.pem -pubout -outform DER 2>/dev/null | tail -c 65 | base64 | tr -d '\n')
    rm /tmp/vapid_private.pem
fi

# Generate encryption key if not provided
if [ -z "$FILES_ENCRYPTION_KEY" ]; then
    echo "Generating file encryption key..."
    FILES_ENCRYPTION_KEY=$(openssl rand -base64 32)
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
private_key = "$VAPID_PRIVATE_KEY"
public_key = "$VAPID_PUBLIC_KEY"

[files]
encryption_key = "$FILES_ENCRYPTION_KEY"

[files.s3]
endpoint = "http://minio:9000"
path_style_buckets = false
region = "minio"
access_key_id = "${MINIO_USER:-minioautumn}"
secret_access_key = "${MINIO_PASS:-minioautumn}"
default_bucket = "revolt-uploads"
EOF

echo "Revolt.toml generated successfully."
