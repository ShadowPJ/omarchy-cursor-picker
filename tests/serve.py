# Test fixture: serves a folder over plain HTTP on 127.0.0.1 and prints its port.
# Usage: python3 -I tests/serve.py <dir>
import functools, http.server, sys

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
handler.log_message = lambda *a, **k: None
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
print(server.server_address[1], flush=True)
server.serve_forever()
