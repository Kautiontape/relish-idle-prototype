# Custom Caddy + Sablier scale-to-zero plugin.
#
# BUILD OFF-BOX ONLY — the xcaddy Go compile needs ~1-2 GB and would OOM
# the 2 GB ktn droplet. The compose `caddy` service references the prebuilt
# image; it has no `build:` directive on purpose.
#
# Build + load onto ktn:
#   docker buildx build --load -t ghcr.io/shawnsquire/caddy-sablier:2.10.0-sablier1.13 caddy-sablier/
#   docker save ghcr.io/shawnsquire/caddy-sablier:2.10.0-sablier1.13 | ssh ktn 'docker load'
#
# The Sablier Caddy plugin pins caddy/v2 v2.10.0 and needs Go >= 1.24,
# hence GOTOOLCHAIN=auto on an older builder.
ARG CADDY_VERSION=2.10.0
FROM caddy:${CADDY_VERSION}-builder AS builder
ENV GOTOOLCHAIN=auto
RUN xcaddy build --with github.com/sablierapp/sablier/plugins/caddy
FROM caddy:${CADDY_VERSION}-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
