# Hosting ucode HTTP handlers in this feed

How each HTTP host used by this feed executes ucode, and the resulting
decision to keep `prometheus-node-exporter-ucode` on its own jailed `uhttpd`
instance rather than moving it to `uwsd`.

Line references are against the versions built at the time of writing:
`uhttpd 2026.06.16~7b1bec45`, `uwsd 20260910` (`uwsd/Makefile`). They are
anchors for re-verification, not API guarantees.

## Summary

| Host | Handler compiled | Top-level run | Per HTTP request | Isolation |
|------|------------------|---------------|------------------|-----------|
| `uhttpd-mod-ucode` | once at startup | once at startup | `fork()`, no `exec`; reuses compiled VM via COW | process per request |
| `uwsd` run-script | once per backend worker | once per backend worker | none (event loop in the worker) | worker process per backend |
| `angie-mod-ucode` (legacy) | every request | every request | fresh VM, in-process | shares the angie worker |

## uhttpd-mod-ucode

The exporter registers `metrics.uc` as a `-O <prefix>` ucode handler
(`prometheus-node-exporter-ucode/files/init:32`).

**Startup** (`uh_ucode_state_init()`, `uhttpd/ucode.c:224-317`): one VM is
created (`uc_vm_init`, `:234`), the `uhttpd` API table is injected as a global
(`:247`), the handler file is compiled **once** (`uc_compile`, `:258`) and its
top-level is executed **once** (`uc_vm_execute`, `:280`) so it can register
`handle_request` (`:303`). For `metrics.uc` this is where the collector
discovery loop runs: `fs.lsdir()` + `loadfile()` per collector
(`metrics.uc:196-227`).

**Per request** (`ucode_handle_request()` → `uh_create_process()`,
`uhttpd/proc.c:330-368`): a bare `fork()` (`:348`) with **no `exec`**; the
child reuses the compiled VM and the already-loaded `collectors` table via
copy-on-write, invokes `handle_request(env)` (through `ucode_main()`,
`ucode.c:319-375`), then `exit(0)`.

So the script is **not** recompiled and the collectors are **not** reloaded per
request — only a process is forked.

### Handler contract

An uhttpd ucode handler is expected to define `global.handle_request(env)` and
emit output through the injected `uhttpd` object:

- `uhttpd.send(...)` / `uhttpd.recv()` / `uhttpd.urlencode()` / `uhttpd.urldecode()`
- the response is a CGI-style block: `Status: <code> <reason>` and
  `Content-Type: ...` lines terminated by a blank line, then the body
  (`metrics.uc:94-96`).

The conventional CLI fallback is `if (!("uhttpd" in global)) { ... }`
(`metrics.uc:231-241`), which runs the handler with `ARGV`-derived arguments and
prints to stdout so the same file can be run by hand or via `run.sh`.

## uwsd run-script

A `run-script` backend is a ucode module exporting
`onConnect` / `onData` / `onRequest` / `onBody` / `onClose`.

**Startup**: at server startup uwsd `fork()`s and `execl()`s itself once per
backend (`script_context_start()`, `uwsd/script.c:2256-2327`) into a worker.
The worker (`script_context_run()`, `uwsd/script.c:2149`) builds a **single
persistent VM** (`uc_vm_init`, `:2175`), compiles the handler once through a
generated bootstrap (`import * as cb from '<script>'`, `:2160-2171`) and
dispatches events on its `uloop`.

**Per request**: no fork, no compile — the worker calls the module's callbacks
directly. Response API:

- `request.reply(headers[, body])` — builds the full HTTP response
  (`uc_script_reply()`, `uwsd/script.c:1168-1296`), including status line and
  `Content-Length`.
- `request.send(data)` — writes **raw bytes** to the socket
  (`uc_script_send()`, `uwsd/script.c:892-938`); use `reply()` for a normal
  response.

`uwsd/files/utpl-wrapper.uc` is an example run-script handler: it injects a
`request` / `response` / `uhttpd` scope and renders `.ut` templates with a
compiled-template cache.

## angie-mod-ucode (legacy)

This was the first attempt at embedding ucode in this feed and is retained only
for in-process embedding; `angie/README.md` already marks it legacy and
recommends `uwsd`. It runs as an in-process angie content handler and creates a
**fresh VM per request**, recompiling the template every time
(`angie/ucode-module/ngx_http_ucode_module.c:1140`, `:1223`, `:1492`, `:1514`),
which blocks the angie worker for the duration of the request.

## Decision: the node exporter stays on its own jailed uhttpd

Moving the exporter to `uwsd` was evaluated and rejected:

- The only gain is skipping one `fork()` per scrape. There is **no**
  compile/reload saving to recover: under uhttpd the collectors are already
  loaded once at startup and inherited by the forked child via COW.
- Scrapes are infrequent (typically every 15–60s), so the per-request fork cost
  is noise.
- `uhttpd` stays in the image for LuCI regardless, so there is no package or
  flash saving, and keeping the exporter on its own jailed uhttpd instance stays
  close to the upstream OpenWrt packaging.

A persistent-VM host would only pay off at high scrape frequency or with many
exporters per host, and even then the win is small.

## Porting gotchas: uhttpd handler → uwsd

If an uhttpd ucode handler is ever adapted to run under a uwsd run-script host,
watch for these:

- `call(fn, null, scope)` makes `scope` the function's **global environment**
  (its prototype is the current global scope). A handler whose only self-run
  path is the CLI fallback (`if (!("uhttpd" in global))`) will therefore see
  `"uhttpd" in global` as **true**, silently register `handle_request`, and emit
  nothing unless the host explicitly invokes it.
- `utpl-wrapper.uc` cannot serve such a handler directly: `resolve_template()`
  accepts only `.ut` paths (`uwsd/files/utpl-wrapper.uc:320-321`), its injected
  `uhttpd` object has no `send` (`:632-638`), and it never calls
  `handle_request`. A dedicated run-script handler that drives `handle_request`
  and converts the CGI block to `request.reply()` is the workable path.
- `metrics.uc`'s CLI mode ignores `QUERY_STRING` and builds `collect=` arguments
  from `ARGV` (`metrics.uc:238`); a CGI-style bridge that relies on the query
  string needs that adjusted.
