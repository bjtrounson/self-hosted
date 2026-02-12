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
voso_legacy = ""
voso_legacy_ws = ""

[hosts.livekit]

[rabbit]
host = "rabbit"
port = 5672
username = "${RABBIT_USER:-rabbituser}"
password = "${RABBIT_PASS:-rabbitpass}"

[api]

[api.registration]
invite_only = false

[api.smtp]
host = ""
username = ""
password = ""
from_address = "noreply@example.com"

[api.security]
authifier_shield_key = ""
voso_legacy_token = ""
trust_cloudflare = false
easypwned = ""
tenor_key = ""

[api.security.captcha]
hcaptcha_key = ""
hcaptcha_sitekey = ""

[api.workers]
max_concurrent_connections = 50

[api.livekit]
call_ring_duration = 30

[api.livekit.nodes]

[api.users]

[pushd]
production = true
mass_mention_chunk_size = 200
exchange = "revolt.notifications"
message_queue = "notifications.origin.message"
mass_mention_queue = "notifications.origin.mass_mention"
fr_accepted_queue = "notifications.ingest.fr_accepted"
fr_received_queue = "notifications.ingest.fr_received"
dm_call_queue = "notifications.ingest.dm_call"
generic_queue = "notifications.ingest.generic"
ack_queue = "notifications.process.ack"

[pushd.vapid]
queue = "notifications.outbound.vapid"
private_key = "$VAPID_PRIV"
public_key = "$VAPID_PUB"

[pushd.fcm]
queue = "notifications.outbound.fcm"
key_type = ""
project_id = ""
private_key_id = ""
private_key = ""
client_email = ""
client_id = ""
auth_uri = ""
token_uri = ""
auth_provider_x509_cert_url = ""
client_x509_cert_url = ""

[pushd.apn]
sandbox = false
queue = "notifications.outbound.apn"
pkcs8 = ""
key_id = ""
team_id = ""

[files]
encryption_key = "$FILES_KEY"
webp_quality = 80.0
blocked_mime_types = []
clamd_host = ""
scan_mime_types = [
    "application/vnd.microsoft.portable-executable",
    "application/vnd.android.package-archive",
    "application/zip",
]

[files.limit]
min_file_size = 1
min_resolution = [1, 1]
max_mega_pixels = 40
max_pixel_side = 10_000

[files.preview]
attachments = [1280, 1280]
avatars = [128, 128]
backgrounds = [1280, 720]
icons = [128, 128]
banners = [480, 480]
emojis = [128, 128]

[files.s3]
endpoint = "http://minio:9000"
path_style_buckets = false
region = "minio"
access_key_id = "${MINIO_USER:-minioautumn}"
secret_access_key = "${MINIO_PASS:-minioautumn}"
default_bucket = "revolt-uploads"

[features]
webhooks_enabled = false
mass_mentions_send_notifications = true
mass_mentions_enabled = true

[features.limits]

[features.limits.global]
group_size = 100
message_embeds = 5
message_replies = 5
message_reactions = 20
server_emoji = 100
server_roles = 200
server_channels = 200

# How many hours since creation a user is considered new
new_user_hours = 72

# Maximum permissible body size in bytes for uploads
# (should be greater than any one file upload limit)
body_limit_size = 20_000_000

[features.limits.new_user]
outgoing_friend_requests = 5
bots = 2
message_length = 2000
message_attachments = 5
servers = 50
voice_quality = 16000
video = true
video_resolution = [1080, 720]
video_aspect_ratio = [0.3, 2.5]

[features.limits.new_user.file_upload_size_limit]
attachments = 20_000_000
avatars = 4_000_000
backgrounds = 6_000_000
icons = 2_500_000
banners = 6_000_000
emojis = 500_000

[features.limits.default]
outgoing_friend_requests = 10
bots = 5
message_length = 2000
message_attachments = 5
servers = 100
voice_quality = 16000
video = true
video_resolution = [1080, 720]
video_aspect_ratio = [0.3, 2.5]

[features.limits.default.file_upload_size_limit]
attachments = 20_000_000
avatars = 4_000_000
backgrounds = 6_000_000
icons = 2_500_000
banners = 6_000_000
emojis = 500_000

[features.advanced]
process_message_delay_limit = 5

[sentry]
api = ""
events = ""
voice_ingress = ""
files = ""
proxy = ""
pushd = ""
crond = ""
gifbox = ""
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

# 3. Create MinIO Buckets (in background)
echo "Waiting for MinIO (minio:9000)..."
(
    while ! mc alias set minio http://minio:9000 "${MINIO_USER:-minioautumn}" "${MINIO_PASS:-minioautumn}" > /dev/null 2>&1; do
        sleep 2
    done
    echo "Connected to MinIO. Creating revolt-uploads bucket..."
    mc mb minio/revolt-uploads || true
    echo "Buckets initialized."
) &

# 4. Start Supervisord
echo "Handing over to Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/revolt.conf
