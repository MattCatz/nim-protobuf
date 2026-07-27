# Wrapping module for texport.nim: parses a specification and exports one of
# its messages, the pattern described in the "Exporting message definitions"
# section of the documentation.
import "../src/protobuf"

const spec = """
syntax = "proto3";

message Person {
  string name = 1;
  int32 id = 2;
  repeated string emails = 3;
  map<string, string> attributes = 4;
}
"""
parseProto(spec)

exportMessage Person
