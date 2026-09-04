# Package

version       = "0.1.0"
author        = "litlighilit"
description   = "provide open function like Python's io.open/builtins.open"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim > 2.0.8"

var pylibPre = "https://github.com/nimpylib"
let envVal = getEnv("NIMPYLIB_PKGS_BARE_PREFIX")
if envVal != "": pylibPre = ""
#if pylibPre == Def: pylibPre = ""
elif pylibPre[^1] != '/':
  pylibPre.add '/'
template pylib(x, ver) =
  requires if pylibPre == "": x & ver
           else: pylibPre & x

pylib "nimpatch", " ^= 0.1.1"
pylib "pyio_abc", " ^= 0.1.0"
pylib "pyerrors", " ^= 0.1.0"
pylib "pywarnings", " ^= 0.1.0"
pylib "auditfunc", " ^= 0.1.0"
pylib "jscompat", " ^= 0.1.1"
pylib "errno", " ^= 0.1.0"

import std/[algorithm, os]

proc testFiles(): seq[string] =
  for kind, path in walkDir("tests"):
    if kind == pcFile:
      let t = path.splitFile
      if t.name[0] == 't' and t.ext == ".nim":
        result.add path
  result.sort()
task t, "t": echo testFiles()

task testJs, "Test Node.js backend":
  for testFile in testFiles():
    exec "nim js -r -d:nodejs " & quoteShell(testFile)
  when defined(posix):
    exec "sh tests/test_stdin_readline.sh node"

task testDeno, "Test Deno backend":
  for testFile in testFiles():
    let name = testFile.splitFile.name
    let output = getTempDir() / (name & ".deno.js")
    exec "nim js -d:deno " & quoteShell("-o:" & output) & " " & quoteShell(testFile)
    exec "deno run --allow-read --allow-write " &
      quoteShell(output)
  when defined(posix):
    exec "sh tests/test_stdin_readline.sh deno"
