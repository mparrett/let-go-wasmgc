// checks/browser-probe.mjs — can the browser lanes run here? Resolves
// Playwright the way checks/browser-boot.mjs does (LW_BROWSER_TOOLS, else
// ../../../local-scripts, each holding browser-smoke-playwright/) and checks
// that its Chromium launches. Prints nothing and exits 0 when both hold;
// otherwise prints the reason on one line and exits 2, and the calling row
// reports its browser lanes as SKIP.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const toolsDir = process.env.LW_BROWSER_TOOLS || path.resolve(here, '../../../local-scripts');
const pwDir = path.resolve(toolsDir, 'browser-smoke-playwright');
const skip = (why) => { console.log(why); process.exit(2); };
if (!fs.existsSync(path.join(pwDir, 'package.json'))) skip(`no Playwright install at ${pwDir} (set LW_BROWSER_TOOLS)`);
let chromium;
try {
  const pw = await import(pathToFileURL(createRequire(path.join(pwDir, 'package.json')).resolve('playwright')).href);
  chromium = pw.chromium || pw.default.chromium;
} catch (e) {
  skip(`Playwright does not load from ${pwDir}: ${String(e).split('\n')[0]}`);
}
// a launch, not executablePath(): headless Playwright runs the headless
// shell, a separate download from the full browser that executablePath() names
try {
  const b = await chromium.launch({ timeout: 30000 });
  await b.close();
} catch (e) {
  skip(`Playwright cannot launch Chromium: ${String(e).split('\n').find((l) => l.trim()) || e} (npx playwright install chromium in ${pwDir})`);
}
