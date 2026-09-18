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

#include <json-c/json.h>
#include <json-c/printbuf.h>

#include "vendor/multipart-parser-c/multipart_parser.h"

typedef struct {
    ngx_str_t     file;
    ngx_uint_t    methods;    /* allowed HTTP methods bitmask; 0 = all */
} ngx_http_ucode_loc_conf_t;

/*
 * Method name -> bit flag table, mirroring the NGX_HTTP_* defines and used
 * by the ucode_methods directive and the Allow: response header.
 */
static struct {
    const char *name;
    ngx_uint_t  bit;
} ngx_http_ucode_method_names[] = {
    { "GET",     NGX_HTTP_GET },
    { "HEAD",    NGX_HTTP_HEAD },
    { "POST",    NGX_HTTP_POST },
    { "PUT",     NGX_HTTP_PUT },
    { "DELETE",  NGX_HTTP_DELETE },
    { "MKCOL",   NGX_HTTP_MKCOL },
    { "COPY",    NGX_HTTP_COPY },
    { "MOVE",    NGX_HTTP_MOVE },
    { "OPTIONS", NGX_HTTP_OPTIONS },
    { "PROPFIND", NGX_HTTP_PROPFIND },
    { "PROPPATCH", NGX_HTTP_PROPPATCH },
    { "LOCK",    NGX_HTTP_LOCK },
    { "UNLOCK",  NGX_HTTP_UNLOCK },
    { "PATCH",   NGX_HTTP_PATCH },
    { "TRACE",   NGX_HTTP_TRACE },
    { "CONNECT", NGX_HTTP_CONNECT },
    { NULL, 0 }
};

#define NGX_HTTP_UCODE_RESP_TYPE  "http_response"

typedef struct {
    ngx_http_request_t *r;
} ngx_http_ucode_res_t;

/*
 * Per-request state that must survive across the asynchronous request-body
 * read: the ucode VM, the request object and the compile config are created
 * up-front, and once the body arrives it is parsed and merged into the
 * request object before the template is compiled and executed.
 */
typedef struct {
    ngx_http_request_t  *r;
    ngx_str_t            file;
    uc_parse_config_t    config;
    uc_vm_t              vm;
    uc_value_t          *request;
} ngx_http_ucode_ctx_t;

static ngx_int_t ngx_http_ucode_handler(ngx_http_request_t *r);
static void ngx_http_ucode_body_handler(ngx_http_request_t *r);

static char *ngx_http_ucode_content(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_ucode_methods(ngx_conf_t *cf, ngx_command_t *cmd,
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

    { ngx_string("ucode_methods"),
      NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_1MORE,
      ngx_http_ucode_methods,
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
    int hi;

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

/*
 * URL-decode into a buffer allocated from the request pool.  This variant is
 * used for request-body parsing where values may exceed the fixed 4k stack
 * buffer used by the uhttpd-style conversion helpers above.
 */
static ngx_int_t
ngx_http_ucode_urldecode_alloc(ngx_pool_t *pool, ngx_str_t *dst,
    const char *src, size_t src_len)
{
    size_t i, o = 0;
    int hi;
    u_char *p;

    p = ngx_pnalloc(pool, src_len + 1);
    if (p == NULL) {
        return NGX_ERROR;
    }

    for (i = 0; i < src_len; i++) {
        if (src[i] == '%' && i + 2 < src_len &&
            (hi = ngx_hextoi((u_char *) (src + i + 1), 2)) >= 0) {
            p[o++] = (u_char) hi;
            i += 2;
        } else if (src[i] == '+') {
            p[o++] = ' ';
        } else {
            p[o++] = (u_char) src[i];
        }
    }

    p[o] = '\0';
    dst->len = o;
    dst->data = p;

    return NGX_OK;
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
    lcf->methods = NGX_CONF_UNSET_UINT;

    return lcf;
}

static char *
ngx_http_ucode_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_ucode_loc_conf_t *prev = parent;
    ngx_http_ucode_loc_conf_t *conf = child;

    ngx_conf_merge_str_value(conf->file, prev->file, "");
    ngx_conf_merge_uint_value(conf->methods, prev->methods,
                              NGX_HTTP_GET | NGX_HTTP_HEAD | NGX_HTTP_OPTIONS);

    return NGX_CONF_OK;
}

/*
 * ucode_methods GET POST ... - explicit list of the HTTP methods wired to the
 * ucode template in this location (replaces the set).  Any method not listed
 * is answered with 405 Method Not Allowed and an Allow: header.  If the
 * directive is absent, only the safe read methods GET, HEAD and OPTIONS are
 * handled - POST/PUT/DELETE/PATCH (and hence JSON bodies, form submissions
 * and file uploads) must be explicitly enabled.
 */
static char *
ngx_http_ucode_methods(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_ucode_loc_conf_t *lcf = conf;
    ngx_str_t *args;
    ngx_uint_t i, m, methods = 0;

    args = cf->args->elts;

    for (i = 1; i < cf->args->nelts; i++) {
        for (m = 0; ngx_http_ucode_method_names[m].name; m++) {
            if (args[i].len == ngx_strlen(ngx_http_ucode_method_names[m].name)
                && ngx_strncasecmp(args[i].data,
                    (u_char *) ngx_http_ucode_method_names[m].name,
                    args[i].len) == 0) {
                methods |= ngx_http_ucode_method_names[m].bit;
                break;
            }
        }

        if (ngx_http_ucode_method_names[m].name == NULL) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                               "invalid method \"%V\"", &args[i]);
            return NGX_CONF_ERROR;
        }
    }

    lcf->methods = methods;

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
 * Append a value to request.form / request.files under the given key,
 * creating the (array) bucket on first use.  All values for one key are
 * collected in an array so repeated form fields and multi-file uploads stay
 * lossless, mirroring how request.headers collects repeated headers.
 */
static void
ngx_http_ucode_map_add(ngx_pool_t *pool, uc_vm_t *vm, uc_value_t *map,
    const char *key, size_t key_len, uc_value_t *value)
{
    u_char     *k;
    uc_value_t *arr;

    /* ucode object keys are NUL-terminated C strings */
    k = ngx_pnalloc(pool, key_len + 1);
    if (k == NULL) {
        return;
    }

    ngx_memcpy(k, key, key_len);
    k[key_len] = '\0';

    arr = ucv_object_get(map, (const char *) k, NULL);

    if (arr == NULL) {
        arr = ucv_array_new(vm);
        ucv_object_add(map, (const char *) k, arr);
    }

    ucv_array_push(arr, value);
}

/* ------------------------------------------------------------------------- */

/*
 * Parse an application/x-www-form-urlencoded body into the given object:
 * name -> array of decoded values.
 */
static void
ngx_http_ucode_parse_urlencoded(ngx_pool_t *pool, uc_vm_t *vm,
    uc_value_t *form, ngx_str_t *body)
{
    size_t start = 0, i;

    for (i = 0; i <= body->len; i++) {
        if (i == body->len || body->data[i] == '&') {
            size_t eq = start;
            ngx_str_t k, v;

            while (eq < i && body->data[eq] != '=') {
                eq++;
            }

            if (eq < i) {
                ngx_http_ucode_urldecode_alloc(pool, &k,
                    (const char *) body->data + start, eq - start);
                ngx_http_ucode_urldecode_alloc(pool, &v,
                    (const char *) body->data + eq + 1, i - eq - 1);
            } else {
                ngx_http_ucode_urldecode_alloc(pool, &k,
                    (const char *) body->data + start, i - start);
                ngx_str_null(&v);
            }

            if (k.len) {
                ngx_http_ucode_map_add(pool, vm, form,
                    (const char *) k.data, k.len,
                    ucv_string_new_length((const char *) v.data, v.len));
            }

            start = i + 1;
        }
    }
}

/*
 * Parse an application/json body.  Returns a ucode value (object/array) on
 * success, or NULL if the payload is not valid JSON.
 *
 * Mirrors ucode's own json() parsing: the trailing NUL byte is passed to the
 * json-c parser (work-around for json-c issue #681) and any remaining bytes
 * after the parsed value must be whitespace.
 */
static uc_value_t *
ngx_http_ucode_parse_json(uc_vm_t *vm, ngx_str_t *body)
{
    json_object *jso;
    uc_value_t  *val;
    json_tokener *tok;
    size_t        i;

    if (body->len == 0) {
        return NULL;
    }

    tok = json_tokener_new();
    if (tok == NULL) {
        return NULL;
    }

    jso = json_tokener_parse_ex(tok, (const char *) body->data, body->len + 1);

    if (json_tokener_get_error(tok) != json_tokener_success) {
        json_tokener_free(tok);
        return NULL;
    }

    for (i = json_tokener_get_parse_end(tok); i < body->len; i++) {
        if (!isspace((u_char) body->data[i])) {
            json_tokener_free(tok);
            json_object_put(jso);
            return NULL;
        }
    }

    json_tokener_free(tok);

    val = ucv_from_json(vm, jso);
    json_object_put(jso);

    return val;
}

/* ------------------------------------------------------------------------- */

/*
 * multipart/form-data parsing, backed by the vendored multipart-parser-c
 * (a proven, callback-driven state machine; see vendor/multipart-parser-c).
 *
 * For each part it reads the Content-Disposition (name/filename) and
 * Content-Type headers, then:
 *   - a part without a filename is a regular form field -> request.form
 *   - a part with a filename is a file upload -> request.files
 *
 * File data is exposed as a (binary-safe) ucode string under the "data" key
 * alongside "name", "filename", "content_type" and "size".
 */

typedef struct {
    ngx_pool_t     *pool;
    uc_vm_t        *vm;
    uc_value_t     *form;
    uc_value_t     *files;
    printbuf       *buf;        /* accumulated part data (json-c printbuf) */
    ngx_str_t       name;       /* field name of the current part */
    ngx_str_t       filename;
    ngx_str_t       ctype;
    ngx_str_t       hfield;     /* current header field name (header_value
                                 * callback runs after header_field) */
    unsigned        has_filename;
} ngx_http_ucode_mp_t;

static int
ngx_http_ucode_mp_on_part_data_begin(multipart_parser *p)
{
    ngx_http_ucode_mp_t *mp = multipart_parser_get_data(p);

    if (mp->buf) {
        printbuf_free(mp->buf);
    }

    mp->buf = printbuf_new();
    if (mp->buf == NULL) {
        return -1;
    }

    return 0;
}

static int
ngx_http_ucode_mp_on_header_field(multipart_parser *p, const char *at,
    size_t length)
{
    ngx_http_ucode_mp_t *mp = multipart_parser_get_data(p);

    mp->hfield.data = (u_char *) at;
    mp->hfield.len = length;
    return 0;
}

static int
ngx_http_ucode_mp_on_header_value(multipart_parser *p, const char *at,
    size_t length)
{
    ngx_http_ucode_mp_t *mp = multipart_parser_get_data(p);
    u_char *hv = (u_char *) at;
    size_t  hl = length;

    /* strip optional trailing CR/whitespace */
    while (hl && (hv[hl - 1] == '\r' || hv[hl - 1] == ' ' || hv[hl - 1] == '\t')) {
        hl--;
    }

    if (mp->hfield.len == 19
        && ngx_strncasecmp(mp->hfield.data,
            (u_char *) "Content-Disposition", 19) == 0) {
        size_t k;

        for (k = 0; k + 5 < hl; k++) {
            if (hv[k] == 'n' && ngx_strncasecmp(hv + k, (u_char *) "name=", 5) == 0) {
                size_t s = k + 5, q = 0;

                if (s < hl && hv[s] == '"') {
                    s++;
                    while (s + q < hl && hv[s + q] != '"') {
                        q++;
                    }
                } else {
                    while (s + q < hl && hv[s + q] != ';'
                           && hv[s + q] != ' ' && hv[s + q] != '\t') {
                        q++;
                    }
                }

                mp->name.data = hv + s;
                mp->name.len = q;
            } else if (hv[k] == 'f' && k + 9 < hl
                && ngx_strncasecmp(hv + k, (u_char *) "filename=", 9) == 0) {
                size_t s = k + 9, q = 0;

                if (s < hl && hv[s] == '"') {
                    s++;
                    while (s + q < hl && hv[s + q] != '"') {
                        q++;
                    }
                } else {
                    while (s + q < hl && hv[s + q] != ';'
                           && hv[s + q] != ' ' && hv[s + q] != '\t') {
                        q++;
                    }
                }

                mp->filename.data = hv + s;
                mp->filename.len = q;
                mp->has_filename = 1;
            }
        }
    } else if (mp->hfield.len == 12
        && ngx_strncasecmp(mp->hfield.data, (u_char *) "Content-Type", 12) == 0) {
        mp->ctype.data = hv;
        mp->ctype.len = hl;
    }

    return 0;
}

static int
ngx_http_ucode_mp_on_part_data(multipart_parser *p, const char *at,
    size_t length)
{
    ngx_http_ucode_mp_t *mp = multipart_parser_get_data(p);

    if (mp->buf == NULL) {
        return -1;
    }

    /* printbuf_memappend returns the byte count (>0) on success, -1 on error */
    if (printbuf_memappend(mp->buf, at, length) < 0) {
        return -1;
    }

    return 0;
}

static int
ngx_http_ucode_mp_on_part_data_end(multipart_parser *p)
{
    ngx_http_ucode_mp_t *mp = multipart_parser_get_data(p);
    uc_value_t          *obj;
    size_t               dlen;

    if (mp->name.len == 0) {
        return 0;
    }

    dlen = mp->buf ? printbuf_length(mp->buf) : 0;

    if (mp->has_filename) {
        obj = ucv_object_new(mp->vm);
        ucv_object_add(obj, "name",
            ucv_string_new_length((const char *) mp->name.data, mp->name.len));
        ucv_object_add(obj, "filename",
            ucv_string_new_length((const char *) mp->filename.data, mp->filename.len));
        ucv_object_add(obj, "content_type",
            mp->ctype.len
                ? ucv_string_new_length((const char *) mp->ctype.data, mp->ctype.len)
                : ucv_string_new_length("", 0));
        ucv_object_add(obj, "data",
            ucv_string_new_length(mp->buf ? mp->buf->buf : "", dlen));
        ucv_object_add(obj, "size",
            ucv_int64_new(dlen));

        ngx_http_ucode_map_add(mp->pool, mp->vm, mp->files,
            (const char *) mp->name.data, mp->name.len, obj);
    } else {
        ngx_http_ucode_map_add(mp->pool, mp->vm, mp->form,
            (const char *) mp->name.data, mp->name.len,
            ucv_string_new_length(mp->buf ? mp->buf->buf : "", dlen));
    }

    return 0;
}

static int
ngx_http_ucode_mp_on_headers_complete(multipart_parser *p)
{
    return 0;
}

static int
ngx_http_ucode_mp_on_body_end(multipart_parser *p)
{
    return 0;
}

static ngx_int_t
ngx_http_ucode_parse_multipart(ngx_pool_t *pool, uc_vm_t *vm,
    uc_value_t *form, uc_value_t *files, ngx_str_t *body, ngx_str_t *boundary)
{
    multipart_parser            *mp;
    multipart_parser_settings    settings;
    ngx_http_ucode_mp_t          ctx;
    size_t                       rc;
    char                        *b;
    char                        *bnd;

    if (boundary->len == 0 || boundary->len > 200) {
        return NGX_OK;
    }

    /* the vendored parser works on NUL-terminated C strings */
    b = ngx_pnalloc(pool, body->len + 1);
    if (b == NULL) {
        return NGX_ERROR;
    }

    ngx_memcpy(b, body->data, body->len);
    b[body->len] = '\0';

    ngx_memzero(&settings, sizeof(settings));
    settings.on_part_data_begin = ngx_http_ucode_mp_on_part_data_begin;
    settings.on_header_field    = ngx_http_ucode_mp_on_header_field;
    settings.on_header_value    = ngx_http_ucode_mp_on_header_value;
    settings.on_headers_complete = ngx_http_ucode_mp_on_headers_complete;
    settings.on_part_data       = ngx_http_ucode_mp_on_part_data;
    settings.on_part_data_end   = ngx_http_ucode_mp_on_part_data_end;
    settings.on_body_end        = ngx_http_ucode_mp_on_body_end;

    /* the parser matches the body against "--<boundary>", so prefix the
     * RFC 2387 boundary (which does not include the leading hyphens) */
    bnd = ngx_pnalloc(pool, boundary->len + 3);
    if (bnd == NULL) {
        return NGX_ERROR;
    }

    bnd[0] = '-';
    bnd[1] = '-';
    ngx_memcpy(bnd + 2, boundary->data, boundary->len);
    bnd[2 + boundary->len] = '\0';

    mp = multipart_parser_init(bnd, &settings);
    if (mp == NULL) {
        return NGX_ERROR;
    }

    ctx.pool = pool;
    ctx.vm = vm;
    ctx.form = form;
    ctx.files = files;
    ctx.buf = NULL;
    ctx.name.data = NULL;
    ctx.name.len = 0;
    ctx.filename.data = NULL;
    ctx.filename.len = 0;
    ctx.ctype.data = NULL;
    ctx.ctype.len = 0;
    ctx.has_filename = 0;

    multipart_parser_set_data(mp, &ctx);

    rc = multipart_parser_execute(mp, b, body->len);

    if (ctx.buf) {
        printbuf_free(ctx.buf);
    }

    /* the parser reports the first byte it could not consume on error */
    if (rc < body->len) {
        multipart_parser_free(mp);
        return NGX_OK;
    }

    multipart_parser_free(mp);
    return NGX_OK;
}

/* ------------------------------------------------------------------------- */

/*
 * Once the request body has been fully read, copy it into a contiguous
 * request-pool buffer and populate the body-derived members of the request
 * object:
 *   request.body              - raw body (always set, possibly empty)
 *   request.json              - application/json payload, parsed
 *   request.form              - form fields, name -> array of values
 *   request.files             - multipart uploads, name -> array of { ... }
 */
static void
ngx_http_ucode_body_parse(ngx_http_ucode_ctx_t *ctx)
{
    ngx_http_request_t *r = ctx->r;
    ngx_chain_t        *cl;
    size_t              len = 0;
    u_char             *p;
    ngx_str_t           body;
    ngx_str_t           ct = ngx_null_string;
    ngx_str_t           empty_ct = ngx_null_string;
    uc_value_t         *form, *files;

    body.len = 0;
    body.data = NULL;

    if (r->request_body && r->request_body->bufs) {
        for (cl = r->request_body->bufs; cl; cl = cl->next) {
            len += (size_t) ngx_buf_size(cl->buf);
        }

        p = ngx_pnalloc(r->pool, len + 1);
        if (p == NULL) {
            goto fail;
        }

        body.data = p;
        body.len = len;

        for (cl = r->request_body->bufs; cl; cl = cl->next) {
            ngx_buf_t *b = cl->buf;

            if (ngx_buf_in_memory(b)) {
                size_t sz = b->last - b->pos;

                ngx_memcpy(p, b->pos, sz);
                p += sz;
            } else if (b->in_file) {
                ssize_t n = ngx_read_file(b->file, p,
                    (size_t) (b->file_last - b->file_pos), b->file_pos);

                if (n < 0) {
                    goto fail;
                }

                p += n;
            }
        }

        *p = '\0';
    }

    ucv_object_add(ctx->request, "body",
        ucv_string_new_length((const char *) (body.data ? body.data : (u_char *) ""),
                              body.len));

    form = ucv_object_new(&ctx->vm);
    ucv_object_add(ctx->request, "form", form);

    files = ucv_object_new(&ctx->vm);
    ucv_object_add(ctx->request, "files", files);

    if (body.len == 0) {
        return;
    }

    ct = r->headers_in.content_type ? r->headers_in.content_type->value
                                    : empty_ct;

    /* application/json or any *+json */
    if (ct.len >= 16
        && ngx_strncasecmp(ct.data, (u_char *) "application/json", 16) == 0) {
        uc_value_t *json = ngx_http_ucode_parse_json(&ctx->vm, &body);

        if (json) {
            ucv_object_add(ctx->request, "json", json);
        }
        return;
    }

    if (ct.len > 5
        && ngx_strncasecmp(ct.data + ct.len - 5, (u_char *) "+json", 5) == 0) {
        uc_value_t *json = ngx_http_ucode_parse_json(&ctx->vm, &body);

        if (json) {
            ucv_object_add(ctx->request, "json", json);
        }
        return;
    }

    /* application/x-www-form-urlencoded */
    if (ct.len >= 33
        && ngx_strncasecmp(ct.data, (u_char *) "application/x-www-form-urlencoded", 33) == 0) {
        ngx_http_ucode_parse_urlencoded(r->pool, &ctx->vm, form, &body);
        return;
    }

    /* multipart/form-data; boundary=... */
    if (ct.len >= 19
        && ngx_strncasecmp(ct.data, (u_char *) "multipart/form-data", 19) == 0) {
        ngx_str_t boundary = ngx_null_string;
        size_t    i;

        for (i = 0; i + 9 < ct.len; i++) {
            if (ngx_strncasecmp(ct.data + i, (u_char *) "boundary=", 9) == 0) {
                size_t s = i + 9;
                size_t e = s;

                if (e < ct.len && ct.data[e] == '"') {
                    s++;
                    e = s;
                    while (e < ct.len && ct.data[e] != '"') {
                        e++;
                    }
                } else {
                    while (e < ct.len && ct.data[e] != ';'
                           && ct.data[e] != ' ' && ct.data[e] != '\t'
                           && ct.data[e] != '\r' && ct.data[e] != '\n') {
                        e++;
                    }
                }

                boundary.data = ct.data + s;
                boundary.len = e - s;
                break;
            }
        }

        ngx_http_ucode_parse_multipart(r->pool, &ctx->vm,
            form, files, &body, &boundary);
        return;
    }

fail:
    return;
}

/* ------------------------------------------------------------------------- */

/*
 * Run a ucode template as the content handler for a request.
 *
 * The request body (if any) is read first via ngx_http_read_client_request_body
 * and parsed into the request object before the template executes, so any HTTP
 * method (GET, POST, PUT, DELETE, PATCH, ...) can be handled.
 *
 * A fresh ucode VM is created per request so concurrent/interleaved requests
 * never share mutable VM state.  The template's top-level is executed directly
 * and all output it produces (print() / {{ ... }}) becomes the response body.
 *
 * Globals exposed to the template:
 *   request  - request object:
 *              request.method, request.uri, request.query,
 *              request.script_name, request.remote_addr, request.protocol,
 *              request.headers.<Header-Name>  (array of all values),
 *              request.body, request.json, request.form, request.files
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

/*
 * Create the per-request VM, response resource and the base (body-less)
 * request object.  Runs synchronously from the content handler; the request
 * body is read asynchronously afterwards.
 */
static ngx_int_t
ngx_http_ucode_prepare(ngx_http_request_t *r, ngx_str_t *file)
{
    ngx_http_ucode_ctx_t *ctx;
    uc_value_t           *request, *hdr, *api, *respval;
    ngx_http_ucode_res_t *resp;
    uc_resource_type_t   *restype;
    ngx_uint_t            i;
    ngx_list_part_t      *part;
    ngx_table_elt_t      *h;

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_ucode_ctx_t));
    if (ctx == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ctx->r = r;
    ctx->file = *file;

    uc_search_path_init(&ctx->config.module_search_path);
    uc_search_path_init(&ctx->config.force_dynlink_list);

    ctx->config.lstrip_blocks = true;
    ctx->config.trim_blocks = true;
    ctx->config.strict_declarations = false;
    ctx->config.raw_mode = false;
    ctx->config.setup_signal_handlers = false;

    ngx_memzero(&ctx->vm, sizeof(ctx->vm));
    uc_vm_init(&ctx->vm, &ctx->config);
    uc_stdlib_load(uc_vm_scope_get(&ctx->vm));

    /* "uhttpd" api table */
    api = ucv_object_new(&ctx->vm);
    ucv_object_add(api, "urlencode",
        ucv_cfunction_new("urlencode", ngx_http_ucode_urlencode_fn));
    ucv_object_add(api, "urldecode",
        ucv_cfunction_new("urldecode", ngx_http_ucode_urldecode_fn));
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "uhttpd", api);

    /* "response" object */
    {
        static const uc_function_list_t response_methods[] = {
            { "status",     ngx_http_ucode_res_status },
            { "set_header", ngx_http_ucode_res_set_header },
            { "add_header", ngx_http_ucode_res_add_header },
        };

        restype = _uc_type_declare(&ctx->vm, NGX_HTTP_UCODE_RESP_TYPE,
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
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "response", respval);

    /* request object */
    request = ucv_object_new(&ctx->vm);

    if (r->args.len) {
        ucv_object_add(request, "query",
            ucv_string_new_length((const char *) r->args.data, r->args.len));
        ucv_object_add(uc_vm_scope_get(&ctx->vm), "QUERY_STRING",
            ucv_string_new_length((const char *) r->args.data, r->args.len));
    }

    ucv_object_add(request, "method",
        ucv_string_new_length((const char *) r->method_name.data,
                              r->method_name.len));
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "REQUEST_METHOD",
        ucv_string_new_length((const char *) r->method_name.data,
                              r->method_name.len));

    ucv_object_add(request, "uri",
        ucv_string_new_length((const char *) r->unparsed_uri.data,
                              r->unparsed_uri.len));
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "REQUEST_URI",
        ucv_string_new_length((const char *) r->unparsed_uri.data,
                              r->unparsed_uri.len));

    ucv_object_add(request, "script_name",
        ucv_string_new_length((const char *) r->uri.data, r->uri.len));
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "SCRIPT_NAME",
        ucv_string_new_length((const char *) r->uri.data, r->uri.len));

    ucv_object_add(request, "remote_addr",
        ucv_string_new_length((const char *) r->connection->addr_text.data,
                              r->connection->addr_text.len));
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "REMOTE_ADDR",
        ucv_string_new_length((const char *) r->connection->addr_text.data,
                              r->connection->addr_text.len));

    ucv_object_add(request, "protocol",
        ucv_string_new_length((const char *) r->http_protocol.data,
                              r->http_protocol.len));
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "SERVER_PROTOCOL",
        ucv_string_new_length((const char *) r->http_protocol.data,
                              r->http_protocol.len));

    hdr = ucv_object_new(&ctx->vm);

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
                arr = ucv_array_new(&ctx->vm);
                ucv_object_add(hdr, (const char *) h[i].key.data, arr);
            }

            ucv_array_push(arr, val);
        }
    }

    ucv_object_add(request, "headers", hdr);

    ctx->request = request;

    /* expose the request object to the template as the global "request" */
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "request", request);

    /* stash the context on the request for the body handler */
    ngx_http_set_ctx(r, ctx, ngx_http_ucode_module);

    return NGX_OK;

fail:
    uc_vm_free(&ctx->vm);
    uc_search_path_free(&ctx->config.module_search_path);
    uc_search_path_free(&ctx->config.force_dynlink_list);
    return NGX_HTTP_INTERNAL_SERVER_ERROR;
}

/*
 * Compile + execute the template and finalize the response.  Called from the
 * request-body handler once the body is available (or known absent).
 */
static void
ngx_http_ucode_run(ngx_http_request_t *r, ngx_http_ucode_ctx_t *ctx)
{
    uc_source_t        *src;
    uc_program_t       *program;
    uc_value_t         *res = NULL;
    char               *syntax_error = NULL;
    FILE               *out;
    ngx_buf_t          *b;
    ngx_chain_t        *cl;
    ngx_int_t           status;
    size_t              n, off;
    ngx_table_elt_t    *he;

    ngx_http_ucode_body_parse(ctx);

    /* compile template */
    src = uc_source_new_file((const char *) ctx->file.data);
    if (src == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "ucode: unable to open template %V", &ctx->file);
        goto fail;
    }

    program = uc_compile(&ctx->config, src, &syntax_error);
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

    ctx->vm.output = out;

    status = (ngx_int_t) uc_vm_execute(&ctx->vm, program, &res);

    /* The result is not guaranteed to be assigned when execution fails. */
    if (res != NULL) {
        ucv_put(res);
    }

    if (status != STATUS_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "ucode: execution error: %s",
                      ctx->vm.exception.message ? ctx->vm.exception.message : "?");
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

            if (ngx_strncasecmp(name.data, (u_char *) "Content-Type", name.len) == 0 &&
                r->headers_out.content_type.len == 0) {
                r->headers_out.content_type = value;
            } else if (ngx_strncasecmp(name.data, (u_char *) "Status", name.len) == 0 &&
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

        b->last_buf = (r == r->main) ? 1 : 0;
        b->last_in_chain = 1;

        cl->buf = b;
        cl->next = NULL;

        ngx_http_send_header(r);
        ngx_http_output_filter(r, cl);
    }

    uc_vm_free(&ctx->vm);
    uc_search_path_free(&ctx->config.module_search_path);
    uc_search_path_free(&ctx->config.force_dynlink_list);

    ngx_http_finalize_request(r, NGX_OK);
    return;

fail:
    uc_vm_free(&ctx->vm);
    uc_search_path_free(&ctx->config.module_search_path);
    uc_search_path_free(&ctx->config.force_dynlink_list);
    ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
}

/*
 * Request-body read completion handler.  Runs (synchronously or after the
 * body is buffered) once the full body is available; then executes the
 * template.
 */
static void
ngx_http_ucode_body_handler(ngx_http_request_t *r)
{
    ngx_http_ucode_ctx_t *ctx;

    if (r != r->main) {
        ngx_http_finalize_request(r, NGX_DONE);
        return;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_ucode_module);
    if (ctx == NULL) {
        ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    ngx_http_ucode_run(r, ctx);
}

static ngx_int_t
ngx_http_ucode_handler(ngx_http_request_t *r)
{
    ngx_http_ucode_loc_conf_t *lcf;
    ngx_int_t                  rc;

    lcf = ngx_http_get_module_loc_conf(r, ngx_http_ucode_module);

    if (lcf->file.len == 0) {
        return NGX_DECLINED;
    }

    /* reject methods not wired to this template with 405 + Allow header.
     * The response is emitted here and NGX_DONE returned so the content
     * phase finalizes the request exactly once. */
    if (!(lcf->methods & (ngx_uint_t) r->method)) {
        ngx_uint_t   m;
        ngx_str_t    allow;
        u_char      *p;
        ngx_buf_t   *b;
        ngx_chain_t *cl;
        size_t       len = 0;
        u_char      *body = (u_char *) "405 Method Not Allowed";

        for (m = 0; ngx_http_ucode_method_names[m].name; m++) {
            if (lcf->methods & ngx_http_ucode_method_names[m].bit) {
                len += ngx_strlen(ngx_http_ucode_method_names[m].name) + 2;
            }
        }

        p = ngx_pnalloc(r->pool, len + 1);
        if (p == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        allow.data = p;
        allow.len = 0;

        for (m = 0; ngx_http_ucode_method_names[m].name; m++) {
            if (lcf->methods & ngx_http_ucode_method_names[m].bit) {
                if (allow.len) {
                    *p++ = ',';
                    *p++ = ' ';
                    allow.len += 2;
                }

                len = ngx_strlen(ngx_http_ucode_method_names[m].name);
                ngx_memcpy(p, ngx_http_ucode_method_names[m].name, len);
                p += len;
                allow.len += len;
            }
        }

        *p = '\0';

        r->headers_out.status = NGX_HTTP_NOT_ALLOWED;
        r->headers_out.content_type.data = (u_char *) "text/plain";
        r->headers_out.content_type.len = sizeof("text/plain") - 1;
        r->headers_out.content_length_n = (off_t) ngx_strlen((char *) body);

        {
            ngx_table_elt_t *he = ngx_list_push(&r->headers_out.headers);

            if (he) {
                he->hash = 1;
                he->key.data = (u_char *) "Allow";
                he->key.len = sizeof("Allow") - 1;
                he->value = allow;
            }
        }

        b = ngx_create_temp_buf(r->pool, r->headers_out.content_length_n + 1);
        if (b == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        ngx_memcpy(b->pos, body, r->headers_out.content_length_n);
        b->last = b->pos + r->headers_out.content_length_n;
        *b->last = '\0';

        cl = ngx_alloc_chain_link(r->pool);
        if (cl == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        b->last_buf = (r == r->main) ? 1 : 0;
        b->last_in_chain = 1;

        cl->buf = b;
        cl->next = NULL;

        if (ngx_http_send_header(r) == NGX_ERROR) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        if (r->method != NGX_HTTP_HEAD) {
            ngx_http_output_filter(r, cl);
        }

        return NGX_DONE;
    }

    if (r->method == NGX_HTTP_HEAD) {
        r->header_only = 1;
    }

    rc = ngx_http_ucode_prepare(r, &lcf->file);
    if (rc != NGX_OK) {
        return rc;
    }

    /* read the request body (if any) asynchronously, then run the template */
    rc = ngx_http_read_client_request_body(r, ngx_http_ucode_body_handler);

    if (rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return rc;
    }

    return NGX_DONE;
}
