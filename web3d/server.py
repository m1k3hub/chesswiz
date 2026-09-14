import http.server
import socketserver
import json
import os
import sys

PORT = 8899
BOARD_STATE = "rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR"

class Chess3DHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        global BOARD_STATE
        if self.path == "/api/board":
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"board": BOARD_STATE}).encode("utf-8"))
        else:
            super().do_GET()

    def do_POST(self):
        global BOARD_STATE
        if self.path == "/api/board":
            content_length = int(self.headers.get("Content-Length", 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode("utf-8"))
                if "board" in data:
                    BOARD_STATE = data["board"]
            except Exception as e:
                pass
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    web_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(web_dir)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), Chess3DHandler) as httpd:
        print(f"Scidb 3D WebGL Server running on port {PORT}...")
        httpd.serve_forever()
