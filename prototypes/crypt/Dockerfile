# Build stage: headless Godot imports the project, runs the smoke test, and
# exports a single-threaded web build (no SharedArrayBuffer → no COOP/COEP
# headers needed, works on mobile Safari).
FROM ubuntu:24.04 AS builder

ARG GODOT_VERSION=4.6.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends wget unzip ca-certificates libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*

# Engine + web export templates first: this layer is static and caches across
# source changes (the templates tpz is ~1 GB to download, worth keeping warm).
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
 && unzip -q Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip -d /usr/local/bin/ \
 && mv /usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
 && rm Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
 && wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz \
 && mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
 && unzip -q -o -j Godot_v${GODOT_VERSION}-stable_export_templates.tpz 'templates/web_nothreads_*' \
      -d /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/ \
 && rm Godot_v${GODOT_VERSION}-stable_export_templates.tpz

WORKDIR /app
COPY . .

RUN godot --headless --import || true
# Smoke test gates the image: a broken build never ships.
RUN godot --headless --script res://tests/smoke_test.gd
RUN mkdir -p build/web && godot --headless --export-release Web build/web/index.html

# Serve stage
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
