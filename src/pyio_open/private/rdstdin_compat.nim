

const Nodejs = defined(nodejs)
const npythonJsAsyncReadline*{.booldefine.} = Nodejs

import pkg/jscompat/utils/asyncIfJs
when defined(js) and not npythonJsAsyncReadline:
  declarePlainNonAsync
else:
  export asyncIfJs
from pkg/pysimperr import KeyboardInterrupt
export KeyboardInterrupt
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

    proc newAbortController(): JsObject {.importjs: "new AbortController()".}

    {.pragma: plainCb, noconv, raises: [].}
    type Callback = proc (e: JsObject){.plainCb.}
    var curAbortController = jsUndefined

    proc rejectWithKeyboardInterrupt() {.plainCb.} =
      #[abort the pending `rl.question` (if any) with a `KeyboardInterrupt`.
       Aborting the `AbortSignal` makes node's readline reject the awaited
       promise with the exception *and* reset its internal question state
       (via `kQuestionCancel`), so that the exception is routed through the
       awaited promise (instead of being thrown out of the `SIGINT` handler)
       and a subsequent prompt is accepted.]#
      if not curAbortController.isUndefined:
        let c = curAbortController
        curAbortController = jsUndefined
        # we `raise` in `try` to setup exception env
        #   to ensure the `e` contains traceback (
        #     otherwise it even doesn't has `.name`
        #   ),
        # as this function is to be called in nodejs inner
        #   event loop
        try: raise new KeyboardInterrupt
        except KeyboardInterrupt as e:
          c.abort(e.toJs)

    proc initReadLine: InterfaceConstructorWrapper =
      {.emit: """
      // top level await must be on ES module
      //const { createInterface } = require('node:readline');
      //const { stdin: input, stdout: output } = require('node:process');

      const rl = createInterface({ input, output });
      """.}
      let rl{.importjs.}: InterfaceConstructor
      discard rl.on("SIGINT", rejectWithKeyboardInterrupt)
      result.obj = rl

    defdestroy InterfaceConstructorWrapper:
      self.obj.close()

    let rl = initReadLine()

    proc questionHandledEof(rl: InterfaceConstructor, ps: cstring
    ): Promise[cstring] =
      ## rl.question(ps) but:
      ## - EOF (ABORT_ERR) resolves as `nil`
      ## - SIGINT rejects with `KeyboardInterrupt`
      proc tnewPromise(cb: proc): typeof(result) {.importjs: "new Promise(@)".}
      result = tnewPromise proc (resolve, reject: Callback) {.raises: [].} =
        curAbortController = newAbortController()
        let opts = newJsObject()
        opts["signal"] = curAbortController.signal
        discard rl.question(ps, opts).then(
          proc (v: JsObject) =
            curAbortController = jsUndefined
            resolve(v)
          ,
          proc (e: JsObject) =
            curAbortController = jsUndefined
            if jsTypeof(e) == "object" and e.code.to(cstring) == "ABORT_ERR":
              let cause = e.cause
              if not cause.isUndefined and not cause.isNull:
                reject(cause)     # SIGINT: KeyboardInterrupt carried as reason
                return
              resolve(nil.toJs)   # EOF
              return
            reject(e)
        )
    
    proc cursorToNewLine{.noconv.} =
      console.log(cstring"")

    proc readLineFromStdinAsync(ps: cstring): cstring{.async.} =
      let res = await rl.obj.questionHandledEof ps
      if res.isNil:
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
  # Q: Why not use std/rdstdin?
  # A: rdstdin.readLineFromStdin cannot distinguish
  #   ctrlC and ctrlD and other error

  # condition copied from source code of rdstdin
  const notSupLinenoise = defined(windows) or defined(genode) or defined(wasm)
  when not notSupLinenoise:
    import std/linenoise
  else:
    import std/syncio

  proc readLineFromStdinMayAsync*(prompt: string): string{.mayAsync.} =
    when notSupLinenoise:
      stdout.write prompt
      stdout.flushFile
      mayNewPromise stdin.readLine()
    else:
      var res: ReadLineResult
      while true:
        readLineStatus(prompt, res)
        case res.status
        of lnCtrlC:
          #raise new InterruptError
          #errEchoCompatNoRaise"KeyboardInterrupt"
          raise new KeyboardInterrupt
        of lnCtrlD:
          raise new EOFError
        of lnCtrlUnkown:
          # neither ctrl-c nor ctrl-d getten
          #  e.g. simple input and pass Enter
          break
      historyAdd cstring res.line
      mayNewPromise res.line

