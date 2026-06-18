# claude-sandbox image: a full dev toolchain + Claude Code, run rootless via Podman.
# The container is the structural boundary - only mounted paths are reachable,
# so the rest of your home partition cannot be touched.

FROM ubuntu:24.04

# These are passed by bin/claude-sandbox so the in-container user matches your
# host user 1:1. With `--userns=keep-id` that means files Claude creates in the
# mounted repo stay owned by *you* on the host (no chown dance).
ARG HOST_USER=antony
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG HOST_HOME=/home/antony

# Tool versions - bump to match your projects.
ARG GO_VERSION=1.23.4
ARG NODE_MAJOR=20

ENV DEBIAN_FRONTEND=noninteractive
# Claude Code is installed globally as root below; the runtime user can't write
# there, so disable the self-updater to avoid failed update attempts.
ENV DISABLE_AUTOUPDATER=1

# --- base packages ---
# podman + podman-docker give a daemonless `docker` command (a shim over podman),
# so `docker build`/`docker run` and kind (KIND_EXPERIMENTAL_PROVIDER=podman) work
# without a Docker daemon. uidmap/fuse-overlayfs/slirp4netns support rootless use.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git make build-essential \
      python3 python3-pip python3-venv pipx \
      jq ripgrep unzip less openssh-client \
      podman podman-docker uidmap fuse-overlayfs slirp4netns \
    && rm -rf /var/lib/apt/lists/* \
    && touch /etc/containers/nodocker


# --- Go ---
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm /tmp/go.tgz

# --- Node + corepack (pnpm, yarn) ---
# corepack ships with Node; `corepack enable` activates pnpm/yarn shims. Each
# project's `packageManager` field pins its own version, fetched on first use
# and cached in the persistent pnpm/npm volumes.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable

# --- GitHub CLI ---
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# --- kubectl ---
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# --- cloud CLIs (comment this whole block out if you don't need them) ---
# gcloud
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*
# Azure CLI
RUN curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash \
    && rm -rf /var/lib/apt/lists/*

# --- Claude Code ---
RUN npm install -g @anthropic-ai/claude-code

# --- match the host user so keep-id maps cleanly ---
# Ubuntu 24.04 ships a default uid/gid 1000 ("ubuntu"); drop it before creating
# ours so the requested HOST_UID/HOST_GID are free.
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupdel ubuntu 2>/dev/null || true; \
    groupadd -g "${HOST_GID}" "${HOST_USER}" 2>/dev/null || true; \
    useradd -m -u "${HOST_UID}" -g "${HOST_GID}" -d "${HOST_HOME}" -s /bin/bash "${HOST_USER}" 2>/dev/null || true; \
    mkdir -p "${HOST_HOME}" && chown "${HOST_UID}:${HOST_GID}" "${HOST_HOME}"; \
    echo "${HOST_USER}:100000:65536" > /etc/subuid; \
    echo "${HOST_USER}:100000:65536" > /etc/subgid

# Cache locations point at dirs that bin/claude-sandbox mounts as persistent
# volumes, so module downloads survive across sessions and are shared between
# parallel containers.
ENV GOPATH=${HOST_HOME}/go
ENV GOCACHE=${HOST_HOME}/.cache/go-build
ENV PATH=${HOST_HOME}/go/bin:${HOST_HOME}/.local/bin:/usr/local/go/bin:${PATH}
# make `kind` use podman instead of looking for a Docker daemon
ENV KIND_EXPERIMENTAL_PROVIDER=podman

USER ${HOST_UID}:${HOST_GID}
WORKDIR ${HOST_HOME}
