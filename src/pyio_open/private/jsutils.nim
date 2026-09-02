
template jsTryCatchE*(body, catchBody) {.dirty.} =
  {.emit: "try {".}
  body
  {.emit: "} catch (e) {".}
  catchBody
  {.emit: "}".}

template jsTryAsIOError*(body) {.dirty.} =
  var failed = false
  var msg: cstring
  jsTryCatchE:
    body
  do:
    failed = true
    {.emit: [msg, " = e.message ?? String(e);"].}
  if failed:
    raise newException(IOError, $msg)
