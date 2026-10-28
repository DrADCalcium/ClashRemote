"""Test the original Swift networking against a loopback fixture, never a router."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
from urllib.parse import urlsplit, parse_qs


class Fixture(http.server.BaseHTTPRequestHandler):
    requests = []
    running = False
    mode = "rule"
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
        path = urlsplit(self.path).path
        query = parse_qs(urlsplit(self.path).query)
        if path == "/fixture/reset":
            Fixture.requests = []
            Fixture.running = False
            Fixture.mode = "rule"
            self.reply(200, {})
            return
        if path == "/fixture/requests":
            self.reply(200, {"requests": Fixture.requests})
            return
        Fixture.requests.append({"method": "GET", "path": path, "query": query,
                                 "cookie": self.headers.get("Cookie", "")})
        if path == "/redirect":
            self.reply(302, {}, cookies=True)
        elif path.endswith("/openclash/status"):
            self.reply(200, {"clash": Fixture.running, "cn_port": self.server.server_port,
                             "dase": "fixture-secret", "core_type": "Mihomo"})
        elif path.endswith("/openclash/rule_mode"):
            self.reply(200, {"mode": Fixture.mode})
        elif path.endswith("/openclash/get_run_mode"):
            self.reply(200, {"mode": "fake-ip"})
        elif path.endswith("/openclash/config_file_list"):
            self.reply(200, {"current_config": "/etc/openclash/config/test.yaml", "config_files": [
                {"name": "test.yaml", "path": "/etc/openclash/config/test.yaml", "size": 100}]})
        elif path.endswith("/openclash/action"):
            action = query.get("action", [""])[0]
            if action not in ("start", "stop", "restart"):
                self.reply(400, {})
                return
            Fixture.running = action != "stop"
            self.reply(200, {})
        elif path.endswith("/openclash/switch_rule_mode"):
            Fixture.mode = query.get("rule_mode", [""])[0]
            self.reply(200, {})
        elif path.startswith("/cgi-bin/luci/admin/services/openclash/"):
            self.reply(200, {})
        elif path == "/connections":
            self.reply(200, {"uploadTotal": 1000, "downloadTotal": 2000, "connections": []})
        elif path == "/proxies":
            self.reply(200, {"proxies": {}})
        elif path == "/rules":
            self.reply(200, {"rules": []})
        else:
            self.reply(500, {"error": "unexpected redirect or path"})

    def do_PATCH(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        Fixture.requests.append({"method": "PATCH", "path": self.path, "body": body,
                                 "auth": self.headers.get("Authorization", "")})
        if self.path != "/configs" or self.headers.get("Authorization") != "Bearer fixture-secret":
            self.reply(403, {})
            return
        Fixture.mode = body["mode"]
        self.reply(204, {})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()
        if self.path == "/ubus":
            request = json.loads(body)
            method = request["params"][1:3]
            if method == ["session", "login"]:
                data = {"ubus_rpc_session": "fixture-session"}
            elif method == ["uci", "get"]:
                data = {"values": {"config": {"cn_port": str(self.server.server_port), "enable": "1", "en_mode": "fake-ip"}}}
            elif method == ["system", "board"]:
                data = {"hostname": "Fixture Router", "model": "Mock"}
            else:
                self.reply(500, {})
                return
            self.reply(200, {"result": [0, data]})
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
    root = Path(__file__).resolve().parent.parent
    try:
        code = subprocess.call([shutil.which("pwsh") or "powershell.exe", "-NoProfile", "-File", str(root / "scripts/build-windows.ps1"), "-CoreChecks"], cwd=root, env=env)
    finally:
        server.shutdown()
        server.server_close()
    raise SystemExit(code)
