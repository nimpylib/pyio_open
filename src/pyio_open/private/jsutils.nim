
template jsTryCatchE*(body, catchBody) {.dirty.} =
  {.emit: "try {".}
  body
  {.emit: "} catch (e) {".}
  catchBody
  {.emit: "}".}
