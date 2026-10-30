#!/usr/bin/env bash
set -euo pipefail
image=${1:-coder-nix-rea:test}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
docker run --rm -i --entrypoint bash \
  --tmpfs /home/coder:exec,uid=1000,gid=1000,mode=0755 \
  --mount "type=bind,src=$root/tests/rea-mcp.py,dst=/tmp/rea-mcp.py,readonly" \
  "$image" -es <<'SMOKE'
for tool in rea node npm java javac ghidra jadx apktool binwalk tshark mitmdump frida r2 gdb strace ltrace file readelf 7z wasm2wat adb ps; do
  command -v "$tool"
done
python3 -c 'import pwn, pefile, capstone, elftools'
rea --help
rea-setup-agents
# Repeat against existing configs to exercise startup after a workspace restart.
rea-setup-agents
python3 - <<'PY'
from pathlib import Path
import json
assert '[mcp_servers.rea]' in (Path.home() / '.codex/config.toml').read_text()
assert 'rea' in json.loads((Path.home() / '.claude.json').read_text())['mcpServers']
PY
python3 /tmp/rea-mcp.py
rea doctor --provider ghidra --json > /tmp/rea-doctor.json
python3 - <<'PYTHON'
import json
report = json.load(open('/tmp/rea-doctor.json'))
assert report['healthy'], report
assert any(p['id'] == 'ghidra' and p['available'] for p in report['providerInspections']), report
PYTHON
printf '%s\n' 'int main(void) { return 42; }' > /tmp/rea-fixture.c
cc -g -o /tmp/rea-fixture /tmp/rea-fixture.c
rea decompile /tmp/rea-fixture --procedure main --provider ghidra --json > /tmp/rea-decompile.json
python3 - <<'PYTHON'
import json
result = json.load(open('/tmp/rea-decompile.json'))
assert '42' in json.dumps(result) or '0x2a' in json.dumps(result), result
PYTHON
SMOKE
