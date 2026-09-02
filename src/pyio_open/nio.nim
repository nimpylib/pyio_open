
when defined(js):
  import ./private/fileobj_js
  export fileobj_js except denoHandle, usesDenoFile
else:
  import std/syncio
  export syncio

