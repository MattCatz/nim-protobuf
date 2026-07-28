# Helper module for tproto.nim. Its block names some types publicly, one
# privately, and leaves one unnamed, so the test can check what does and
# doesn't cross the module boundary.
import "../src/protobuf"

protoSpec """
syntax = "proto3";
package test.pkg;

enum Kind {
  PLAIN = 0;
  FANCY = 1;
}

message Chart {
  string title = 1;
}

message Detail {
  string note = 1;
}

message Empty {}

message Report {
  message Note {
    string body = 1;
  }
  Chart chart = 1;
  Detail detail = 2;
  string name = 3;
  Kind kind = 4;
  Note note = 5;
  oneof source {
    string path = 6;
    int32 handle = 7;
  }
}
""":
  type
    Report* = test.pkg.Report
    Kind* = test.pkg.Kind
    Note* = test.pkg.Report.Note          # nested message
    Source* = test.pkg.Report.source      # the helper type of a oneof
    Empty* = test.pkg.Empty               # a message with no fields
    Detail = test.pkg.Detail              # named, but private to this module

# Chart is never named, so it only exists behind Report's chart field.

proc localDetail*(): string =
  ## Proves the private name is usable here, where it was declared.
  Detail.init(note = "local").note
