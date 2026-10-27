"""Test the original Swift networking against a loopback fixture, never a router."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading


class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, value, cookies=False):
        body = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if cookies:
            self.send_header("Location", "/must-not-follow")
            self.send_header("Set-Cookie", "sysauth_http=test-token; Path=/")
            self.send_header("Set-Cookie", "other=value; Path=/")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/redirect":
            self.reply(302, {}, cookies=True)
        else:
            self.reply(500, {"error": "unexpected redirect or path"})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()
        if self.path == "/ubus":
            request = json.loads(body)
            assert request["params"][1:3] == ["session", "login"]
            self.reply(200, {"result": [0, {"ubus_rpc_session": "fixture-session"}]})
        elif self.path == "/cgi-bin/luci/":
            self.reply(302, {}, cookies=True)
        elif self.path == "/echo":
            self.reply(200, {"body": body, "method": self.command, "header": self.headers.get("X-Test", ""), "cookie": self.headers.get("Cookie", "")})
        else:
            self.reply(404, {})


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = os.environ.copy()
    env["CR_TEST_URL"] = f"http://127.0.0.1:{server.server_port}"
    # Keep requests working even with an unusable proxy environment.
    env["HTTP_PROXY"] = env["HTTPS_PROXY"] = "http://127.0.0.1:1"
    root = Path(__file__).resolve().parent.parent
    try:
        code = subprocess.call([shutil.which("pwsh") or "powershell.exe", "-NoProfile", "-File", str(root / "scripts/build-windows.ps1"), "-CoreChecks"], cwd=root, env=env)
    finally:
        server.shutdown()
        server.server_close()
    raise SystemExit(code)
