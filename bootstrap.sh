#!/usr/bin/env bash
set -euo pipefail

user="${USER:-dev}"
home="/home/${user}"

mkdir -p "${home}/.config" "${home}/.ssh" "/workspace"
chmod 700 "${home}/.ssh"

# Pre-populate known_hosts for common forges to avoid interactive prompts
# SSH host keys so first git clone doesn't prompt
ssh-keyscan -H github.com gitlab.com bitbucket.org 2>/dev/null >> "${home}/.ssh/known_hosts" || true
chmod 600 "${home}/.ssh/known_hosts" || true

# If agent is present, keep it alive in tmux
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
  export SSH_AUTH_SOCK
fi

# Configure Git identity if not already set by dotfiles
git config --global user.name  "${GIT_USER_NAME:-${USER}}"      || true
git config --global user.email "${GIT_USER_EMAIL:-${USER}@local}" || true

# Optional: prefer SSH for GitHub URLs automatically (safe if you use SSH keys)
if [[ "${GIT_AUTH_MODE:-ssh}" == "ssh" ]]; then
  git config --global url."ssh://git@github.com/".insteadOf "https://github.com/"
  git config --global url."ssh://git@gitlab.com/".insteadOf "https://gitlab.com/"
fi

# If host forwarded an agent, ensure perms
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
  export SSH_AUTH_SOCK
fi

# Secrets import (read-only mount from host)
if [[ -d /secrets ]]; then
  mkdir -p "${home}/.secrets"
  cp -r /secrets/. "${home}/.secrets" 2>/dev/null || true
  chmod -R go-rwx "${home}/.secrets" || true
fi

# Dotfiles import
if [[ -n "${DOTFILES_REPO:-}" ]]; then
  git clone --depth=1 "${DOTFILES_REPO}" "${home}/.dotfiles" || true
  if [[ "${DOTFILES_METHOD:-copy}" == "stow" ]]; then
    sudo -n true 2>/dev/null || true
    # stow might not exist; install if needed
    if ! command -v stow >/dev/null 2>&1; then
      echo "[*] Installing stow for dotfiles..."
      # best-effort; container may not have sudo, so attempt apt directly
      if command -v apt-get >/dev/null 2>&1; then
        # shellcheck disable=SC2024
        sudo apt-get update 2>/dev/null || true
        sudo apt-get install -y stow 2>/dev/null || true
      fi
    fi
    if command -v stow >/dev/null 2>&1; then
      pushd "${home}/.dotfiles" >/dev/null
      for pkg in ${DOTFILES_PACKAGES:-}; do stow -v -t "${home}" "${pkg}" || true; done
      popd >/dev/null
    fi
  else
    cp -a "${home}/.dotfiles/." "${home}/" || true
  fi
fi

# HTTPS token helper (only kicks in for https remotes)
if [[ -n "${GITHUB_TOKEN:-}" || -n "${GITLAB_TOKEN:-}" || (-n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}") ]]; then
  install -m 0755 /dev/stdin /usr/local/bin/git-credential-passthru <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
action="${1:-get}"

# Parse stdin: lines like key=value, blank line terminates
host=""; protocol=""
while IFS= read -r line; do
  [[ -z "$line" ]] && break
  case "$line" in
    host=*) host="${line#host=}" ;;
    protocol=*) protocol="${line#protocol=}" ;;
  esac
done

if [[ "$action" == "get" ]]; then
  case "$host" in
    github.com)
      if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "username=${GIT_USERNAME:-oauth2}"
        echo "password=${GITHUB_TOKEN}"
        echo
        exit 0
      fi
      ;;
    gitlab.com)
      if [[ -n "${GITLAB_TOKEN:-}" ]]; then
        echo "username=${GIT_USERNAME:-oauth2}"
        echo "password=${GITLAB_TOKEN}"
        echo
        exit 0
      fi
      ;;
    bitbucket.org)
      if [[ -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ]]; then
        echo "username=${BITBUCKET_USERNAME}"
        echo "password=${BITBUCKET_APP_PASSWORD}"
        echo
        exit 0
      fi
      ;;
  esac
fi
# No creds to offer
exit 0
EOF

  git config --global credential.helper "/usr/local/bin/git-credential-passthru"
  # Avoid GUI askpass in headless envs; if we can't auth, fail fast
  git config --global core.askPass ""
fi

# Pull user repos into ephemeral workspace
IFS=',' read -ra repos <<< "${GIT_REPOS:-}"
for spec in "${repos[@]}"; do
  [[ -z "${spec}" ]] && continue
  name="$(basename "${spec}" .git)"
  dest="/workspace/${name}"
  if [[ ! -d "${dest}/.git" ]]; then
    echo "[*] Cloning ${spec} -> ${dest}"
    git clone --depth 1 "${spec}" "${dest}" || true
  fi
done

# Default debug command
dbg="${DEBUG_COMMAND:-python3 -m http.server 8000}"
session="${TMUX_SESSION:-dev}"

# Tmux layout: editor + server
tmux new-session -d -s "${session}" -n editor "cd /workspace && nvim"
tmux new-window -t "${session}:" -n server "cd /workspace && ${dbg}"
tmux select-window -t "${session}:editor"
exec tmux attach -t "${session}"

# ...later, after starting tmux session...
tmux set-environment -g SSH_AUTH_SOCK "${SSH_AUTH_SOCK:-}" 2>/dev/null || true

