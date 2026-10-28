import puppeteer from "puppeteer-core";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] || path.join(dir, "out");
fs.mkdirSync(out, { recursive: true });
const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: "new" });
const page = await browser.newPage();
await page.setViewport({ width: 768, height: 768, deviceScaleFactor: 1 });
await page.goto("file://" + path.join(dir, "biu.html"));
const names = await page.evaluate(() => window.FRAME_NAMES);
for (const n of names) {
  await page.evaluate(n => window.show(n), n);
  await page.screenshot({ path: path.join(out, n + ".png"), omitBackground: true, clip: { x: 0, y: 0, width: 768, height: 768 } });
}
console.log(names.length, "frames");
await browser.close();
