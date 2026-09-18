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

```
location /api {
    ucode_content /www/api.ut;
    ucode_methods GET POST DELETE;
}
```

`ucode_methods <method> ...` restricts which HTTP methods are wired to the
template in this location (it **replaces** the default set). Any method not
listed is answered with `405 Method Not Allowed` and an `Allow:` header.

By default (no `ucode_methods`) only the safe read methods `GET`, `HEAD` and
`OPTIONS` are handled. Body-bearing methods — `POST`, `PUT`, `DELETE`, `PATCH`,
… — must be explicitly enabled, since they are the only ones that can carry
JSON payloads, form submissions and file uploads. This keeps upload and body
handling opt-in rather than enabled by default.

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
| `request.body`        | raw request body as a string (empty when there is no body) |
| `request.json`        | parsed `application/json` (or `*+json`) body, if valid |
| `request.form`        | form fields, name → array of values (from `application/x-www-form-urlencoded` and `multipart/form-data`) |
| `request.files`       | multipart file uploads, name → array of `{ name, filename, content_type, data, size }` |

`request.form` / `request.files` always collect values in an array (mirroring
`request.headers`) so repeated fields and multi-file uploads stay lossless. A
multipart file entry has `data` (the binary file contents) plus `size`, and the
regular fields of a multipart request land in `request.form`.

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

### JSON API with POST

```ucode
{%
// request.json is the parsed application/json body (or null)
let name = request.json && request.json.name ? request.json.name : null;
if (!name) {
    response.status(400);
    response.set_header("Content-Type", "application/json; charset=utf-8");
    print("{\"error\":\"name is required\"}");
    return;
}
response.set_header("Content-Type", "application/json; charset=utf-8");
print("{\"hello\":\"" + name + "\"}");
%}
```

## Notes

- The template is **recompiled on every request**, so edits are picked up
  immediately — no `angie` reload needed.
- The template runs synchronously in the worker process. Fine for low-traffic
  pages; a long-running template blocks that worker. The request body (if any)
  is read fully into memory before the template runs, bounded by
  `client_max_body_size`.
- Requires `libucode` and `libjson-c` (OpenWrt shared libraries), selected
  automatically.

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
behaviour (syntax compile + behaviour assertions) without needing an
Angie build.

### Rendering a template standalone

`angie/ucode-module/test/angie-ucode-test.uc` is a `#!/usr/bin/ucode` tool that
renders any `.ut` template the way angie would, mocking the request globals and
printing the simulated status/headers/body. It is handy for iterating on a
template without booting a server:

```sh
angie-ucode-test -- --method GET --uri /profiles \
    --header "X-Username: home" angie/ucode-module/examples/profiles.ut

angie-ucode-test -- --method POST --content-type application/json \
    --json '{"name":"vovan"}' myapi.ut
```

`--data` parses a urlencoded body into `request.form`; `--json` parses into
`request.json`. (The `--` separator is required so ucode's own getopt does not
consume the tool's options.)