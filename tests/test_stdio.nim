import std/unittest

import pyio_open as io

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
  check io.stdout.write("stdout stream works\n") == 20
  check io.stderr.write("stderr stream works\n") == 20
  io.stdout.flush()
  io.stderr.flush()
