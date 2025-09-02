# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

ARG EXTRA_APT=""
ARG USERNAME=dev
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 LANG=C.UTF-8 \
    PATH=/home/${USERNAME}/.local/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git tmux neovim ripgrep fd-find jq python3 openssh-client stow python3-debugpy \
    && rm -rf /var/lib/apt/lists/*

# optional extra packages baked into the image
RUN if [ -n "${EXTRA_APT}" ]; then \
      apt-get update && apt-get install -y --no-install-recommends ${EXTRA_APT} && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

# add a non-root user
RUN groupadd -g ${GID} ${USERNAME} && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

WORKDIR /workspace

# tiny quality-of-life: yq (binary release)
RUN curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# defaults for tmux and nvim
COPY tmux.conf /etc/tmux.conf
COPY --chown=${USERNAME}:${USERNAME} nvim/ /home/${USERNAME}/.config/nvim/

# bootstrap logic
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh && chown -R ${USERNAME}:${USERNAME} /workspace

USER ${USERNAME}
ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]

