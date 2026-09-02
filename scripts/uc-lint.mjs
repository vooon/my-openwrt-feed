/*
 * uc-lint.mjs - lightweight ucode linter using node's ESM parser.
 *
 * ucode is ECMAScript-based, so node can syntax-check the `.uc` modules. This
 * also enforces a couple of ucode-specific rules that a plain node parse won't
 * catch:
 *   - `export function foo(){...}` must be terminated with `;`
 *     (this ucode parses the export as an expression statement)
 *   - array ops use the global form `push(arr, ...)`, not `arr.push(...)`
 *   - strings are not []-indexable in ucode (use substr(s, i, 1) / ord(s, i))
 *
 * Scans the ucode packages in this feed. ucode template files (`.nft.uc`, or
 * any file whose first line is the template-open marker `{%`) are skipped —
 * they are not ECMAScript.
 *
 * Usage: node scripts/uc-lint.mjs
 */
import { readFileSync, statSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

/* package relative dirs that hold `.uc` sources (scanned recursively) */
const roots = [
	'prometheus-node-exporter-ucode/files',
	'prometheus-node-exporter-ucode/test',
	'rpcd-mod-bird/src',
	'rpcd-mod-bird/test',
	'inotify-rsync/files',
	'vpn-sticky/files',
];

let failed = 0;

function err(file, msg) {
	console.error(`[uc-lint] ${file}: ${msg}`);
	failed = 1;
}

function warn(file, msg) {
	console.warn(`[uc-lint] ${file}: warning: ${msg}`);
}

/* recursively collect `.uc` candidates, skipping template files */
function collect(dir, out) {
	for (const name of readdirSync(dir)) {
		const p = path.join(dir, name);
		if (statSync(p).isDirectory()) {
			collect(p, out);
			continue;
		}
		if (!name.endsWith('.uc'))
			continue;
		if (name.endsWith('.nft.uc'))
			continue;
		let first = readFileSync(p, 'utf8').split('\n').find((l) => l.trim() != '' && !l.startsWith('#!'));
		if (first != null && first.includes('{%'))
			continue;
		out.push(p);
	}
}

function lintFile(file) {
	const src = readFileSync(file, 'utf8');

	// 1) ESM syntax via node's parser. ucode's `function name;` /
	//    `export function name;` forward-declaration (ucode docs §4.2) is not
	//    valid ECMAScript, so strip those lines first. The collector scripts use
	//    ucode's top-level `return` (valid ucode, not ECMAScript), so after
	//    removing imports / `export` prefixes / a shebang the body is wrapped in
	//    a function — this still catches real syntax errors (unbalanced braces,
	//    bad tokens) while tolerating ucode's script-mode idiom.
	const syntaxSrc = 'function __uc_check__() {\n' +
		src.replace(/^(?:export\s+)?function\s+[A-Za-z_$][\w$]*\s*;\s*$/gm, '')
		   .replace(/^[ \t]*import\b.*$/gm, '')
		   .replace(/^[ \t]*export[ \t]+/gm, '')
		   .replace(/^(#![^\n]+\n?)?/, '')
		   /* ucode `for (k, v in obj)` iterates keys+elements; not valid
		    * ECMAScript, so collapse the second binding for the parse pass */
		   .replace(/for\s*\(\s*(?:let\s+)?([A-Za-z_$][\w$]*)\s*,\s*[A-Za-z_$][\w$]*\s+in\s+/g, 'for (let $1 in ')
		   .replace(/for\s*\(\s*([A-Za-z_$][\w$]*)\s*,\s*[A-Za-z_$][\w$]*\s+in\s+/g, 'for ($1 in ') +
		'\n}\n';
	const r = spawnSync(process.execPath, ['--input-type=module', '--check'], {
		input: syntaxSrc,
		encoding: 'utf8',
	});
	if (r.status !== 0)
		err(file, `syntax:\n${r.stderr}`);

	// 2) ucode-specific rules
	// 2a) `export function foo(){...}` must be terminated with `;`. Brace
	//     matching is token-aware (skips comments / strings / templates) so
	//     `{ ... }` inside docs or regexes cannot throw the count off.
	const endOfExport = (src, open) => {
		let i = open;
		let depth = 1;
		while (i < src.length) {
			const c = src[i];
			if (c === '"' || c === "'" || c === '`') {
				const q = c;
				i++;
				while (i < src.length) {
					if (src[i] === '\\') { i += 2; continue; }
					if (src[i] === q) { i++; break; }
					i++;
				}
				continue;
			}
			if (c === '/' && src[i + 1] === '/') {
				while (i < src.length && src[i] !== '\n') i++;
				continue;
			}
			if (c === '/' && src[i + 1] === '*') {
				i += 2;
				while (i + 1 < src.length && !(src[i] === '*' && src[i + 1] === '/' )) i++;
				i += 2;
				continue;
			}
			if (c === '{') depth++;
			else if (c === '}') depth--;
			if (depth === 0)
				return i + 1;
			i++;
		}
		return -1;
	};
	for (const m of src.matchAll(/export function\s+\w+\s*\([^)]*\)\s*\{/g)) {
		const end = endOfExport(src, m.index + m[0].length);
		if (end < 0 || src[end] !== ';')
			err(file, `export function not terminated with ';': ${m[0].replace(/\s+/g, ' ')}`);
	}
	// 2b) arrays use the global form push(arr,...), not arr.push(...)
	for (const line of src.split('\n')) {
		if (/\.\s*(push|pop|map|filter|shift|unshift|join|slice)\s*\(/.test(line))
			err(file, `array method must be global (e.g. push(arr,...)): "${line.trim()}"`);
	}

	// 2c) strings are not []-indexable in ucode (use substr(s,i,1) / ord(s,i)).
	//     Static heuristic: a variable is "string-typed" if an initializer is a
	//     string literal / sprintf / substr / readfile / getenv / template
	//     literal, and it is never assigned an array/object. Only flag []-index
	//     on such string-typed vars, plus direct literal indexing.
	const stringVars = new Set();
	const arrayOrObjVars = new Set();
	const initRe = /^\s*(?:let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*(.*)$/;
	for (const line of src.split('\n')) {
		const m = line.match(initRe);
		if (!m)
			continue;
		const [, id, rhs] = m;
		if (/^['"`]|^sprintf\s*\(|^substr\s*\(|^readfile\s*\(|^getenv\s*\)|^getenv\s*\(|^\`/.test(rhs))
			stringVars.add(id);
		if (/^\[|^\{|^ctx\.get\s*\(|^struct\.unpack\s*\(|^parse_key\s*\(|^parse_value\s*\(|^flows\s*\(|^filter\s*\(|^map\s*\(/.test(rhs))
			arrayOrObjVars.add(id);
	}
	src.split('\n').forEach((line, ln) => {
		if (line.match(/(?:'[^'\\]*(?:\\.[^'\\]*)*'|"[^"\\]*(?:\\.[^"\\]*)*")\s*\[/))
			err(file, `string literal is not []-indexable (line ${ln + 1})`);
		for (const id of stringVars) {
			if (arrayOrObjVars.has(id))
				continue;
			if (new RegExp(`\\b${id}\\s*\\[`).test(line))
				err(file, `'${id}' is a string and not []-indexable (line ${ln + 1}): "${line.trim()}"`);
		}
	});

	// 2d) forward-declared exports: warn that the target (OpenWrt) ucode does not
	//     support `export function name;`, and require a matching definition.
	const defnOf = (name) =>
		new RegExp(`export\\s+function\\s+${name}\\s*\\(`).test(src);
	for (const m of src.matchAll(/^export\s+function\s+([A-Za-z_$][\w$]*)\s*;\s*$/gm)) {
		warn(file, `forward-export declaration 'export function ${m[1]};' is not supported by the target (OpenWrt) ucode; prefer declare-before-use`);
		if (!defnOf(m[1]))
			err(file, `forward-declared export '${m[1]}' has no matching definition`);
	}
	// 2e) a plain `function name;` must not shadow a later `export function name`.
	for (const m of src.matchAll(/^function\s+([A-Za-z_$][\w$]*)\s*;\s*$/gm)) {
		if (new RegExp(`export\\s+function\\s+${m[1]}\\s*\\(`).test(src))
			err(file, `plain forward declaration 'function ${m[1]};' would shadow the exported '${m[1]}'`);
	}
}

for (const root of roots) {
	const dir = path.join(repoRoot, root);
	if (!statSync(dir, { throwIfNoEntry: false }))
		continue;
	const files = [];
	collect(dir, files);
	for (const file of files)
		lintFile(file);
}

if (failed)
	process.exit(1);
console.log('[uc-lint] all modules OK');