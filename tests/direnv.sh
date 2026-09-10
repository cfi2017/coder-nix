#!/usr/bin/env bash
# Run in a disposable directory containing tests/flake's flake.nix.
set -euo pipefail

# Model an agent with stale environment already stored in a tmux server.
# Use a private socket so this test cannot affect workspace sessions.
socket="direnv-test-$$"
cleanup() {
  status=$?
  if ((status != 0)); then
    echo "direnv/tmux test failed (exit $status)" >&2
    tmux -L "$socket" list-panes -a -F '#{session_name}: dead=#{pane_dead} status=#{pane_dead_status} command=#{pane_current_command}' >&2 || true
    tmux -L "$socket" capture-pane -p -S - -t codex >&2 || true
  fi
  tmux -L "$socket" kill-server 2>/dev/null || true
}
trap cleanup EXIT
WORKSPACE_DEV_SHELL=stale tmux -L "$socket" -f /dev/null new-session -d -s stale 'sleep infinity'

printf 'use flake\n' > .envrc
# Unapproved project code must not run, even when launched noninteractively.
if direnv exec . touch should-not-exist; then
  echo 'direnv accepted an unapproved .envrc' >&2
  exit 1
fi
test ! -e should-not-exist
direnv allow .
# shellcheck disable=SC2016 # Expansion belongs to the child inside direnv.
direnv exec . bash -c 'test "$WORKSPACE_DEV_SHELL" = ready && hello'

# Fake Codex: capture exactly the environment seen by the pane's process.
cat > check-context.sh <<'CHECK'
#!/usr/bin/env bash
set -euo pipefail
test "$WORKSPACE_DEV_SHELL" = ready
hello > hello.txt
printf 'ok\n' > context-ok
CHECK
chmod +x check-context.sh
# Keep a failed pane around so tmux can report its exit code as well.
tmux -L "$socket" set-option -g remain-on-exit on
tmux -L "$socket" new-session -d -s codex -c "$PWD" \
  'exec direnv exec . ./check-context.sh'
for ((attempt = 0; attempt < 60; attempt++)); do
  if [[ $(tmux -L "$socket" display-message -p -t codex '#{pane_dead}') == 1 ]]; then
    break
  fi
  sleep 1
done
test "$(tmux -L "$socket" display-message -p -t codex '#{pane_dead_status}')" = 0
test "$(cat context-ok)" = ok
grep -q 'Hello, world!' hello.txt
