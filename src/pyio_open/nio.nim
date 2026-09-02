
when defined(js):
  import ./private/fileobj_js
  export fileobj_js
else:
  import std/syncio
  export syncio

