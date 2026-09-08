
import pkg/jscompat/utils/[jstypedarrays, jsarraybuffer]
export jstypedarrays, jsarraybuffer

# XXX: this relies on assumption: Nim string is represeted as
#  UTF-8 Array[Number] in js.
# tho it's correct currently, no gurantee from official.
proc toUint8Array*(s: string): TypedArray[uint8, ArrayBuffer] {.
  importjs: "Uint8Array.from(#)".}

