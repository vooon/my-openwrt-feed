/*
 * http_parse - the pure byte-level parsing used by ngx_http_ucode_module.
 * See http_parse.h for the contract of each function.
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

#include "http_parse.h"

#include <ctype.h>
#include <string.h>
#include <strings.h>


static bool
uc_http_is_space(char c)
{
    return c == ' ' || c == '\t';
}


bool
uc_http_is_token(const char *s, size_t len)
{
    static const char specials[] = "!#$%&'*+-.^_`|~";
    size_t i;

    if (len == 0) {
        return false;
    }

    for (i = 0; i < len; i++) {
        unsigned char c = (unsigned char) s[i];

        if (!isalnum(c) && memchr(specials, c, sizeof(specials) - 1) == NULL) {
            return false;
        }
    }

    return true;
}


bool
uc_http_is_field_value(const char *s, size_t len)
{
    size_t i;

    for (i = 0; i < len; i++) {
        if (s[i] == '\r' || s[i] == '\n' || s[i] == '\0') {
            return false;
        }
    }

    return true;
}


bool
uc_http_name_is(const char *name, size_t name_len, const char *lit,
    size_t lit_len)
{
    return name_len == lit_len && strncasecmp(name, lit, lit_len) == 0;
}


bool
uc_http_param(const char *v, size_t v_len, const char *attr, size_t attr_len,
    size_t *off, size_t *len)
{
    size_t i = 0;

    while (i < v_len) {
        size_t s, q;

        /* advance to the start of the next parameter */
        while (i < v_len && v[i] != ';') {
            i++;
        }

        if (i == v_len) {
            return false;
        }

        i++; /* skip ';' */

        while (i < v_len && uc_http_is_space(v[i])) {
            i++;
        }

        if (v_len - i < attr_len + 1
            || strncasecmp(v + i, attr, attr_len) != 0
            || v[i + attr_len] != '=') {
            continue;
        }

        s = i + attr_len + 1;
        q = 0;

        if (s < v_len && v[s] == '"') {
            s++;
            while (s + q < v_len && v[s + q] != '"') {
                q++;
            }
        } else {
            while (s + q < v_len && v[s + q] != ';'
                   && !uc_http_is_space(v[s + q])) {
                q++;
            }
        }

        *off = s;
        *len = q;

        return true;
    }

    return false;
}


bool
uc_http_media_type_is(const char *ct, size_t ct_len, const char *type,
    size_t type_len)
{
    if (ct_len < type_len || strncasecmp(ct, type, type_len) != 0) {
        return false;
    }

    return ct_len == type_len
           || ct[type_len] == ';'
           || uc_http_is_space(ct[type_len]);
}


bool
uc_http_media_type_is_json(const char *ct, size_t ct_len)
{
    size_t len = ct_len;
    const char *semi = memchr(ct, ';', ct_len);

    if (semi != NULL) {
        len = (size_t) (semi - ct);
    }

    while (len && uc_http_is_space(ct[len - 1])) {
        len--;
    }

    return len > 5 && strncasecmp(ct + len - 5, "+json", 5) == 0;
}


int
uc_http_cgi_line(const char *buf, size_t len, size_t *off,
    uc_http_header_t *out)
{
    const char *line = buf + *off;
    size_t      avail = len - *off;
    const char *eol = memchr(line, '\n', avail);
    size_t      line_len = eol ? (size_t) (eol - line) : avail;
    const char *colon;

    *off += line_len + (eol ? 1 : 0);

    if (line_len == 0 || (line_len == 1 && line[0] == '\r')) {
        return UC_HTTP_CGI_END;
    }

    colon = memchr(line, ':', line_len);

    if (colon == NULL) {
        return UC_HTTP_CGI_INVALID;
    }

    out->name = line;
    out->name_len = (size_t) (colon - line);

    if (!uc_http_is_token(out->name, out->name_len)) {
        return UC_HTTP_CGI_INVALID;
    }

    out->value = colon + 1;
    out->value_len = line_len - out->name_len - 1;

    while (out->value_len && uc_http_is_space(out->value[0])) {
        out->value++;
        out->value_len--;
    }

    while (out->value_len
           && (out->value[out->value_len - 1] == '\r'
               || uc_http_is_space(out->value[out->value_len - 1]))) {
        out->value_len--;
    }

    if (!uc_http_is_field_value(out->value, out->value_len)) {
        return UC_HTTP_CGI_INVALID;
    }

    return UC_HTTP_CGI_HEADER;
}


size_t
uc_http_cgi_block_len(const char *buf, size_t len)
{
    uc_http_header_t hdr;
    size_t           off = 0;
    unsigned         headers = 0;

    while (off < len) {
        switch (uc_http_cgi_line(buf, len, &off, &hdr)) {
        case UC_HTTP_CGI_END:
            /* a leading blank line is a body starting with one */
            return headers ? off : 0;
        case UC_HTTP_CGI_INVALID:
            return 0;
        default:
            headers++;
            break;
        }
    }

    /* ran out of output without the terminating blank line */
    return 0;
}


static int
uc_http_unhex(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}


size_t
uc_http_urldecode(char *dst, const char *src, size_t src_len)
{
    size_t i, o = 0;

    for (i = 0; i < src_len; i++) {
        int hi, lo;

        if (src[i] == '%' && i + 2 < src_len
            && (hi = uc_http_unhex(src[i + 1])) >= 0
            && (lo = uc_http_unhex(src[i + 2])) >= 0) {
            dst[o++] = (char) ((hi << 4) | lo);
            i += 2;
        } else if (src[i] == '+') {
            dst[o++] = ' ';
        } else {
            dst[o++] = src[i];
        }
    }

    dst[o] = '\0';

    return o;
}


size_t
uc_http_urlencode(char *dst, const char *src, size_t src_len)
{
    static const char hex[] = "0123456789abcdef";
    size_t i, o = 0;

    for (i = 0; i < src_len; i++) {
        unsigned char c = (unsigned char) src[i];

        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            dst[o++] = (char) c;
        } else {
            dst[o++] = '%';
            dst[o++] = hex[c >> 4];
            dst[o++] = hex[c & 0x0f];
        }
    }

    dst[o] = '\0';

    return o;
}
