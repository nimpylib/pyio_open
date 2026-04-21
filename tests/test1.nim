
import std/unittest

import pyio_open as io
test "base":
  let f = io.open(currentSourcePath(), "r")
  check not f.closed
  f.close()

