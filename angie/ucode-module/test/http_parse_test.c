/*
 * Unit tests for ucode-module/http_parse.c - the byte-level parsing that the
 * angie module does on request and response data.  Builds and runs on the
 * host with nothing but a C compiler (see run_tests.sh).
 *
 * Every case here corresponds to something that was, or easily could be,
 * wrong: "name=" matching inside "filename=", prefix-only header name
 * comparisons, media types matched without their parameter delimiter, and a
 * CGI header block eating a JSON response body.
 */

#include "../http_parse.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static int failures;
static int checks;

static void
check(int cond, const char *fmt, ...)
{
    va_list ap;

    checks++;

    if (cond) {
        return;
    }

    failures++;

    fputs("FAIL: ", stderr);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

#define S(lit) lit, sizeof(lit) - 1

/* ------------------------------------------------------------------------ */

static void
test_token(void)
{
    check(uc_http_is_token(S("Content-Type")), "plain token accepted");
    check(uc_http_is_token(S("X-Foo_bar.baz~1")), "token specials accepted");

    check(!uc_http_is_token(S("")), "empty name rejected");
    check(!uc_http_is_token(S("X Foo")), "space in name rejected");
    check(!uc_http_is_token(S("X:Foo")), "colon in name rejected");
    check(!uc_http_is_token(S("X\rFoo")), "CR in name rejected");
    check(!uc_http_is_token(S("{\"error\"")), "JSON-ish name rejected");
}

static void
test_field_value(void)
{
    check(uc_http_is_field_value(S("text/html; charset=utf-8")),
          "plain value accepted");
    check(uc_http_is_field_value(S("")), "empty value accepted");

    check(!uc_http_is_field_value(S("a\r\nX-Evil: 1")),
          "CRLF injection rejected");
    check(!uc_http_is_field_value(S("a\nb")), "bare LF rejected");
    check(!uc_http_is_field_value("a\0b", 3), "NUL rejected");
}

static void
test_name_is(void)
{
    check(uc_http_name_is(S("content-type"), S("Content-Type")),
          "name compare is case insensitive");

    /* the bug: strncasecmp over name_len alone accepts a prefix */
    check(!uc_http_name_is(S("Content"), S("Content-Type")),
          "prefix is not Content-Type");
    check(!uc_http_name_is(S("S"), S("Status")), "prefix is not Status");
    check(!uc_http_name_is(S("Content-Type-Extra"), S("Content-Type")),
          "longer name is not Content-Type");
}

static void
test_param(void)
{
    static const char upload[] =
        "form-data; name=\"upload\"; filename=\"report.txt\"";
    static const char field[] = "form-data; name=\"comment\"";
    static const char bare[] = "form-data; name=comment; filename=a.txt";
    static const char ct[] = "multipart/form-data; boundary=--abc123";
    size_t off, len;

    /* the bug: "filename=" contains "name=" at offset 4 */
    check(uc_http_param(S(upload), S("name"), &off, &len)
          && len == 6 && memcmp(upload + off, "upload", 6) == 0,
          "file part keeps its field name, not the filename");

    check(uc_http_param(S(upload), S("filename"), &off, &len)
          && len == 10 && memcmp(upload + off, "report.txt", 10) == 0,
          "filename is extracted");

    check(uc_http_param(S(field), S("name"), &off, &len)
          && len == 7 && memcmp(field + off, "comment", 7) == 0,
          "plain field name is extracted");

    check(!uc_http_param(S(field), S("filename"), &off, &len),
          "plain field has no filename");

    check(uc_http_param(S(bare), S("name"), &off, &len)
          && len == 7 && memcmp(bare + off, "comment", 7) == 0,
          "unquoted parameter is extracted");

    check(uc_http_param(S(ct), S("boundary"), &off, &len)
          && len == 8 && memcmp(ct + off, "--abc123", 8) == 0,
          "boundary is extracted from a Content-Type");

    /* an attribute that only appears as a suffix must not match */
    check(!uc_http_param(S("form-data; filename=\"x\""), S("name"),
                         &off, &len),
          "filename alone does not provide a name");
}

static void
test_media_type(void)
{
    check(uc_http_media_type_is(S("application/json"), S("application/json")),
          "bare media type matches");
    check(uc_http_media_type_is(S("application/json; charset=utf-8"),
                                S("application/json")),
          "media type with parameter matches");
    check(uc_http_media_type_is(S("APPLICATION/JSON"), S("application/json")),
          "media type match is case insensitive");

    /* the bug: a plain prefix compare also matches this */
    check(!uc_http_media_type_is(S("application/jsonfoo"),
                                 S("application/json")),
          "longer media type does not match");
    check(!uc_http_media_type_is(S("application/js"), S("application/json")),
          "shorter media type does not match");

    check(uc_http_media_type_is_json(S("application/merge-patch+json")),
          "+json suffix matches");
    check(uc_http_media_type_is_json(S("application/ld+json; charset=utf-8")),
          "+json suffix with parameter matches");
    check(!uc_http_media_type_is_json(S("application/json")),
          "plain application/json is not a +json suffix");
    check(!uc_http_media_type_is_json(S("text/x+jsonish")),
          "+json must end the media type");
}

static void
test_cgi_block(void)
{
    static const char headers_then_body[] =
        "Content-Type: text/plain\r\n"
        "X-Foo: bar\r\n"
        "\r\n"
        "hello\n";
    static const char headers_only[] = "Status: 302\nLocation: /elsewhere\n\n";
    static const char no_blank_line[] = "Status: 302\nLocation: /elsewhere\n";
    static const char one_liner[] = "rejected: bad header\n";
    static const char json_body[] = "{\"hello\":\"vovan\"}";
    static const char json_pretty[] = "{\n  \"hello\": \"vovan\"\n}\n";
    static const char prose[] = "Error: not found\nplease try again\n";
    static const char html[] = "<h1>Hello</h1>\n";

    uc_http_header_t hdr;
    size_t off, body;

    body = uc_http_cgi_block_len(S(headers_then_body));
    check(body == sizeof("Content-Type: text/plain\r\nX-Foo: bar\r\n\r\n") - 1,
          "header block ends after the blank line, got %zu", body);
    check(strcmp(headers_then_body + body, "hello\n") == 0,
          "body survives the header block");

    off = 0;
    check(uc_http_cgi_line(S(headers_then_body), &off, &hdr)
              == UC_HTTP_CGI_HEADER
          && hdr.name_len == 12
          && memcmp(hdr.name, "Content-Type", 12) == 0
          && hdr.value_len == 10
          && memcmp(hdr.value, "text/plain", 10) == 0,
          "first header parses with CR and spaces stripped");

    check(uc_http_cgi_block_len(S(headers_only)) == sizeof(headers_only) - 1,
          "a body-less header block ending in a blank line is accepted");

    /* RFC 3875 requires the blank line; without it nothing is a header */
    check(uc_http_cgi_block_len(S(no_blank_line)) == 0,
          "header lines without the terminating blank line are body");
    check(uc_http_cgi_block_len(S(one_liner)) == 0,
          "a lone token: value line is body, not a header");
    check(uc_http_cgi_block_len(S("\r\nbody\n")) == 0,
          "a leading blank line is not a header block");

    /* the bug: this used to be parsed as a header named {"hello" */
    check(uc_http_cgi_block_len(S(json_body)) == 0,
          "single-line JSON body is not a header block");
    check(uc_http_cgi_block_len(S(json_pretty)) == 0,
          "pretty-printed JSON body is not a header block");

    /* a colon in prose must not swallow the rest of the output either */
    check(uc_http_cgi_block_len(S(prose)) == 0,
          "prose with a colon is not a header block");

    check(uc_http_cgi_block_len(S(html)) == 0, "HTML is not a header block");
    check(uc_http_cgi_block_len(S("")) == 0, "empty output has no headers");
}

static void
test_urlcodec(void)
{
    char buf[256];
    size_t n;

    n = uc_http_urldecode(buf, S("a+b%20c%2Fd"));
    check(n == 7 && strcmp(buf, "a b c/d") == 0, "urldecode, got \"%s\"", buf);

    n = uc_http_urldecode(buf, S("100%"));
    check(n == 4 && strcmp(buf, "100%") == 0,
          "trailing %% is literal, got \"%s\"", buf);

    n = uc_http_urldecode(buf, S("%zz"));
    check(n == 3 && strcmp(buf, "%zz") == 0,
          "invalid escape is literal, got \"%s\"", buf);

    n = uc_http_urlencode(buf, S("a b/c~d"));
    check(n == 11 && strcmp(buf, "a%20b%2fc~d") == 0,
          "urlencode, got \"%s\"", buf);

    /* round trip over every byte value, including NUL-adjacent ones */
    {
        char raw[256], enc[256 * 3 + 1], dec[256 + 1];
        size_t i;

        for (i = 0; i < sizeof(raw); i++) {
            raw[i] = (char) i;
        }

        n = uc_http_urlencode(enc, raw + 1, sizeof(raw) - 1);
        check(uc_http_urldecode(dec, enc, n) == sizeof(raw) - 1
              && memcmp(dec, raw + 1, sizeof(raw) - 1) == 0,
              "urlencode/urldecode round trip over all byte values");
    }
}

int
main(void)
{
    test_token();
    test_field_value();
    test_name_is();
    test_param();
    test_media_type();
    test_cgi_block();
    test_urlcodec();

    if (failures) {
        fprintf(stderr, "%d of %d checks failed\n", failures, checks);
        return 1;
    }

    fprintf(stderr, "http_parse: all %d checks passed\n", checks);
    return 0;
}
