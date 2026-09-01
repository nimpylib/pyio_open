## EXT. Nim's codec.
##  not the same as Python's codec

import std/unicode
import pkg/pyerrors/lkuperr
export LookupError

# XXX: not take effect yet
type EncErrors*{.pure.} = enum
  strict  ## - raise a ValueError error (or a subclass)
  ignore  ## - ignore the character and continue with the next
  replace ##[  - replace with a suitable replacement character;
             Python will use the official U+FFFD REPLACEMENT
             CHARACTER for the builtin Unicode codecs on
             decoding and "?" on encoding.]##
  surrogateescape   ## - replace with private code points U+DCnn.
  xmlcharrefreplace ## - Replace with the appropriate XML
                      ##   character reference (only for encoding).
  backslashreplace  ## - Replace with backslashed escape sequences.
  namereplace       ## - Replace with \N{...} escape sequences
                      ##   (only for encoding).

type
  CvtRes = tuple[data: string, len: int]
  EncoderCvt = proc (s: string): CvtRes
  EncoderClose = proc ()
  NCodecInfo* = object
    name*: string
    errors*: string
    encode*, decode*: EncoderCvt
    close*: EncoderClose

const
  DefErrors* = "strict"

when defined(js):
  import std/[jsffi, strutils]
  import ./jsutils

  proc jsTextDecNew(enc: cstring, fatal: bool): JsObject {.
    importjs: "new TextDecoder(#, {fatal: #})".}
  proc jsDecodeToStr(dec: JsObject, s: string): cstring {.
    importjs: "#.decode(Uint8Array.from(#))".}
  proc jsTextEncNew(): JsObject {.importjs: "new TextEncoder()".}
  proc jsEncodeToBytes(enc: JsObject, s: cstring): JsObject {.
    importjs: "#.encode(#)".}
  proc jsBytesLen(o: JsObject): int {.importjs: "#.length".}
  proc jsBytesOf(o: JsObject, i: int): char {.importjs: "#[#]".}
  proc jsBufFromStrEnc(s: cstring, enc: cstring): JsObject {.
    importjs: "Buffer.from(#, #)".}

  # NOTE: WHATWG's encoding list, which is also what JS's TextDecoder
  # supports, overlaps with but is not the same as Python's codecs list.
  const jsEncAliases = [
    ("utf-8", "utf-8"), ("utf8", "utf-8"), ("u8", "utf-8"),
    ("utf-16", "utf-16le"), ("utf16", "utf-16le"), ("utf-16le", "utf-16le"),
    ("ascii", "ascii"), ("us-ascii", "ascii"),
    ("latin-1", "iso-8859-1"), ("latin1", "iso-8859-1"),
    ("l1", "iso-8859-1"), ("iso-8859-1", "iso-8859-1"),
    ("iso8859-1", "iso-8859-1"), ("iso-8859-15", "iso-8859-15"),
    ("cp1250", "windows-1250"), ("cp1251", "windows-1251"),
    ("cp1252", "windows-1252"), ("cp1253", "windows-1253"),
    ("cp1254", "windows-1254"), ("cp1255", "windows-1255"),
    ("cp1256", "windows-1256"), ("cp1257", "windows-1257"),
    ("cp1258", "windows-1258"),
    ("windows-1250", "windows-1250"), ("windows-1251", "windows-1251"),
    ("windows-1252", "windows-1252"), ("windows-1253", "windows-1253"),
    ("windows-1254", "windows-1254"), ("windows-1255", "windows-1255"),
    ("windows-1256", "windows-1256"), ("windows-1257", "windows-1257"),
    ("windows-1258", "windows-1258"),
    ("shift-jis", "shift_jis"), ("shiftjis", "shift_jis"),
    ("sjis", "shift_jis"), ("shift_jis", "shift_jis"),
    ("euc-jp", "euc-jp"), ("eucjp", "euc-jp"),
    ("euc-kr", "euc-kr"), ("euckr", "euc-kr"),
    ("koi8-r", "koi8-r"), ("koi8r", "koi8-r"), ("koi8-u", "koi8-u"),
    ("gb2312", "gbk"), ("gbk", "gbk"), ("gb18030", "gb18030"),
    ("big5", "big5"), ("big5hkscs", "big5-hkscs"), ("big5-hkscs", "big5-hkscs"),
    ("mac-roman", "x-mac-roman"), ("macroman", "x-mac-roman"),
    ("iso-2022-jp", "iso-2022-jp"), ("hz-gb-2312", "hz-gb-2312"),
    ("utf-16be", "utf-16be"), ("utf-16-be", "utf-16be"),
  ]

  # NOTE: Buffer's encoding list is smaller than TextDecoder's label list
  const jsBufEncAliases = [
    ("utf-8", "utf8"),
    ("utf-16le", "utf16le"),
    ("ascii", "ascii"),
    ("iso-8859-1", "latin1"),
  ]

  proc normalizeJsEncoding(encoding: string): string =
    var name = encoding.replace('_', '-').toLowerAscii
    for (a, b) in jsEncAliases:
      if name == a:
        name = b
        break
    name

  proc jsBufEncNameFor(enc: string): string =
    for (a, b) in jsBufEncAliases:
      if enc == a:
        return b

  proc jsBytesToString(b: JsObject): string =
    for i in 0..<jsBytesLen(b):
      result.add jsBytesOf(b, i)

  func initNCodecInfo*(encoding: string, errors = DefErrors): NCodecInfo =
    ## JS backend impl: decode with TextDecoder, encode with TextEncoder
    ## (utf-8) or Buffer (other supported encodings)
    result.name = encoding
    result.errors = errors
    var dec: JsObject
    var decFailed = false
    let enc = normalizeJsEncoding(encoding)
    jsTryCatchE:
      dec = jsTextDecNew(cstring enc, errors == "strict")
    do:
      decFailed = true
    if decFailed:
      raise newException(LookupError, "unknown encoding: " & encoding)

    let textEnc = jsTextEncNew()
    let bufName = jsBufEncNameFor(enc)
    let isUtf8 = enc == "utf-8"

    result.encode = proc (s: string): CvtRes =
      if isUtf8:
        result.data = jsBytesToString(jsEncodeToBytes(textEnc, cstring s))
      elif bufName != "":
        # Buffer raised RangeError for unknown enc is handled by jsBufEncNameFor
        let t = jsBufFromStrEnc(cstring s, cstring bufName)
        result.data = jsBytesToString(t)
      else:
        raise newException(ValueError,
          "encoding " & encoding & " does not support encode on js backend")
      result.len = s.runeLen

    result.decode = proc (s: string): CvtRes =
      var failed = false
      var res: cstring
      jsTryCatchE:
        res = jsDecodeToStr(dec, s)
      do:
        failed = true
      if failed:
        raise newException(ValueError,
          "can not decode bytes for encoding " & encoding)
      result.data = $res
      result.len = s.len

    result.close = proc () = discard

else:
  import std/encodings

  proc encodings_open(
      destEncoding = "UTF-8"; srcEncoding = "CP1252";
      errors=DefErrors  # XXX: just ignored
    ): EncodingConverter =
    encodings.open(destEncoding=destEncoding, srcEncoding=srcEncoding)

  const innerEnc = "UTF-8"
  func initNCodecInfo*(encoding: string, errors = DefErrors): NCodecInfo =
    result.name = encoding
    var iEncCvt, oEncCvt: EncodingConverter
    try:
      iEncCvt = encodings_open(
        destEncoding = innerEnc,
        srcEncoding = encoding,
        errors = errors
      )
      oEncCvt = encodings_open(
        destEncoding = encoding,
        srcEncoding = innerEnc,
        errors = errors
      )
    except EncodingError:
      raise newException(LookupError, "unknown encoding: " & encoding)
    result.encode = proc (s: string): CvtRes =
      result.data = oEncCvt.convert(s)
      result.len = s.runeLen
    result.decode = proc(s: string): CvtRes =
      result.data = iEncCvt.convert(s)
      result.len = s.len
    result.close = proc() =
      oEncCvt.close()
      iEncCvt.close()
