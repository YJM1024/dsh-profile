#!/bin/sh
# dsh-sync — mirror this DSH profile to a git remote (bidirectional).
#
#   dsh-sync status   show profile path, branch, remote and pending changes
#   dsh-sync push     commit local changes, then push
#   dsh-sync pull     fetch and rebase onto the remote branch
#   dsh-sync sync     commit + pull + push (what the timer runs)
#
# Overridable with DSH_SYNC_PROFILE, DSH_SYNC_REMOTE, DSH_SYNC_BRANCH,
# DSH_SYNC_LOG. DSH_HOME is honoured, so relocated installs work.
set -eu

resolve_profile() {
  if [ -n "${DSH_SYNC_PROFILE:-}" ]; then
    printf '%s' "$DSH_SYNC_PROFILE"
  elif [ -n "${DSH_HOME:-}" ]; then
    printf '%s/profiles/desktop' "$DSH_HOME"
  else
    printf '%s/.dsh/profiles/desktop' "$HOME"
  fi
}

PROFILE=$(resolve_profile)
LOG=${DSH_SYNC_LOG:-"${DSH_HOME:-$HOME/.dsh}/dsh-sync.log"}
# Windows/Git Bash: DSH_HOME comes from the Windows environment with
# backslashes, which the shell cannot use as a path.
if command -v cygpath >/dev/null 2>&1; then
  PROFILE=$(cygpath -u "$PROFILE")
  LOG=$(cygpath -u "$LOG")
fi

REMOTE=${DSH_SYNC_REMOTE:-origin}
BRANCH=${DSH_SYNC_BRANCH:-main}
GIT="git -C $PROFILE -c core.quotepath=false"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true
}

say() {
  printf '%s\n' "$*"
  log "$*"
}

die() {
  say "error: $*"
  exit 1
}

[ -d "$PROFILE" ] || die "profile directory not found: $PROFILE"
[ -d "$PROFILE/.git" ] || die "not a git repository: $PROFILE"

LOCKDIR="${TMPDIR:-/tmp}/dsh-sync.lock"
acquire_lock() {
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    # Break a lock left behind by a crashed or suspended run.
    if [ -n "$(find "$LOCKDIR" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
      rmdir "$LOCKDIR" 2>/dev/null || true
    fi
    mkdir "$LOCKDIR" 2>/dev/null || die "another dsh-sync is running"
  fi
  trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT
  trap 'rmdir "$LOCKDIR" 2>/dev/null || true; exit 130' INT
  trap 'rmdir "$LOCKDIR" 2>/dev/null || true; exit 143' TERM
}

have_remote() {
  $GIT remote get-url "$REMOTE" >/dev/null 2>&1
}

require_identity() {
  $GIT config --get user.email >/dev/null 2>&1 && return 0
  say "error: git has no user.email; set it once with:"
  say "  git config --global user.name  \"Your Name\""
  say "  git config --global user.email \"you@example.com\""
  exit 1
}

host_label() {
  printf '%s' "$(uname -n 2>/dev/null | cut -d. -f1)"
}

commit_local() {
  $GIT add -A
  if $GIT diff --cached --quiet; then
    log "no local changes"
    return 0
  fi
  $GIT commit -q -m "sync: $(host_label) $(date '+%Y-%m-%d %H:%M:%S')"
  say "committed local changes"
}

pull_remote() {
  have_remote || { say "no remote '$REMOTE' configured; pull skipped"; return 0; }
  before=$($GIT rev-parse HEAD 2>/dev/null || true)
  if ! $GIT fetch -q "$REMOTE" "$BRANCH" 2>>"$LOG"; then
    say "fetch failed (network, or credentials not stored yet); see $LOG"
    return 1
  fi
  if ! $GIT rev-parse --verify -q "refs/remotes/$REMOTE/$BRANCH" >/dev/null; then
    say "remote branch $REMOTE/$BRANCH does not exist yet; pull skipped"
    return 0
  fi
  if $GIT merge-base --is-ancestor "refs/remotes/$REMOTE/$BRANCH" HEAD; then
    log "already up to date"
    return 0
  fi
  if $GIT rebase --autostash "$REMOTE/$BRANCH" >/dev/null 2>&1; then
    say "pulled $REMOTE/$BRANCH"
    after=$($GIT rev-parse HEAD 2>/dev/null || true)
    if [ -n "$before" ] && [ -n "$after" ] && \
      [ -n "$($GIT diff --name-only "$before" "$after" -- pnpm-lock.yaml package.json 2>/dev/null)" ]; then
      say "manifest changed: run 'pnpm install' in $PROFILE, then restart DSH"
    fi
    return 0
  fi
  # Leave a usable working tree and let a human decide.
  $GIT rebase --abort >/dev/null 2>&1 || true
  say "rebase conflict: run 'git -C \"$PROFILE\" status' and resolve by hand"
  return 1
}

push_remote() {
  have_remote || { say "no remote '$REMOTE' configured; push skipped"; return 0; }
  if $GIT rev-parse --verify -q "refs/remotes/$REMOTE/$BRANCH" >/dev/null; then
    if [ "$($GIT rev-list --count "refs/remotes/$REMOTE/$BRANCH..HEAD")" = "0" ]; then
      log "nothing to push"
      return 0
    fi
  fi
  if $GIT push -q -u "$REMOTE" "$BRANCH" 2>>"$LOG"; then
    say "pushed to $REMOTE/$BRANCH"
  else
    say "push failed (network, or credentials not stored yet); see $LOG"
    return 1
  fi
}

show_status() {
  say "profile: $PROFILE"
  say "log:     $LOG"
  say "remote:  $($GIT remote get-url "$REMOTE" 2>/dev/null || echo '(not set)')"
  $GIT status --short --branch
  $GIT log -1 --format='last commit: %h %s (%cr)' 2>/dev/null || true
}

case "${1:-sync}" in
  sync)
    acquire_lock
    require_identity
    commit_local
    pull_remote || exit 1
    push_remote
    ;;
  push)
    acquire_lock
    require_identity
    commit_local
    push_remote
    ;;
  pull)
    acquire_lock
    pull_remote
    ;;
  status)
    show_status
    ;;
  *)
    die "usage: dsh-sync [sync|push|pull|status]"
    ;;
esac
