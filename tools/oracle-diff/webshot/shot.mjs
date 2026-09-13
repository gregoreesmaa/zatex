// One-shot headless-Chromium renderer for the KaTeX / MathJax oracles.
// Serves bundled assets over a localhost-only HTTP server — no external
// network at run time — renders one TeX string, screenshots the math
// element with padding, writes PNG. A TeX error exits nonzero (the case
// is then reported as a missing render, never silently blank).
//
// Usage:
//   node shot.mjs --engine katex|mathjax --tex '<tex>' [--display]
//                  --out out.png [--css-px 32] [--chrome /usr/bin/chromium]
import { createServer } from "node:http";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const ROOT = path.dirname(fileURLToPath(import.meta.url));

function arg(name, def = null) {
  const i = process.argv.indexOf("--" + name);
  if (i < 0) return def;
  const v = process.argv[i + 1];
  if (v === undefined || v.startsWith("--")) return true;
  return v;
}

const MIME = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css",
  ".woff2": "font/woff2", ".woff": "font/woff", ".ttf": "font/ttf",
  ".otf": "font/otf",
};

// Prefix mounts: web fonts resolve relative to their CSS/JS, so each
// bundle keeps its own URL subtree. /fonts serves the mounted math
// fonts (LM fixture first, STIX fallback) for the record.
const MOUNTS = [
  ["/katex/", ROOT + "/node_modules/katex/dist/"],
  ["/mathjax/", ROOT + "/node_modules/mathjax-full/es5/"],
  ["/fonts/", "/fonts/"],
  ["/", ROOT + "/public/"],
];

async function serve() {
  const server = createServer(async (req, res) => {
    try {
      const p = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
      for (const [prefix, dir] of MOUNTS) {
        if (!p.startsWith(prefix)) continue;
        if (prefix === "/fonts/" && !existsSync("/fonts")) continue;
        const f = path.normalize(path.join(dir, p.slice(prefix.length)));
        if (!f.startsWith(path.normalize(dir))) continue;
        try {
          const body = await readFile(f);
          res.writeHead(200, { "Content-Type": MIME[path.extname(f)] || "application/octet-stream" });
          res.end(body);
          return;
        } catch { /* try next mount */ }
      }
      res.writeHead(404);
      res.end("nope");
    } catch (e) {
      res.writeHead(500);
      res.end(String(e));
    }
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return server;
}

const engine = arg("engine");
const tex = arg("tex", "");
const out = arg("out");
const display = arg("display", false) !== false && arg("display", false) !== "0";
const cssPx = parseInt(arg("css-px", "32"), 10);
const chrome = arg("chrome", "/usr/bin/chromium");
if (!engine || !out || (engine !== "katex" && engine !== "mathjax")) {
  console.error("usage: shot.mjs --engine katex|mathjax --tex '<tex>' --out o.png [--display]");
  process.exit(2);
}

const texJS = JSON.stringify(tex);
const body = engine === "katex"
  ? `<div id="m"></div><link rel="stylesheet" href="/katex/katex.min.css">
     <script src="/katex/katex.min.js"></script>
     <script>try {
       katex.render(${texJS}, document.getElementById("m"),
         {displayMode: ${display}, throwOnError: true, strict: false, trust: true});
       document.title = "ready";
     } catch (e) { document.title = "katex-error: " + e.message; }</script>`
  : `<div id="m"></div>
     <script>window.MathJax = {startup: {typeset: false}};</script>
     <script src="/mathjax/tex-chtml.js"></script>
     <script>MathJax.startup.promise.then(() => {
       document.getElementById("m").textContent =
         ${display} ? "$$" + ${texJS} + "$$" : "$" + ${texJS} + "$";
       return MathJax.typesetPromise(["#m"]);
     }).then(() => { document.title = "ready"; })
       .catch((e) => { document.title = "mathjax-error: " + e.message; });</script>`;

const html = `<!doctype html><html><head><meta charset="utf-8"><title>…</title></head>
<body style="margin:0;background:#fff">
<style>body{font-size:${cssPx}px} #m{display:inline-block;background:#fff;padding:8px}</style>
${body}</body></html>`;

await mkdir(ROOT + "/public", { recursive: true });
await writeFile(ROOT + "/public/shot.html", html);

const server = await serve();
const port = server.address().port;
const browser = await puppeteer.launch({
  executablePath: chrome,
  args: ["--no-sandbox", "--disable-gpu", "--force-color-profile=srgb"],
});
let failed = false;
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1600, height: 600, deviceScaleFactor: 2 });
  await page.goto(`http://127.0.0.1:${port}/shot.html`);
  await page.waitForFunction(`document.title !== "…"`, { timeout: 30000 });
  const title = await page.title();
  if (title !== "ready") {
    console.error("oracle render failed: " + title + " :: " + tex);
    failed = true;
  } else {
    const el = await page.$("#m");
    const box = await el.boundingBox();
    await page.screenshot({
      path: out,
      clip: {
        x: Math.max(0, box.x - 8), y: Math.max(0, box.y - 8),
        width: box.width + 16, height: box.height + 16,
      },
    });
    console.log("shot: " + out);
  }
} finally {
  await browser.close();
  server.close();
}
process.exit(failed ? 1 : 0);
