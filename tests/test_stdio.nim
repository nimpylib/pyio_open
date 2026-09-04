import std/unittest

import pyio_open as io
import pyio_open/nio

test "standard streams":
  check io.stdin.name == "<stdin>"
  check io.stdout.name == "<stdout>"
  check io.stderr.name == "<stderr>"
  check io.stdin.mode == "r"
  check io.stdout.mode == "w"
  check io.stderr.mode == "w"
  check io.stdin.fileno() == 0
  check io.stdout.fileno() == 1
  check io.stderr.fileno() == 2
  check io.stdin.read(0) == ""
  check io.stdout.write("") == 0
  check io.stderr.write("") == 0
  check io.stdin.isatty() in {false, true}
  check io.stdout.isatty() in {false, true}
  check io.stderr.isatty() in {false, true}
  check io.stdout.write("stdout") == 6
  check io.stdout.write("stdout\n") == 7
  check io.stdout.write("stdout stream works\n") == 20
  check io.stderr.write("stderr stream works\n") == 20
  io.stdout.flush()
  io.stderr.flush()
  nio.stdout.writeLine("stdout writeLine works")
  nio.stderr.writeLine("stderr writeLine works")

when defined(js) and defined(testStdinReadLine):
  test "read standard input lines":
    nio.stdout.writeLine("stdin-ready-1")
    check nio.stdin.readLine() == "first"
    nio.stdout.writeLine("stdin-ready-2")
    check nio.stdin.readLine() == "second"
    nio.stdout.writeLine("stdin-ready-3")
    check nio.stdin.readLine() == "last"
    nio.stdout.writeLine("stdin-ready-eof")
    expect EOFError:
      discard nio.stdin.readLine()
