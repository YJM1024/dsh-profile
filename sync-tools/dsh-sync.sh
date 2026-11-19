#!/bin/sh
# dsh-sync — mirror this DSH profile to a git remote.
#
#   dsh-sync status   show branch, remote and pending changes
#   dsh-sync push     commit local changes, then push
#   dsh-sync pull     fetch and rebase onto the remote branch
#   dsh-sync sync     commit + pull + push (what the timer runs)
#
# Overridable with DSH_SYNC_PROFILE, DSH_SYNC_REMOTE, DSH_SYNC_BRANCH,
# DSH_SYNC_LOG.
set -eu

PROFILE=${DSH_SYNC_PROFILE:-"$HOME/.dsh/profiles/desktop"}
REMOTE=${DSH_SYNC_REMOTE:-origin}
BRANCH=${DSH_SYNC_BRANCH:-main}
LOG=${DSH_SYNC_LOG:-"${DSH_HOME:-$HOME/.dsh}/dsh-sync.log"}

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
  trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT INT TERM
}

have_remote() {
  git -C "$PROFILE" remote get-url "$REMOTE" >/dev/null 2>&1
}

host_label() {
  printf '%s' "$(uname -n 2>/dev/null | cut -d. -f1)"
}

commit_local() {
  git -C "$PROFILE" add -A
  if git -C "$PROFILE" diff --cached --quiet; then
    log "no local changes"
    return 0
  fi
  git -C "$PROFILE" commit -q -m "sync: $(host_label) $(date '+%Y-%m-%d %H:%M:%S')"
  say "committed local changes"
}

pull_remote() {
  have_remote || { say "no remote '$REMOTE' configured; pull skipped"; return 0; }
  if ! git -C "$PROFILE" fetch -q "$REMOTE" "$BRANCH" 2>>"$LOG"; then
    say "fetch failed (network, or credentials not stored yet)"
    return 1
  fi
  if ! git -C "$PROFILE" rev-parse --verify -q "refs/remotes/$REMOTE/$BRANCH" >/dev/null; then
    say "remote branch $REMOTE/$BRANCH does not exist yet; pull skipped"
    return 0
  fi
  if git -C "$PROFILE" merge-base --is-ancestor "refs/remotes/$REMOTE/$BRANCH" HEAD; then
    log "already up to date"
    return 0
  fi
  if git -C "$PROFILE" rebase --autostash "$REMOTE/$BRANCH" >/dev/null 2>&1; then
    say "pulled $REMOTE/$BRANCH"
    return 0
  fi
  # Leave a usable working tree and let a human decide.
  git -C "$PROFILE" rebase --abort >/dev/null 2>&1 || true
  say "rebase conflict: run 'git -C $PROFILE status' and resolve by hand"
  return 1
}

push_remote() {
  have_remote || { say "no remote '$REMOTE' configured; push skipped"; return 0; }
  if git -C "$PROFILE" rev-parse --verify -q "refs/remotes/$REMOTE/$BRANCH" >/dev/null; then
    if [ "$(git -C "$PROFILE" rev-list --count "refs/remotes/$REMOTE/$BRANCH..HEAD")" = "0" ]; then
      log "nothing to push"
      return 0
    fi
  fi
  if git -C "$PROFILE" push -q -u "$REMOTE" "$BRANCH" 2>>"$LOG"; then
    say "pushed to $REMOTE/$BRANCH"
  else
    say "push failed (network, or credentials not stored yet)"
    return 1
  fi
}

show_status() {
  say "profile: $PROFILE"
  say "remote:  $(git -C "$PROFILE" remote get-url "$REMOTE" 2>/dev/null || echo '(not set)')"
  git -C "$PROFILE" status --short --branch
  git -C "$PROFILE" log -1 --format='last commit: %h %s (%cr)' 2>/dev/null || true
}

case "${1:-sync}" in
  sync)
    acquire_lock
    commit_local
    pull_remote || exit 1
    push_remote
    ;;
  push)
    acquire_lock
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
