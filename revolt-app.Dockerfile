# Stage 1: Get binaries from official images
FROM ghcr.io/revoltchat/server:20250930-2 as server
FROM ghcr.io/revoltchat/bonfire:20250930-2 as bonfire
FROM ghcr.io/revoltchat/autumn:20250930-2 as autumn
FROM ghcr.io/revoltchat/january:20250930-2 as january
FROM ghcr.io/revoltchat/gifbox:20250930-2 as gifbox
FROM ghcr.io/revoltchat/crond:20250930-2 as crond
FROM ghcr.io/revoltchat/pushd:20250930-2 as pushd
FROM ghcr.io/revoltchat/client:master as client
FROM minio/mc:latest as mc

# Stage 2: Final consolidated image
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    caddy \
    supervisor \
    openssl \
    ca-certificates \
    curl \
    libc6-compat \
    bash

# Copy binaries from stages
COPY --from=server /revolt-server /usr/bin/revolt-server
COPY --from=bonfire /bonfire /usr/bin/bonfire
COPY --from=autumn /autumn /usr/bin/autumn
COPY --from=january /january /usr/bin/january
COPY --from=gifbox /gifbox /usr/bin/gifbox
COPY --from=crond /revolt-crond /usr/bin/revolt-crond
COPY --from=pushd /revolt-pushd /usr/bin/revolt-pushd
COPY --from=mc /usr/bin/mc /usr/bin/mc

# Copy web client files
COPY --from=client /usr/share/nginx/html /www/client

# Create data directory for shared volume
RUN mkdir -p /data /etc/revolt /scripts

# Copy configuration and entrypoint
COPY supervisord.conf /etc/supervisor/conf.d/revolt.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment defaults
ENV PORT=80
ENV REVOLT_CONFIG=/data/Revolt.toml

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
