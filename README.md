# fluxforge

**Ephemeral development environments** - A containerized development workspace that spins up fully configured development environments with Neovim, tmux, Codex CLI, and seamless Git integration.

## Overview

fluxforge creates isolated, reproducible development environments using Docker containers. It automatically configures a complete development stack including:

- **Neovim** (pinned version 0.10.2) with minimal sensible defaults
- **tmux** with TPM plugin manager and keyboard-friendly navigation
- **Codex CLI** (OpenAI's AI coding assistant) with workspace integration
- **Git** with SSH/HTTPS authentication support and credential helpers
- **Development tools**: ripgrep, fd-find, yq, jq, Python3, and more

The environment automatically handles SSH agent forwarding, secrets management, dotfiles installation, and repository cloning. It creates a tmux session with pre-configured windows for editing, development server, and AI assistance.

## Getting Started

### Prerequisites

- Docker installed and running
- SSH agent running (for private repository access)
- Optional: OpenAI API key for Codex CLI functionality

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd fluxforge
   ```

2. **Build the development image:**
   ```bash
   ./iac
   ```

3. **The container will automatically:**
   - Mount your current directory to `/workspace`
   - Forward your SSH agent for Git authentication
   - Start a tmux session with Neovim and development tools
   - Attach you to the development environment

### Environment Setup

Create a `.env` file in the project root to customize your environment:

```bash
# Image configuration
IMAGE_TAG=my-dev:latest
BASE_IMAGE=debian:bookworm-slim
EXTRA_APT="nodejs npm"

# Neovim version
NVIM_VERSION=0.10.2

# Git repositories to clone
GIT_REPOS="https://github.com/user/repo1.git,https://github.com/user/repo2.git@main"

# Dotfiles configuration
DOTFILES_REPO="https://github.com/user/dotfiles.git"
DOTFILES_METHOD=stow
DOTFILES_PACKAGES="nvim tmux"

# Development server
DEBUG_COMMAND="python3 -m http.server 8000"
TMUX_SESSION=dev

# Authentication
GIT_AUTH_MODE=ssh
GITHUB_TOKEN=your_token_here
```

### Secrets Management

Create a secrets directory to store sensitive information:

```bash
mkdir -p ~/.dev-secrets
echo "your_openai_api_key" > ~/.dev-secrets/openai_api_key
```

The container will automatically mount this directory and configure Codex CLI with your API key.

## Runtime Parameters

### Build Arguments

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BASE_IMAGE` | `debian:bookworm-slim` | Base Docker image |
| `EXTRA_APT` | `""` | Additional apt packages to install |
| `USERNAME` | `dev` | Container username |
| `UID` | `1000` | User ID |
| `GID` | `1000` | Group ID |
| `NVIM_VERSION` | `0.10.2` | Neovim version to install |
| `NVIM_INSTALL_METHOD` | `appimage` | Neovim installation method |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GIT_REPOS` | `""` | Comma-separated list of Git repositories to clone |
| `DOTFILES_REPO` | `""` | URL of dotfiles repository |
| `DOTFILES_METHOD` | `copy` | Dotfiles installation method (`stow` or `copy`) |
| `DOTFILES_PACKAGES` | `""` | Space-separated list of dotfiles packages |
| `DOTFILES_REF` | `""` | Git reference (branch/tag) for dotfiles |
| `DOTFILES_STOW_FLAGS` | `""` | Additional flags for stow command |
| `DEBUG_COMMAND` | `python3 -m http.server 8000` | Command to run in server window |
| `TMUX_SESSION` | `dev` | Name of the tmux session |
| `GIT_DEPTH` | `1` | Git clone depth |
| `GIT_AUTH_MODE` | `ssh` | Git authentication mode (`ssh` or `https`) |
| `GIT_USER_NAME` | `$USER` | Git user name |
| `GIT_USER_EMAIL` | `$USER@local` | Git user email |
| `GIT_USERNAME` | `oauth2` | Username for HTTPS authentication |
| `GITHUB_TOKEN` | `""` | GitHub personal access token |
| `GITLAB_TOKEN` | `""` | GitLab personal access token |
| `BITBUCKET_USERNAME` | `""` | Bitbucket username |
| `BITBUCKET_APP_PASSWORD` | `""` | Bitbucket app password |
| `OPENAI_API_KEY` | `""` | OpenAI API key for Codex CLI |
| `CODEX_URL` | `""` | Custom URL for Codex CLI download |
| `SECRETS_DIR` | `~/.dev-secrets` | Directory containing secrets |
| `SSH_AUTH_SOCK` | `""` | SSH agent socket (auto-detected) |

### Repository Specification Format

Git repositories can be specified with branch references:

- `https://github.com/user/repo.git` - Clone default branch
- `https://github.com/user/repo.git@main` - Clone specific branch
- `https://github.com/user/repo.git#feature-branch` - Alternative branch syntax

### Dotfiles Integration

fluxforge supports two methods for dotfiles installation:

1. **Stow method** (recommended): Uses GNU Stow for symlink-based dotfiles management
2. **Copy method**: Simple file copying for basic dotfiles

The dotfiles repository should be organized with package directories containing the relevant configuration files.

### SSH Agent Forwarding

The container automatically detects and forwards your SSH agent for seamless Git operations with private repositories. On Windows with Docker Desktop, you may need to manually specify the SSH agent socket:

```bash
# Windows Docker Desktop
-v //./pipe/openssh-ssh-agent:/ssh-agent
-e SSH_AUTH_SOCK=/ssh-agent
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
