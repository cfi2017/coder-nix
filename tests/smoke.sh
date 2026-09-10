#!/usr/bin/env bash
set -euo pipefail
image=${1:-coder-nix:test}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# A tmpfs hides every file originally installed in HOME. Override the
# entrypoint exactly as Coder does; Nix must work without shell startup files.
docker run --rm -i --entrypoint sh \
  --tmpfs /home/coder:uid=1000,gid=1000,mode=0755 \
  --mount "type=bind,src=$root/tests/flake,dst=/tmp/fixture,readonly" \
  --mount "type=bind,src=$root/tests/direnv.sh,dst=/tmp/test-direnv.sh,readonly" \
  "$image" -es <<'SMOKE'
    test "$(id -un)" = coder
    test "$(id -u)" = 1000
    sudo -n true
    for tool in nix git curl bash tmux rg bwrap direnv; do command -v "$tool"; done
    tmux -V
    rg --version
    bwrap --version
    nix --version
    cp -r /tmp/fixture "$HOME/flake"
    cd "$HOME/flake"
    nix flake metadata
    nix build --print-build-logs
    test "$(cat result)" = flakes-work
    nix develop --command bash -c 'test "$WORKSPACE_DEV_SHELL" = ready && hello'
    bash -lic "nix --version"
    bash -ic "declare -F _direnv_hook"
    bash -lic "declare -F _direnv_hook"
    bash /tmp/test-direnv.sh
SMOKE
