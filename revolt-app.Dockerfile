# Stage 1: Get binaries from official images
FROM ghcr.io/revoltchat/server:20250930-2 AS server
FROM ghcr.io/revoltchat/bonfire:20250930-2 AS bonfire
FROM ghcr.io/revoltchat/autumn:20250930-2 AS autumn
FROM ghcr.io/revoltchat/january:20250930-2 AS january
FROM ghcr.io/revoltchat/gifbox:20250930-2 AS gifbox
FROM ghcr.io/revoltchat/crond:20250930-2 AS crond
FROM ghcr.io/revoltchat/pushd:20250930-2 AS pushd
FROM ghcr.io/revoltchat/client:master AS client
FROM minio/mc:latest AS mc

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
COPY --from=server /home/nonroot/revolt-delta /usr/bin/revolt-delta
COPY --from=bonfire /home/nonroot/revolt-bonfire /usr/bin/revolt-bonfire
COPY --from=autumn /home/nonroot/revolt-autumn /usr/bin/revolt-autumn
COPY --from=january /home/nonroot/revolt-january /usr/bin/revolt-january
COPY --from=gifbox /home/nonroot/revolt-gifbox /usr/bin/revolt-gifbox
COPY --from=crond /home/nonroot/revolt-crond /usr/bin/revolt-crond
COPY --from=pushd /home/nonroot/revolt-pushd /usr/bin/revolt-pushd
COPY --from=mc /usr/bin/mc /usr/bin/mc

# Copy web client files
COPY --from=client /usr/src/app/dist /www/client

# Create data directory for shared volume
RUN mkdir -p /data /etc/revolt /scripts /www/client

# Copy configuration and entrypoint
COPY supervisord.conf /etc/supervisor/conf.d/revolt.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment defaults
ENV PORT=80
ENV REVOLT_CONFIG=/data/Revolt.toml

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
