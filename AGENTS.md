# AGENTS.md

Guidance for AI coding agents working in this repository.

## Hard rules

- **Never run `./scripts/feeds clean` or delete the `feeds/` directory.** It
  wipes the feed clone including unpushed commits and uncommitted work. To
  apply openwrt feed changes use `./scripts/feeds update <feed>` /
  `./scripts/feeds install -a -p <feed>` instead.

## Project

`vooon` — a personal OpenWrt package feed (`src-git vooon
https://github.com/vooon/my-openwrt-feed.git`). Packages are compiled by the
OpenWrt build system; this repo carries no build system of its own. CI
(`.github/workflows/ci.yml`) validates the packages that ship **ucode** code —
`.uc` collector/daemon scripts and C `ucode-mod-*` plugin modules — against a
pinned upstream ucode build.

## ucode packages in this feed

- `prometheus-node-exporter-ucode/` — Prometheus node exporter rewritten in
  ucode. Collectors in `files/base/` and `files/extra/`, entry template in
  `files/metrics.uc`, self-contained regression tests in `test/`
  (`test/<name>.uc`), run with `test.sh`. Each collector is `loadfile()`d with
  `raw_mode: true` and mocked `ubus`/`uci`/`gauge`/`counter`/`fs`/`raw`.
  Tests are run from the package dir with `UCODE`/`UCODE_MODULES` set.
- `rpcd-mod-bird/` — BIRD control-socket ubus rpcd plugin. `src/bird.uc`
  (imports `socket`/`log`/`fs` + the pure `./birdconfig.uc`), and the pure
  BIRD-config editor/parser `src/birdconfig.uc`. Unit tests in `test/`
  (`birdconfig.test.uc` + fixtures + goldens), run with `run_tests.sh`
  (`UCODE` / `UCODE_MODULE_PATH`).
- `ucode-mod-inotify/` — C ucode module wrapping the Linux inotify API
  (`src/inotify.c`, cmake). Built in CI against the pinned ucode headers and
  exercised with `test/inotify.uc` (real kernel round-trip).
- `inotify-rsync/` — `files/inotify-rsync.uc`: `require()`-based daemon script
  (fs/uloop/uci/log/inotify), run by `files/inotify-rsync.init`.
- `vpn-sticky/` — `files/vpn-sticky.nft.uc`: a ucode **nft template** (raw text
  + `{% %}` blocks), compiled with `ucode -T`.

## CI checks (see `.github/workflows/ci.yml`)

```sh
# ucode lint: ucode-lsp CLI checker (type inference, flow analysis,
# null-safety, unused imports, version gating to target 25.12). Pinned
# ucode-lsp version; runs first.
node scripts/uc-lint.mjs

# pinned ucode + upstream modules (OpenWrt 25.12 revision), cached.
# Composite action: .github/actions/build-ucode (outputs bin/mods/inc).
sh scripts/build-ucode.sh /tmp/ucode-build

# syntax-check every tracked *.uc file without executing it:
#   raw scripts:    strip import lines + `export` prefix, then `ucode -c`
#   template files (file starts with `{%`, e.g. metrics.uc, *.nft.uc):
#       strip as above, then `ucode -T -c`
# (ucode resolves imports at compile time; the OpenWrt modules uci/ubus/... are
#  not in the upstream tree, hence the stripping. `-c` writes the bytecode to
#  `-o <file>`, else it would clobber a `./uc.out` in the cwd.)

# unit tests (upstream modules on the module path):
UCODE=.../ucode UCODE_MODULES=... prometheus-node-exporter-ucode/test.sh
UCODE=.../ucode UCODE_MODULE_PATH=... rpcd-mod-bird/test/run_tests.sh

# C plugin:
cmake -S ucode-mod-inotify/src -B ... -Ducode_include_dir=$UCODE_SRC/include
cmake --build ...
ucode -L <mods+inotify.so> ucode-mod-inotify/test/inotify.uc
```

Run the tests locally against a build ("UCODE_MODULES" vs "UCODE_MODULE_PATH" is
the env var each runner expects; point them at the build dir with the `*.so`s).

## ucode-lsp lint conventions

`scripts/uc-lint.mjs` drives `ucode-lsp` (pinned `0.8.11`) with
`--target-version 25.12` over the maintained ucode packages:
`rpcd-mod-bird`, `inotify-rsync/files`, `vpn-sticky/files`,
`ucode-mod-inotify/test`. (`prometheus-node-exporter-ucode` is deliberately
excluded — its collectors run as raw-mode scripts with runtime-injected
globals that static analysis can't see.)

To keep the linter green, follow these conventions (mirroring the
community.openwrt collection):

- **Annotate function parameters/returns with multi-line JSDoc** (`/** … */`)
  merged with the descriptive comment — one JSDoc block per function, not a
  `/* */` description next to a `/** */` annotation. This is what makes
  ucode-lsp narrow argument types (e.g. `@param {string}` silences
  `incompatible-function-argument`).
- **`split()`/array element access yields nullable elements** in ucode-lsp's
  model (even after a `length()` guard). Either capture into a local with an
  explicit `if (x == null) …` guard, or use a targeted
  `// ucode-lsp disable-next-line <CODE>   # reason` suppression when the
  element is guaranteed present. Prefer real guards for production code;
  `disable-next-line` is fine for tests/fixtures.
- **The `|null` union on a `@typedef` reference is not resolved** by ucode-lsp
  0.8.11 (e.g. `@returns {Prefix|null}` → `UC7001 Unknown type`). Declare
  `@returns {Prefix}` and guard null at call sites, or accept the
  `UC7005` warning.
- **`match()` result capture groups are `string|null`** and `m[1]` etc. need a
  guard or suppression when reused across different regexes (reusing one `m`
  for two regexes also loses the capture-group count → `UC5008`).
- **ucode-lsp enforces the ucode-only pitfalls** (`export function foo(){…};`
  trailing `;` → UC6005, forward-declaration shadowing → UC1007) that the old
  node-based linter checked manually, so they need no separate rule.

## ucode (the agent language) is NOT JavaScript

ucode is ECMAScript-inspired but is a distinct language with a smaller
standard library. Do not assume JS features. Write code against the official
docs, which are authoritative:

- **Language/tutorials:** https://ucode.mein.io (Usage, Syntax, Memory,
  Arrays, Dictionaries tutorials)
- **Core module:** https://ucode.mein.io/module-core.html
- **Log:** https://ucode.mein.io/module-log.html
- **Struct:** https://ucode.mein.io/module-struct.html
- **UCI:** https://ucode.mein.io/module-uci.html
- **Ubus:** https://ucode.mein.io/module-ubus.html
- **Uloop:** https://ucode.mein.io/module-uloop.html

Known non-JS gotchas that have already bitten this project:

- **`export function foo(){…}` must end with `;` in a `.uc` module** (this ucode
  parses the export as an expression statement, so `export function f(){};`).
  Import with `import { foo } from './foo.uc'` (relative path, like
  node-exporter's `import { fetch_json } from '../http_client.uc'`).
- **No function hoisting.** A function declared later in the file is undefined
  when called earlier. Declare before use, or assign at the bottom near `main()`.
  Do **not** use ucode's `function name;` forward-declaration (docs §4.2) for an
  exported function: OpenWrt's shipped ucode lacks the export form, and a plain
  `function x;` shadows the later `export function x` and silently stops the
  module exporting it. Order definitions before use instead.
- **No `arr.push()` / `arr.map()` etc. as methods.** Arrays use *global*
  functions: `push(arr, …)`, `filter(arr, fn)`, `map(arr, fn)`, `pop(arr)`.
- **No string `[]` indexing.** `s[i]` raises `left-hand side expression is not an
  array or object`. Use `substr(s, i, 1)` or `ord(s, i)` to read a character.
- **`for (x in arr)` yields elements, not indices** (on objects it yields keys).
  Use `for (item in arr)` directly when you want the elements; iterate
  `i = 0..length(arr)-1` only when you need the index. `for (k, v in obj)` (two
  bindings) yields keys + elements — valid ucode, invalid ECMAScript.
- **No `throw` statement** (there is `try`/`catch`; use `die()` to raise).
- **No `RegExp` / `new RegExp`.** Use `regexp(source, flags)` plus `match(str, re)`,
  or the built-in `wildcard(subject, pattern[, nocase])` (fnmatch-based glob) for
  simple glob/pattern matching.
- **No `{const x} = y` / `for (const i in …)`** — no `const` in loop heads; use
  `let`.
- **No implicit adjacent-string concatenation** (`'a' 'b'` is invalid) — use `+`.
- **Object iteration**: `for (let k in obj)` gives keys; `keys(obj)` also works.
  `for..in` over an object value that is actually null/other throws — guard first.
- Undefined identifiers raise runtime "left-hand side is not a function"-style
  errors, and `import` resolution needs the `ucode-mod-*` `.so` present (so a
  CLI `ucode -c` syntax check requires stubbing/stripping imports — see CI).
- **uci option values are strings.** Parse explicitly: `int(ctx.get('cfg',
  'main', 'x'))` for a number, and for a bool use `int()`/explicit truthy
  (`v == '1' && v`). List options (`list device …`) return an array.
- **`fs`, `log`, `socket`, `struct`, `math`, `uloop`, `regexp`, …** are
  `require()`-able module objects, e.g. `log.ulog_open(...)`,
  `log.NOTE(...)`, `fs.readfile`, `inotify.add(fd, path, 'wDMndc')`. A script
  `require()`s them (`require("fs")`), a module `import {}`s from them.
- Raw-mode collector scripts use a **top-level `return`** (`return false;`) to
  signal failure — that idiom is ucode-only and not valid ECMAScript.

When in doubt, check the docs rather than assuming ECMAScript semantics.

## Testing (see also `.github/workflows/ci.yml`)

- **node-exporter collector tests** (`test/<name>.uc` + `test.sh`): each test
  mocks the collector's dependencies with plain ucode objects, `loadfile()`s
  the collector from `files/extra/` with `raw_mode: true` and asserts the
  emitted metric set. Fixtures live under `test/`.
- **rpcd-mod-bird unit tests** (`test/run_tests.sh` + `birdconfig.test.uc`):
  fixture BIRD configs vs golden `expected/` files; asserts byte-exact edits,
  idempotency, round trips and parser edge cases. Pure, no sockets.
- **inotify smoke test** (`ucode-mod-inotify/test/inotify.uc`): real kernel
  round-trip through the built interpreter and module — requires a Linux host.