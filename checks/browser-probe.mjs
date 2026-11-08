// checks/browser-probe.mjs — can the browser lanes run here? Finds a
// Playwright whose Chromium launches (checks/playwright.mjs). Prints nothing
// and exits 0 when there is one; otherwise prints the reason on one line and
// exits 2, and the calling row reports its browser lanes as SKIP.
import { findChromium } from './playwright.mjs';

const found = await findChromium();
if (!found.chromium) { console.log(found.why); process.exit(2); }
