#!/usr/bin/env bash
set -euo pipefail

# ---------- Resolve USER/HOME early ----------
USER_NAME="${USER-}"; [[ -z "$USER_NAME" ]] && USER_NAME="$(id -un 2>/dev/null || echo dev)"
HOME_DIR="${HOME-}"; [[ -z "$HOME_DIR" ]] && HOME_DIR="$(getent passwd "${USER_NAME}" 2>/dev/null | cut -d: -f6)"
HOME_DIR="${HOME_DIR:-/home/${USER_NAME}}"
export USER="${USER_NAME}" HOME="${HOME_DIR}"

mkdir -p "${HOME}/.config" "${HOME}/.ssh" "/workspace" "${HOME}/.local/bin"
chmod 700 "${HOME}/.ssh"

# ---------- Neovim version gate (optional but recommended) ----------
REQ_NVIM="${NVIM_VERSION:-}"
if command -v nvim >/dev/null 2>&1 && [[ -n "$REQ_NVIM" ]]; then
  if ! nvim --version | head -n1 | grep -q "NVIM v${REQ_NVIM}"; then
    echo "[!] Neovim version mismatch. Wanted ${REQ_NVIM}, got: $(nvim --version | head -n1)"
    exit 1
  fi
fi

# ---------- Known hosts (deduped) ----------
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

# --- Codex/OpenAI key wiring ---
# Prefer env, else read from secrets file (either location)
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  for p in "${HOME}/.secrets/openai_api_key" "/secrets/openai_api_key"; do
    if [[ -f "$p" ]]; then
      OPENAI_API_KEY="$(<"$p")"; export OPENAI_API_KEY
      break
    fi
  done
fi

# ---------- HTTPS token helper (only if tokens are present) ----------
if [[ -n "${GITHUB_TOKEN:-}" || -n "${GITLAB_TOKEN:-}" || ( -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ) ]]; then
  install -m 0755 /dev/stdin "${HOME}/.local/bin/git-credential-passthru" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
action="${1:-get}"
host=""; protocol=""
while IFS= read -r line; do [[ -z "$line" ]] && break; case "$line" in host=*) host="${line#host=}";; protocol=*) protocol="${line#protocol=}";; esac; done
if [[ "$action" == "get" ]]; then
  case "$host" in
    github.com)    [[ -n "${GITHUB_TOKEN:-}" ]] && { echo "username=${GIT_USERNAME:-oauth2}"; echo "password=${GITHUB_TOKEN}"; echo; exit 0; } ;;
    gitlab.com)    [[ -n "${GITLAB_TOKEN:-}"  ]] && { echo "username=${GIT_USERNAME:-oauth2}"; echo "password=${GITLAB_TOKEN}"; echo; exit 0; } ;;
    bitbucket.org) [[ -n "${BITBUCKET_USERNAME:-}" && -n "${BITBUCKET_APP_PASSWORD:-}" ]] && { echo "username=${BITBUCKET_USERNAME}"; echo "password=${BITBUCKET_APP_PASSWORD}"; echo; exit 0; } ;;
  esac
fi
exit 0
EOF
  git config --global credential.helper "${HOME}/.local/bin/git-credential-passthru"
  git config --global core.askPass ""   # headless: fail fast
fi

# ---------- Dotfiles import (Stow-first, copy fallback) ----------
clone_update_repo() {
  local url="$1" dest="$2" ref="${3:-}"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" fetch --tags --prune origin || true
    if [[ -n "$ref" ]]; then
      git -C "$dest" checkout -q "$ref" || true
      git -C "$dest" pull --ff-only || true
    else
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


# --- Codex CLI: ensure installed, auth, and wrapper presence ---

# 0) Wrapper safety net (in case image missed it)
if [[ ! -x /usr/local/bin/ff-codex ]]; then
  install -m 0755 /dev/stdin /usr/local/bin/ff-codex <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec codex --cd /workspace --approval-mode auto "$@"
SH
fi

# 1) Install CLI if missing (optional, controlled by env)
#    Provide CODEX_URL yourself if you don’t want me guessing releases.
if ! command -v codex >/dev/null 2>&1; then
  if [[ -n "${CODEX_URL:-}" ]]; then
    echo "[*] Installing Codex CLI from \$CODEX_URL"
    curl -fsSL "$CODEX_URL" | tar -xz -C /usr/local/bin
    # If the tarball extracts a versioned filename, normalize it:
    [[ -f /usr/local/bin/codex ]] || mv /usr/local/bin/codex-* /usr/local/bin/codex 2>/dev/null || true
    chmod +x /usr/local/bin/codex || true
  else
    echo "[!] Codex CLI not found and CODEX_URL not set; skipping install"
  fi
fi

# 2) Auth: prefer OPENAI_API_KEY from env or /secrets
if [[ -z "${OPENAI_API_KEY:-}" && -f "${HOME}/.secrets/openai_api_key" ]]; then
  export OPENAI_API_KEY="$(< "${HOME}/.secrets/openai_api_key")"
fi
mkdir -p "${HOME}/.codex"
[[ -f "${HOME}/.codex/config.toml" ]] || cat > "${HOME}/.codex/config.toml" <<'TOML'
# ~/.codex/config.toml
# Keep minimal; CLI flags override this.
TOML

# --- tmux preflight: ensure TPM and sane paths ---
export TMUX_PLUGIN_MANAGER_PATH="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins}"
if [[ ! -x "$TMUX_PLUGIN_MANAGER_PATH/tpm/tpm" ]]; then
  echo "[*] Installing TPM"
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TMUX_PLUGIN_MANAGER_PATH/tpm" || true
fi

TMUX_CONF=""
[[ -f "$HOME/.tmux.conf" ]] && TMUX_CONF="$HOME/.tmux.conf"
[[ -z "$TMUX_CONF" && -f "$HOME/.config/tmux/tmux.conf" ]] && TMUX_CONF="$HOME/.config/tmux/tmux.conf"

if [[ -n "$TMUX_CONF" ]]; then
  # If default-shell in config is missing, fall back to bash
  dshell="$(awk '/^[[:space:]]*set(-option)?[[:space:]]+-g[[:space:]]+default-shell/ {print $NF}' "$TMUX_CONF" 2>/dev/null \
            | sed -e "s/^['\"]//" -e "s/['\"]$//" | head -n1)"
  [[ -n "$dshell" && ! -x "$dshell" ]] && export TMUX_FORCE_DEFAULT_SHELL="/bin/bash"
fi

# ---------- Minimal defaults if user provided none ----------
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

# ---------- Permissions ----------
chown -R "${USER_NAME}:${USER_NAME}" "${HOME}" 2>/dev/null || true

# ---------- Clone requested repos (supports @branch and #branch) ----------
GIT_DEPTH="${GIT_DEPTH:-1}"

parse_repo_spec() {
  local spec="$1" url branch
  if [[ "$spec" =~ ^(.+\.git)@([^@/]+)$ ]]; then
    url="${BASH_REMATCH[1]}"; branch="${BASH_REMATCH[2]}"
  elif [[ "$spec" =~ ^(.+)\#([^/]+)$ ]]; then
    url="${BASH_REMATCH[1]}"; branch="${BASH_REMATCH[2]}"
  else
    url="$spec"; branch=""
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

# ---------- Headless TPM plugin install (silent & robust) ----------
export TMUX_TMPDIR="${TMUX_TMPDIR:-$HOME/.tmux-tmp}"
mkdir -p "$TMUX_TMPDIR" && chmod 700 "$TMUX_TMPDIR" || true

missing=0
if [[ -n "${TMUX_CONF:-}" ]]; then
  while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue
    base="${repo##*/}"
    [[ -d "$TMUX_PLUGIN_MANAGER_PATH/$base" ]] || { missing=1; break; }
  done < <(awk -F"'" '/@plugin[[:space:]]/ {print $2}' "$TMUX_CONF" 2>/dev/null)
fi

if [[ $missing -eq 1 && -x "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/install_plugins" ]]; then
  sock="tpm-setup"
  # Keep the server alive for the whole install
  TMUX_TMPDIR="$TMUX_TMPDIR" tmux -L "$sock" -f /dev/null new-session -d -s "$sock" \
    "sh -c 'while :; do sleep 60; done'" >/dev/null 2>&1 || true
  TMUX_TMPDIR="$TMUX_TMPDIR" tmux -L "$sock" source-file "$TMUX_CONF" >/dev/null 2>&1 || true
  TMUX_PLUGIN_MANAGER_PATH="$TMUX_PLUGIN_MANAGER_PATH" TMUX_TMPDIR="$TMUX_TMPDIR" \
    tmux -L "$sock" run-shell "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/install_plugins" >/dev/null 2>&1 || true
  tmux -L "$sock" kill-server >/dev/null 2>&1 || true
fi

# ---------- Start tmux + debug server (quiet, resilient) ----------
dbg="${DEBUG_COMMAND:-python3 -m http.server 8000}"
session="${TMUX_SESSION:-dev}"

# Clean server ignoring user config, then seed env
tmux -f /dev/null start-server >/dev/null 2>&1 || true
tmux set-environment -g SSH_AUTH_SOCK "${SSH_AUTH_SOCK:-}" >/dev/null 2>&1 || true
tmux set-environment -g USER "${USER}" >/dev/null 2>&1 || true
tmux set-environment -g HOME "${HOME}" >/dev/null 2>&1 || true
tmux set-environment -g PATH "${PATH}" >/dev/null 2>&1 || true
tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "${TMUX_PLUGIN_MANAGER_PATH}" >/dev/null 2>&1 || true
[[ -n "${OPENAI_API_KEY:-}" ]] && tmux set-environment -g OPENAI_API_KEY "${OPENAI_API_KEY}" >/dev/null 2>&1 || true

# Honor fallback shell if dotfiles pointed at a missing one
[[ -n "${TMUX_FORCE_DEFAULT_SHELL:-}" ]] && tmux set -g default-shell "${TMUX_FORCE_DEFAULT_SHELL}" >/dev/null 2>&1 || true

# Create session if missing
if ! tmux has-session -t "${session}" >/dev/null 2>&1; then
  tmux new-session -d -s "${session}" -n editor "cd /workspace && nvim"
  tmux new-window  -t "${session}:" -n server "cd /workspace && ${dbg}"
fi

# After creating editor + server:
if command -v codex >/dev/null 2>&1; then
  tmux new-window -t "${session}:" -n codex "cd /workspace && ff-codex"
fi

# Source user config; ignore errors so you still get a session
if [[ -n "${TMUX_CONF:-}" ]]; then
  tmux source-file "${TMUX_CONF}" >/dev/null 2>&1 || echo "[!] tmux config had errors; using defaults"
fi

# Attach
exec tmux attach -t "${session}"

