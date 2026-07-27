# Testee for the official protobuf conformance suite. The runner starts this
# program and sends length-prefixed ConformanceRequest messages on stdin,
# expecting a length-prefixed ConformanceResponse on stdout for each. Run it
# through run.sh.
import streams, os
import "../../src/protobuf"

const confDir = currentSourcePath().parentDir()
parseProtoFile(confDir / "conformance.proto")
parseProtoFile(confDir / "test_messages_proto3.proto")

const testAllTypesProto3 = "protobuf_test_messages.proto3.TestAllTypesProto3"

# Option indices of the ConformanceResponse result oneof, in declaration order
const
  optParseError = 0
  optSerializeError = 1
  optRuntimeError = 3
  optProtobufPayload = 4
  optSkipped = 6

proc toStream(bytes: seq[uint8]): StringStream =
  result = newStringStream()
  for b in bytes:
    result.write(b)
  result.setPosition(0)

proc toBytes(str: string): seq[uint8] =
  result = newSeq[uint8](str.len)
  for i, c in str:
    result[i] = c.uint8

proc respond(option: range[0..8], text: string): conformance_ConformanceResponse =
  result = initconformance_ConformanceResponse()
  case option:
  of optParseError:
    result.result = conformance_ConformanceResponse_result_OneOf(option: optParseError, parse_error: text)
  of optSerializeError:
    result.result = conformance_ConformanceResponse_result_OneOf(option: optSerializeError, serialize_error: text)
  of optRuntimeError:
    result.result = conformance_ConformanceResponse_result_OneOf(option: optRuntimeError, runtime_error: text)
  of optSkipped:
    result.result = conformance_ConformanceResponse_result_OneOf(option: optSkipped, skipped: text)
  else:
    doAssert false

proc respond(payload: seq[uint8]): conformance_ConformanceResponse =
  result = initconformance_ConformanceResponse()
  result.result = conformance_ConformanceResponse_result_OneOf(option: optProtobufPayload, protobuf_payload: payload)

proc handle(req: conformance_ConformanceRequest): conformance_ConformanceResponse =
  let messageType = if req.has(message_type): req.message_type else: ""

  if messageType == "conformance.FailureSet":
    var payload = newStringStream()
    payload.write initconformance_FailureSet()
    return respond(payload.data.toBytes)

  if not req.has(payload) or req.payload.option != 0:
    return respond(optSkipped, "only protobuf input is supported")
  if messageType != testAllTypesProto3:
    return respond(optSkipped, "unsupported message type: " & messageType)
  let outputFormat = if req.has(requested_output_format): req.requested_output_format
    else: conformance_WireFormat.UNSPECIFIED
  if outputFormat != conformance_WireFormat.PROTOBUF:
    return respond(optSkipped, "only protobuf output is supported")

  var msg: protobuf_test_messages_proto3_TestAllTypesProto3
  try:
    msg = toStream(req.payload.protobuf_payload).readprotobuf_test_messages_proto3_TestAllTypesProto3()
  except Exception as e:
    return respond(optParseError, e.msg)
  try:
    var output = newStringStream()
    output.write msg
    return respond(output.data.toBytes)
  except Exception as e:
    return respond(optSerializeError, e.msg)

proc main() =
  let input = newFileStream(stdin)
  let output = newFileStream(stdout)
  while true:
    var msgLen: uint32
    let lenRead = input.readData(addr msgLen, 4)
    if lenRead == 0:
      break
    if lenRead != 4:
      stderr.writeLine "testee: truncated length prefix"
      quit 1
    var buf = newString(msgLen.int)
    if msgLen > 0'u32 and input.readData(addr buf[0], msgLen.int) != msgLen.int:
      stderr.writeLine "testee: truncated request"
      quit 1
    var resp: conformance_ConformanceResponse
    try:
      let req = newStringStream(buf).readconformance_ConformanceRequest()
      resp = handle(req)
    except Exception as e:
      resp = respond(optRuntimeError, e.msg)
    var respStream = newStringStream()
    respStream.write resp
    var respLen = respStream.data.len.uint32
    output.writeData(addr respLen, 4)
    output.write respStream.data
    output.flush

main()
