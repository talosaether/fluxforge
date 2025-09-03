#!/usr/bin/env bash
set -euo pipefail

# ---------- Resolve USER/HOME early, even if env is empty ----------
USER_NAME="${USER-}"; [[ -z "$USER_NAME" ]] && USER_NAME="$(id -un 2>/dev/null || echo dev)"
HOME_DIR="${HOME-}"; [[ -z "$HOME_DIR" ]] && HOME_DIR="$(getent passwd "${USER_NAME}" 2>/dev/null | cut -d: -f6)"
HOME_DIR="${HOME_DIR:-/home/${USER_NAME}}"
export USER="${USER_NAME}" HOME="${HOME_DIR}"

mkdir -p "${HOME}/.config" "${HOME}/.ssh" "/workspace"
chmod 700 "${HOME}/.ssh"

# ---------- Neovim version gate (optional but recommended) ----------
REQ_NVIM="${NVIM_VERSION:-}"
if command -v nvim >/dev/null 2>&1 && [[ -n "$REQ_NVIM" ]]; then
  if ! nvim --version | head -n1 | grep -q "NVIM v${REQ_NVIM}"; then
    echo "[!] Neovim version mismatch. Wanted ${REQ_NVIM}, got: $(nvim --version | head -n1)"
    exit 1
  fi
fi

# ---------- Known hosts so first git op doesn't prompt ----------
tmpkh="$(mktemp)"
ssh-keyscan -H github.com gitlab.com bitbucket.org 2>/dev/null > "${tmpkh}" || true
touch "${HOME}/.ssh/known_hosts"
cat "${tmpkh}" "${HOME}/.ssh/known_hosts" | awk '!seen[$0]++' > "${HOME}/.ssh/known_hosts.new" || true
mv -f "${HOME}/.ssh/known_hosts.new" "${HOME}/.ssh/known_hosts"
chmod 600 "${HOME}/.ssh/known_hosts"
rm -f "${tmpkh}"

# ---------- SSH agent (forwarded) ----------
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
  export SSH_AUTH_SOCK
fi

# ---------- Git identity & transport prefs ----------
git config --global user.name  "${GIT_USER_NAME:-${USER}}"            || true
git config --global user.email "${GIT_USER_EMAIL:-${USER}@local}"     || true

# Prefer SSH for forges when URLs are https (safe if you use SSH keys)
if [[ "${GIT_AUTH_MODE:-ssh}" == "ssh" ]]; then
  git config --global url."ssh://git@github.com/".insteadOf "https://github.com/"
  git config --global url."ssh://git@gitlab.com/".insteadOf  "https://gitlab.com/"
fi

# ---------- Secrets import (read-only mount from host) ----------
if [[ -d /secrets ]]; then
  mkdir -p "${HOME}/.secrets"
  cp -r /secrets/. "${HOME}/.secrets" 2>/dev/null || true
  chmod -R go-rwx "${HOME}/.secrets" || true
fi

# ---------- HTTPS token helper (only for https remotes) ----------
if [[ -n "${GITHUB_TOKEN:-}" || -n "${GITLAB_TOKEN:-}" || ( -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ) ]]; then
  install -m 0755 /dev/stdin /usr/local/bin/git-credential-passthru <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
action="${1:-get}"
host=""; protocol=""
while IFS= read -r line; do [[ -z "$line" ]] && break; case "$line" in host=*) host="${line#host=}";; protocol=*) protocol="${line#protocol=}";; esac; done
if [[ "$action" == "get" ]]; then
  case "$host" in
    github.com)    [[ -n "${GITHUB_TOKEN:-}" ]] && { echo "username=${GIT_USERNAME:-oauth2}"; echo "password=${GITHUB_TOKEN}";    echo; exit 0; } ;;
    gitlab.com)    [[ -n "${GITLAB_TOKEN:-}"  ]] && { echo "username=${GIT_USERNAME:-oauth2}"; echo "password=${GITLAB_TOKEN}";   echo; exit 0; } ;;
    bitbucket.org) [[ -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ]] && { echo "username=${BITBUCKET_USERNAME}"; echo "password=${BITBUCKET_APP_PASSWORD}"; echo; exit 0; } ;;
  esac
fi
exit 0
EOF
  git config --global credential.helper "/usr/local/bin/git-credential-passthru"
  git config --global core.askPass ""   # fail fast, no GUI prompts in headless
fi

# ---------- Dotfiles import (Stow-first, copy fallback) ----------
clone_update_repo() {
  local url="$1" dest="$2" ref="${3:-}"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" fetch --tags --prune origin || true
    if [[ -n "$ref" ]]; then
      git -C "$dest" checkout -q "$ref" || true
      git -C "$dest" pull --ff-only      || true
    else
      # stay on current branch or fallback to main
      git -C "$dest" checkout -q "$(git -C "$dest" symbolic-ref --short HEAD 2>/dev/null || echo main)" || true
      git -C "$dest" pull --ff-only || true
    fi
  else
    if [[ -n "$ref" ]]; then
      git clone --depth 1 --branch "$ref" "$url" "$dest" || git clone "$url" "$dest"
    else
      git clone --depth 1 "$url" "$dest" || git clone "$url" "$dest"
    fi
  fi
}

if [[ -n "${DOTFILES_REPO:-}" ]]; then
  DOTS_DIR="${HOME}/.dotfiles"
  echo "[*] Importing dotfiles from ${DOTFILES_REPO} ${DOTFILES_REF:+(ref $DOTFILES_REF)}"
  clone_update_repo "${DOTFILES_REPO}" "${DOTS_DIR}" "${DOTFILES_REF:-}"
  METHOD="${DOTFILES_METHOD:-stow}"

  if [[ "${METHOD}" == "stow" ]]; then
    if ! command -v stow >/dev/null 2>&1; then
      echo "[!] stow not found; falling back to copy"
      METHOD="copy"
    fi
  fi

  if [[ "${METHOD}" == "stow" ]]; then
    pushd "${DOTS_DIR}" >/dev/null
    for pkg in ${DOTFILES_PACKAGES:-}; do
      [[ -d "$pkg" ]] || continue
      echo "[*] stow $pkg"
      stow ${DOTFILES_STOW_FLAGS:-} -t "${HOME}" "$pkg"
    done
    popd >/dev/null
  else
    echo "[*] Copying dotfiles"
    cp -a "${DOTS_DIR}/." "${HOME}/" || true
  fi
fi

# ---------- Minimal defaults if dotfiles didn't supply tmux/nvim ----------
# tmux
if [[ ! -f "${HOME}/.tmux.conf" && ! -f "${HOME}/.config/tmux/tmux.conf" ]]; then
  echo "[*] Installing minimal tmux config"
  mkdir -p "${HOME}/.config/tmux"
  cat > "${HOME}/.config/tmux/tmux.conf" <<'TMUX'
set -g mouse on
set -g history-limit 10000
bind -n C-h select-pane -L
bind -n C-j select-pane -D
bind -n C-k select-pane -U
bind -n C-l select-pane -R
set -g update-environment "SSH_AUTH_SOCK SSH_AGENT_PID SSH_CONNECTION SSH_CLIENT USER HOME PATH"
TMUX
  ln -sf "${HOME}/.config/tmux/tmux.conf" "${HOME}/.tmux.conf"
fi

# nvim
if [[ ! -f "${HOME}/.config/nvim/init.lua" ]]; then
  echo "[*] Installing minimal nvim config"
  mkdir -p "${HOME}/.config/nvim"
  cat > "${HOME}/.config/nvim/init.lua" <<'NVIM'
vim.o.number = true
vim.o.relativenumber = true
vim.o.termguicolors = true
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
NVIM
fi

# Ensure perms on home (harmless if already owned)
chown -R "${USER_NAME}:${USER_NAME}" "${HOME}" 2>/dev/null || true


# ---------- Clone requested repos into ephemeral workspace (supports @branch and #branch) ----------
GIT_DEPTH="${GIT_DEPTH:-1}"

parse_repo_spec() {
  local spec="$1" url branch
  if [[ "$spec" =~ ^(.+\.git)@([^@/]+)$ ]]; then
    # Suffix form: ...repo.git@branch
    url="${BASH_REMATCH[1]}"
    branch="${BASH_REMATCH[2]}"
  elif [[ "$spec" =~ ^(.+)\#([^/]+)$ ]]; then
    # Alt delimiter to avoid SSH '@' collisions: ...repo.git#branch
    url="${BASH_REMATCH[1]}"
    branch="${BASH_REMATCH[2]}"
  else
    url="$spec"
    branch=""
  fi
  printf '%s %s\n' "$url" "$branch"
}

IFS=',' read -ra repos <<< "${GIT_REPOS:-}"
for spec in "${repos[@]}"; do
  [[ -z "$spec" ]] && continue

  read -r url ref < <(parse_repo_spec "$spec")
  name="$(basename "${url}" .git)"
  dest="/workspace/${name}"

  if [[ ! -d "${dest}/.git" ]]; then
    echo "[*] Cloning ${url} -> ${dest} ${ref:+(branch ${ref})}"
    if [[ -n "${ref}" ]]; then
      git clone --depth "${GIT_DEPTH}" --branch "${ref}" "${url}" "${dest}" || {
        # Fallback: clone default then fetch the branch
        git clone --depth "${GIT_DEPTH}" "${url}" "${dest}" && \
        git -C "${dest}" fetch --depth "${GIT_DEPTH}" origin "${ref}" && \
        git -C "${dest}" switch -c "${ref}" --track "origin/${ref}"
      }
      git -C "${dest}" remote set-branches --add origin "${ref}" || true
    else
      git clone --depth "${GIT_DEPTH}" "${url}" "${dest}"
    fi
  fi
done




# ---------- Start tmux + debug server ----------
dbg="${DEBUG_COMMAND:-python3 -m http.server 8000}"
session="${TMUX_SESSION:-dev}"

# Start tmux server, seed env, then create windows so panes inherit SSH_AUTH_SOCK etc.
tmux start-server
tmux set-environment -g SSH_AUTH_SOCK "${SSH_AUTH_SOCK:-}" 2>/dev/null || true
tmux set-environment -g USER "${USER}"
tmux set-environment -g HOME "${HOME}"
tmux set-environment -g PATH "${PATH}"

tmux new-session -d -s "${session}" -n editor "cd /workspace && nvim"
tmux new-window  -t "${session}:" -n server "cd /workspace && ${dbg}"
tmux select-window -t "${session}:editor"
exec tmux attach -t "${session}"

