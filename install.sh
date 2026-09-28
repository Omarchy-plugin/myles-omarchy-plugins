#!/bin/bash
# omarchy:summary=Install the Mylesoft Omarchy plugin suite and its auto-updater
# omarchy:args=[] [--no-hooks] [--only <id,...>]

# One command installs every plugin published by the Omarchy-plugin organisation,
# wires up the periodic updater, and leaves the stock Omarchy widgets disabled
# where a fork replaces them.
#
# Safe to re-run: a plugin that is already installed from this organisation is
# updated instead of reinstalled, so settings and history are never clobbered.

set -uo pipefail

ORG="https://github.com/Omarchy-plugin"
PREFIX="${MYLES_PLUGIN_PREFIX:-myles.}"

# This script sits at the repository root, so its own directory is the repo.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# repo:plugin-id:upstream-builtin-to-disable
PLUGINS=(
  "myles-clock:myles.clock:omarchy.clock"
  "myles-network:myles.network:omarchy.network"
  "myles-agents:myles.agents:omarchy.agents"
  "myles-usage:myles.usage:"
  "myles-calculator:myles.calculator:"
  "myles-appearance-picker:myles.appearance-picker:"
  "myles-workspaces:myles.workspaces:omarchy.workspaces"
  "omarchy-myles-media:myles.media:omarchy.media"
)

NO_HOOKS=0
ONLY=""
while (($#)); do
  case "$1" in
    --no-hooks) NO_HOOKS=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    -h | --help) awk 'NR>1 && NR<=15 && /^#/ {sub(/^# ?/,""); print}' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

for cmd in omarchy omarchy-shell; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: $cmd not found; is this an Omarchy system?" >&2; exit 1; }
done

# Installer's own home, so the updater keeps working after this repo moves.
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/myles-omarchy-plugins"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$STATE_DIR" "$BIN_DIR" || { echo "error: cannot create $STATE_DIR" >&2; exit 1; }

# Keep a copy of the updater and the hook files somewhere stable, then link
# them onto PATH. A symlink into a possibly-deleted checkout would break the
# updater on the next shell start.
cp -f "$SCRIPT_DIR/bin/omarchy-myles-plugin-update" "$BIN_DIR/" || {
  echo "error: could not install the updater into $BIN_DIR" >&2
  echo "       source was $SCRIPT_DIR/bin/omarchy-myles-plugin-update" >&2
  exit 1
}
chmod +x "$BIN_DIR/omarchy-myles-plugin-update"

installed=()
skipped=()
failed=()

install_one() {
  local repo="$1" id="$2" builtin="$3"
  local dir="$HOME/.config/omarchy/plugins/$id"

  if [[ -d $dir/.git ]] && git -C "$dir" remote get-url origin 2>/dev/null | grep -q "$ORG/$repo.git"; then
    # Already ours. Update in place so local settings survive.
    if omarchy plugin update "$id" --yes >/dev/null 2>&1; then
      skipped+=("$id (already installed, updated)")
    else
      failed+=("$id (update failed)")
    fi
    return
  fi

  if [[ -e $dir || -L $dir ]]; then
    # Something else owns this id. Never clobber it: the validator forbids two
    # plugins sharing an id anyway, and the user may have local changes.
    failed+=("$id (a different plugin already owns this id; remove it first with: omarchy plugin remove $id --yes)")
    return
  fi

  if omarchy plugin add "$ORG/$repo.git" --enable --yes >/dev/null 2>&1; then
    installed+=("$id")
    [[ -n $builtin ]] && omarchy plugin disable "$builtin" >/dev/null 2>&1
  else
    failed+=("$id (omarchy plugin add failed; re-run without --yes to see why)")
  fi
}

for entry in "${PLUGINS[@]}"; do
  IFS=: read -r repo id builtin <<<"$entry"
  if [[ -n $ONLY && ,$ONLY, != *",$id,"* && ,$ONLY, != *",$repo,"* ]]; then
    continue
  fi
  install_one "$repo" "$id" "$builtin"
done

# Ask the shell to re-read the plugin set so new widgets appear without a
# logout, then place anything that is enabled but not yet on the bar.
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

if ((NO_HOOKS)); then
  echo "skipping updater setup (--no-hooks)"
else
  # Omarchy-native hooks: run after a system update and after boot.
  for event in post-update.d post-boot.d; do
    mkdir -p "$HOME/.config/omarchy/hooks/$event"
    cat >"$HOME/.config/omarchy/hooks/$event/10-myles-plugin-update" <<'HOOK'
#!/bin/bash
# Pull updates for the Omarchy-plugin suite. Quiet unless something changed.
# shellcheck disable=SC1091
[[ -x "$HOME/.local/bin/omarchy-myles-plugin-update" ]] && \
  "$HOME/.local/bin/omarchy-myles-plugin-update" >/dev/null 2>&1
exit 0
HOOK
    chmod +x "$HOME/.config/omarchy/hooks/$event/10-myles-plugin-update"
  done

  # A periodic timer is what makes updates feel automatic between reboots and
  # system updates. --user so it needs no root and follows the login session.
  mkdir -p "$HOME/.config/systemd/user"
  cp -f "$SCRIPT_DIR/systemd/myles-plugin-update.service" \
        "$HOME/.config/systemd/user/" 2>/dev/null || true
  cp -f "$SCRIPT_DIR/systemd/myles-plugin-update.timer" \
        "$HOME/.config/systemd/user/" 2>/dev/null || true
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now myles-plugin-update.timer >/dev/null 2>&1 || true
    # Keep the timer alive across logout on Omarchy, which does not linger by
    # default. Best effort: some sessions refuse this, and the Omarchy hooks
    # still cover those cases.
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
  fi
fi

echo
if ((${#installed[@]})); then
  printf 'installed:  %s\n' "${installed[*]}"
fi
if ((${#skipped[@]})); then
  printf 'already ok: %s\n' "${skipped[*]}"
fi
if ((${#failed[@]})); then
  echo
  printf 'problems:\n'
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi

echo
echo "Verify with:  omarchy plugin list"
echo "Update with:  omarchy plugin update --yes"
echo "Update log:   ${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/myles-plugin-update.log"
