/*
 * http_parse - the pure byte-level parsing used by ngx_http_ucode_module.
 *
 * These helpers deliberately depend on nothing but the C library so that
 * they can be exercised by test/http_parse_test.c on the build host.  Every
 * one of them guards a spot that has produced a bug before: unanchored
 * "name=" matching, prefix-only header name comparisons, media types matched
 * without their parameter delimiter, and CGI header blocks eating a body.
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

#ifndef _uc_http_parse_h
#define _uc_http_parse_h

#include <stdbool.h>
#include <stddef.h>

/* a name/value slice into a caller-owned buffer */
typedef struct {
    const char *name;
    size_t      name_len;
    const char *value;
    size_t      value_len;
} uc_http_header_t;

/* return codes of uc_http_cgi_line() */
enum {
    UC_HTTP_CGI_INVALID = -1,  /* not a "token: value" line */
    UC_HTTP_CGI_END     = 0,   /* blank line: end of the header block */
    UC_HTTP_CGI_HEADER  = 1    /* header parsed into *out */
};

/*
 * RFC 9110 field-name: a non-empty token.  Rejects ":", CR, LF and
 * whitespace, which is what keeps a template from injecting extra headers.
 */
bool uc_http_is_token(const char *s, size_t len);

/*
 * RFC 9110 field-value: anything without CR, LF or NUL.  A value that can
 * carry CRLF would let a template split the response.
 */
bool uc_http_is_field_value(const char *s, size_t len);

/*
 * Case-insensitive comparison against a literal, including the length - a
 * bare strncasecmp() over name_len would also accept "Content" as
 * "Content-Type".
 */
bool uc_http_name_is(const char *name, size_t name_len, const char *lit,
    size_t lit_len);

/*
 * Extract the value of parameter "attr" from a header value such as
 *
 *     form-data; name="upload"; filename="report.txt"
 *
 * The match is anchored on a preceding ";", so looking for "name" does not
 * also match the "name=" tail of "filename=".  Both the quoted and the bare
 * token form are accepted.  On success the value is delimited within v by
 * the returned off and len, and true is returned.
 */
bool uc_http_param(const char *v, size_t v_len, const char *attr,
    size_t attr_len, size_t *off, size_t *len);

/*
 * Compare a Content-Type against a bare media type, ignoring parameters:
 * "application/json; charset=utf-8" matches "application/json",
 * "application/jsonfoo" does not.
 */
bool uc_http_media_type_is(const char *ct, size_t ct_len, const char *type,
    size_t type_len);

/* Match the "+json" structured-syntax suffix, parameters ignored. */
bool uc_http_media_type_is_json(const char *ct, size_t ct_len);

/*
 * Parse one line of a CGI-style header block starting at *off, advancing
 * *off past it.  Returns one of the UC_HTTP_CGI_* codes; on
 * UC_HTTP_CGI_HEADER the name/value slices in *out point into buf, with
 * surrounding whitespace and the trailing CR already stripped.
 */
int uc_http_cgi_line(const char *buf, size_t len, size_t *off,
    uc_http_header_t *out);

/*
 * Length of the CGI header block at the start of buf, i.e. the offset at
 * which the response body begins, or 0 when there is no header block.
 *
 * Following RFC 3875 the block must consist of well-formed "token: value"
 * lines and must be terminated by a blank line.  Output that merely looks
 * header-ish is therefore left alone in its entirety - a body whose first
 * line happens to contain a colon (`{"error":"nope"}`, `Error: nope`) is
 * never mistaken for headers, and a template that prints only header lines
 * but forgets the blank line gets them as its body rather than silently
 * losing them.
 */
size_t uc_http_cgi_block_len(const char *buf, size_t len);

/*
 * Percent-decode src into dst, which needs room for src_len + 1 bytes.
 * "+" decodes to a space.  Returns the decoded length.
 */
size_t uc_http_urldecode(char *dst, const char *src, size_t src_len);

/*
 * Percent-encode src into dst, which needs room for src_len * 3 + 1 bytes.
 * Returns the encoded length.
 */
size_t uc_http_urlencode(char *dst, const char *src, size_t src_len);

#endif /* _uc_http_parse_h */
