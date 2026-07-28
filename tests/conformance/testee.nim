# Testee for the official protobuf conformance suite. The runner starts this
# program and sends length-prefixed ConformanceRequest messages on stdin,
# expecting a length-prefixed ConformanceResponse on stdout for each. Run it
# through run.sh.
import streams
import "../../src/protobuf"

proto "conformance.proto":
  type
    ConformanceRequest* = conformance.ConformanceRequest
    ConformanceResponse* = conformance.ConformanceResponse
    ResponseResult* = conformance.ConformanceResponse.result
    RequestPayload* = conformance.ConformanceRequest.payload
    FailureSet* = conformance.FailureSet
    WireFormat* = conformance.WireFormat

proto "test_messages_proto3.proto":
  type TestAllTypesProto3* = protobuf_test_messages.proto3.TestAllTypesProto3

const testAllTypesProto3 = "protobuf_test_messages.proto3.TestAllTypesProto3"

proc toStream(bytes: seq[uint8]): StringStream =
  result = newStringStream()
  for b in bytes:
    result.write(b)
  result.setPosition(0)

proc toBytes(str: string): seq[uint8] =
  result = newSeq[uint8](str.len)
  for i, c in str:
    result[i] = c.uint8

proc respond(option: ResponseResultKind, text: string): ConformanceResponse =
  result = ConformanceResponse.init()
  case option:
  of parse_error:
    result.result = ResponseResult.init(parse_error = text)
  of serialize_error:
    result.result = ResponseResult.init(serialize_error = text)
  of runtime_error:
    result.result = ResponseResult.init(runtime_error = text)
  of skipped:
    result.result = ResponseResult.init(skipped = text)
  else:
    doAssert false

proc respond(payload: seq[uint8]): ConformanceResponse =
  result = ConformanceResponse.init()
  result.result = ResponseResult.init(protobuf_payload = payload)

proc handle(req: ConformanceRequest): ConformanceResponse =
  let messageType = if req.has(message_type): req.message_type else: ""

  if messageType == "conformance.FailureSet":
    var payload = newStringStream()
    payload.write FailureSet.init()
    return respond(payload.data.toBytes)

  if not req.has(payload) or req.payload.option != RequestPayloadKind.protobuf_payload:
    return respond(skipped, "only protobuf input is supported")
  if messageType != testAllTypesProto3:
    return respond(skipped, "unsupported message type: " & messageType)
  let outputFormat = if req.has(requested_output_format): req.requested_output_format
    else: WireFormat.UNSPECIFIED
  if outputFormat != WireFormat.PROTOBUF:
    return respond(skipped, "only protobuf output is supported")

  var msg: TestAllTypesProto3
  try:
    msg = toStream(req.payload.protobuf_payload).read(TestAllTypesProto3)
  except Exception as e:
    return respond(parse_error, e.msg)
  try:
    var output = newStringStream()
    output.write msg
    return respond(output.data.toBytes)
  except Exception as e:
    return respond(serialize_error, e.msg)

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
    var resp: ConformanceResponse
    try:
      let req = newStringStream(buf).read(ConformanceRequest)
      resp = handle(req)
    except Exception as e:
      resp = respond(runtime_error, e.msg)
    var respStream = newStringStream()
    respStream.write resp
    var respLen = respStream.data.len.uint32
    output.writeData(addr respLen, 4)
    output.write respStream.data
    output.flush

main()
