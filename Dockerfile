# =============================================================================
# Paperclip AI — downstream image
#
# Composes on top of the official upstream image instead of rebuilding Core.
# Upstream (https://github.com/paperclipai/paperclip) publishes the standard
# `production` target for linux/amd64 + linux/arm64 to GHCR; its build now
# needs a Rust toolchain, the runner provider pack and a stamped commit, so
# rebuilding from source here would just drift from it (see upstream
# doc/DOCKER.md, "Standard images and downstream composition").
#
# The base image already provides:
#   - tini as PID 1 (reaps zombie agent processes) + docker-entrypoint.sh,
#     which remaps the `node` user to USER_UID/USER_GID at runtime and repairs
#     /paperclip ownership
#   - claude, codex, opencode, gemini and kimi CLIs, gh, git, ripgrep, jq, ssh
#   - NODE_ENV/HOST/PORT/SERVE_UI/PAPERCLIP_* defaults, EXPOSE 3100
#
# Pin PAPERCLIP_BASE_IMAGE to a release tag (e.g. :2026.916.1) or an immutable
# digest for reproducible deploys; `latest` tracks the newest stable release.
# Add site-specific layers (extra tools, CA certs, …) below.
# =============================================================================

ARG PAPERCLIP_BASE_IMAGE=ghcr.io/paperclipai/paperclip:latest
FROM ${PAPERCLIP_BASE_IMAGE}

# ENTRYPOINT ["/usr/bin/tini", "--", "docker-entrypoint.sh"] and CMD are
# inherited from the base image — do not override them.
