#!/usr/bin/env python3
"""Termuxから標準ブラウザの入力欄でアプリ名を受け取る。"""

from __future__ import annotations

import argparse
import html
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--default", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--ready", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--timeout", type=int, default=300)
    return parser.parse_args()


def is_valid_name(value: str) -> bool:
    return bool(value.strip()) and len(value) <= 80 and not any(
        ord(character) < 32 or ord(character) == 127 for character in value
    )


def write_text_atomically(path: Path, value: str) -> None:
    temporary_path = path.with_name(f".{path.name}.{secrets.token_hex(8)}.tmp")
    temporary_path.write_text(value, encoding="utf-8")
    os.chmod(temporary_path, 0o600)
    temporary_path.replace(path)


def render_page(token: str, default_name: str) -> bytes:
    escaped_default = html.escape(default_name, quote=True)
    escaped_token = html.escape(token, quote=True)
    document = f"""<!doctype html>
<html lang="ja">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>KBC cloneにゃんこ</title>
<style>
  body {{ background:#111827; color:#f9fafb; font-family:sans-serif; margin:0; padding:28px 20px; }}
  main {{ max-width:520px; margin:auto; }}
  h1 {{ font-size:22px; margin:0 0 20px; }}
  p {{ color:#d1d5db; line-height:1.65; }}
  input {{ box-sizing:border-box; width:100%; border:1px solid #6b7280; border-radius:10px; background:#fff; color:#111827; font-size:20px; padding:14px; }}
  button {{ width:100%; margin-top:16px; border:0; border-radius:10px; background:#22c55e; color:#052e16; font-size:17px; font-weight:bold; padding:14px; }}
  #message {{ min-height:1.6em; color:#fbbf24; }}
</style>
<main>
  <h1>アプリ名を入力</h1>
  <p>ここは端末の通常入力欄です。日本語キーボードで入力してください。</p>
  <form id="name-form" method="post" action="/submit?token={escaped_token}">
    <input id="app-name" name="name" type="text" lang="ja" autocapitalize="off" autocomplete="off" spellcheck="false" value="{escaped_default}" maxlength="80" required>
    <button type="submit">この名前で決定</button>
  </form>
  <p id="message"></p>
</main>
<script>
  const form = document.getElementById('name-form');
  const input = document.getElementById('app-name');
  const message = document.getElementById('message');
  input.focus();
  input.select();
  form.addEventListener('submit', async (event) => {{
    event.preventDefault();
    message.textContent = '保存しています…';
    const response = await fetch(form.action, {{ method: 'POST', body: new URLSearchParams(new FormData(form)) }});
    if (!response.ok) {{
      message.textContent = '入力を確認してください。';
      return;
    }}
    form.hidden = true;
    message.style.color = '#86efac';
    message.textContent = '保存しました。Termuxへ戻ってください。';
  }});
</script>
</html>"""
    return document.encode("utf-8")


def main() -> int:
    args = parse_args()
    if not args.token or args.timeout < 1:
        return 2

    result_path = Path(args.result)
    ready_path = Path(args.ready)
    result_path.parent.mkdir(parents=True, exist_ok=True)
    page = render_page(args.token, args.default)
    completed = threading.Event()

    class RequestHandler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *arguments: object) -> None:
            return

        def send_plain_response(self, status: int, payload: bytes) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self) -> None:
            request = urlparse(self.path)
            if request.path != "/" or parse_qs(request.query).get("token", [""])[0] != args.token:
                self.send_plain_response(404, b"Not found")
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'self'")
            self.end_headers()
            self.wfile.write(page)

        def do_POST(self) -> None:
            request = urlparse(self.path)
            if request.path != "/submit" or parse_qs(request.query).get("token", [""])[0] != args.token:
                self.send_plain_response(404, b"Not found")
                return
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 4096:
                self.send_plain_response(400, b"Invalid input")
                return
            form = parse_qs(self.rfile.read(content_length).decode("utf-8", errors="replace"))
            app_name = form.get("name", [""])[0]
            if not is_valid_name(app_name):
                self.send_plain_response(400, b"Invalid input")
                return
            write_text_atomically(result_path, app_name)
            completed.set()
            self.send_plain_response(200, b"Saved")
            threading.Thread(target=self.server.shutdown, daemon=True).start()

    server = ThreadingHTTPServer(("127.0.0.1", 0), RequestHandler)
    port = server.server_address[1]
    query = urlencode({"token": args.token})
    write_text_atomically(ready_path, f"http://127.0.0.1:{port}/?{query}")

    timer = threading.Timer(args.timeout, server.shutdown)
    timer.daemon = True
    timer.start()
    try:
        server.serve_forever()
    finally:
        timer.cancel()
        server.server_close()
    return 0 if completed.is_set() else 1


if __name__ == "__main__":
    raise SystemExit(main())
