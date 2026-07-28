# Pins the representation of a message: a plain object by default, a ref object
# when a line in the block asks for one. What a plain object buys — copying on
# assignment, structural equality, const messages, an immutable `let` — and what
# `ref` is still needed for, which is sharing and recursion through a singular
# field.
import "../src/protobuf"
import streams

protoSpec """
syntax = "proto3";

message Payload {
  int32 count = 1;
}

message Wrapper {
  string name = 1;
  Payload payload = 2;
}
""":
  type
    Payload* = Payload
    Wrapper* = Wrapper

# Assignment copies the message instead of aliasing it
block:
  var a = Wrapper.init(name = "a", payload = Payload.init(count = 1'i32))
  var b = a
  b.name = "b"
  b.payload.count = 2'i32
  assert a.name == "a"
  assert a.payload.count == 1
  assert b.name == "b"
  assert b.payload.count == 2

# Setting a message field copies the value in, so the source can move on
block:
  var source = Payload.init(count = 1'i32)
  var w = Wrapper.init(name = "w")
  w.payload = source
  source.count = 99'i32
  assert w.payload.count == 1

# Equality is structural, which also makes a message usable as a table key
block:
  assert Payload.init(count = 1'i32) == Payload.init(count = 1'i32)
  assert Payload.init(count = 1'i32) != Payload.init(count = 2'i32)
  assert Wrapper.init(name = "x") != Wrapper.init(name = "y")
  var seen = {Payload.init(count = 1'i32): "one"}.toTable
  assert seen[Payload.init(count = 1'i32)] == "one"

# A message can be a const, evaluated by the VM and baked into the binary
block:
  const defaultPayload = Payload.init(count = 42'i32)
  assert defaultPayload.count == 42
  assert defaultPayload == Payload.init(count = 42'i32)

# A nested field is mutated in place through the accessor chain, as long as the
# message at the root of the chain is mutable
block:
  var w = Wrapper.init(name = "w", payload = Payload.init(count = 1'i32))
  w.payload.count = 7'i32
  assert w.payload.count == 7
  w.payload.count.inc
  assert w.payload.count == 8
  w.reset(name)
  assert not w.has(name)

# ...and a `let` message really is immutable, unlike a `let` ref message. Reads
# still work, they go through a `lent` getter.
block:
  let frozen = Wrapper.init(name = "w", payload = Payload.init(count = 3'i32))
  assert frozen.name == "w"
  assert frozen.payload.count == 3
  assert not compiles(frozen.name = "other")
  assert not compiles(frozen.payload.count = 9'i32)
  assert not compiles(frozen.reset(name))
  var ss = newStringStream()
  assert not compiles(ss.readInto(frozen))

# readInto merges into a message that already exists, mutating it in place
block:
  var ss = newStringStream()
  ss.write Payload.init(count = 7'i32)
  ss.setPosition(0)
  var target = Payload.init()
  ss.readInto(target)
  assert target.count == 7

# Recursion through a repeated field needs no annotation: the seq is already an
# indirection, so the message stays a plain object
protoSpec """
syntax = "proto3";

message Tree {
  string label = 1;
  repeated Tree children = 2;
}
""":
  type Tree* = Tree

block:
  var t = Tree.init(label = "root")
  t.children = @[Tree.init(label = "a"), Tree.init(label = "b")]
  t.children[0].children = @[Tree.init(label = "deep")]
  var ss = newStringStream()
  ss.write t
  ss.setPosition(0)
  let back = ss.read(Tree)
  assert back.label == "root"
  assert back.children.len == 2
  assert back.children[1].label == "b"
  assert back.children[0].children.len == 1
  assert back.children[0].children[0].label == "deep"

# A cycle of singular fields needs one ref to break it. Marking either message
# on the cycle is enough — the other one keeps holding its field by value.
protoSpec """
syntax = "proto3";

message Outer {
  string tag = 1;
  Inner inner = 2;
}

message Inner {
  int32 depth = 1;
  Outer back = 2;
}
""":
  type
    Outer* = Outer
    Inner* = ref Inner

block:
  var o = Outer.init(tag = "top")
  o.inner = Inner.init(depth = 1'i32)
  o.inner.back = Outer.init(tag = "nested")
  var ss = newStringStream()
  ss.write o
  ss.setPosition(0)
  let back = ss.read(Outer)
  assert back.tag == "top"
  assert back.inner.depth == 1
  assert back.inner.back.tag == "nested"
  assert not back.inner.back.has(inner)

# A message that refers to itself through a singular field is the same case
protoSpec """
syntax = "proto3";

message Node {
  int32 value = 1;
  Node next = 2;
}
""":
  type Node* = ref Node

block:
  var n = Node.init(value = 1'i32)
  n.next = Node.init(value = 2'i32)
  n.next.next = Node.init(value = 3'i32)
  var ss = newStringStream()
  ss.write n
  ss.setPosition(0)
  let back = ss.read(Node)
  assert back.value == 1
  assert back.next.value == 2
  assert back.next.next.value == 3
  assert not back.next.next.has(next)

# A ref message keeps the sharing it always had: assignment copies the
# reference, and a `let` freezes only that reference, not the message
block:
  var n = Node.init(value = 1'i32)
  let alias = n
  alias.value = 9'i32
  assert n.value == 9

# ref is a choice about a message. An enum has no fields to hold and a oneof
# lives inside the message that declares it, so neither can be asked for as ref.
template refOnEnum(): untyped =
  protoSpec """
  syntax = "proto3";
  enum Colour { RED = 0; }
  """:
    type X = ref Colour

template refOnOneof(): untyped =
  protoSpec """
  syntax = "proto3";
  message Holder {
    oneof choice {
      int32 number = 1;
      string text = 2;
    }
  }
  """:
    type X = ref Holder.choice

template refOnMessage(): untyped =
  protoSpec """
  syntax = "proto3";
  message Known { int32 a = 1; }
  """:
    type X = ref Known

assert compiles(refOnMessage())
assert not compiles(refOnEnum())
assert not compiles(refOnOneof())

# A cycle left unbroken is a compile error — Nim rejects the generated type
# section with "illegal recursion in type". It can't be asserted here: an
# illegal recursion inside a `compiles` context segfaults the compiler, which
# is a Nim bug independent of this library. See nim-bugs/illegal-recursion-in-
# compiles.md for the plain-Nim repro.

echo "All good!"
