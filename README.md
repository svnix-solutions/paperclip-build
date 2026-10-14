# Paperclip AI — Komodo Stack

A [Komodo](https://komo.do)-managed deployment of **Paperclip AI**. A Komodo
**Build** resource builds the `server` image from the [`Dockerfile`](./Dockerfile)
— a thin layer on the official multi-arch image
`ghcr.io/paperclipai/paperclip` — and pushes it to a registry; the **Stack**
then pulls that image and runs the two-service compose stack (PostgreSQL 17 +
Paperclip server). The image is **not** built at deploy time.

Upstream's own build (UI, server, Rust runner, remote provider pack) is
non-trivial, so this repo follows upstream's recommended *downstream
composition* pattern instead of rebuilding Core from source. If you don't need
any extra layers, skip the Build and set `PAPERCLIP_IMAGE` to the official image
directly.

> Paperclip itself: https://github.com/paperclipai/paperclip
> (see its `doc/DOCKER.md` and `docker/docker-compose.yml`).

## What's here

| File | Purpose |
|------|---------|
| `compose.yaml` | The Komodo Stack compose file (db + server, pulls `${PAPERCLIP_IMAGE}`, named volumes). |
| `Dockerfile` | Thin layer `FROM ghcr.io/paperclipai/paperclip` (used by the Build resource). |
| `.env.example` | Environment template (local use + reference for Komodo). |
| `komodo/resources.toml` | **Resource Sync** — Build + Stack + release Procedure, as code. |

The server listens on container port `3100` (published on an ephemeral host
port) and is meant to sit behind a reverse proxy (Cloudflare Tunnel, Nginx,
Caddy, or Traefik). Data lives in named Docker volumes `pgdata` and
`paperclip-data`.

The upstream image runs `tini` as PID 1 (reaps orphaned agent processes) and an
entrypoint that remaps the `node` user to `USER_UID`/`USER_GID` and repairs
`/paperclip` ownership at start. It ships the `claude`, `codex`, `opencode`,
`gemini` and `kimi` CLIs for the local adapters.

### Image flow

```
ghcr.io/paperclipai/paperclip  ──FROM──▶  Dockerfile
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
   or run the Build first and then Deploy the Stack. The build only pulls the
   official base and adds the Dockerfile's layers, so it is quick.

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
To ship a new Paperclip version: bump `PAPERCLIP_BASE_IMAGE` in the Build's
`build_args` (if pinned) and `version`, then run the `paperclip-release`
Procedure — it rebuilds the image on the new base and redeploys the Stack. With
the base on `:latest`, re-running the Procedure picks up the newest stable
upstream release. `webhook_enabled` + `poll_for_updates` are set, so a push can also trigger
this; set `auto_update = true` to redeploy automatically.

## Local / manual deploy (without Komodo)

Without Komodo's builder you can build the image locally and point
`PAPERCLIP_IMAGE` at it — or set `PAPERCLIP_IMAGE=ghcr.io/paperclipai/paperclip:latest`
and skip the build:

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
| `GEMINI_API_KEY` | – | Optional Gemini integration (key must be restricted to the Gemini API) |
| `PAPERCLIP_ALLOWED_HOSTNAMES` | – | Extra hostnames beyond the public URL host, comma-separated |
| `USER_UID` / `USER_GID` | – | Default `1000`; applied at container start |
