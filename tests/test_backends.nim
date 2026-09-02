import std/unittest
import std/[strutils, unicode]

import pyio_open as io

const fn = "tempfiletest2"

proc binWrite(s: string) =
  var f = io.open(fn, "wb")
  discard f.write(bytes s)
  f.close()

proc binRead(): string =
  var f = io.open(fn, "rb")
  result = $f.read()
  f.close()

test "w+r":
  binWrite "abc"
  check binRead() == "abc"

test "reading newlines":
  binWrite "abc\r\n123\n-\r_"
  proc check(ls: varargs[string], newline: string) =
    var f = io.open(fn, newline=newline)
    for l in ls:
      let s = f.readline()
      check s == l
    f.close()

  check "abc\n", "123\n", "-\n", "_", newline=io.DefNewLine
  check "abc\r\n", "123\n", "-\r", "_", newline=""
  check "abc\r", "\n123\n-\r", "_", newline="\r"
  check "abc\r\n", "123\n", "-\r_", newline="\n"
  check "abc\r\n", "123\n-\r_", newline="\r\n"

test "writing newlines":
  proc checkW(s, dest: string, newline=io.DefNewLine, encoding=io.DefEncoding) =
    var f = io.open(fn, 'w', newline=newline, encoding=encoding)
    let expectLen = if newline == "\r\n": s.runeLen + s.count('\n') else: s.runeLen
    check f.write(s) == expectLen
    f.close()
    check binRead() == dest

  checkW "1\n2", (when defined(windows): "1\r\n2" else: "1\n2")
  checkW "1\n2", "1\r2", newline="\r"
  checkW "1\n2", "1\r\n2", newline="\r\n"
  checkW "我\n你", "我\n你", encoding="utf-8"

test "seek/tell (binary)":
  binWrite "abcdef1234567890"
  var f = io.open(fn, "r+b")
  defer: f.close()
  check f.seek(3) == 3
  check $f.read(3) == "def"
  check f.tell() == 6
  check f.seek(0, io.SEEK_END) == 16
  check f.seek(-10, io.SEEK_CUR) == 6
  var g = io.open(fn, "r")
  check g.seek(0) == 0  # text seek: positional reset
  g.close()

test "encoding":
  var f = io.open(fn, "w", encoding="utf-8")
  check f.write("我") == 1
  f.close()
  check binRead() == "我"
  var g = io.open(fn, "r", encoding="utf-8")
  check g.read() == "我"
  g.close()

test "errors":
  doAssertRaises FileNotFoundError:
    discard io.open("__file_that_does_not_exist__", "r")
  doAssertRaises LookupError:
    discard io.open(fn, encoding="this is a invalid enc")

when defined(js):
  test "read translates runtime errors and flush discards them":
    var reader = io.open(fn, "rb")
    let readerFile = reader
    reader.close()
    doAssertRaises IOError:
      discard readerFile.read()

    var writer = io.open(fn, "wb")
    let writerFile = writer
    writer.close()
    writerFile.flush()

test "closed":
  var f = io.open(fn, "r")
  check not f.closed
  f.close()
  check f.closed
