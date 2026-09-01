when defined(js):
  import std/jsffi
  import pkg/jscompat/utils/dispatch
  proc cIsatty(fd: cint): cint {.importc: ttyOrDenoInJs & ".isatty".}
  proc denoStdinIsatty(): bool {.importjs: "Deno.stdin.isTerminal(@)".}
  proc denoStdoutIsatty(): bool {.importjs: "Deno.stdout.isTerminal(@)".}
  proc denoStderrIsatty(): bool {.importjs: "Deno.stderr.isTerminal(@)".}
  proc isatty*(fd: int): bool =
    if not notDeno:
      case fd
      of 0: denoStdinIsatty()
      of 1: denoStdoutIsatty()
      of 2: denoStderrIsatty()
      else: false
    elif ttyOrDeno.isNull: fd in 0..2
    else: cIsatty(fd.cint) != 0
else:
  when defined(posix):
    proc isatty(fildes: cint): cint {.
      importc: "isatty", header: "<unistd.h>".}
  else:
    proc isatty(fildes: cint): cint {.
      importc: "_isatty", header: "<io.h>".}

  func isatty*(fd: int): bool =
    isatty(fd.cint) != 0
