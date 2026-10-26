#!/usr/bin/env python3
"""Run HTTPS regressions against a private SNI-checking TLS echo server.

Requires openssl, tclsh, and tcl-tls. No requests leave loopback. Exit 77
means a missing dependency or sandbox restriction, not a successful test.
"""
import http.server
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading


def main():
    root = Path(__file__).resolve().parent.parent
    check = subprocess.run(
        ["tclsh"], input="if {[catch {package require tls} e]} {puts stderr $e; exit 77}\n",
        text=True, capture_output=True,
    )
    if check.returncode:
        print("SKIP real HTTPS: " + check.stderr.strip())
        return 77
    with tempfile.TemporaryDirectory(prefix="chesswiz-https-") as temp:
        cert, key = Path(temp) / "cert.pem", Path(temp) / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
            "-keyout", str(key), "-out", str(cert),
        ], check=True, capture_output=True)
        received_sni = []

        class Echo(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, *_):
                pass

        try:
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Echo)
        except (OSError, PermissionError) as error:
            print(f"SKIP real HTTPS: loopback unavailable: {error}")
            return 77
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)

        def sni(_sock, name, _context):
            received_sni.append(name)
            if name != "localhost":
                return ssl.ALERT_DESCRIPTION_UNRECOGNIZED_NAME

        context.set_servername_callback(sni)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            env = dict(os.environ, PULSE_SINK="cwtests", HTTPS_TEST_PORT=str(server.server_port),
                       HTTPS_TEST_CA=str(cert))
            result = subprocess.run(["tclsh", str(root / "tests/test_https_registration.tcl")],
                                    env=env, timeout=30)
            if result.returncode:
                return result.returncode
            if received_sni != ["localhost"] * 3:
                print(f"FAIL SNI sequence: {received_sni!r}")
                return 1
            print("PASS real TLS POST, GET, UTF-8 echo, 200 KB POST, and per-connection SNI")
            return 0
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
