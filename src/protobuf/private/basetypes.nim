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

  template varIntInto(buf, i, value: untyped) =
    ## Encodes ``value`` into ``buf`` at ``i``, advancing ``i``. A VarInt is at
    ## most 10 bytes, and a tag at most 5.
    var num = value
    while num >= 0x80'u64:
      buf[i] = (num and 0x7f or 0x80).uint8
      inc i
      num = num shr 7
    buf[i] = num.uint8
    inc i

  proc protoWriteInt64*(s: Stream, x: int64) =
    ## Writes the number ``x`` to a stream using the protobuf VarInt encoding.
    ## The bytes are built in a stack buffer and handed over in one write: a
    ## byte at a time is an indirect call and a one-byte copy each.
    var
      buf: array[10, uint8]
      i = 0
    varIntInto(buf, i, cast[uint64](x))
    s.writeData(addr buf[0], i)

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
    ## The payload goes out in one write: a character at a time is one indirect
    ## call, one length check, and one one-byte copy per character.
    s.protoWriteInt64(x.len)
    s.write(x)

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
    ## Written in one go like ``protoWriteString``. There is no stream overload
    ## taking a seq, so the write goes through the sequence's buffer, which is
    ## contiguous and outlives the call.
    s.protoWriteInt64(x.len)
    if x.len > 0:
      s.writeData(unsafeAddr x[0], x.len)

  proc protoReadBytes*(s: Stream): seq[uint8] =
    ## Reads a byte sequence according to the protobuf specification. See
    ## ``protoWriteBytes``
    let length = s.protoReadInt64()
    if length < 0:
      raise newException(ValueError, "Negative length prefix")
    result = newSeq[uint8](length.int)
    if length > 0 and s.readData(addr result[0], length.int) != length.int:
      raise newException(IOError, "Stream ended before end of bytes")

  # A field is a tag followed by its value, and the code generator knows both at
  # the same moment, so they go out in one write. Each of these is the same
  # writer as above with the tag in front, so the generated code just passes an
  # extra argument: which encoding a proto type gets is carried by the name, not
  # by the Nim type — sint64 and int64 are both int64 here, and so are fixed64
  # and uint64.
  proc taggedFixed[T](s: Stream, tag: int64, x: T) =
    ## Writes a tag and a fixed-width value in one write. The value keeps the
    ## byte order ``write`` gave it, which on this branch is little endian.
    var
      buf: array[16, uint8]
      i = 0
    varIntInto(buf, i, cast[uint64](tag))
    copyMem(addr buf[i], unsafeAddr x, sizeof(x))
    i += sizeof(x)
    s.writeData(addr buf[0], i)

  proc protoWriteInt64*(s: Stream, tag: int64, x: int64) =
    ## Writes a field's tag and its VarInt value in a single write. A tag is at
    ## most 5 bytes and a VarInt at most 10.
    var
      buf: array[16, uint8]
      i = 0
    varIntInto(buf, i, cast[uint64](tag))
    varIntInto(buf, i, cast[uint64](x))
    s.writeData(addr buf[0], i)

  proc protoWriteInt32*(s: Stream, tag: int64, x: int32) =
    s.protoWriteInt64(tag, x.int64)

  proc protoWriteUint64*(s: Stream, tag: int64, x: uint64) =
    s.protoWriteInt64(tag, cast[int64](x))

  proc protoWriteUint32*(s: Stream, tag: int64, x: uint32) =
    s.protoWriteInt64(tag, x.int64)

  proc protoWriteBool*(s: Stream, tag: int64, x: bool) =
    s.protoWriteInt64(tag, x.int64)

  proc protoWriteSint64*(s: Stream, tag: int64, x: int64) =
    s.protoWriteInt64(tag,
      cast[int64]((cast[uint64](x) shl 1) xor cast[uint64](x shr 63)))

  proc protoWriteSint32*(s: Stream, tag: int64, x: int32) =
    s.protoWriteSint64(tag, x.int64)

  proc protoWriteFixed64*(s: Stream, tag: int64, x: uint64) =
    s.taggedFixed(tag, x)

  proc protoWriteFixed32*(s: Stream, tag: int64, x: uint32) =
    s.taggedFixed(tag, x)

  proc protoWriteSfixed64*(s: Stream, tag: int64, x: int64) =
    s.taggedFixed(tag, x)

  proc protoWriteSfixed32*(s: Stream, tag: int64, x: int32) =
    s.taggedFixed(tag, x)

  proc protoWriteFloat*(s: Stream, tag: int64, x: float32) =
    s.taggedFixed(tag, x)

  proc protoWriteDouble*(s: Stream, tag: int64, x: float64) =
    s.taggedFixed(tag, x)

  proc protoWriteString*(s: Stream, tag: int64, x: string) =
    ## The tag and the length prefix share one write, the payload takes the
    ## second — two writes per string field instead of one per byte.
    var
      buf: array[16, uint8]
      i = 0
    varIntInto(buf, i, cast[uint64](tag))
    varIntInto(buf, i, cast[uint64](x.len))
    s.writeData(addr buf[0], i)
    if x.len > 0:
      s.writeData(cstring(x), x.len)

  proc protoWriteBytes*(s: Stream, tag: int64, x: seq[uint8]) =
    ## Like ``protoWriteString``, for a byte sequence.
    var
      buf: array[16, uint8]
      i = 0
    varIntInto(buf, i, cast[uint64](tag))
    varIntInto(buf, i, cast[uint64](x.len))
    s.writeData(addr buf[0], i)
    if x.len > 0:
      s.writeData(unsafeAddr x[0], x.len)

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
