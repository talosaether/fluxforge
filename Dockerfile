# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

# ----------------------------
# Build args (override in iac)
# ----------------------------
ARG EXTRA_APT=""
ARG USERNAME=dev
ARG UID=1000
ARG GID=1000
ARG NVIM_VERSION=0.10.2          # pin me; can be overridden at build time
ARG NVIM_INSTALL_METHOD=appimage # appimage only here (use bob for arm64)

# Base env
ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 LANG=C.UTF-8 \
    PATH=/home/${USERNAME}/.local/bin:$PATH

# Core packages (no distro neovim)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tmux ripgrep fd-find jq python3 openssh-client stow python3-debugpy \
    xz-utils tar \
    && rm -rf /var/lib/apt/lists/*

# Optional extra packages baked into the image
RUN if [ -n "${EXTRA_APT}" ]; then \
      apt-get update && apt-get install -y --no-install-recommends ${EXTRA_APT} && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

# Non-root user
RUN groupadd -g ${GID} ${USERNAME} && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

WORKDIR /workspace

# yq (binary release)
RUN curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# ----------------------------
# Neovim pinned install (AppImage extract)
# ----------------------------
# Note: AppImage releases are x86_64. For arm64, use a different method (e.g., bob).
RUN set -eux; \
  if [ "${NVIM_INSTALL_METHOD}" = "appimage" ]; then \
    curl -fsSL -o /tmp/nvim.appimage \
      "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim.appimage"; \
    chmod +x /tmp/nvim.appimage; \
    /tmp/nvim.appimage --appimage-extract >/dev/null; \
    mv squashfs-root "/opt/nvim-v${NVIM_VERSION}"; \
    ln -sf "/opt/nvim-v${NVIM_VERSION}/usr/bin/nvim" /usr/local/bin/nvim; \
  else \
    echo "Unsupported NVIM_INSTALL_METHOD: ${NVIM_INSTALL_METHOD}"; exit 1; \
  fi; \
  nvim --version | head -n1 | grep -q "NVIM v${NVIM_VERSION}"

# --- Codex CLI + wrapper ---
ARG CODEX_VERSION=0.28.0
# Optional: install the static binary now. Comment out if you prefer bootstrap-time install.
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64)  COD_ARCH="x86_64-unknown-linux-musl" ;; \
    arm64)  COD_ARCH="aarch64-unknown-linux-musl" ;; \
    *) echo "Unsupported arch: $arch"; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-${COD_ARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin; \
  mv /usr/local/bin/codex-* /usr/local/bin/codex; \
  chmod +x /usr/local/bin/codex

# The wrapper that nails Codex to /workspace
RUN install -m 0755 /dev/stdin /usr/local/bin/ff-codex <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# Force Codex’s working root and keep approvals contained to /workspace
exec codex --cd /workspace --approval-mode auto "$@"
SH

# bootstrap logic
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh && chown -R ${USERNAME}:${USERNAME} /workspace

# runtime user and sane env
USER ${USERNAME}
ENV USER=${USERNAME} HOME=/home/${USERNAME}

ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]

