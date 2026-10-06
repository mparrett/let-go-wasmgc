// checks/explorer-page-check.mjs — row P10.3 (D194): host/explorer.html in
// headless Chromium. Builds the page with host/build-explorer-serve.sh into a
// temporary directory (or uses LW_EXPLORER_DIR, a directory that script
// produced), serves it from this process (plain HTTP: the JSPI lane needs no
// COOP/COEP, D91), and submits three sources:
//   scalar  a defn and a call: both panes print the same values, the
//           indicator says agree, the module pane shows a size, the
//           encoder's sections and a hex view starting with the wasm magic;
//   limit   (defn f [] [1]): the compiled pane shows the emitter's named
//           limit as text, the eval pane the var, the page keeps working;
//   reader  (+ 1 2)): both panes show native's reader error.
// Exit 0 all pass, 1 a failed assertion (each printed), 2 the page or its
// build script does not exist yet. Playwright comes from the workspace's
// smoke-script install, as in checks/browser-boot.mjs.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
if (!fs.existsSync(path.join(root, 'host/explorer.html')) || !fs.existsSync(path.join(root, 'host/build-explorer-serve.sh'))) {
  console.log('NOT IMPLEMENTED: host/explorer.html or host/build-explorer-serve.sh missing');
  process.exit(2);
}
console.log('NOT IMPLEMENTED: assertions');
process.exit(2);
