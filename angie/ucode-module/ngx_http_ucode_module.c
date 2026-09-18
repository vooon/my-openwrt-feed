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
#include <inttypes.h>
#include <strings.h>

#include <ucode/compiler.h>
#include <ucode/lib.h>
#include <ucode/source.h>
#include <ucode/vm.h>

#include <json-c/json.h>
#include <json-c/printbuf.h>

#include "http_parse.h"
#include "vendor/multipart-parser-c/multipart_parser.h"

typedef struct {
    ngx_str_t     file;
    ngx_uint_t    methods;    /* allowed HTTP methods bitmask; 0 = all */
    ngx_flag_t    cgi_headers;
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
    unsigned             vm_valid:1;   /* VM/search paths still need freeing */
} ngx_http_ucode_ctx_t;

static ngx_int_t ngx_http_ucode_handler(ngx_http_request_t *r);
static void ngx_http_ucode_body_handler(ngx_http_request_t *r);
static void ngx_http_ucode_cleanup(void *data);

static char *ngx_http_ucode_content(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static char *ngx_http_ucode_methods(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

static void *ngx_http_ucode_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_ucode_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);

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

    { ngx_string("ucode_cgi_headers"),
      NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF
          | NGX_HTTP_LIF_CONF | NGX_CONF_FLAG,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_ucode_loc_conf_t, cgi_headers),
      NULL },

      ngx_null_command
};

static ngx_http_module_t ngx_http_ucode_module_ctx = {
    NULL,                            /* preconfiguration */
    NULL,                            /* postconfiguration */
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

/*
 * URL-decode into a buffer allocated from the request pool, for request-body
 * parsing where values can be arbitrarily long.
 */
static ngx_int_t
ngx_http_ucode_urldecode_alloc(ngx_pool_t *pool, ngx_str_t *dst,
    const char *src, size_t src_len)
{
    u_char *p;

    p = ngx_pnalloc(pool, src_len + 1);
    if (p == NULL) {
        ngx_str_null(dst);
        return NGX_ERROR;
    }

    dst->len = uc_http_urldecode((char *) p, src, src_len);
    dst->data = p;

    return NGX_OK;
}

/*
 * Shared body of uhttpd.urlencode()/urldecode().  The destination buffer is
 * sized from the input (expand = 3 for encoding, 1 for decoding) so that
 * arbitrarily long values convert without truncation.
 */
static uc_value_t *
ngx_http_ucode_strconvert(uc_vm_t *vm, size_t nargs, size_t expand,
    size_t (*convert)(char *, const char *, size_t))
{
    uc_value_t *val = uc_fn_arg(0);
    uc_value_t *res;
    const char *in;
    char       *tmp = NULL, *out;
    size_t      in_len, out_len;

    if (val == NULL) {
        return ucv_string_new_length("", 0);
    }

    if (ucv_type(val) == UC_STRING) {
        in = ucv_string_get(val);
        in_len = ucv_string_length(val);
    } else {
        tmp = ucv_to_string(vm, val);

        if (tmp == NULL) {
            uc_vm_raise_exception(vm, EXCEPTION_RUNTIME,
                                  "URL conversion error");
            return NULL;
        }

        in = tmp;
        in_len = strlen(tmp);
    }

    out = malloc(in_len * expand + 1);

    if (out == NULL) {
        free(tmp);
        uc_vm_raise_exception(vm, EXCEPTION_RUNTIME, "Out of memory");
        return NULL;
    }

    out_len = convert(out, in, in_len);
    res = ucv_string_new_length(out, out_len);

    free(out);
    free(tmp);

    return res;
}

static uc_value_t *
ngx_http_ucode_urlencode_fn(uc_vm_t *vm, size_t nargs)
{
    return ngx_http_ucode_strconvert(vm, nargs, 3, uc_http_urlencode);
}

static uc_value_t *
ngx_http_ucode_urldecode_fn(uc_vm_t *vm, size_t nargs)
{
    return ngx_http_ucode_strconvert(vm, nargs, 1, uc_http_urldecode);
}

/*
 * Response object ("response") methods, exposed to templates as a resource
 * so the cfunctions can be type-checked with uc_fn_thisval().  Templates set
 * the HTTP status and arbitrary response headers through these; the rendered
 * body comes from print()/{{ }} output.
 */

static ngx_int_t
ngx_http_ucode_res_strcopy(ngx_pool_t *pool, ngx_str_t *dst, const char *src, size_t len)
{
    u_char *p;

    p = ngx_pnalloc(pool, len + 1);

    if (p == NULL) {
        ngx_str_null(dst);
        return NGX_ERROR;
    }

    ngx_memcpy(p, src, len);
    p[len] = '\0';

    dst->data = p;
    dst->len = len;

    return NGX_OK;
}

#define ngx_http_ucode_name_eq(name, nlen, lit) \
    uc_http_name_is(name, nlen, lit, sizeof(lit) - 1)

static uc_value_t *
ngx_http_ucode_res_status(uc_vm_t *vm, size_t nargs)
{
    ngx_http_ucode_res_t *resp = uc_fn_thisval(NGX_HTTP_UCODE_RESP_TYPE);
    uc_value_t *code = uc_fn_arg(0);
    uc_value_t *phrase = uc_fn_arg(1);
    int64_t status;

    if (!resp || !code)
        return NULL;

    status = ucv_to_integer(code);

    if (status < NGX_HTTP_CONTINUE || status > 599) {
        uc_vm_raise_exception(vm, EXCEPTION_RUNTIME,
                              "HTTP status code out of range: %" PRId64,
                              status);
        return NULL;
    }

    resp->r->headers_out.status = (ngx_uint_t) status;

    if (phrase && ucv_type(phrase) != UC_NULL) {
        char *p = ucv_to_string(vm, phrase);
        ngx_str_t sl;
        size_t plen = p ? strlen(p) : 0;

        /* the phrase lands verbatim in the status line, so it must not be
         * able to terminate it */
        if (!uc_http_is_field_value(p ? p : "", plen)) {
            free(p);
            uc_vm_raise_exception(vm, EXCEPTION_RUNTIME,
                                  "invalid character in HTTP reason phrase");
            return NULL;
        }

        sl.len = 3 + 1 + plen; /* "418" SP phrase */
        sl.data = ngx_pnalloc(resp->r->pool, sl.len + 1);

        if (sl.data) {
            ngx_sprintf(sl.data, "%03ui %*s", (ngx_uint_t) status, plen,
                        p ? p : "");
            sl.data[sl.len] = '\0';
            resp->r->headers_out.status_line = sl;
        }

        free(p);
    }

    return NULL;
}

/*
 * Content-Type and Location live in dedicated headers_out members rather
 * than the generic header list, so they are always single-valued: both
 * set_header() and add_header() replace the previous value.
 *
 * Content-Length is deliberately ignored - the body length is known only
 * once the template has finished, and ngx_http_ucode_run() computes it.
 *
 * Returns true when the header was handled here.
 */
static bool
ngx_http_ucode_res_header_special(ngx_http_request_t *r, const char *nv,
    size_t nlen, const char *vv, size_t vlen)
{
    if (ngx_http_ucode_name_eq(nv, nlen, "Content-Type")) {
        ngx_http_ucode_res_strcopy(r->pool, &r->headers_out.content_type,
                                   vv, vlen);
        r->headers_out.content_type_len = r->headers_out.content_type.len;
        r->headers_out.content_type_lowcase = NULL;
        return true;
    }

    if (ngx_http_ucode_name_eq(nv, nlen, "Content-Length")) {
        return true;
    }

    if (ngx_http_ucode_name_eq(nv, nlen, "Location")) {
        ngx_table_elt_t *he = r->headers_out.location;

        if (he == NULL) {
            he = ngx_list_push(&r->headers_out.headers);

            if (he == NULL) {
                return true;
            }

            he->key.data = (u_char *) "Location";
            he->key.len = sizeof("Location") - 1;
            he->hash = 1;
            r->headers_out.location = he;
        }

        ngx_http_ucode_res_strcopy(r->pool, &he->value, vv, vlen);
        return true;
    }

    return false;
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
    size_t nlen, vlen;
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

    nlen = strlen(nv);
    vlen = strlen(vv);

    if (!uc_http_is_token(nv, nlen)) {
        uc_vm_raise_exception(vm, EXCEPTION_RUNTIME,
                              "invalid response header name: %s", nv);
        free(nv);
        free(vv);
        return NULL;
    }

    if (!uc_http_is_field_value(vv, vlen)) {
        uc_vm_raise_exception(vm, EXCEPTION_RUNTIME,
                              "invalid character in value of response "
                              "header %s", nv);
        free(nv);
        free(vv);
        return NULL;
    }

    if (ngx_http_ucode_res_header_special(r, nv, nlen, vv, vlen)) {
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
                he[i].key.len == nlen &&
                ngx_strncasecmp(he[i].key.data, (u_char *) nv, nlen) == 0) {
                he[i].hash = 0;
            }
        }
    }

    he = ngx_list_push(&r->headers_out.headers);
    if (he) {
        if (ngx_http_ucode_res_strcopy(r->pool, &he->key, nv, nlen) != NGX_OK
            || ngx_http_ucode_res_strcopy(r->pool, &he->value, vv, vlen)
                   != NGX_OK) {
            he->hash = 0;
        } else {
            he->hash = 1;
        }
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
    lcf->cgi_headers = NGX_CONF_UNSET;

    return lcf;
}

static char *
ngx_http_ucode_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_ucode_loc_conf_t *prev = parent;
    ngx_http_ucode_loc_conf_t *conf = child;

    /*
     * conf->file is deliberately NOT inherited: ucode_content installs a
     * content handler for exactly the location it appears in, like every
     * other nginx content-handler directive.  A nested location without its
     * own ucode_content must keep serving whatever it is configured for.
     */

    ngx_conf_merge_uint_value(conf->methods, prev->methods,
                              NGX_HTTP_GET | NGX_HTTP_HEAD | NGX_HTTP_OPTIONS);
    ngx_conf_merge_value(conf->cgi_headers, prev->cgi_headers, 1);

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

    /* HEAD is GET without a body everywhere else in nginx; keep it that way
     * so "ucode_methods GET POST" does not answer HEAD with 405 */
    if (methods & NGX_HTTP_GET) {
        methods |= NGX_HTTP_HEAD;
    }

    lcf->methods = methods;

    return NGX_CONF_OK;
}

static char *
ngx_http_ucode_content(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_ucode_loc_conf_t *lcf = conf;
    ngx_http_core_loc_conf_t  *clcf;
    ngx_file_info_t            fi;
    ngx_str_t                 *args;

    if (lcf->file.len) {
        return "is duplicate";
    }

    args = cf->args->elts;
    lcf->file = args[1];

    /* resolve a relative template path against the angie prefix */
    if (ngx_conf_full_name(cf->cycle, &lcf->file, 0) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    if (ngx_file_info(lcf->file.data, &fi) == NGX_FILE_ERROR) {
        ngx_conf_log_error(NGX_LOG_WARN, cf, ngx_errno,
                           "ucode template \"%V\" is not accessible",
                           &lcf->file);
    }

    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    clcf->handler = ngx_http_ucode_handler;

    return NGX_CONF_OK;
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

/*
 * Called by the vendored parser before the headers of each part (both for
 * the first part and after every subsequent boundary), so this is where all
 * per-part state has to be reset - otherwise a plain field following a file
 * upload inherits the previous part's filename and content type.
 */
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

    ngx_str_null(&mp->name);
    ngx_str_null(&mp->filename);
    ngx_str_null(&mp->ctype);
    ngx_str_null(&mp->hfield);
    mp->has_filename = 0;

    return 0;
}

/*
 * ngx_str_t wrapper around uc_http_param(): resolve the returned offset into
 * a slice of the header value.
 */
static bool
ngx_http_ucode_mp_param(ngx_str_t *dst, u_char *hv, size_t hl,
    const char *attr, size_t alen)
{
    size_t off, len;

    if (!uc_http_param((const char *) hv, hl, attr, alen, &off, &len)) {
        return false;
    }

    dst->data = hv + off;
    dst->len = len;

    return true;
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

        ngx_http_ucode_mp_param(&mp->name, hv, hl, "name", 4);

        if (ngx_http_ucode_mp_param(&mp->filename, hv, hl, "filename", 8)) {
            mp->has_filename = 1;
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
ngx_http_ucode_parse_multipart(ngx_http_request_t *r, uc_vm_t *vm,
    uc_value_t *form, uc_value_t *files, ngx_str_t *body, ngx_str_t *boundary)
{
    multipart_parser            *mp;
    multipart_parser_settings    settings;
    ngx_http_ucode_mp_t          ctx;
    ngx_pool_t                  *pool = r->pool;
    size_t                       rc;
    char                        *bnd;

    /* RFC 2046 caps the boundary at 70 characters */
    if (boundary->len == 0 || boundary->len > 70) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "ucode: multipart body with missing or oversized "
                      "boundary, ignored");
        return NGX_OK;
    }

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

    ngx_memzero(&ctx, sizeof(ctx));
    ctx.pool = pool;
    ctx.vm = vm;
    ctx.form = form;
    ctx.files = files;

    multipart_parser_set_data(mp, &ctx);

    /* the parser reads buf[0..len), so the body is passed in place */
    rc = multipart_parser_execute(mp, (const char *) body->data, body->len);

    if (ctx.buf) {
        printbuf_free(ctx.buf);
    }

    multipart_parser_free(mp);

    /* the parser reports the first byte it could not consume on error;
     * whatever was decoded up to that point stays in request.form/files */
    if (rc < body->len) {
        ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                      "ucode: malformed multipart body, stopped at offset %uz "
                      "of %uz", rc, body->len);
    }

    return NGX_OK;
}

/* ------------------------------------------------------------------------- */

#define ngx_http_ucode_ct_eq(ct, type) \
    uc_http_media_type_is((const char *) (ct)->data, (ct)->len, type, \
                          sizeof(type) - 1)

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
    uc_value_t         *form, *files;

    body.len = 0;
    body.data = NULL;

    if (r->request_body && r->request_body->bufs) {
        for (cl = r->request_body->bufs; cl; cl = cl->next) {
            len += (size_t) ngx_buf_size(cl->buf);
        }

        p = ngx_pnalloc(r->pool, len + 1);
        if (p == NULL) {
            goto empty;
        }

        body.data = p;

        for (cl = r->request_body->bufs; cl; cl = cl->next) {
            ngx_buf_t *b = cl->buf;

            if (ngx_buf_in_memory(b)) {
                size_t sz = b->last - b->pos;

                ngx_memcpy(p, b->pos, sz);
                p += sz;
            } else if (b->in_file) {
                size_t  want = (size_t) (b->file_last - b->file_pos);
                off_t   at = b->file_pos;

                while (want) {
                    ssize_t n = ngx_read_file(b->file, p, want, at);

                    if (n <= 0) {
                        ngx_log_error(NGX_LOG_ERR, r->connection->log, ngx_errno,
                                      "ucode: reading buffered request body "
                                      "from \"%V\" failed", &b->file->name);
                        goto empty;
                    }

                    p += n;
                    at += n;
                    want -= (size_t) n;
                }
            }
        }

        body.len = (size_t) (p - body.data);
        *p = '\0';
    }

empty:

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

    if (r->headers_in.content_type) {
        ct = r->headers_in.content_type->value;
    }

    /* application/json or any */
    if (ngx_http_ucode_ct_eq(&ct, "application/json")
        || uc_http_media_type_is_json((const char *) ct.data, ct.len)) {
        uc_value_t *json = ngx_http_ucode_parse_json(&ctx->vm, &body);

        if (json) {
            ucv_object_add(ctx->request, "json", json);
        } else {
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "ucode: request body is not valid JSON, "
                          "request.json left unset");
        }
        return;
    }

    /* application/x-www-form-urlencoded */
    if (ngx_http_ucode_ct_eq(&ct, "application/x-www-form-urlencoded")) {
        ngx_http_ucode_parse_urlencoded(r->pool, &ctx->vm, form, &body);
        return;
    }

    /* multipart/form-data; boundary=... */
    if (ngx_http_ucode_ct_eq(&ct, "multipart/form-data")) {
        ngx_str_t boundary = ngx_null_string;

        ngx_http_ucode_mp_param(&boundary, ct.data, ct.len, "boundary", 8);

        ngx_http_ucode_parse_multipart(r, &ctx->vm,
            form, files, &body, &boundary);
        return;
    }
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
 *              request.headers["header-name"]  (lower-cased name -> array
 *              of all values),
 *              request.body, request.json, request.form, request.files
 *   response - response object with response.status(code[, phrase]),
 *              response.set_header(name, value) and
 *              response.add_header(name, value)
 *
 * Classic CGI variables are also available as top-level globals:
 * REQUEST_METHOD, REQUEST_URI, QUERY_STRING, SCRIPT_NAME, REMOTE_ADDR and
 * SERVER_PROTOCOL.
 *
 * As a fallback, a CGI-style header block (Content-Type:/Status:/X-...)
 * printed at the very start of the output is also applied to the response
 * (and stripped from the body), mirroring uhttpd templates.  See
 * uc_http_cgi_block_len() for what counts as a header block, and
 * "ucode_cgi_headers off" to disable it.
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
    ngx_pool_cleanup_t   *cln;
    ngx_uint_t            i;
    ngx_list_part_t      *part;
    ngx_table_elt_t      *h;

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_ucode_ctx_t));
    if (ctx == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    /*
     * The VM and its search paths are heap allocations that outlive this
     * function but are not owned by the request pool, and the request can be
     * torn down before the body handler ever runs (client abort, or a 413
     * from ngx_http_read_client_request_body).  Register the cleanup up
     * front so those paths cannot leak.
     */
    cln = ngx_pool_cleanup_add(r->pool, 0);
    if (cln == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    cln->handler = ngx_http_ucode_cleanup;
    cln->data = ctx;

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
    ctx->vm_valid = 1;

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
    if (restype == NULL || resp == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
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

    /*
     * Request headers are keyed by their lower-cased name: h->key preserves
     * whatever casing the client happened to send, which would make lookups
     * client-dependent (and HTTP/2 lower-cases names on the wire anyway).
     */
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
            /* h->lowcase_key is not NUL-terminated, so map_add() copies it */
            ngx_http_ucode_map_add(r->pool, &ctx->vm, hdr,
                (const char *) h[i].lowcase_key, h[i].key.len,
                ucv_string_new_length((const char *) h[i].value.data,
                                      h[i].value.len));
        }
    }

    ucv_object_add(request, "headers", hdr);

    ctx->request = request;

    /* expose the request object to the template as the global "request" */
    ucv_object_add(uc_vm_scope_get(&ctx->vm), "request", request);

    /* stash the context on the request for the body handler */
    ngx_http_set_ctx(r, ctx, ngx_http_ucode_module);

    return NGX_OK;
}

/*
 * Release the ucode VM.  Called either explicitly once the template has run
 * or, if the request never got that far, from the request pool cleanup.
 */
static void
ngx_http_ucode_cleanup(void *data)
{
    ngx_http_ucode_ctx_t *ctx = data;

    if (!ctx->vm_valid) {
        return;
    }

    ctx->vm_valid = 0;
    ctx->request = NULL;

    uc_vm_free(&ctx->vm);
    uc_search_path_free(&ctx->config.module_search_path);
    uc_search_path_free(&ctx->config.force_dynlink_list);
}

/*
 * Apply one header of a validated CGI block to the response.  Values the
 * template already set through the "response" object take precedence.
 */
static void
ngx_http_ucode_cgi_apply(ngx_http_request_t *r, uc_http_header_t *hdr)
{
    ngx_str_t value;

    value.data = (u_char *) hdr->value;
    value.len = hdr->value_len;

    if (ngx_http_ucode_name_eq(hdr->name, hdr->name_len, "Status")) {
        ngx_int_t sc = ngx_atoi(value.data, value.len);

        /* the code may be followed by a reason phrase */
        if (sc == NGX_ERROR) {
            u_char *sp = ngx_strlchr(value.data, value.data + value.len, ' ');

            if (sp) {
                sc = ngx_atoi(value.data, sp - value.data);
            }
        }

        if (sc < NGX_HTTP_CONTINUE || sc > 599) {
            ngx_log_error(NGX_LOG_INFO, r->connection->log, 0,
                          "ucode: ignoring out-of-range CGI status \"%V\"",
                          &value);

        } else if (r->headers_out.status == 0) {
            r->headers_out.status = (ngx_uint_t) sc;
        }

        return;
    }

    if ((ngx_http_ucode_name_eq(hdr->name, hdr->name_len, "Content-Type")
         && r->headers_out.content_type.len)
        || (ngx_http_ucode_name_eq(hdr->name, hdr->name_len, "Location")
            && r->headers_out.location)) {
        /* already set through the response object; that wins */
        return;
    }

    if (!ngx_http_ucode_res_header_special(r, hdr->name, hdr->name_len,
                                           hdr->value, hdr->value_len)) {
        ngx_table_elt_t *he = ngx_list_push(&r->headers_out.headers);

        if (he) {
            if (ngx_http_ucode_res_strcopy(r->pool, &he->key, hdr->name,
                    hdr->name_len) != NGX_OK
                || ngx_http_ucode_res_strcopy(r->pool, &he->value, hdr->value,
                       hdr->value_len) != NGX_OK) {
                he->hash = 0;
            } else {
                he->hash = 1;
            }
        }
    }
}

/*
 * uhttpd-style fallback: apply a CGI header block printed by the template
 * and return the offset of the response body within the output.  The block
 * is validated as a whole first (see uc_http_cgi_block_len), so output that
 * only looks header-ish - `{"error":"nope"}` and friends - is left alone.
 */
static size_t
ngx_http_ucode_cgi_headers(ngx_http_request_t *r, u_char *buf, size_t len)
{
    ngx_http_ucode_loc_conf_t *lcf;
    uc_http_header_t           hdr;
    size_t                     body_off, off = 0;

    lcf = ngx_http_get_module_loc_conf(r, ngx_http_ucode_module);

    if (!lcf->cgi_headers || len == 0) {
        return 0;
    }

    body_off = uc_http_cgi_block_len((const char *) buf, len);

    if (body_off == 0) {
        return 0;
    }

    while (off < body_off
           && uc_http_cgi_line((const char *) buf, len, &off, &hdr)
                  == UC_HTTP_CGI_HEADER) {
        ngx_http_ucode_cgi_apply(r, &hdr);
    }

    return body_off;
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
    char               *obuf = NULL;
    size_t              osize = 0;
    FILE               *out;
    u_char             *out_buf = NULL;
    ngx_buf_t          *b;
    ngx_chain_t        *cl;
    ngx_int_t           rc, status;
    size_t              off, body_len;

    ngx_http_ucode_body_parse(ctx);

    /* compile template */
    src = uc_source_new_file((const char *) ctx->file.data);
    if (src == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, errno,
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

    /* capture template output in memory */
    out = open_memstream(&obuf, &osize);
    if (out == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, errno,
                      "ucode: open_memstream() failed");
        uc_program_put(program);
        goto fail;
    }

    ctx->vm.output = out;

    status = (ngx_int_t) uc_vm_execute(&ctx->vm, program, &res);

    /* The result is not guaranteed to be assigned when execution fails. */
    if (res != NULL) {
        ucv_put(res);
    }

    uc_program_put(program);

    /* fclose() flushes and publishes obuf/osize; drop the dangling handle */
    fclose(out);
    ctx->vm.output = stdout;

    if (status != STATUS_OK) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                      "ucode: execution error: %s",
                      ctx->vm.exception.message ? ctx->vm.exception.message : "?");
        free(obuf);
        goto fail;
    }

    if (osize) {
        out_buf = ngx_pnalloc(r->pool, osize + 1);

        if (out_buf == NULL) {
            free(obuf);
            goto fail;
        }

        ngx_memcpy(out_buf, obuf, osize);
        out_buf[osize] = '\0';
    }

    free(obuf);

    off = osize ? ngx_http_ucode_cgi_headers(r, out_buf, osize) : 0;
    body_len = osize - off;

    if (r->headers_out.content_type.len == 0) {
        ngx_str_set(&r->headers_out.content_type, "text/html; charset=utf-8");
        r->headers_out.content_type_len = r->headers_out.content_type.len;
    }

    if (r->headers_out.status == 0) {
        r->headers_out.status = NGX_HTTP_OK;
    }

    r->headers_out.content_length_n = body_len;

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        ngx_http_ucode_cleanup(ctx);
        ngx_http_finalize_request(r, rc);
        return;
    }

    cl = ngx_alloc_chain_link(r->pool);
    b = ngx_calloc_buf(r->pool);

    if (cl == NULL || b == NULL) {
        goto fail;
    }

    /*
     * A template that only sets headers produces no output at all.  Such a
     * buffer must carry no memory flags, otherwise ngx_buf_special() is
     * false and the write filter rejects it as a "zero size buf".
     */
    if (body_len) {
        b->pos = out_buf + off;
        b->last = out_buf + osize;
        b->memory = 1;
    } else {
        b->sync = 1;
    }

    b->last_buf = (r == r->main) ? 1 : 0;
    b->last_in_chain = 1;

    cl->buf = b;
    cl->next = NULL;

    rc = ngx_http_output_filter(r, cl);

    ngx_http_ucode_cleanup(ctx);
    ngx_http_finalize_request(r, rc);
    return;

fail:
    ngx_http_ucode_cleanup(ctx);
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

    ctx = ngx_http_get_module_ctx(r, ngx_http_ucode_module);
    if (ctx == NULL) {
        ngx_http_finalize_request(r, NGX_HTTP_INTERNAL_SERVER_ERROR);
        return;
    }

    ngx_http_ucode_run(r, ctx);
}

/*
 * Answer a method that ucode_methods did not wire to the template with
 * 405 and an Allow: header listing the ones it did.
 */
static ngx_int_t
ngx_http_ucode_not_allowed(ngx_http_request_t *r, ngx_uint_t methods)
{
    static u_char    body[] = "405 Method Not Allowed" CRLF;
    ngx_uint_t       m;
    ngx_str_t        allow;
    u_char          *p;
    ngx_buf_t       *b;
    ngx_chain_t      cl;
    ngx_table_elt_t *he;
    ngx_int_t        rc;
    size_t           len = 0;

    /* an unread body would be taken for a pipelined request on keepalive */
    rc = ngx_http_discard_request_body(r);
    if (rc != NGX_OK) {
        return rc;
    }

    for (m = 0; ngx_http_ucode_method_names[m].name; m++) {
        if (methods & ngx_http_ucode_method_names[m].bit) {
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
        if (methods & ngx_http_ucode_method_names[m].bit) {
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

    if (allow.len) {
        he = ngx_list_push(&r->headers_out.headers);
        if (he == NULL) {
            return NGX_HTTP_INTERNAL_SERVER_ERROR;
        }

        he->hash = 1;
        ngx_str_set(&he->key, "Allow");
        he->value = allow;
    }

    r->headers_out.status = NGX_HTTP_NOT_ALLOWED;
    ngx_str_set(&r->headers_out.content_type, "text/plain");
    r->headers_out.content_type_len = r->headers_out.content_type.len;
    r->headers_out.content_length_n = sizeof(body) - 1;

    rc = ngx_http_send_header(r);

    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) {
        return rc;
    }

    b = ngx_calloc_buf(r->pool);
    if (b == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    b->pos = body;
    b->last = body + sizeof(body) - 1;
    b->memory = 1;
    b->last_buf = (r == r->main) ? 1 : 0;
    b->last_in_chain = 1;

    cl.buf = b;
    cl.next = NULL;

    return ngx_http_output_filter(r, &cl);
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

    if (!(lcf->methods & (ngx_uint_t) r->method)) {
        return ngx_http_ucode_not_allowed(r, lcf->methods);
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
