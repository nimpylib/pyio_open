## JS target only (Node.js/Deno)
## 
## it re-declares `File`/`FileHandle` and implements file IO
## on top of `node:fs` or Deno's synchronous FsFile API,
## modeled after `std/syncio`

import std/jsffi
import pkg/jscompat/utils/[dispatch, deno]
import pkg/pyerrors/oserr
import pkg/jscompat/utils/oserr
import pkg/errno/errnoUtils
import ./jsutils

const JS_READ_BUF_SIZE = 8192

#-------- JS side helpers ---------

proc jsBufAlloc(n: cint): JsObject {.importjs: "Buffer.alloc(#)".}
proc jsBufFromBytes(s: string): JsObject {.importjs: "Buffer.from(#)".}
proc jsBufLen(b: JsObject): cint {.importjs: "#.length".}
proc jsByteOf(b: JsObject, i: cint): char {.importjs: "#[#]".}
proc jsFstatSize(o: JsObject): cint {.importjs: "#.size".}
proc consoleLog(s: cstring) {.importjs: "console.log(#)".}
proc consoleError(s: cstring) {.importjs: "console.error(#)".}

proc fsOpenSync(path: cstring, flags: cstring): cint {.importjs: fs"openSync".}
proc fsCloseSync(fd: cint) {.importjs: fs"closeSync".}
# NOTE: `pos` must be a JS `number` (not a BigInt) for node's `fs`
proc fsReadSync(fd: cint, buf: JsObject, offset: cint, len: cint, pos: cint | JsObject = jsUndefined): cint {.
  importjs: fs"readSync".}
proc fsWriteSync(fd: cint, buf: JsObject, offset: cint, len: cint, pos: cint | JsObject = jsUndefined): cint {.
  importjs: fs"writeSync".}
proc fsFstatSync(fd: cint): JsObject {.importjs: fs"fstatSync".}
proc fsFsyncSync(fd: cint) {.importjs: fs"fsyncSync".}
proc jsvmIsatty(fd: cint): cint {.importc: ttyOrDenoInJs & ".isatty".}

proc denoOpenSync(path: cstring, opts: JsObject): JsObject {.
  importjs: "Deno.openSync(#, #)".}
proc denoClose(f: JsObject) {.importjs: "#.close()".}
proc denoReadSync(f, buf: JsObject): cint {.importjs: "(#.readSync(#) ?? 0)".}
proc denoWriteSync(f, buf: JsObject): cint {.importjs: "#.writeSync(#)".}
proc denoBufSlice(buf: JsObject, start: cint): JsObject {.importjs: "#.subarray(#)".}
proc denoSeekSync(f: JsObject, pos: cint, whence: cint): cint {.
  importjs: "#.seekSync(#, #)".}
proc denoSync(f: JsObject) {.importjs: "#.syncSync()".}
proc denoSyncIfSupported(f: JsObject) {.importjs: "#.syncSync?.()".}

template jsExpr(x: string): JsObject =
  var temp: JsObject
  {.emit: [temp, " = " & x].}
  temp

proc denoOpenOpts(mode: FileMode): JsObject =
  case mode
  of fmRead: jsExpr"({read: true})"
  of fmWrite: jsExpr"({write: true, create: true, truncate: true})"
  of fmReadWrite: jsExpr"({read: true, write: true, create: true, truncate: true})"
  of fmReadWriteExisting: jsExpr"({read: true, write: true})"
  of fmAppend: jsExpr"({write: true, create: true, append: true})"

proc denoErrno(name: string): cint =
  case name
  of "NotFound": ErrNoent.cint
  of "AlreadyExists": ErrExist.cint
  of "IsADirectory": ErrIsdir.cint
  else: 0

#------------------------------------
# NOTE: `catchJsErrAndRaise` and `catchJsErrAndSetErrno` used below
# come from `pkg/pyerrors/oserr` (imported by pyio_open.nim)

type
  FileHandle* = distinct cint
  File* = ref object
    fd*: FileHandle
    denoFile: JsObject
    isDenoFile: bool
    isStd: bool
    basePos*: int64  # pos when read-buffer is inactive
    name*: string
    writable*: bool
    append*: bool
    # read-buffer, used for getFilePos consistency
    rbuf: JsObject
    rbufValid: bool
    rbufLen: cint
    rbufPos: cint
    rbufStart: int64
    # 1-char pushback, used by `pyio_open.peekChar`
    hasPB: bool
    pb: char

proc getFileHandle*(f: File): FileHandle = f.fd

proc discardRbuf(f: File) =
  f.hasPB = false
  if f.rbufValid:
    f.basePos = f.rbufStart + int64(f.rbufPos)
    f.rbufValid = false

proc getFilePos*(f: File): int64 =
  if f.rbufValid: f.rbufStart + int64(f.rbufPos)
  else: f.basePos

proc fillRbuf(f: File): bool =
  if not f.rbufValid:
    f.rbuf = jsBufAlloc(JS_READ_BUF_SIZE.cint)
    f.rbufValid = true
  var n: cint
  jsTryAsIOError:
    if f.isDenoFile:
      if not f.isStd:
        discard denoSeekSync(f.denoFile, cint(f.basePos), 0)
      n = denoReadSync(f.denoFile, f.rbuf)
    elif f.isStd:
      n = fsReadSync(f.fd.cint, f.rbuf, 0, JS_READ_BUF_SIZE.cint)
    else:
      n = fsReadSync(f.fd.cint, f.rbuf, 0, JS_READ_BUF_SIZE.cint, cint(f.basePos))
  if n <= 0: return false
  f.rbufStart = f.basePos
  f.rbufLen = n
  f.rbufPos = 0
  f.basePos += int64 n
  result = true

proc readChar*(f: File): char =
  if f.hasPB:
    f.hasPB = false
    inc f.rbufPos
    return f.pb
  if not f.rbufValid or f.rbufPos >= f.rbufLen:
    if not f.fillRbuf():
      raise newException(EOFError, "readChar got EOF")
  result = jsByteOf(f.rbuf, f.rbufPos)
  inc f.rbufPos

proc pushCharBack*(f: File, c: char) =
  f.hasPB = true
  f.pb = c
  if f.rbufValid and f.rbufPos > 0:
    dec f.rbufPos

proc readChars*(f: File, dst: var openArray[char], startIndex = 0): int =
  var i = startIndex
  while i < dst.len:
    try:
      dst[i] = f.readChar()
    except EOFError:
      break
    inc i
  result = i - startIndex

proc readAll*(f: File): string =
  var tmp: array[64 * 1024, char]
  while true:
    let n = f.readChars(tmp, 0)
    if n <= 0: break
    for i in 0..<n: result.add tmp[i]

proc write*(f: File, s: string) =
  if s.len == 0: return
  f.discardRbuf()
  let buf = jsBufFromBytes(s)
  let total = jsBufLen(buf)
  var written = 0
  catchJsErrAndRaise:
    block writeBlock:
      while written < total:
        let w =
          if f.isDenoFile:
            if not (f.isStd or f.append):
              discard denoSeekSync(f.denoFile,
                cint(f.basePos) + cint(written), 0)
            denoWriteSync(f.denoFile, denoBufSlice(buf, written))
          elif f.isStd or f.append:
            fsWriteSync(f.fd.cint, buf, written, total - written)
          else:
            fsWriteSync(f.fd.cint, buf, written, total - written,
              cint(f.basePos) + cint(written))
        if w <= 0: break writeBlock
        written += w
  if not f.append:
    f.basePos += int64(written)

proc setFilePos*(f: File, pos: int64, rel: FileSeekPos = fspSet) =
  if f.isStd:
    raise newException(IOError, "cannot set file position")
  f.discardRbuf()
  case rel
  of fspSet:
    f.basePos = pos
  of fspCur:
    f.basePos = f.basePos + pos
  of fspEnd:
    if f.isDenoFile:
      jsTryAsIOError:
        f.basePos = int64(denoSeekSync(f.denoFile, cint(pos), 2))
    else:
      var sz: cint
      jsTryAsIOError:
        sz = jsFstatSize(fsFstatSync(f.fd.cint))
      f.basePos = int64(sz) + pos

proc flushFile*(f: File) =
  if f.isStd: return
  if f.isDenoFile:
    if f.writable:
      jsTryAsIOError:
        denoSync(f.denoFile)
    return
  if f.writable:
    jsTryAsIOError:
      fsFsyncSync(f.fd.cint)

proc isatty*(f: File): bool =
  if f.isDenoFile:
    try:
      return denoIsTerminal(f.denoFile)
    except:
      return false
  if f.fd.cint < 0: return false
  if ttyOrDeno.isNull:
    result = f.fd.cint < 3
  else:
    result = jsvmIsatty(f.fd.cint) != 0

proc close*(f: File) =
  if f.isStd: return
  if f.isDenoFile:
    if f.fd.cint in 0..2: return  # never close stdio
    catchJsErrAndRaise:
      denoClose(f.denoFile)
    f.fd = FileHandle -1
    return
  if f.fd.cint < 3: return  # never close stdio
  catchJsErrAndRaise:
    fsCloseSync(f.fd.cint)
  f.fd = FileHandle -1

const jsPrivOpenFlags: array[FileMode, cstring] = [
  cstring"r", cstring"w", cstring"w+", cstring"r+", cstring"a"
]

proc open*(f: var File, p: string, mode: FileMode = fmRead): bool =
  if inDeno:
    var denoFile: JsObject
    var failed = false
    var errName: cstring
    jsTryCatchE:
      block:
        denoFile = denoOpenSync(cstring p, denoOpenOpts(mode))
    do:
      failed = true
      {.emit: [errName, " = e.name;"].}
    if failed:
      setErrnoRaw(denoErrno($errName))
      return false
    if denoFile.isNull or denoFile.isUndefined: return false
    f = File(fd: FileHandle -1, denoFile: denoFile, isDenoFile: true,
      name: p,
      writable: mode in {fmWrite, fmAppend, fmReadWriteExisting, fmReadWrite},
      append: mode == fmAppend)
    return true
  var fd: cint = -1
  catchJsErrAndSetErrno:
    fd = fsOpenSync(cstring p, jsPrivOpenFlags[mode])
  if fd < 0: return false
  f = File(
    fd: FileHandle fd,
    name: p,
    writable: mode in {fmWrite, fmAppend, fmReadWriteExisting, fmReadWrite},
    append: mode == fmAppend)
  result = true

proc open*(f: var File, filehandle: FileHandle,
    mode: FileMode = fmRead): bool =
  if filehandle.cint < 0: return false
  if inDeno:
    let denoFile = case filehandle.cint
      of 0: jsExpr"Deno.stdin"
      of 1: jsExpr"Deno.stdout"
      of 2: jsExpr"Deno.stderr"
      else: return false
    f = File(fd: filehandle, denoFile: denoFile, isDenoFile: true,
      isStd: true,
      name: "<fd " & $filehandle.int & ">",
      writable: mode != fmRead, append: mode == fmAppend)
  else:
    f = File(fd: filehandle, isStd: filehandle.cint in 0..2,
      name: "<fd " & $filehandle.int & ">",
      writable: mode != fmRead, append: mode == fmAppend)
  result = true

proc newStdFile(name: string, fd: int, mode: FileMode): File =
  discard result.open(FileHandle fd, mode)
  result.name = name

let
  stdin* = newStdFile("<stdin>", 0, fmRead)
  stdout* = newStdFile("<stdout>", 1, fmWrite)
  stderr* = newStdFile("<stderr>", 2, fmWrite)
