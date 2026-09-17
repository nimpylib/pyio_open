

const Nodejs = defined(nodejs)
const npythonJsAsyncReadline*{.booldefine.} = Nodejs

import pkg/jscompat/utils/asyncIfJs
when defined(js) and not npythonJsAsyncReadline:
  declarePlainNonAsync
else:
  export asyncIfJs

when defined(js):

  type ReadLineCb = proc(ps: cstring): MayPromise[cstring] {.raises: [KeyboardInterrupt, IOError, EOFError].}
  var rlCb: ReadLineCb
  proc setReadLine*(f: ReadLineCb) =
    rlCb = f

  when defined(nimPreviewSlimSystem):
    import std/assertions
  static:assert Nodejs == npythonJsAsyncReadline
  when Nodejs:
    import pkg/jscompat/utils/asyncIfJs/js
    import std/[jsffi, jsconsole]
    import pkg/nimpatch/destroyPatch

    type
      InterfaceConstructor = JsObject
      InterfaceConstructorWrapper = object
        obj: InterfaceConstructor
    {.emit: """/*INCLUDESECTION*/
     import {createInterface}  from 'node:readline/promises';
     import { stdin as input, stdout as output } from 'node:process';
     """.} # """ <- for code hint

    proc initReadLine: InterfaceConstructorWrapper =
      {.emit: """
      // top level await must be on ES module
      //const { createInterface } = require('node:readline');
      //const { stdin: input, stdout: output } = require('node:process');

      const rl = createInterface({ input, output });
      rl.on("SIGINT", ()=>{});
      // XXX: TODO: correctly handle ctrl-c (SIGINT)
      """.}
      # Python does not exit on ctrl-c
      # but re-asking a new input
      #  I'd tried to implement that but failed,
      #  current impl of handler is just doing nothing (an empty function)
      {.emit: [result.obj, "= rl;"].}

    defdestroy InterfaceConstructorWrapper:
      self.obj.close()

    proc cursorToNewLine{.noconv.} =
      console.log(cstring"")

    let rl = initReadLine()

    #proc question(rl: InterfaceConstructor, ps: cstring): Promise[cstring]{.importcpp.}
    proc questionHandledEof(rl: InterfaceConstructor, ps: cstring
    ): Promise[cstring] =
      ## rl.question(ps) but catch EOF and raise as EOFError
      {.emit: [
        result, " = ",
        rl, ".question(", ps, """).catch(e=>{
          if (typeof(e) === "object" && e.code === "ABORT_ERR") {""",
            r"return '\0';",
          """
          }
        });"""
        # """ <- for code hint
      ].}

    
    proc readLineFromStdinAsync(ps: cstring): cstring{.async.} =
      let res = await rl.obj.questionHandledEof ps
      if res == cstring("\0"):
        cursorToNewLine()
        raise new EOFError
      res

    setReadLine readLineFromStdinAsync
  else:
    proc prompt(ps: cstring): cstring#[nilable]#{.importc.}

    when not (defined(deno) or defined(jspure)):
      import std/jsffi
      import ./fileobj_js
    proc readLineFromStdin(ps: cstring): cstring =
      when defined(deno):
        # XXX: deno's prompt(ps) when ps is non-empty
        #   performs tty.clearline && readLineFromStdin(if ps.len==0:"" else: ps+" ")
        #
        {.push noconv.}
        proc length(s: cstring): cint {.importjs: "#.length".}
        proc endsWith(s: cstring, c: char): bool =
          s.len > 0 and s[s.high] == c
        proc substring(s: cstring, indexStart, indexEnd: cint): cstring {.importcpp.}
        proc removesuffix(s: cstring, sub: char): cstring =
          if s.endsWith sub: s.substring(0, s.length-1)
          else: s
        {.pop.}
        # XXX: we just try to keep consist
        # FIXME: if not ps.endsWith(' ')
        result = prompt ps.removesuffix' '
      elif defined(jspure):
        result = prompt ps
      else:
        if jsTypeof(prompt.toJs) != "undefined":
          result = prompt ps
        else:
          stdout.write ps
          stdout.flushFile()
          return cstring stdin.readLine
      if result.isNil:
        raise new EOFError

    setReadLine readLineFromStdin

  proc readLineFromStdinMayAsync*(ps: cstring): cstring{.mayAsync.} =
    mayAwait rlCb ps
  proc readLineFromStdinMayAsync*(ps: string): string{.mayAsync.} =
    $(mayAwait rlCb ps.cstring)
else:
  when not defined(wasm):
    import std/rdstdin
    template readLineFromStdinMayAsync*(prompt): string = 
      bind readLineFromStdin
      readLineFromStdin prompt
  else:
    when defined(nimPreviewSlimSystem):
      import std/syncio
    template readLineFromStdinMayAsync*(prompt): string = 
      stdout.write prompt
      stdout.flushFile()
      stdin.readLine()


