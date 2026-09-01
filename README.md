
# pyio_open

[![Test](https://github.com/nimpylib/pyio_open/actions/workflows/ci.yml/badge.svg)](https://github.com/nimpylib/pyio_open/actions/workflows/ci.yml)
[![Docs](https://github.com/nimpylib/pyio_open/actions/workflows/docs.yml/badge.svg)](https://github.com/nimpylib/pyio_open/actions/workflows/docs.yml)
<!--[![Commits](https://img.shields.io/github/last-commit/nimpylib/pyio_open?style=flat)](https://github.com/nimpylib/pyio_open/commits/)-->

---

[Docs](https://nimpylib.github.io/pyio_open/)

provide open function like Python's io.open/builtins.open
as well as some of functions in Lib/io

The JavaScript backend is supported experimentally on Node.js and Deno.

- Node.js: compile with `nim js -d:nodejs`.
- Deno: compile with `nim js -d:deno`, then run with `deno run --allow-read --allow-write`.

Filesystem access uses synchronous runtime APIs.
