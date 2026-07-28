# From bug #23
import "../src/protobuf"
import streams
import strutils

const spec = """
syntax = "proto3";

message Example2 {
    string field1 = 1;
}

message Example {
    message ExampleNested {
        Example2 example2 = 1;
    }
    ExampleNested exampleNested = 1;
}
"""

protoSpec spec:
  type
    Example* = Example
    ExampleNested* = Example.ExampleNested
    Example2* = Example2

var msg = Example.init()
msg.exampleNested = ExampleNested.init()
# Fill message with enough data to make the size span more than a single byte
# (the variable can't be called example2, that name is taken by the accessor
# procs generated for the example2 field)
let inner = Example2.init(field1 = "This is a test" & "!".repeat(120))
msg.exampleNested.example2 = inner

var strm = newStringStream()
strm.write(msg)
strm.setPosition(0)
assert strm.readAll ==
  "\x0a\x8c\x01\x0a\x89\x01\x0a\x86\x01\x54\x68\x69\x73\x20\x69\x73" &
  "\x20\x61\x20\x74\x65\x73\x74\x21\x21\x21\x21\x21\x21\x21\x21\x21" &
  "\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21" &
  "\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21" &
  "\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21" &
  "\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21" &
  "\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21" &
  "\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21" &
  "\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21\x21"

