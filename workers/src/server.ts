// Minimal HTTP surface for Railway health checks and FFmpeg probe.
import { createServer } from "node:http";
import { execFile } from "node:child_process";

createServer((req, res) => {
  if (req.url === "/health") {
    execFile("ffmpeg", ["-version"], (err, out) => {
      res.writeHead(err ? 500 : 200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: !err, ffmpeg: err ? String(err) : out.split("\n")[0] }));
    });
    return;
  }
  res.writeHead(404); res.end();
}).listen(Number(process.env.PORT ?? 8080));
