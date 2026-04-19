#!/usr/bin/env bash
set -euo pipefail

# Rill CLI installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/rillmd/rill/main/install.sh | bash
#
# What this script does:
#   1. Checks prerequisites (git, jq)
#   2. Clones rillmd/rill to ~/.rill/source/ (or pulls if already cloned)
#   3. Symlinks ~/.local/bin/rill → ~/.rill/source/bin/rill
#   4. Verifies rill is on PATH
#   5. Creates a default vault at ~/Documents/my-rill (override later: rill init <path>)
#
# Safe to run multiple times (idempotent).

RILL_REPO="https://github.com/rillmd/rill.git"
RILL_SOURCE="$HOME/.rill/source"
RILL_BIN_DIR="$HOME/.local/bin"
RILL_BIN="$RILL_BIN_DIR/rill"
RILL_VAULT="$HOME/Documents/my-rill"

# ── Helpers ──────────────────────────────────────────────────────────

info()  { printf "  %s\n" "$*"; }
ok()    { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[33m!\033[0m %s\n" "$*"; }
err()   { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; }

# ── Pre-flight checks ───────────────────────────────────────────────

echo ""
echo "  Installing Rill CLI"
echo "  ───────────────────"
echo ""

errors=0

if command -v git &>/dev/null; then
    ok "git found"
else
    err "git not found — install git first"
    errors=$((errors + 1))
fi

if command -v jq &>/dev/null; then
    ok "jq found"
else
    err "jq not found — install jq first (brew install jq / apt install jq)"
    errors=$((errors + 1))
fi

if [ "$errors" -gt 0 ]; then
    echo ""
    err "Missing prerequisites. Install them and re-run this script."
    exit 1
fi

# ── Step 1: Clone or update source ───────────────────────────────────

echo ""

if [ -d "$RILL_SOURCE/.git" ]; then
    info "Source exists at $RILL_SOURCE, updating..."
    (cd "$RILL_SOURCE" && git pull --ff-only 2>/dev/null) && ok "Source updated" || {
        warn "git pull failed (offline?). Using existing source."
    }
else
    if [ -d "$RILL_SOURCE" ]; then
        warn "$RILL_SOURCE exists but is not a git repo. Removing and re-cloning."
        rm -rf "$RILL_SOURCE"
    fi
    info "Cloning rillmd/rill to $RILL_SOURCE ..."
    mkdir -p "$(dirname "$RILL_SOURCE")"
    git clone "$RILL_REPO" "$RILL_SOURCE"
    ok "Source cloned"
fi

# ── Step 2: Symlink to PATH ──────────────────────────────────────────

echo ""

mkdir -p "$RILL_BIN_DIR"

if [ -L "$RILL_BIN" ]; then
    # Symlink exists — verify it points to the right place
    local_target="$(readlink "$RILL_BIN")"
    if [ "$local_target" = "$RILL_SOURCE/bin/rill" ]; then
        ok "Symlink already correct: $RILL_BIN"
    else
        ln -sf "$RILL_SOURCE/bin/rill" "$RILL_BIN"
        ok "Symlink updated: $RILL_BIN → $RILL_SOURCE/bin/rill"
    fi
elif [ -e "$RILL_BIN" ]; then
    warn "$RILL_BIN exists and is not a symlink. Skipping."
    warn "Remove it manually if you want this installer to manage it."
else
    ln -s "$RILL_SOURCE/bin/rill" "$RILL_BIN"
    ok "Symlink created: $RILL_BIN → $RILL_SOURCE/bin/rill"
fi

# ── Step 3: Verify PATH ─────────────────────────────────────────────

echo ""

path_ok=true
if command -v rill &>/dev/null; then
    ok "rill is on PATH: $(command -v rill)"
else
    path_ok=false
    warn "~/.local/bin is not in your PATH"
    echo ""
    info "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo ""
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    info "Then restart your terminal or run: source ~/.zshrc"
fi

# ── Step 4: Create default vault ─────────────────────────────────────

echo ""

# Resolve rill binary — prefer the one we just symlinked, fall back to source
rill_cmd=""
if command -v rill &>/dev/null; then
    rill_cmd="rill"
elif [ -x "$RILL_SOURCE/bin/rill" ]; then
    rill_cmd="$RILL_SOURCE/bin/rill"
fi

if [ -n "$rill_cmd" ]; then
    # Check if any vault is already registered
    registry="$HOME/.rill/vaults.json"
    has_vault=false
    if [ -f "$registry" ]; then
        vault_count="$(jq '.vaults | length' "$registry" 2>/dev/null || echo 0)"
        [ "$vault_count" -gt 0 ] && has_vault=true
    fi

    if [ "$has_vault" = false ]; then
        echo ""
        info "Setting up your first vault — a folder of Markdown notes."
        info "  Location: $RILL_VAULT"
        info "  (in Documents — easy to find, and iCloud-friendly if iCloud Drive is on)"
        info "  To use a different folder later: rill init <path>"
        echo ""
        info "Creating vault ..."
        mkdir -p "$RILL_VAULT"
        (cd "$RILL_VAULT" && git init -q 2>/dev/null || true)
        "$rill_cmd" init "$RILL_VAULT" --name my-rill 2>/dev/null && \
            ok "Vault created at $RILL_VAULT" || {
            warn "Vault creation failed. You can create one manually:"
            info "  cd ~/Documents/my-rill && git init && rill init"
        }
    else
        ok "Vault already registered, skipping creation"
    fi
else
    warn "Could not locate rill command. Vault creation skipped."
    info "After adding ~/.local/bin to PATH, run:"
    info "  mkdir -p ~/Documents/my-rill && cd ~/Documents/my-rill && git init && rill init"
fi

# ── Done ─────────────────────────────────────────────────────────────

echo ""
echo "  ───────────────────"
echo ""
ok "Rill installed"
echo ""
if [ "$path_ok" = true ]; then
    info "Next: open Claude Code in your vault and start /onboarding."
else
    info "Next: finish the PATH setup printed above, then open Claude Code"
    info "      in your vault and start /onboarding."
fi
echo ""
echo "      cd ~/Documents/my-rill"
echo "      claude"
echo ""
info "  Then type:   /onboarding"
echo ""
info "/onboarding takes about 5 minutes and walks you through:"
info "  • Capturing your first journal entry"
info "  • Asking Claude about your own vault (this is the core habit)"
info "  • Setting a reminder for tomorrow's morning briefing (optional)"
echo ""
info "By the end you won't have memorized a command list — you'll"
info "have one thing working and can ask about the rest."
echo ""
info "New to Claude Code? → https://docs.anthropic.com/en/docs/claude-code"
echo ""
