#!/bin/sh
# Install the macOS launchd agent that runs "dsh-sync sync" every N seconds,
# plus a "dsh-sync" command on PATH.
#
#   sh sync-tools/install-macos.sh [interval-seconds]
#
# Default interval is 900 seconds (15 minutes).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
PROFILE=$(cd "$HERE/.." && pwd)
INTERVAL=${1:-900}
LABEL=com.yjm1024.dsh-sync
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
BIN="$HOME/.local/bin"
SCRIPT="$PROFILE/sync-tools/dsh-sync.sh"
DSHHOME="${DSH_HOME:-$HOME/.dsh}"
RUNLOG="$DSHHOME/dsh-sync.log"

[ -d "$PROFILE/.git" ] || { echo "not a git repository: $PROFILE" >&2; exit 1; }
chmod +x "$SCRIPT"

mkdir -p "$AGENTS" "$BIN" "$DSHHOME"

# Seed this machine's local patch layer on a fresh checkout. DSH reads
# $DSH_HOME/cordis.patch.yml after the profile's cordis.patch.yml, so rows there
# win on this machine alone; the file lives outside the profile and is never
# committed or synced. An existing file is left untouched on purpose.
TEMPLATE="$HERE/machine/cordis.patch.macos.yml"
if [ -f "$DSHHOME/cordis.patch.yml" ]; then
    printf 'machine-local layer kept as is: %s\n' "$DSHHOME/cordis.patch.yml"
elif [ -f "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$DSHHOME/cordis.patch.yml"
    printf 'seeded machine-local layer: %s\n' "$DSHHOME/cordis.patch.yml"
else
    printf 'warning: no machine-local template at %s\n' "$TEMPLATE" >&2
fi

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$SCRIPT</string>
    <string>sync</string>
  </array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key><string>$RUNLOG</string>
  <key>StandardErrorPath</key><string>$RUNLOG</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true

ln -sf "$SCRIPT" "$BIN/dsh-sync"

printf 'installed %s (every %s seconds)\n' "$PLIST" "$INTERVAL"
printf 'command: %s/dsh-sync status\n' "$BIN"
printf 'log:     %s\n' "$RUNLOG"
