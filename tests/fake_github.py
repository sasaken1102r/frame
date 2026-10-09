"""テスト用の偽の GitHub。インストーラー（i）が使う 2 つの道だけに答える。

  GET /<owner>/<repo>/releases/latest            → 302 で /<owner>/<repo>/releases/tag/<tag> へ
  GET /<owner>/<repo>/releases/download/<tag>/F  → ROOT/<repo>/F を返す

使い方: python3 fake_github.py ROOT PORT_FILE TAG
空いているポートで待ち受け、その番号を PORT_FILE に書く。止めるまで動き続ける。
"""
import http.server
import os
import sys

ROOT, PORT_FILE, TAG = sys.argv[1], sys.argv[2], sys.argv[3]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parts = self.path.split('?', 1)[0].strip('/').split('/')
        base = f'http://127.0.0.1:{self.server.server_port}'
        if len(parts) == 4 and parts[2:] == ['releases', 'latest']:
            self.send_response(302)
            self.send_header('Location', f'{base}/{parts[0]}/{parts[1]}/releases/tag/{TAG}')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if len(parts) == 6 and parts[2:4] == ['releases', 'download'] and parts[4] == TAG:
            path = os.path.join(ROOT, parts[1], parts[5])
            if os.path.isfile(path):
                with open(path, 'rb') as f:
                    body = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
        self.send_response(404)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
tmp = PORT_FILE + '.tmp'
with open(tmp, 'w') as f:
    f.write(str(server.server_port))
os.replace(tmp, PORT_FILE)
server.serve_forever()
