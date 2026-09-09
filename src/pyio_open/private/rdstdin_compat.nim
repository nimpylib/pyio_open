
import pkg/jscompat/utils/asyncIfJs
export asyncIfJs

when defined(js):
  import std/jsffi
  import pkg/jscompat/utils/asyncIfJs/js

  when defined(nodejs):
    import std/jsconsole
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

    proc question(rl: InterfaceConstructor, ps: cstring): Promise[cstring]{.importcpp.}
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

    
    proc readLineFromStdinMayAsync*(ps: cstring): cstring{.async.} =
      let res = await rl.obj.questionHandledEof ps
      if res == cstring("\0"):
        cursorToNewLine()
        raise new EOFError
      res
    proc readLineFromStdinMayAsync*(prompt: string): string{.async.} =
      $(await prompt.cstring.readLineFromStdinMayAsync)

  else:
    import std/jsffi
    proc prompt(ps: cstring): JsObject#[cstring or null]#{.importc.}

    proc readLineFromStdin(ps: cstring): JsObject =
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
        prompt ps.removesuffix' '
      else:
        prompt ps
    proc readLineFromStdin*(prompt: string): string =
      let res = prompt.cstring.readLineFromStdin
      if res.isNull:
        raise new EOFError
      $(res.to(cstring))
    # To make consist with nodejs's async
    proc readLineFromStdinMayAsync*(prompt: string): Promise[string] =
      newPromise readLineFromStdin prompt
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

const NPythonAsyncReadline* = declared(async)

