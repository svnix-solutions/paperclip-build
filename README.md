# Paperclip AI — Komodo Stack

A [Komodo](https://komo.do)-managed deployment of **Paperclip AI**, built from
source. A Komodo **Build** resource compiles the `server` image from the
[`Dockerfile`](./Dockerfile) and pushes it to a registry; the **Stack** then
pulls that image and runs the two-service compose stack (PostgreSQL 17 +
Paperclip server). The image is **not** built at deploy time.

> Adapted from the community Docker setup at
> [MadeByAdem/paperclipai-docker](https://github.com/MadeByAdem/paperclipai-docker).
> Paperclip itself: https://github.com/paperclipai/paperclip

## What's here

| File | Purpose |
|------|---------|
| `compose.yaml` | The Komodo Stack compose file (db + server, pulls `${PAPERCLIP_IMAGE}`, named volumes). |
| `Dockerfile` | Multi-stage build of Paperclip from source (used by the Build resource). |
| `docker-entrypoint.sh` | Maps container UID/GID to host & fixes volume perms. |
| `.env.example` | Environment template (local use + reference for Komodo). |
| `komodo/resources.toml` | **Resource Sync** — Build + Stack + release Procedure, as code. |

The server listens on container port `3100` (published on an ephemeral host
port) and is meant to sit behind a reverse proxy (Cloudflare Tunnel, Nginx,
Caddy, or Traefik). Data lives in named Docker volumes `pgdata` and
`paperclip-data`.

### Image flow

```
[[build]] paperclip-server  ──build & push──▶  ghcr.io/<owner>/paperclip-server:latest
[[stack]] paperclip         ──pull & run──▶    compose.yaml  (image: ${PAPERCLIP_IMAGE})
[[procedure]] paperclip-release  chains:  build ▶ deploy stack
```

## Deploy via Komodo (recommended)

1. **Push this repo** to your git provider (GitHub/GitLab/Gitea).

2. **Prerequisites in Komodo:**
   - A connected **Server** (Periphery agent) with Docker + Compose v2.
   - A **Builder** resource (a Server builder or AWS builder) for the image build.
   - A **Git account** alias with read access to this repo (Settings → Providers).
   - A **Registry account** alias (e.g. `ghcr.io`) Komodo can push to and pull from.

3. **Generate secrets:**
   ```bash
   openssl rand -hex 32   # BETTER_AUTH_SECRET
   openssl rand -hex 16   # POSTGRES_PASSWORD
   ```

4. **Create resources** — choose either:

   **A. As code (Resource Sync) — preferred**
   - Edit `komodo/resources.toml`: set `<builder>`, `<server>`, `<git-account>`,
     `<owner/repo>`, `<registry-acct>`, and the `environment` (leave secrets blank
     and set them in the UI to keep them out of git).
   - In Komodo: **Syncs → New Resource Sync** → point it at this repo with
     resource path `komodo/resources.toml` → **Execute**. This creates the
     `paperclip-server` Build, the `paperclip` Stack, and the
     `paperclip-release` Procedure.

   **B. In the UI**
   - **Builds → New Build**: source = this repo, `Dockerfile`, target your
     registry. Run it once to push the first image.
   - **Stacks → New Stack**, mode **Files on Git Repo**, file path `compose.yaml`,
     **Build disabled** (`run_build` off), **Auto Pull** on, registry account set.
   - Set the **Environment** (the variables from `.env.example`, incl.
     `PAPERCLIP_IMAGE`).

5. **Build, then deploy.** Run the `paperclip-release` Procedure (build ▶ deploy),
   or run the Build first and then Deploy the Stack. The first build compiles
   Paperclip from source (several minutes); subsequent deploys just pull the image.

6. **Onboard** (one-time), via the Stack's terminal or on the server:
   ```bash
   docker exec -it paperclip-server-1 pnpm paperclipai onboard
   # choose "External PostgreSQL", then configure LLM provider / storage
   docker exec -it paperclip-server-1 pnpm paperclipai auth bootstrap-ceo
   ```
   (Container name may differ — check `docker ps`; project name is `paperclip`.)

7. **Reverse proxy** your `PAPERCLIP_PUBLIC_URL` to the server's `3100` (reach it
   over the project's default network or the published host port — see `docker ps`).

### Updates
To ship a new version: bump `version` in the Build (or push to `main`) and run
the `paperclip-release` Procedure — it rebuilds the image and redeploys the
Stack. `webhook_enabled` + `poll_for_updates` are set, so a push can also trigger
this; set `auto_update = true` to redeploy automatically.

## Local / manual deploy (without Komodo)

Without Komodo's builder you can build the image locally and point
`PAPERCLIP_IMAGE` at it (or build inline):

```bash
cp .env.example .env       # fill in secrets + PAPERCLIP_PUBLIC_URL + PAPERCLIP_IMAGE
docker build -t "$PAPERCLIP_IMAGE" .
docker compose up -d
docker compose logs -f server
```

## Environment variables

| Variable | Required | Notes |
|----------|:--------:|-------|
| `PAPERCLIP_IMAGE` | ✅ | Registry image built by Komodo, e.g. `ghcr.io/OWNER/paperclip-server:latest` |
| `BETTER_AUTH_SECRET` | ✅ | `openssl rand -hex 32` |
| `PAPERCLIP_PUBLIC_URL` | ✅ | Public URL behind your reverse proxy |
| `POSTGRES_PASSWORD` | ✅ | `openssl rand -hex 16` |
| `ANTHROPIC_API_KEY` | – | Optional Claude integration |
| `OPENAI_API_KEY` | – | Optional OpenAI integration |
| `USER_UID` / `USER_GID` | – | Default `1000` |
