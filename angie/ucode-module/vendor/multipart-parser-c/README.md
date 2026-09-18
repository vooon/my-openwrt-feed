# vendored: multipart-parser-c

A battle-tested, self-contained HTTP `multipart/form-data` parser, vendored
unchanged (upstream files only, original MIT license preserved in `LICENSE`).

## Upstream

- Repository: https://github.com/iafonov/multipart-parser-c
- Author: Igor Afonov <afonov@gmail.com> (2012)
- Fork: MIT license; based on `node-formidable` by Felix Geisendörfer
- Vendored commit: `772639cf10db6d9f5a655ee9b7eb20b815fab396` (2015-12-14)
  (the final commit on the upstream `master` branch)

## Files

- `multipart_parser.c`, `multipart_parser.h` — the parser (verbatim upstream).

## Why

The angie-mod-ucode module needs to parse uploaded `multipart/form-data`
request bodies, which is a security-sensitive area (boundary / header /
content-length handling). Rather than hand-rolling a parser, we vendor this
proven, callback-driven state-machine implementation. It is embedded unchanged
so upstream fixes can be pulled in by re-syncing this directory.

## Updating

```
git -C <tmp> clone https://github.com/iafonov/multipart-parser-c
cp <tmp>/multipart_parser.c <tmp>/multipart_parser.h ./multipart-parser-c/
```
Update `LICENSE` (unchanged) and the commit SHA above.