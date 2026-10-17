#!/usr/bin/env bash
# ============================================================
# bootstrap.sh - Linux worker script
# Invoked once by bootstrap.ps1 via a single wsl.exe call.
# Can also be run standalone for the Linux phases only.
# ============================================================
set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
GIT_NAME=""
GIT_EMAIL=""
GIT_CREDENTIAL_HELPER=""
WSL_PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --git-name)
    GIT_NAME="$2"
    shift 2
    ;;
  --git-email)
    GIT_EMAIL="$2"
    shift 2
    ;;
  --git-credential-helper)
    GIT_CREDENTIAL_HELPER="$2"
    shift 2
    ;;
  --password)
    WSL_PASSWORD="$2"
    shift 2
    ;;
  *)
    echo "[XX] Unknown argument: $1"
    exit 1
    ;;
  esac
done

# ── Paths ─────────────────────────────────────────────────────────────────────
DOTFILES_DIR="$HOME/dotfiles"
SENTINEL="$DOTFILES_DIR/.bootstrap_complete"
LOG="$DOTFILES_DIR/.bootstrap_log"

# ── Logging helpers ───────────────────────────────────────────────────────────
log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" | tee -a "$LOG"; }
phase() {
  echo "" | tee -a "$LOG"
  echo "==========================================" | tee -a "$LOG"
  echo "  $*" | tee -a "$LOG"
  echo "==========================================" | tee -a "$LOG"
}
ok() { echo "  [OK] $*" | tee -a "$LOG"; }
skip() { echo "  [--] $*" | tee -a "$LOG"; }
warn() { echo "  [!!] $*" | tee -a "$LOG"; }
fail() { echo "  [XX] $*" | tee -a "$LOG"; }

# ── Error trap ────────────────────────────────────────────────────────────────
trap 'fail "Script failed at line $LINENO - check $LOG for details."' ERR

# ── Idempotency helpers ───────────────────────────────────────────────────────
is_installed() { command -v "$1" &>/dev/null; }
dnf_installed() { rpm -q "$1" &>/dev/null; }

# ── Sentinel guard ────────────────────────────────────────────────────────────
phase "Checking bootstrap sentinel"
if [[ -f "$SENTINEL" ]]; then
  fail "Sentinel file found at $SENTINEL"
  fail "Bootstrap appears to have already completed."
  warn "Delete .bootstrap_complete manually if you want to re-run."
  exit 1
fi
ok "No sentinel found - proceeding."
log "Bootstrap started. user=$(whoami) git-name='$GIT_NAME' git-email='$GIT_EMAIL'"

# ── Phase 5: System update ────────────────────────────────────────────────────
phase "Phase 5 - System update"
sudo dnf upgrade --refresh -y
ok "System updated."
log "PHASE 5 DONE: system update"

# ── Phase 6: Dev toolchain (dnf) ─────────────────────────────────────────────
phase "Phase 6 - Dev toolchain (dnf)"

DEV_PKGS=(
  gcc gcc-c++ make cmake clang
  gawk
  luarocks
  python3-devel pipx
  rustup
  openssl openssl-devel
  docker
  webkit2gtk4.1-devel
  librsvg2-devel
  xorg-x11-server-Xvfb
)

# Oracle Instant Client — install matching RPMs together
ORACLE_IC_VERSION="23.9.0.25.07-1.el9"
ORACLE_IC_BASE_URL="https://yum.oracle.com/repo/OracleLinux/OL9/oracle/instantclient23/x86_64/getPackage"

ORACLE_BASIC_URL="${ORACLE_IC_BASE_URL}/oracle-instantclient-basic-${ORACLE_IC_VERSION}.x86_64.rpm"
ORACLE_SQLPLUS_URL="${ORACLE_IC_BASE_URL}/oracle-instantclient-sqlplus-${ORACLE_IC_VERSION}.x86_64.rpm"

if dnf_installed oracle-instantclient-basic &&
  dnf_installed oracle-instantclient-sqlplus; then
  skip "Oracle Instant Client Basic and SQL*Plus already installed."
else
  sudo dnf install -y "$ORACLE_BASIC_URL" "$ORACLE_SQLPLUS_URL"
  ok "Oracle Instant Client Basic and SQL*Plus installed."
fi

# SQLPlus glogin.sql
GLOGIN_SQL="/usr/lib/oracle/23/client64/lib/glogin.sql"

if sudo test -f "$GLOGIN_SQL" && sudo grep -qF "SET COLSEP '|'" "$GLOGIN_SQL" 2>/dev/null; then
  skip "glogin.sql already configured."
else
  sudo tee -a "$GLOGIN_SQL" >/dev/null <<'EOF'
SET PAGESIZE 50000
SET LINESIZE 32767
SET TRIMSPOOL ON
SET WRAP OFF
SET FEEDBACK OFF
SET COLSEP '|'
EOF
  ok "glogin.sql configured at $GLOGIN_SQL."
fi

log "PHASE 6 DONE: dev toolchain"

# ── Phase 7: CLI tools (dnf) ──────────────────────────────────────────────────
phase "Phase 7 - CLI tools (dnf)"

CLI_PKGS=(
  zsh stow putty
  ripgrep fzf fd zoxide
  tealdeer chafa eza bat
  btop jq wl-clipboard
  ImageMagick fastfetch
)

for pkg in "${CLI_PKGS[@]}"; do
  if dnf_installed "$pkg"; then
    skip "$pkg already installed."
  else
    sudo dnf install -y "$pkg"
    ok "$pkg installed."
  fi
done

# Neovim - skip weak deps to avoid pulling bundled nodejs and tree-sitter-cli
if dnf_installed "neovim"; then
  skip "neovim already installed."
else
  sudo dnf install -y --setopt=install_weak_deps=False neovim
  sudo dnf install -y python3-neovim
  ok "neovim installed."
fi

# COPR: lazygit
if ! is_installed lazygit; then
  sudo dnf copr enable atim/lazygit -y
  sudo dnf install -y lazygit
  ok "lazygit installed."
else
  skip "lazygit already installed."
fi

# COPR: yazi
if ! is_installed yazi; then
  sudo dnf copr enable lihaohong/yazi -y
  sudo dnf install -y yazi
  ok "yazi installed."
else
  skip "yazi already installed."
fi

log "PHASE 7 DONE: CLI tools"

# ── Phase 8: Git configuration ────────────────────────────────────────────────
phase "Phase 8 - Git configuration"

[[ -n "$GIT_NAME" ]] && git config --global user.name "$GIT_NAME" && ok "Git user.name set." || warn "GIT_NAME empty - skipping."
[[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL" && ok "Git user.email set." || warn "GIT_EMAIL empty - skipping."

git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor nvim

if [[ -n "$GIT_CREDENTIAL_HELPER" ]]; then
  git config --global credential.helper "$GIT_CREDENTIAL_HELPER"
  ok "Git credential helper set to Windows GCM."
else
  warn "GCM not configured - set git credential.helper manually"
fi

log "PHASE 8 DONE: git configuration"

# ── Phase 9: Curl-based installers ───────────────────────────────────────────
phase "Phase 9 - Curl-based installers"

# Rustup - installed from dnf, just needs initialising
if ! is_installed rustc; then
  rustup-init -y --no-modify-path
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
  cargo install cargo-update --locked
  ok "Rust toolchain initialised."
else
  skip "Rust already initialised."
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env" 2>/dev/null || true
fi

# Zinit
ZINIT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_DIR" ]]; then
  bash -c "$(curl --fail --show-error --silent --location \
    https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)" \
    -- --no-preamble <<<"N"
  ok "Zinit installed."
else
  skip "Zinit already installed."
fi

# SDKMAN
if [[ ! -d "$HOME/.sdkman" ]]; then
  curl -s "https://get.sdkman.io" | bash
  ok "SDKMAN installed."
else
  skip "SDKMAN already installed."
fi

# Bun
if [[ ! -d "$HOME/.bun/bin" ]]; then
  curl -fsSL https://bun.sh/install | bash
  ok "Bun installed."
else
  skip "Bun already installed."
fi

# Misc: pipx path and smassh
pipx ensurepath
if ! is_installed smassh; then
  pipx install smassh
  ok "smassh installed via pipx."
else
  skip "smassh already installed."
fi

log "PHASE 9 DONE: curl-based installers"

# ── Phase 10: Cargo builds ────────────────────────────────────────────────────
phase "Phase 10 - Cargo builds"

# Rustup - installed from dnf, just needs initialising
if ! is_installed rustc; then
  rustup-init -y --no-modify-path
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
  cargo install cargo-update --locked
  ok "Rust toolchain initialised."
else
  skip "Rust already initialised."
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env" 2>/dev/null || true
fi

# Remove any dnf tree-sitter-cli pulled in as a neovim weak dep
if dnf_installed "tree-sitter-cli"; then
  sudo dnf remove -y tree-sitter-cli
  warn "Removed dnf tree-sitter-cli - cargo version takes precedence."
fi

cargo_install() {
  local pkg="$1"
  if cargo install --list | rg -q "^$pkg "; then
    skip "$pkg already installed via cargo."
  else
    cargo install "$pkg" --locked
    ok "$pkg installed."
  fi
}

cargo_install starship
cargo_install tree-sitter-cli
cargo_install fnm

log "PHASE 10 DONE: cargo builds"

# ── Phase 11: Node.js (fnm) ───────────────────────────────────────────────────
phase "Phase 11 - Node.js (fnm)"

# Eval fnm into this session so node/npm are immediately on PATH
eval "$(fnm env --use-on-cd)"

if ! fnm list | rg -q "lts"; then
  fnm install --lts
  ok "Node LTS installed via fnm."
else
  skip "Node LTS already installed."
fi

fnm use lts-latest
eval "$(fnm env)" # re-eval so node/npm are live in this session now

corepack enable
corepack prepare pnpm --activate

ok "Node ecosystem ready."
log "PHASE 11 DONE: Node.js ecosystem"

# ── Phase 12: JVM (SDKMAN) ───────────────────────────────────────────────────
phase "Phase 12 - JVM (SDKMAN)"

export SDKMAN_DIR="$HOME/.sdkman"
set +u
# shellcheck disable=SC1091
source "$SDKMAN_DIR/bin/sdkman-init.sh"

sdk_install() {
  local pkg="$1"
  if [[ -d "$SDKMAN_DIR/candidates/$pkg" ]]; then
    skip "$pkg already installed via sdk."
  else
    sdk install "$pkg"
    ok "$pkg installed."
  fi
}

sdk_install java
sdk_install maven
sdk_install gradle
sdk_install groovy
sdk_install kotlin

set -u
log "PHASE 12 DONE: JVM ecosystem"

# ── Phase 13: Change default shell ───────────────────────────────────────────
phase "Phase 13 - Default shell"

if [[ "$(getent passwd "$(whoami)" | cut -d: -f7)" != "/bin/zsh" ]]; then
  # usermod bypasses PAM - no password prompt
  sudo usermod -s /bin/zsh "$(whoami)"
  ok "Default shell changed to zsh."
else
  skip "Default shell is already zsh."
fi

log "PHASE 13 DONE: default shell"

# ── Phase 14: Stow dotfiles ───────────────────────────────────────────────────
phase "Phase 14 - Stow dotfiles"

cd "$DOTFILES_DIR"

stow_package() {
  local pkg="$1"
  if stow --simulate "$pkg" &>/dev/null; then
    stow "$pkg"
    ok "stow: $pkg"
  else
    warn "stow: $pkg has conflicts - skipping. Resolve manually and re-stow."
  fi
}

# Remove default .zshrc
if [[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
  rm "$HOME/.zshrc"
  warn "Removed pre-existing .zshrc"
fi

stow_package zsh
stow_package starship
stow_package nvim
stow_package tealdeer

# shellcheck disable=SC2015
tldr --update && ok "tealdeer cache updated." || warn "tldr --update failed - run manually."

log "PHASE 14 DONE: stow"

# ── Phase 15: Set user password ───────────────────────────────────────────────
phase "Phase 15 - Set user password"

if [[ -n "$WSL_PASSWORD" ]]; then
  echo "$(whoami):$WSL_PASSWORD" | sudo chpasswd
  ok "Password set for $(whoami)."
else
  warn "No password provided - account remains passwordless. Set manually with: passwd"
fi

log "PHASE 15 DONE: password set"

# Phase 16 - Restore sudo password requirement
phase "Phase 16 - Restore sudo security"
sudo rm -f "/etc/sudoers.d/$USER"
ok "NOPASSWD sudo removed - password required for sudo from now on."
log "PHASE 16 DONE: sudo security restored"

# ── Write sentinel ────────────────────────────────────────────────────────────
echo "Bootstrap completed at $(date)" >"$SENTINEL"
log "Sentinel written. Bootstrap complete."

phase "All done"
echo ""
echo "  Linux bootstrap completed successfully."
echo "  Returning to Windows script for final steps..."
echo ""
