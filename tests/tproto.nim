# Pins the semantics of the proto block itself: which names it introduces,
# which of them cross a module boundary, how paths resolve, and what it
# rejects. See protodefs.nim for the specification these use.
import protodefs
import "../src/protobuf"
import streams

# A starred line gives a type a name that other modules can use, along with
# the whole API for it
block:
  var r = Report.init(name = "weekly", kind = Kind.FANCY)
  r.note = Note.init(body = "text")
  r.source = Source.init(handle = 7'i32)
  assert r.has(name, kind, note, source)
  assert not r.has(chart)
  var ss = newStringStream()
  ss.write r
  ss.setPosition(0)
  var back = ss.read(Report)
  assert back.name == "weekly"
  assert back.kind == Kind.FANCY
  assert back.note.body == "text"
  assert back.source.option == SourceKind.handle and back.source.handle == 7
  # The discriminator enum is named after the oneof. Its members can be used
  # unqualified where nothing else in scope shares the name; `handle` collides
  # with system.handle, so this one has to be qualified.
  case back.source.option
  of SourceKind.path: assert false
  of SourceKind.handle: assert back.source.handle == 7
  assert $back.source.option == "handle"
  assert back.len == r.len
  back.reset(name)
  assert not back.has(name)

# A type the block never names is still generated and still works through the
# field of a type that is named, it just has no name to reach it by
block:
  var ss = newStringStream()
  ss.write "\x0A\x08\x0A\x06signal"      # field 1 (Chart) with title "signal"
  ss.setPosition(0)
  var r = ss.read(Report)
  assert r.has(chart)
  assert r.chart.title == "signal"
  r.chart.title = "changed"
  assert r.chart.has(title)
  r.chart.reset(title)
  assert not r.chart.has(title)
  # ...and neither the hidden name nor the proto name is reachable
  assert not compiles(Chart)
  assert not compiles(proto_test_pkg_Chart)

# An unstarred line names a type only inside the module that declared it
block:
  assert protodefs.localDetail() == "local"
  assert not compiles(Detail)

# Paths are resolved against the specification, so a file without a package
# uses bare names, and nested types are reached through their parent. A block
# with starred lines has to be at top level, since that is where Nim allows an
# export marker at all.
protoSpec """
syntax = "proto3";

message Bare {
  message Deep {
    message Deeper {
      int32 value = 1;
    }
    Deeper deeper = 1;
  }
  Deep deep = 1;
}
""":
  type
    Bare* = Bare
    Deep* = Bare.Deep
    Deeper* = Bare.Deep.Deeper

block:
  var b = Bare.init(deep = Deep.init(deeper = Deeper.init(value = 3'i32)))
  assert b.deep.deeper.value == 3

# A second block in the same module is fine as long as it introduces different
# names, which is what lets a module gather several specifications
protoSpec """
syntax = "proto3";
package other.pkg;

message Thing {
  string label = 1;
}
""":
  type Thing* = other.pkg.Thing

block:
  assert Thing.init(label = "x").label == "x"

# What the block rejects. These are macro errors, so they're checked by
# instantiating a template that contains the offending block. None of them
# star their lines: an export marker is illegal inside a `compiles` context, so
# a starred block would come back false for the wrong reason.
template unknownPath(): untyped =
  protoSpec """
  syntax = "proto3";
  message Known { int32 a = 1; }
  """:
    type X = Unknown

template partialPath(): untyped =
  protoSpec """
  syntax = "proto3";
  package a.b;
  message Known { int32 a = 1; }
  """:
    type X = Known                   # full paths only: a.b.Known is required

template pathNamedTwice(): untyped =
  protoSpec """
  syntax = "proto3";
  message Known { int32 a = 1; }
  """:
    type
      X = Known
      Y = Known

template nameUsedTwice(): untyped =
  protoSpec """
  syntax = "proto3";
  message Known { int32 a = 1; }
  message Other { int32 a = 1; }
  """:
    type
      X = Known
      X = Other

template notADeclaration(): untyped =
  protoSpec """
  syntax = "proto3";
  message Known { int32 a = 1; }
  """:
    echo "not a type declaration"

template withGenericParams(): untyped =
  protoSpec """
  syntax = "proto3";
  message Known { int32 a = 1; }
  """:
    type X[T] = Known

template unknownFieldName(): untyped =
  discard Report.init(nosuchfield = "x")

template emptyMessageWithFields(): untyped =
  discard Empty.init(nosuchfield = "x")

template oneofNoMember(): untyped =
  discard Source.init()

template oneofTwoMembers(): untyped =
  discard Source.init(path = "a", handle = 1'i32)

template oneofUnknownMember(): untyped =
  discard Source.init(nosuchmember = 1'i32)

template oneofWrongType(): untyped =
  discard Source.init(handle = "not an int")

# A block whose oneof's derived enum name collides with a name the block
# declares is an error too, but it can't be checked here: a template body
# gensyms the names it declares, so `Choice` and `ChoiceKind` come out as
# `Choice`gensym0` and `ChoiceKind`gensym0` and no longer collide.

template goodBlock(): untyped =
  protoSpec """
  syntax = "proto3";
  message Known { int32 a = 1; }
  """:
    type X = Known

assert compiles(goodBlock())
assert not compiles(unknownPath())
assert not compiles(partialPath())
assert not compiles(pathNamedTwice())
assert not compiles(nameUsedTwice())
assert not compiles(notADeclaration())
assert not compiles(withGenericParams())
assert compiles(Empty.init())
assert not compiles(unknownFieldName())
assert not compiles(emptyMessageWithFields())
assert not compiles(oneofNoMember())
assert not compiles(oneofTwoMembers())
assert not compiles(oneofUnknownMember())
assert not compiles(oneofWrongType())

echo "All good!"
