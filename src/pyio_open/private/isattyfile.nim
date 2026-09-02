
when defined(js):
  import ./[fileobj_js, isatty]
  proc isatty*(f: fileobj_js.File): bool =
    isatty(f.fd.int, denoHandle(f), usesDenoFile(f))
else:
  from std/terminal import isatty
  export isatty
