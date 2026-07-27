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

message Inner {
  string s = 1;
}

message Maps {
  enum Kind {
    DEFAULT = 0;
    SPECIAL = 1;
  }
  map<string, int32> counts = 1;
  map<int64, string> names = 2;
  map<string, Inner> inners = 3;
  map<string, Kind> kinds = 4;
}
"""
parseProto(testSpec)

# Single-entry maps have deterministic output, check the exact bytes against
# what protoc produces. Multi-entry output depends on table iteration order.
block:
  var msg = new Maps
  msg.counts = {"a": 1'i32}.toTable
  var ss = newStringStream()
  ss.write msg
  assert $ss == "0A050A01611001", "unexpected bytes: " & $ss

block:
  var msg = new Maps
  msg.names = {3'i64: "hi"}.toTable
  var ss = newStringStream()
  ss.write msg
  assert $ss == "1206080312026869", "unexpected bytes: " & $ss

block:
  var inner = new Inner
  inner.s = "v"
  var msg = new Maps
  msg.inners = {"k": inner}.toTable
  var ss = newStringStream()
  ss.write msg
  assert $ss == "1A080A016B12030A0176", "unexpected bytes: " & $ss

block:
  var msg = new Maps
  msg.kinds = {"e": Maps_Kind.SPECIAL}.toTable
  var ss = newStringStream()
  ss.write msg
  assert $ss == "22050A01651001", "unexpected bytes: " & $ss

# Multi-entry round trip
block:
  var msg = new Maps
  msg.counts = {"a": 1'i32, "bc": -2'i32, "": 300'i32}.toTable
  msg.names = {0'i64: "", -1'i64: "x"}.toTable
  var ss = newStringStream()
  ss.write msg
  ss.setPosition(0)
  let read = ss.readMaps()
  assert read.counts == msg.counts
  assert read.names == msg.names

# An unset map writes nothing
block:
  var msg = new Maps
  var ss = newStringStream()
  ss.write msg
  assert $ss == "", "unexpected bytes: " & $ss

# The init macro and has() treat maps like any other field
block:
  var msg = initMaps(counts = {"x": 42'i32}.toTable)
  assert msg.has(counts)
  assert not msg.has(names)
  assert msg.counts["x"] == 42

# Duplicate keys: last entry wins
block:
  var ss = newStringStream()
  ss.write "\x0A\x05\x0A\x01\x61\x10\x01\x0A\x05\x0A\x01\x61\x10\x02"
  ss.setPosition(0)
  let read = ss.readMaps()
  assert read.counts == {"a": 2'i32}.toTable

# Entries with a missing key or value produce the default value
block:
  var ss = newStringStream()
  ss.write "\x0A\x03\x0A\x01\x61\x0A\x02\x10\x05"
  ss.setPosition(0)
  let read = ss.readMaps()
  assert read.counts == {"a": 0'i32, "": 5'i32}.toTable

# A missing message value becomes a default instance, not nil
block:
  var ss = newStringStream()
  ss.write "\x1A\x03\x0A\x01\x6B"
  ss.setPosition(0)
  let read = ss.readMaps()
  assert not read.inners["k"].isNil

echo "All good!"
