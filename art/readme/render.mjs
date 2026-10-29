// 把 readme.html 里的每张图截成 2 倍清晰度的透明底 PNG，放进 docs/images/
// 用法：node art/readme/render.mjs（要 Google Chrome 和 puppeteer-core，见 art/biu/README.md）
import puppeteer from "puppeteer-core";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(dir, "../..");
const out = path.join(root, "docs/images");

// 新版 Chrome 不让无头模式直接读本地文件，起一个只在本机的小网页服务
const types = { ".html": "text/html; charset=utf-8", ".webp": "image/webp", ".png": "image/png", ".ttf": "font/ttf" };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(new URL(req.url, "http://x").pathname);
  // logo 的字用系统自带的 SF 圆体
  const file = url === "/font/rounded.ttf" ? "/System/Library/Fonts/SFNSRounded.ttf" : path.join(root, url);
  if (!(file.startsWith(root) || file.startsWith("/System/Library/Fonts/")) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
}).listen(0, "127.0.0.1");
await new Promise(r => server.once("listening", r));

const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: "new" });
const page = await browser.newPage();
await page.setViewport({ width: 1400, height: 1000, deviceScaleFactor: 2 });
await page.goto(`http://127.0.0.1:${server.address().port}/art/readme/readme.html`);
const ids = await page.evaluate(() => window.GRAPHICS);
for (const id of ids) {
  await page.evaluate(async id => {
    document.querySelectorAll(".g").forEach(el => el.classList.toggle("on", el.id === id));
    await document.fonts.ready;
    await Promise.all([...document.images].map(i => i.decode().catch(() => {})));
  }, id);
  await (await page.$("#" + id)).screenshot({ path: path.join(out, id + ".png"), omitBackground: true });
  console.log(id);
}
await browser.close();
server.close();
