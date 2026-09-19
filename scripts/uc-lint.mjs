/**
 * uc-lint.mjs - ucode linter built on ucode-lsp (https://github.com/NoahBPeterson/ucode-lsp).
 *
 * Runs `ucode-lsp`'s CLI checker (type inference, flow analysis, null-safety,
 * unused imports, forward-declarations, version gating) against the feed's
 * `.uc` files, gated to the oldest supported OpenWrt release (25.12.x) via
 * `--target-version`.
 *
 * ucode-lsp resolves relative `import { ... } from './x.uc'` and
 * `require()` calls from the importing file's directory, matching how the
 * packages ship their files, so no staging is needed.
 *
 * ucode-lsp also enforces the ucode-only pitfalls that used to need custom
 * rules: `export function foo(){...}` must end with a `;` (UC6005), and
 * forward declarations (`export function name;`) that shadow a later function
 * are flagged (UC1007).
 *
 * Usage: node scripts/uc-lint.mjs
 *
 * Copyright (C) 2026 Vladimir Ermakov <vooon341@gmail.com>
 * SPDX-License-Identifier: LGPL-2.1+
 */
import { statSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

/* package dirs holding `.uc` sources (scanned recursively by ucode-lsp) */
const roots = [
	'rpcd-mod-bird',
	'inotify-rsync/files',
	'vpn-sticky/files',
	'ucode-mod-inotify/test',
	'ucode-mod-sqlite/test',
	'angie/ucode-module/test',
	'uwsd/files',
	'uwsd/test',
];

/* Pin the ucode-lsp version for reproducibility. Bump deliberately. */
const UCODE_LSP_VERSION = '0.8.11';

let failed = 0;

function err(msg) {
	console.error(`[uc-lint] ${msg}`);
	failed = 1;
}

for (const root of roots) {
	const dir = path.join(repoRoot, root);
	if (!statSync(dir, { throwIfNoEntry: false })?.isDirectory())
		continue;

	const r = spawnSync('npx', ['-y', `ucode-lsp@${UCODE_LSP_VERSION}`, dir, '--target-version', '25.12'], {
		encoding: 'utf8',
		stdio: 'inherit',
	});
	if (r.status !== 0)
		err(`ucode-lsp (target 25.12) found issues in ${root}`);
}

if (failed) {
	process.exit(1);
}
console.log('[uc-lint] all ucode sources OK');