import "../src/protobuf"
import streams

proc `$`(stream: Stream): string =
  stream.setPosition(0)
  while not stream.atEnd:
    let num = stream.readUint8()
    result.add num.toHex()
  stream.setPosition(0)

const testSpec = """
syntax = "proto3";

message WithOptional {
  optional int32 counter = 1;
  optional string label = 2;
  int32 plain = 3;
}
"""
parseProto(testSpec)

# An unset optional field is not serialized
block:
  var msg = new WithOptional
  var ss = newStringStream()
  ss.write msg
  assert $ss == "", "unexpected bytes: " & $ss
  assert not msg.has(counter)

# An optional field explicitly set to its default value is serialized
block:
  var msg = new WithOptional
  msg.counter = 0
  var ss = newStringStream()
  ss.write msg
  assert $ss == "0800", "unexpected bytes: " & $ss
  ss.setPosition(0)
  let read = ss.readWithOptional()
  assert read.has(counter)
  assert read.counter == 0
  assert not read.has(label)

# Round trip and reset
block:
  var msg = initWithOptional(counter = 42'i32, label = "hi")
  var ss = newStringStream()
  ss.write msg
  ss.setPosition(0)
  var read = ss.readWithOptional()
  assert read.counter == 42
  assert read.label == "hi"
  read.reset(counter)
  assert not read.has(counter)

echo "All good!"
