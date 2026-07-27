import streams

when cpuEndian == littleEndian:
  proc hob(x: int64): uint =
    result = x.uint
    result = result or (result shr 1)
    result = result or (result shr 2)
    result = result or (result shr 4)
    result = result or (result shr 8)
    result = result or (result shr 16)
    result = result or (result shr 32)
    result = result - (result shr 1)

  proc getVarIntLen*(num: int | int64 | int32 | uint64 | uint32 | bool | enum): int =
    ## Get's the length a number would take when written with the protobuf
    ## VarInt encoding.
    result = 1
    var bits = num.uint64
    while bits > 0b0111_1111.uint64:
      result += 1
      bits = bits shr 7

  proc protoWriteInt64*(s: Stream, x: int64) =
    ## Writes the number ``x`` to a stream using the protobuf VarInt encoding
    var
      bytes = x.hob shr 7
      num = x
    s.write((num and 0x7f or (if bytes != 0: 0x80 else: 0)).uint8)
    while bytes != 0:
      num = num shr 7
      bytes = bytes shr 7
      s.write((num and 0x7f or (if bytes != 0: 0x80 else: 0)).uint8)

  proc protoReadInt64*(s: Stream): int64 =
    ## Reads a number from the stream using the protobuf VarInt encoding
    var
      byte: int64 = s.readInt8()
      i = 1
    result = byte and 0x7f
    while (byte and 0x80) != 0:
      if i >= 10:
        raise newException(ValueError, "VarInt is longer than 10 bytes")
      byte = s.readInt8()
      result = result or ((byte and 0x7f) shl (7*i))
      i += 1

  proc protoReadTag*(s: Stream): uint64 =
    ## Reads a field specifier (tag) and validates it: a tag is a VarInt of at
    ## most 5 bytes whose field number must be in 1 .. 2^29-1.
    var
      byte: uint64 = s.readUint8()
      i = 1
    result = byte and 0x7f
    while (byte and 0x80) != 0:
      if i >= 5:
        raise newException(ValueError, "Tag VarInt is longer than 5 bytes")
      byte = s.readUint8()
      result = result or ((byte and 0x7f) shl (7*i))
      i += 1
    let fieldNumber = result shr 3
    if fieldNumber == 0 or fieldNumber > 536870911'u64:
      raise newException(ValueError, "Illegal field number: " & $fieldNumber)

  proc protoReadInt32*(s: Stream): int32 =
    ## Similar to the ``protoReadInt64`` procedure, but returns a 32-bit
    ## integer, truncating the VarInt to its lower 32 bits as per the protobuf
    ## specification.
    cast[int32](s.protoReadInt64())

  proc protoWriteInt32*(s: Stream, x: int32) =
    ## Similar to the ``protoWriteInt64`` procedure, but takes a 32-bit
    ## integer instead.
    s.protoWriteInt64(x.int64)

  proc protoReadUint64*(s: Stream): uint64 =
    ## Similar to the ``protoReadInt64`` procedure, but returns a 64-bit
    ## unsigned integer instead.
    cast[uint64](s.protoReadInt64())

  proc protoWriteUint64*(s: Stream, x: uint64) =
    ## Similar to the ``protoWriteInt64`` procedure, but takes a 64-bit
    ## unsigned integer instead.
    s.protoWriteInt64(cast[int64](x))

  proc protoReadUint32*(s: Stream): uint32 =
    ## Similar to the ``protoReadInt32`` procedure, but returns a 32-bit
    ## unsigned integer, truncating the VarInt to its lower 32 bits.
    cast[uint32](s.protoReadInt64())

  proc protoWriteUint32*(s: Stream, x: uint32) =
    ## Similar to the ``protoWriteInt32`` procedure, but takes a 32-bit
    ## unsigned integer instead.
    s.protoWriteInt64(x.int64)

  proc protoReadBool*(s: Stream): bool =
    ## Reads a bool as a VarInt, any non-zero value is true.
    s.protoReadInt64() != 0

  proc protoWriteBool*(s: Stream, x: bool) =
    ## Similar to the ``protoWriteInt64`` procedure, but takes a bool instead.
    s.protoWriteInt64(x.int64)

  proc protoWriteSint64*(s: Stream, x: int64) =
    ## Writes an integer using the protobuf ZigZag and VarInt encoding. Use
    ## this for signed numbers, the regular ``protoWriteInt64`` will always use
    ## 10 bytes when writing a negative number.
    s.protoWriteInt64(cast[int64]((cast[uint64](x) shl 1) xor cast[uint64](x shr 63)))

  proc protoReadSint64*(s: Stream): int64 =
    ## Reads an integer using the protobuf ZigZag and VarInt encoding.
    let y = cast[uint64](s.protoReadInt64())
    cast[int64]((y shr 1) xor (0'u64 - (y and 1'u64)))

  proc protoWriteSint32*(s: Stream, x: int32) =
    ## Similar to the ``protoWriteSint64`` procedure, but takes a 32-bit
    ## integer instead.
    s.protoWriteSint64(x.int64)

  proc protoReadSint32*(s: Stream): int32 =
    ## Similar to the ``protoReadSint64`` procedure, but returns a 32-bit
    ## integer. As per the protobuf specification the VarInt is truncated to
    ## its lower 32 bits before the ZigZag decoding.
    let y = cast[uint32](s.protoReadInt64())
    cast[int32]((y shr 1) xor (0'u32 - (y and 1'u32)))

  proc getSVarIntLen*(num: int64 | int32): int =
    ## Get's the length a number would take when written with the protobuf
    ## ZigZag and VarInt encoding.
    getVarIntLen(cast[uint64]((cast[uint64](num.int64) shl 1) xor cast[uint64](num.int64 shr 63)))

  proc protoWriteFixed64*(s: Stream, x: uint64) =
    ## A simple wrapper for writing 64-bit unsigned integers to a stream
    s.write(x)

  proc protoReadFixed64*(s: Stream): uint64 =
    ## A simple wrapper for reading 64-bit unsigned integers from a stream
    s.readUint64()

  proc protoWriteFixed32*(s: Stream, x: uint32) =
    ## A simple wrapper for writing 32-bit unsigned integers to a stream
    s.write(x)

  proc protoReadFixed32*(s: Stream): uint32 =
    ## A simple wrapper for reading 32-bit unsigned integers from a stream
    s.readUInt32()

  proc protoWriteSfixed64*(s: Stream, x: int64) =
    ## A simple wrapper for writing 64-bit signed integers to a stream
    s.write(x)

  proc protoReadSfixed64*(s: Stream): int64 =
    ## A simple wrapper for reading 64-bit signed integers from a stream
    s.readInt64()

  proc protoWriteSfixed32*(s: Stream, x: int32) =
    ## A simple wrapper for writing 32-bit signed integers to a stream
    s.write(x)

  proc protoReadSfixed32*(s: Stream): int32 =
    ## A simple wrapper for reading 32-bit signed integers from a stream
    s.readInt32()

  proc protoWriteString*(s: Stream, x: string) =
    ## Writes a string according to the protobuf specification. First the
    ## length of the string is written with VarInt encoding, then the string
    ## follow.
    s.protoWriteInt64(x.len)
    for c in x:
      s.write(c)

  proc protoReadString*(s: Stream): string =
    ## Reads a string according to the protobuf specification. See
    ## ``protoWriteString``
    let length = s.protoReadInt64()
    if length < 0:
      raise newException(ValueError, "Negative length prefix")
    result = s.readStr(length.int)
    if result.len != length.int:
      raise newException(IOError, "Stream ended before end of string")

  proc protoWriteBytes*(s: Stream, x: seq[uint8]) =
    ## Writes a string according to the protobuf specification. First the
    ## length of the byte sequence is written with VarInt encoding, then the
    ## bytes follow.
    s.protoWriteInt64(x.len)
    for c in x:
      s.write(c)

  proc protoReadBytes*(s: Stream): seq[uint8] =
    ## Reads a byte sequence according to the protobuf specification. See
    ## ``protoWriteBytes``
    let length = s.protoReadInt64()
    if length < 0:
      raise newException(ValueError, "Negative length prefix")
    result = newSeq[uint8](length.int)
    if length > 0 and s.readData(addr result[0], length.int) != length.int:
      raise newException(IOError, "Stream ended before end of bytes")

  proc protoSkipField*(s: Stream, fieldSpec: uint64) =
    ## Skips over an unknown field, consuming its bytes based on the wire type
    ## in the field specifier.
    case fieldSpec and 0b111:
    of 0:
      discard s.protoReadInt64()
    of 1:
      discard s.readInt64()
    of 2:
      let length = s.protoReadInt64()
      if length < 0:
        raise newException(ValueError, "Negative length prefix")
      if s.readStr(length.int).len != length.int:
        raise newException(IOError, "Stream ended before end of field")
    of 5:
      discard s.readInt32()
    else:
      raise newException(ValueError, "Unsupported wire type: " & $(fieldSpec and 0b111))

  proc protoCaptureField*(s: Stream, fieldSpec: uint64, dest: var string) =
    ## Consumes an unknown field like ``protoSkipField``, but appends its wire
    ## representation to ``dest`` so it can be written back out again.
    let capture = newStringStream()
    capture.protoWriteInt64(cast[int64](fieldSpec))
    case fieldSpec and 0b111:
    of 0:
      capture.protoWriteInt64(s.protoReadInt64())
    of 1:
      capture.write(s.readInt64())
    of 2:
      let length = s.protoReadInt64()
      if length < 0:
        raise newException(ValueError, "Negative length prefix")
      let data = s.readStr(length.int)
      if data.len != length.int:
        raise newException(IOError, "Stream ended before end of field")
      capture.protoWriteInt64(length)
      capture.write(data)
    of 5:
      capture.write(s.readInt32())
    else:
      raise newException(ValueError, "Unsupported wire type: " & $(fieldSpec and 0b111))
    dest.add capture.data

  proc protoWriteFloat*(s: Stream, x: float32) =
    ## A simple wrapper for writing 32-bit floats
    s.write(x)

  proc protoReadFloat*(s: Stream): float32 =
    ## A simple wrapper for reading 32-bit floats
    s.readFloat32()

  proc protoWriteDouble*(s: Stream, x: float64) =
    ## A simple wrapper for writing 64-bit floats
    s.write(x)

  proc protoReadDouble*(s: Stream): float64 =
    ## A simple wrapper for reading 64-bit floats
    s.readFloat64()
