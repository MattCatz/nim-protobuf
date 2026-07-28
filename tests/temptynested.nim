# From bug #23
import "../src/protobuf"
import streams
import strutils

const spec = """
syntax = "proto3";

message Example2 {}

message Example {
    message ExampleNested {}
}

message Example3{
  int32 aField = 1;
  message Child{}
}

"""

protoSpec spec:
  type
    ExampleNested* = Example.ExampleNested
    Example2* = Example2
    Example* = Example
    Example3* = Example3
    Child* = Example3.Child

var
  a = ExampleNested.init()
  b = Example2.init()
  c = Example.init()
  d = Example3.init()
  e = Child.init()
