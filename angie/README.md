# angie-mod-ucode

Execute OpenWrt **ucode templates** as [Angie](https://angie.software/) HTTP
content handlers — the same request-driven templating uhttpd does, but in
process. No uwsgi/CGI worker, no `uhttpd`; just point a location at a `.ut`
template and it renders a page per request.

Packaged as `angie-mod-ucode`, built as an Angie dynamic module and loaded via
`load_module` from `module.d/`.

## Directive

```
location /profiles {
    ucode_content /www/vpn/profiles.ut;
}
```

`ucode_content <file>` sets the content handler for a location to run the given
ucode template. The file is read and compiled per request.

## Template API

The template top-level runs once per request. Body output comes from `print()`
and `{{ ... }}`; header lines printed first are handled as CGI (see below).

### `request` — request object

| key | value |
|-----|-------|
| `request.method`      | HTTP method (`GET`, …) |
| `request.uri`         | raw request URI (path + query) |
| `request.query`       | query string (no leading `?`) |
| `request.script_name` | location URI |
| `request.remote_addr` | client address |
| `request.protocol`    | `HTTP/1.1`, … |
| `request.headers.<Name>` | array of all values for that header (e.g. `request.headers["X-Request-Id"][0]`); repeated headers are preserved |

The classic CGI variables are also available as top-level globals:
`REQUEST_METHOD`, `REQUEST_URI`, `QUERY_STRING`, `SCRIPT_NAME`,
`REMOTE_ADDR`, `SERVER_PROTOCOL`.

### `response` — response object

| call | effect |
|------|--------|
| `response.status(code[, phrase])` | set HTTP status; optional custom reason phrase (e.g. `response.status(418, "I'm a Teapot")`) |
| `response.set_header(name, value)` | set a header, replacing any previous value of the same name |
| `response.add_header(name, value)` | append another value (response gets multiple `Name:` lines, e.g. several `Set-Cookie`) |

`Content-Type`, `Content-Length` and `Location` are handled specially
(single-valued regardless of `set_header`/`add_header`).

### `uhttpd` — legacy helpers

`uhttpd.urlencode(s)` / `uhttpd.urldecode(s)` mirror the uhttpd API.

### CGI-style fallback

For templates written the uhttpd way, header lines printed at the very start of
the output (`Content-Type: …`, `Status: …`, `X-…: …`) are applied to the
response and stripped from the body. Values set via the `response` object take
precedence. Default content type is `text/html; charset=utf-8` if neither is
set.

## Example

```ucode
{%
let user = request.headers["X-Username"] ? request.headers["X-Username"][0] : null;

if (!user || user == "guest") {
    response.status(401, "Authentication required");
    response.set_header("WWW-Authenticate", "Basic realm=\"vpn\"");
    return;
}
%}
<h1>Hello {{ user }}</h1>
```

See `examples/profiles.ut` for a fuller example (per-user VPN profile listing).

## Notes

- The template is **recompiled on every request**, so edits are picked up
  immediately — no `angie` reload needed.
- The template runs synchronously in the worker process. Fine for low-traffic
  pages; a long-running template blocks that worker.
- Requires `libucode` (OpenWrt's shared ucode library), selected automatically.

## Building

```
CONFIG_PACKAGE_angie-mod-ucode=y
```

Builds inside the `angie` package (`--add-dynamic-module`) and installs:

- `/usr/lib/angie/modules/ngx_http_ucode_module.so`
- `/etc/angie/module.d/ngx_http_ucode.module` (the `load_module` line)

Reloading (`/etc/init.d/angie reload`) re-loads the module and picks up
`module.d` changes automatically via procd.

## Testing

```
UCODE=…/ucode UCODE_MODULES=… angie/ucode-module/test/run_tests.sh
```

Mocks `request`/`response`/`uhttpd` and asserts the example template's
behaviour (syntax compile + 401 vs. allowed rendering) without needing an
Angie build.