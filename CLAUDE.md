# Relish Prototypes

Monorepo for throwaway game prototypes exploring mechanics for the Relish idle RPG. Each prototype is fully independent — own framework, own build, own Dockerfile. The only shared infrastructure is the Caddy reverse proxy that routes traffic to each prototype's container.

## Architecture

```
relish-idle-prototype/
├── prototypes/
│   └── casting/           # Each prototype is self-contained
│       ├── Dockerfile
│       ├── package.json
│       ├── src/
│       └── ...
├── landing/               # Static hub page served by Caddy
├── docker-compose.yml     # Caddy + all prototype services
├── Caddyfile              # Routing rules
└── PROTOTYPES.md          # Concept tracker
```

## How Prototypes Work

- Each prototype lives in `prototypes/<name>/` with its own build tooling
- Each has its own `Dockerfile` that builds and serves its output
- Caddy reverse-proxies `/<name>/` to the prototype's container using `handle_path` (which strips the prefix before forwarding)
- The landing page at `/` lists all prototypes

## Adding a New Prototype

1. Create `prototypes/<name>/` with whatever framework you want
2. Add a Dockerfile that serves the built output on port 80
3. Add a service to `docker-compose.yml`:
   ```yaml
   <name>:
     build:
       context: ./prototypes/<name>
       dockerfile: Dockerfile
     container_name: relish_<name>
     restart: always
     networks:
       - relish
   ```
4. Add routing to `Caddyfile`:
   ```
   redir /<name> /<name>/ 301
   handle_path /<name>/* {
       reverse_proxy <name>:80
   }
   ```
5. Add a card to `landing/index.html`
6. Update `PROTOTYPES.md`

## Important: Vite base path

If the prototype uses Vite, set `base: '/<name>/'` in `vite.config.ts` so asset URLs are correct. However, because Caddy uses `handle_path` (which strips the prefix before proxying), the container's internal nginx sees requests at `/` not `/<name>/`. This means the Vite `base` setting is needed for the *browser* to request correct paths, but the container serves files from its own root as usual.

## Deployment

- Hosted at `relish.kautiontape.com` on ktn (DigitalOcean)
- Self-hosted GitHub Actions runner: `runs-on: [self-hosted, ktn]`
- Push to main triggers automatic deploy via `.github/workflows/deploy.yml`
- Deploy path on server: `/opt/services/relish-idle-prototype`
- Port 8104 → Caddy → individual prototype containers
- TLS is handled upstream by the host nginx on ktn

## Design Philosophy

Prototypes are throwaway. Each one answers a specific design question. Don't share code between prototypes — copy-paste is fine. If three prototypes solve the same problem the same way, that's a signal worth noting, not a reason to extract a library. See PROTOTYPES.md for what each prototype is testing.
