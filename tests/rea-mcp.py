"""Exercise the installed stdio server without any agent installed."""
import json
import selectors
import subprocess

server = subprocess.Popen(["rea", "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
try:
    request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2024-11-05", "capabilities": {},
        "clientInfo": {"name": "workspace-smoke", "version": "1"}}}
    server.stdin.write(json.dumps(request) + "\n")
    server.stdin.flush()
    selector = selectors.DefaultSelector()
    selector.register(server.stdout, selectors.EVENT_READ)
    assert selector.select(60), "MCP initialize timed out"
    response = json.loads(server.stdout.readline())
    assert response.get("id") == 1 and "result" in response, response
    assert "tools" in response["result"]["capabilities"], response
finally:
    server.terminate()
    try:
        server.wait(timeout=15)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait()
