/*
 * ngx_http_ucode_module - execute ucode templates as angie/nginx content
 * handlers, mirroring the OpenWrt uhttpd style of request-driven ucode
 * templating.
 *
 * Copyright (C) 2026 Vladimir Ermakov <vooon341@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#include <ctype.h>
#include <strings.h>

#include <ucode/compiler.h>
#include <ucode/lib.h>
#include <ucode/source.h>
#include <ucode/vm.h>

typedef struct {
    ngx_str_t   file;
} ngx_http_ucode_loc_conf_t;

#define NGX_HTTP_UCODE_RESP_TYPE  "http_response"

typedef struct {
    ngx_http_request_t *r;
} ngx_http_ucode_res_t;

static ngx_int_t ngx_http_ucode_handler(ngx_http_request_t *r);

static char *ngx_http_ucode_content(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static void *ngx_http_ucode_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_ucode_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);

static ngx_int_t ngx_http_ucode_init(ngx_conf_t *cf);

/* ------------------------------------------------------------------------- */

static ngx_command_t ngx_http_ucode_commands[] = {

    { ngx_string("ucode_content"),
      NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
      ngx_http_ucode_content,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

      ngx_null_command
};

static ngx_http_module_t ngx_http_ucode_module_ctx = {
    NULL,                            /* preconfiguration */
    ngx_http_ucode_init,             /* postconfiguration */
    NULL,                            /* create main configuration */
    NULL,                            /* init main configuration */
    NULL,                            /* create server configuration */
    NULL,                            /* merge server configuration */
    ngx_http_ucode_create_loc_conf,  /* create location configuration */
    ngx_http_ucode_merge_loc_conf    /* merge location configuration */
};

ngx_module_t ngx_http_ucode_module = {
    NGX_MODULE_V1,
    &ngx_http_ucode_module_ctx,      /* module context */
    ngx_http_ucode_commands,         /* module directives */
    NGX_HTTP_MODULE,                 /* module type */
    NULL,                            /* init master */
    NULL,                            /* init module */
    NULL,                            /* init process */
    NULL,                            /* init thread */
    NULL,                            /* exit thread */
    NULL,                            /* exit process */
    NULL,                            /* exit master */
    NGX_MODULE_V1_PADDING
};

/* ------------------------------------------------------------------------- */

/*
 * ucode API helpers exposed to templates through the "uhttpd" global
 * object, mirroring uhttpd.  send()/recv() are omitted because this runs
 * in-process and the real stdin/stdout belong to the nginx process.
 */

static int
ngx_http_ucode_urldecode(char *dst, size_t dst_size, const char *src,
    size_t src_len)
{
    size_t i, o = 0;
    int hi, lo;

    for (i = 0; i < src_len && o < dst_size - 1; i++) {
        if (src[i] == '%' && i + 2 < src_len &&
            (hi = ngx_hextoi((u_char *) (src + i + 1), 2)) >= 0) {
            dst[o++] = (char) hi;
            i += 2;
        } else if (src[i] == '+') {
            dst[o++] = ' ';
        } else {
            dst[o++] = src[i];
        }
    }

    dst[o] = 0;

    return (int) o;
}

static int
ngx_http_ucode_urlencode(char *dst, size_t dst_size, const char *src,
    size_t src_len)
{
    static const char hex[] = "0123456789abcdef";
    size_t i, o = 0;

    for (i = 0; i < src_len && o < dst_size - 3; i++) {
        u_char c = (u_char) src[i];

        if (isalnum((u_char) c) || c == '-' || c == '_' || c == '.' || c == '~') {
            dst[o++] = (char) c;
        } else {
            dst[o++] = '%';
            dst[o++] = hex[c >> 4];
            dst[o++] = hex[c & 0x0f];
        }
    }

    dst[o] = 0;

    return (int) o;
}

static uc_value_t *
ngx_http_ucode_strconvert(uc_vm_t *vm, size_t nargs,
    int (*convert)(char *, size_t, const char *, size_t))
{
    uc_value_t *val = uc_fn_arg(0);
    static char out[4096];
    int out_len;

    if (ucv_type(val) == UC_STRING) {
        out_len = convert(out, sizeof(out), ucv_string_get(val),
                          ucv_string_length(val));
    } else if (val != NULL) {
        char *p = ucv_to_string(vm, val);
        out_len = p ? convert(out, sizeof(out), p, strlen(p)) : 0;
        free(p);
    } else {
        out_len = 0;
    }

    if (out_len < 0) {
        uc_vm_raise_exception(vm, EXCEPTION_RUNTIME,
                              "URL conversion error");
        return NULL;
    }

    return ucv_string_new_length(out, out_len);
}

static uc_value_t *
ngx_http_ucode_urlencode_fn(uc_vm_t *vm, size_t nargs)
{
    return ngx_http_ucode_strconvert(vm, nargs, ngx_http_ucode_urlencode);
}

static uc_value_t *
ngx_http_ucode_urldecode_fn(uc_vm_t *vm, size_t nargs)
{
    return ngx_http_ucode_strconvert(vm, nargs, ngx_http_ucode_urldecode);
}

/*
 * Response object ("response") methods, exposed to templates as a resource
 * so the cfunctions can be type-checked with uc_fn_thisval().  Templates set
 * the HTTP status and arbitrary response headers through these; the rendered
 * body comes from print()/{{ }} output.
 */

static void
ngx_http_ucode_res_strcopy(ngx_pool_t *pool, ngx_str_t *dst, const char *src, size_t len)
{
    dst->len = len;
    dst->data = ngx_pnalloc(pool, len + 1);

    if (dst->data) {
        ngx_memcpy(dst->data, src, len);
        dst->data[len] = '\0';
    }
}

static uc_value_t *
ngx_http_ucode_res_status(uc_vm_t *vm, size_t nargs)
{
    ngx_http_ucode_res_t *resp = uc_fn_thisval(NGX_HTTP_UCODE_RESP_TYPE);
    uc_value_t *code = uc_fn_arg(0);
    uc_value_t *phrase = uc_fn_arg(1);
    ngx_uint_t status;

    if (!resp || !code)
        return NULL;

    status = (ngx_uint_t) ucv_to_integer(code);
    resp->r->headers_out.status = status;

    if (phrase && ucv_type(phrase) != UC_NULL) {
        char *p = ucv_to_string(vm, phrase);
        ngx_str_t sl;
        size_t plen = p ? strlen(p) : 0;

        sl.len = 4 + plen; /* "418 " + phrase */
        sl.data = ngx_pnalloc(resp->r->pool, sl.len + 1);

        if (sl.data) {
            ngx_snprintf(sl.data, sl.len + 1, "%ui %s",
                         (ngx_uint_t) status, p ? p : "");
            resp->r->headers_out.status_line = sl;
        }

        free(p);
    }

    return NULL;
}

static void
ngx_http_ucode_res_header_special(ngx_http_request_t *r, char *nv, char *vv)
{
    if (strcasecmp(nv, "Content-Type") == 0) {
        ngx_http_ucode_res_strcopy(r->pool, &r->headers_out.content_type,
                                   vv, strlen(vv));
    } else if (strcasecmp(nv, "Content-Length") == 0) {
        off_t len = ngx_atosz((u_char *) vv, strlen(vv));

        if (len >= 0)
            r->headers_out.content_length_n = len;
    } else if (strcasecmp(nv, "Location") == 0) {
        ngx_table_elt_t *he = ngx_list_push(&r->headers_out.headers);

        if (he) {
            he->key.data = (u_char *) "Location";
            he->key.len = sizeof("Location") - 1;
            ngx_http_ucode_res_strcopy(r->pool, &he->value, vv, strlen(vv));
            he->hash = 1;
            r->headers_out.location = he;
        }
    }
}

/*
 * set_header(name, value): replace any previously set header of the same
 * name.  add_header(name, value): append an additional value (the response
 * will contain multiple "Name:" lines).
 */
static uc_value_t *
ngx_http_ucode_res_header_internal(uc_vm_t *vm, size_t nargs, bool replace)
{
    ngx_http_ucode_res_t *resp = uc_fn_thisval(NGX_HTTP_UCODE_RESP_TYPE);
    uc_value_t *nameval = uc_fn_arg(0);
    uc_value_t *valval = uc_fn_arg(1);
    char *nv, *vv;
    ngx_http_request_t *r;
    ngx_table_elt_t *he;
    ngx_list_part_t *part;
    ngx_uint_t i;

    if (!resp || !nameval || !valval)
        return NULL;

    r = resp->r;

    nv = ucv_to_string(vm, nameval);
    vv = ucv_to_string(vm, valval);

    if (!nv || !vv) {
        free(nv);
        free(vv);
        return NULL;
    }

    if (strcasecmp(nv, "Content-Type") == 0 ||
        strcasecmp(nv, "Content-Length") == 0 ||
        strcasecmp(nv, "Location") == 0) {
        ngx_http_ucode_res_header_special(r, nv, vv);
        free(nv);
        free(vv);
        return NULL;
    }

    if (replace) {
        /* drop any existing header of the same name (hash == 0 is skipped
         * by the header filter, so we can re-use the entry below) */
        part = &r->headers_out.headers.part;
        he = part->elts;

        for (i = 0; /* void */; i++) {
            if (i >= part->nelts) {
                if (part->next == NULL) {
                    break;
                }

                part = part->next;
                he = part->elts;
                i = 0;
            }

            if (he[i].hash &&
                he[i].key.len == strlen(nv) &&
                ngx_strncasecmp(he[i].key.data, (u_char *) nv, he[i].key.len) == 0) {
                he[i].hash = 0;
            }
        }
    }

    he = ngx_list_push(&r->headers_out.headers);
    if (he) {
        ngx_http_ucode_res_strcopy(r->pool, &he->key, nv, strlen(nv));
        ngx_http_ucode_res_strcopy(r->pool, &he->value, vv, strlen(vv));
        he->hash = 1;
    }

    free(nv);
    free(vv);

    return NULL;
}

static uc_value_t *
ngx_http_ucode_res_set_header(uc_vm_t *vm, size_t nargs)
{
    return ngx_http_ucode_res_header_internal(vm, nargs, true);
}

static uc_value_t *
ngx_http_ucode_res_add_header(uc_vm_t *vm, size_t nargs)
{
    return ngx_http_ucode_res_header_internal(vm, nargs, false);
}

/* ------------------------------------------------------------------------- */

static void *
ngx_http_ucode_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_ucode_loc_conf_t *lcf;

    lcf = ngx_pcalloc(cf->pool, sizeof(ngx_http_ucode_loc_conf_t));
    if (lcf == NULL) {
        return NULL;
    }

    ngx_str_null(&lcf->file);

    return lcf;
}

static char *
ngx_http_ucode_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_ucode_loc_conf_t *prev = parent;
    ngx_http_ucode_loc_conf_t *conf = child;

    ngx_conf_merge_str_value(conf->file, prev->file, "");

    return NGX_CONF_OK;
}

static char *
ngx_http_ucode_content(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_ucode_loc_conf_t *lcf = conf;
    ngx_str_t *args;

    if (lcf->file.len) {
        return "is duplicate";
    }

    args = cf->args->elts;
    lcf->file = args[1];

    return NGX_CONF_OK;
}

static ngx_int_t
ngx_http_ucode_init(ngx_conf_t *cf)
{
    ngx_http_handler_pt         *h;
    ngx_http_core_main_conf_t   *cmcf;

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    h = ngx_array_push(&cmcf->phases[NGX_HTTP_CONTENT_PHASE].handlers);
    if (h == NULL) {
        return NGX_ERROR;
    }

    *h = ngx_http_ucode_handler;

    return NGX_OK;
}

/* ------------------------------------------------------------------------- */

/*
 * Run a ucode template as the content handler for a request.
 *
 * A fresh ucode VM is created per request so concurrent/interleaved requests
 * never share mutable VM state.  The template's top-level is executed
 * directly and all output it produces (print() / {{ ... }}) becomes the
 * response body.
 *
 * Two globals are exposed to the template:
 *   request  - request object:
 *              request.method, request.uri, request.query,
 *              request.script_name, request.remote_addr, request.protocol,
 *              request.headers.<Header-Name>  (array of all values)
 *   response - response object with response.status(code[, phrase]),
 *              response.set_header(name, value) and
 *              response.add_header(name, value)
 *
 * Classic CGI variables are also available as top-level globals:
 * REQUEST_METHOD, REQUEST_URI, QUERY_STRING, SCRIPT_NAME, REMOTE_ADDR and
 * SERVER_PROTOCOL.
 *
 * As a fallback, CGI-style header lines (Content-Type:/Status:/X-...)
 * printed at the very start of the output are also applied to the response
 * (and stripped from the body), mirroring uhttpd templates.
 *
 * The template is recompiled on every request, so edits to the .ut file are
 * picked up immediately and no reload is required.
 *
 * NOTE: the template runs to completion synchronously in the worker process.
 * This is acceptable for low-traffic use (e.g. a personal config page) but
 * will block the worker while a template executes.
 */
static void
ngx_http_ucode_execute(ngx_http_request_t *r, ngx_str_t *file)
{
    uc_vm_t             vm;
    uc_parse_config_t   config = { 0 };
    uc_value_t         *request, *hdr, *api, *v, *res = NULL, *respval;
    uc_source_t        *src;
    uc_program_t       *program;
    char               *syntax_error = NULL;
    FILE               *out;
    ngx_buf_t          *b;
    ngx_chain_t        *cl;
    ngx_int_t           status;
    size_t              n, off;
    ngx_uint_t          i;
    ngx_list_part_t    *part;
    ngx_table_elt_t    *h;
    ngx_table_elt_t    *he;
    ngx_http_ucode_res_t  *resp;
    uc_resource_type_t *restype;

    uc_search_path_init(&config.module_search_path);
    uc_search_path_init(&config.force_dynlink_list);

    config.lstrip_blocks = true;
    config.trim_blocks = true;
    config.strict_declarations = false;
    config.raw_mode = false;
    config.setup_signal_handlers = false;

    ngx_memzero(&vm, sizeof(vm));
    uc_vm_init(&vm, &config);
    uc_stdlib_load(uc_vm_scope_get(&vm));

    /* "uhttpd" api table */
    api = ucv_object_new(&vm);
    ucv_object_add(api, "urlencode",
        ucv_cfunction_new("urlencode", ngx_http_ucode_urlencode_fn));
    ucv_object_add(api, "urldecode",
        ucv_cfunction_new("urldecode", ngx_http_ucode_urldecode_fn));
    ucv_object_add(uc_vm_scope_get(&vm), "uhttpd", api);

    /* "response" object */
    {
        static const uc_function_list_t response_methods[] = {
            { "status",     ngx_http_ucode_res_status },
            { "set_header", ngx_http_ucode_res_set_header },
            { "add_header", ngx_http_ucode_res_add_header },
        };

        restype = _uc_type_declare(&vm, NGX_HTTP_UCODE_RESP_TYPE,
                                   response_methods,
                                   sizeof(response_methods) / sizeof(response_methods[0]),
                                   NULL);
    }

    resp = ngx_pcalloc(r->pool, sizeof(ngx_http_ucode_res_t));
    if (resp == NULL) {
        goto fail;
    }

    resp->r = r;

    respval = ucv_resource_new(restype, resp);
    ucv_object_add(uc_vm_scope_get(&vm), "response", respval);

    /* request object */
    request = ucv_object_new(&vm);

    if (r->args.len) {
        ucv_object_add(request, "query",
            ucv_string_new_length((const char *) r->args.data, r->args.len));
        ucv_object_add(uc_vm_scope_get(&vm), "QUERY_STRING",
            ucv_string_new_length((const char *) r->args.data, r->args.len));
    }

    ucv_object_add(request, "method",
        ucv_string_new_length((const char *) r->method_name.data,
                              r->method_name.len));
    ucv_object_add(uc_vm_scope_get(&vm), "REQUEST_METHOD",
        ucv_string_new_length((const char *) r->method_name.data,
                              r->method_name.len));

    ucv_object_add(request, "uri",
        ucv_string_new_length((const char *) r->unparsed_uri.data,
                              r->unparsed_uri.len));
    ucv_object_add(uc_vm_scope_get(&vm), "REQUEST_URI",
        ucv_string_new_length((const char *) r->unparsed_uri.data,
                              r->unparsed_uri.len));

    ucv_object_add(request, "script_name",
        ucv_string_new_length((const char *) r->uri.data, r->uri.len));
    ucv_object_add(uc_vm_scope_get(&vm), "SCRIPT_NAME",
        ucv_string_new_length((const char *) r->uri.data, r->uri.len));

    ucv_object_add(request, "remote_addr",
        ucv_string_new_length((const char *) r->connection->addr_text.data,
                              r->connection->addr_text.len));
    ucv_object_add(uc_vm_scope_get(&vm), "REMOTE_ADDR",
        ucv_string_new_length((const char *) r->connection->addr_text.data,
                              r->connection->addr_text.len));

    ucv_object_add(request, "protocol",
        ucv_string_new_length((const char *) r->http_protocol.data,
                              r->http_protocol.len));
    ucv_object_add(uc_vm_scope_get(&vm), "SERVER_PROTOCOL",
        ucv_string_new_length((const char *) r->http_protocol.data,
                              r->http_protocol.len));

    hdr = ucv_object_new(&vm);

    part = &r->headers_in.headers.part;
    h = part->elts;

    for (i = 0; /* void */; i++) {
        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }

            part = part->next;
            h = part->elts;
            i = 0;
        }

        if (h[i].hash) {
            uc_value_t *val = ucv_string_new_length(
                (const char *) h[i].value.data, h[i].value.len);
            uc_value_t *arr = ucv_object_get(hdr,
                (const char *) h[i].key.data, NULL);

            if (arr == NULL) {
                arr = ucv_array_new(&vm);
                ucv_object_add(hdr, (const char *) h[i].key.data, arr);
            }

            ucv_array_push(arr, val);
        }
    }

    ucv_object_add(request, "headers", hdr);

    /* expose the request object to the template as the global "request" */
    ucv_object_add(uc_vm_scope_get(&vm), "request", request);

    /* compile template */
    src = uc_source_new_file((const char *) file->data);
    if (src == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "ucode: unable to open template %V", file);
        goto fail;
    }

    program = uc_compile(&config, src, &syntax_error);
    uc_source_put(src);

    if (program == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "ucode: compilation error: %s",
                      syntax_error ? syntax_error : "?");
        free(syntax_error);
        goto fail;
    }

    /* capture output */
    out = tmpfile();
    if (out == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "ucode: tmpfile() failed: %s", strerror(errno));
        uc_program_put(program);
        goto fail;
    }

    vm.output = out;

    status = (ngx_int_t) uc_vm_execute(&vm, program, &res);

    /* The result is not guaranteed to be assigned when execution fails. */
    if (res != NULL) {
        ucv_put(res);
    }

    if (status != STATUS_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "ucode: execution error: %s",
                      vm.exception.message ? vm.exception.message : "?");
        uc_program_put(program);
        fclose(out);
        goto fail;
    }

    uc_program_put(program);

    fflush(out);

    {
        size_t len = (size_t) ftell(out);

        rewind(out);

        b = ngx_create_temp_buf(r->pool, len + 1);
        if (b == NULL) {
            fclose(out);
            goto fail;
        }

        n = fread(b->pos, 1, len, out);
        fclose(out);

        b->last = b->pos + n;
        *b->last = '\0';

        /*
         * CGI-style fallback: templates may print header lines
         * ("Content-Type: ...", "Status: ...", "X-Foo: ...") at the very
         * start of the output, uhttpd style.  Parse them, strip them from
         * the body, and apply them to the response unless the template
         * already set the same header via the "response" object.
         */
        off = 0;

        while (off < n) {
            u_char  *line = b->pos + off;
            u_char  *eol = ngx_strlchr(line, b->last, '\n');
            size_t   linelen = eol ? (size_t) (eol - line) : n - off;
            u_char  *colon;
            ngx_str_t name, value;

            if (linelen == 0 || line[0] == '\r' || line[0] == '\n') {
                off += linelen + (eol ? 1 : 0);
                break;
            }

            colon = ngx_strlchr(line, line + linelen, ':');

            if (colon == NULL) {
                break;
            }

            name.data = line;
            name.len = colon - line;

            /* skip leading whitespace after the colon */
            value.data = colon + 1;
            value.len = linelen - (colon - line) - 1;

            while (value.len && (value.data[0] == ' ' || value.data[0] == '\t')) {
                value.data++;
                value.len--;
            }
            while (value.len && (value.data[value.len - 1] == '\r' ||
                                 value.data[value.len - 1] == ' ' ||
                                 value.data[value.len - 1] == '\t')) {
                value.len--;
            }

            if (ngx_strncasecmp(name.data, "Content-Type", name.len) == 0 &&
                r->headers_out.content_type.len == 0) {
                r->headers_out.content_type = value;
            } else if (ngx_strncasecmp(name.data, "Status", name.len) == 0 &&
                       r->headers_out.status == 0) {
                ngx_int_t sc = ngx_atoi(value.data, value.len);

                if (sc > 0) {
                    r->headers_out.status = sc;
                }
            } else {
                he = ngx_list_push(&r->headers_out.headers);
                if (he) {
                    ngx_http_ucode_res_strcopy(r->pool, &he->key,
                                               (const char *) name.data, name.len);
                    ngx_http_ucode_res_strcopy(r->pool, &he->value,
                                               (const char *) value.data, value.len);
                    he->hash = 1;
                }
            }

            off += linelen + (eol ? 1 : 0);

            if (eol == NULL) {
                break;
            }
        }

        b->pos += off;

        if (r->headers_out.content_type.len == 0) {
            r->headers_out.content_type.data =
                (u_char *) "text/html; charset=utf-8";
            r->headers_out.content_type.len =
                sizeof("text/html; charset=utf-8") - 1;
        }

        if (r->headers_out.status == 0) {
            r->headers_out.status = NGX_HTTP_OK;
        }

        r->headers_out.content_length_n = b->last - b->pos;

        cl = ngx_alloc_chain_link(r->pool);
        if (cl == NULL) {
            goto fail;
        }

        cl->buf = b;
        cl->next = NULL;

        ngx_http_send_header(r);
        ngx_http_output_filter(r, cl);
    }

    uc_vm_free(&vm);
    uc_search_path_free(&config.module_search_path);
    uc_search_path_free(&config.force_dynlink_list);

    ngx_http_finalize_request(r, NGX_OK);
    return;

fail:
    uc_vm_free(&vm);
    uc_search_path_free(&config.module_search_path);
    uc_search_path_free(&config.force_dynlink_list);
    ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
}

static ngx_int_t
ngx_http_ucode_handler(ngx_http_request_t *r)
{
    ngx_http_ucode_loc_conf_t *lcf;

    if (r->method != NGX_HTTP_GET && r->method != NGX_HTTP_HEAD) {
        return NGX_HTTP_NOT_ALLOWED;
    }

    lcf = ngx_http_get_module_loc_conf(r, ngx_http_ucode_module);

    if (lcf->file.len == 0) {
        return NGX_DECLINED;
    }

    if (r->method == NGX_HTTP_HEAD) {
        r->header_only = 1;
    }

    ngx_http_ucode_execute(r, &lcf->file);

    return NGX_DONE;
}
