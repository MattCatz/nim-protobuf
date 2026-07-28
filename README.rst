protobuf
===========
This is a pure Nim implementation of protobuf, meaning that it doesn't rely
on the ``protoc`` compiler. The entire implementation is based on a block
that takes a file or a string containing the proto3 format as specified at
https://developers.google.com/protocol-buffers/docs/proto3, along with a list
of the types you want to use from it. It then produces procedures to read,
write, and calculate the length of a message, along with types to hold the
data in your Nim program. The data types are intended to be as close as
possible to what you would normally use in Nim, making it feel very natural
to use these types in your program in contrast to some protobuf
implementations. Protobuf 3 however has all fields as optional fields, this
means that the types generated have a little bit of special sauce going on
behind the scenes. This will be explained in a later section. The entire
read/write structure is built on top of the Stream interface from the
``streams`` module, meaning it can be used directly with anything that uses
streams.

Example
-------
To whet your appetite the following example shows how this protobuf block can
be used to generate the required code and read and write protobuf messages.
This example can also be found in the examples folder. Note that it is also
possible to read the protobuf specification from a file with ``proto``.

.. code-block:: nim

  import protobuf, streams

  # Define our protobuf specification and generate Nim code to use it
  const spec = """
  syntax = "proto3";

  message ExampleMessage {
    int32 number = 1;
    string text = 2;
    SubMessage nested = 3;
    message SubMessage {
      int32 a_field = 1;
    }
  }
  """

  # Every line names one type from the specification. The names are yours to
  # pick, the paths on the right are the ones the specification uses.
  protoSpec spec:
    type
      ExampleMessage* = ExampleMessage
      SubMessage* = ExampleMessage.SubMessage

  # Create our message
  var msg = ExampleMessage.init()
  msg.number = 10
  msg.text = "Hello world"
  msg.nested = SubMessage.init(aField = 100)

  # Write it to a stream
  var stream = newStringStream()
  stream.write msg

  # Read the message from the stream and output the data, if it's all present
  stream.setPosition(0)
  var readMsg = stream.read(ExampleMessage)
  if readMsg.has(number, text, nested) and readMsg.nested.has(aField):
    echo readMsg.number
    echo readMsg.text
    echo readMsg.nested.aField

The specification more commonly lives in its own file, in which case ``proto``
takes the path, resolved relative to the Nim file containing the block:

.. code-block:: nim

  proto "example.proto":
    type ExampleMessage* = ExampleMessage

Editing the specification recompiles the module that reads it.

Naming and visibility
---------------------
The body of the block is a list of ``type Name = some.proto.Path``
declarations. The path on the right is interpreted against the specification
and is always the full path: the package, then any enclosing messages, then
the type. A specification without a ``package`` statement has bare paths. The
name on the left is what the type is called in your program, and starring it
exports it exactly as starring any other Nim type does. Writing ``ref`` in
front of the path asks for that message to be a reference, which is covered
under `Messages`_.

You only name what you use. Types you leave out are still generated, so they
still work as the types of fields — the only thing you can't do with them is
declare or construct one, because they have no name you can reach:

.. code-block:: nim

  proto "example.proto":
    type Report* = app.Report      # app.Chart is left unnamed

  var report = stream.read(Report)
  echo report.chart.title          # fine, reached through the field
  report.chart.title = "signal"    # also fine
  let c = Chart.init()             # won't compile, there is no such name

Because starring a line exports procs alongside the type, a block with a
starred line has to appear at top level, where Nim allows export markers.

An unstarred line names a type only inside the module holding the block, and
a block with no starred line at all exports nothing, which keeps a module's
specification entirely to itself.

Generated code
--------------
Since all the code is generated from the macro on compile-time and not stored
anywhere the generated code is made to be deterministic and easy to
understand. If you would like to see the code however you can pass
``-d:echoProtobuf`` switch on compile-time and the macro will output the
generated code.

Optional fields
^^^^^^^^^^^^^^^
As mentioned earlier protobuf 3 makes all fields optional. This means that
each field can either exist or not exist in a message. In many other protobuf
implementations you notice this by having to use special getter or setter
procs for field access. This library generates such getters and setters for
every field, but since Nim resolves ``msg.field`` and ``msg.field = x``
through them automatically it looks just like normal Nim code, except from
one thing, the call to
``has``. Whenever a field is set to something it will register its presence
in the object. Then when you access the field Nim will first check if it is
present or not, throwing a runtime ``ValueError`` if it isn't set. If you
want to remove a value already set in an object you simply call ``reset``
with the name of the field as seen in example 3. To check if a value exists
or not you can call ``has`` on it as seen in the above example. Since it's a
varargs call you can simply add all the fields you require in a single check.
In the below sections we will have a look at what the protobuf macro outputs.
Since the actual field names are hidden behind this abstraction the following
sections will show what the objects "feel" like they are defined as. Notice
also that since the fields don't actually have these names a regular object
initialiser wouldn't work, therefore you have to use the "init" procs created
as seen in the above example.

Since every field tracks its presence this way, the proto3 ``optional``
keyword is accepted and simply behaves like a regular field: a field that
is explicitly set to its default value is written out, and ``has`` tells
you whether it was present.

One consequence of the generated accessors is that their names live in the
module holding the block: a top-level variable in that module can't share a
name with a field, and a field can't share a name with a generated procedure
such as ``write`` or ``len``.

Messages
^^^^^^^^
A message becomes an ``object`` under the name your block gives it. So for
a specification like this:

.. code-block:: protobuf

  syntax = "proto3"; // The only syntax supported
  package our.package;
  message ExampleMessage {
      int32 simpleField = 1;
  }

a block naming it

.. code-block:: nim

  proto "example.proto":
    type Example* = our.package.ExampleMessage

produces a type that would appear to be:

.. code-block:: nim

  type
    Example* = object
      simpleField: int32

Being a plain object means a message behaves like any other Nim value.
Assigning one copies it, so the two go their separate ways:

.. code-block:: nim

  var a = Example.init(simpleField = 1)
  var b = a
  b.simpleField = 2
  assert a.simpleField == 1    # a is untouched

Comparing two messages compares their contents, so ``==`` is what you would
want it to be and a message can be a ``Table`` key. A message can be a
``const``, evaluated while compiling and baked into your program. There is no
nil: the default value of a message type is the empty message, which is
exactly what proto3 says an unset message field means. And a ``let`` message
is genuinely immutable — mutating a field needs a message you can mutate:

.. code-block:: nim

  let frozen = stream.read(Example)
  echo frozen.simpleField      # reading is fine
  frozen.simpleField = 2       # won't compile, frozen isn't mutable

The same applies to a message reached through a field of another message, and
to a message you want to pass somewhere that mutates it, such as
``readInto``. If you need to mutate it, bind it with ``var``.

Recursive messages and ``ref``
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
An object can't contain itself, so a message that reaches itself through a
plain field has no representation as a plain object. Nim rejects it while
compiling the generated types:

.. code-block:: protobuf

  message Node {
    int32 value = 1;
    Node next = 2;      // Node inside Node
  }

::

  Error: illegal recursion in type 'proto_Node'

Writing ``ref`` in front of the path in the block makes that message a
reference, which gives the indirection the cycle needs:

.. code-block:: nim

  proto "tree.proto":
    type Node* = ref our.package.Node

Only a message can be asked for as ``ref``; an enum or a oneof is an error at
that line. Nothing else about the message changes — the same fields, the same
procedures, the same bytes on the wire — but it goes back to behaving the way
a reference does: assigning one shares it rather than copying it, ``==``
compares identity, and a ``let`` freezes only the reference, so its fields
stay mutable.

``repeated`` and map fields don't need any of this. They are held in a ``seq``
and a ``Table``, which are indirections already, so a message that reaches
itself only through them stays a plain object:

.. code-block:: protobuf

  message Tree {
    string label = 1;
    repeated Tree children = 2;   // fine as a plain object
  }

A cycle can run through several messages, and through a oneof member, since a
oneof is held inside the message that declares it. Marking any one message on
the cycle is enough, because the others then hold it by reference. The
conformance suite's own ``TestAllTypesProto3`` is a real example: its
``NestedMessage`` has a field back to it, reached both through a plain field
and through a oneof, so it is named ``type TestAllTypesProto3* = ref
protobuf_test_messages.proto3.TestAllTypesProto3``.

Messages also generate a reader, writer, and length procedure to read,
write, and get the length of a message on the wire respectively. They are
named ``read``, ``write``, and ``len`` for every message and tell each other
apart by their types alone, so there are no generated names to remember.
The write procedure takes two arguments plus an optional third parameter,
the ``Stream`` to write to, an instance of the message type to write, and a
boolean telling it to prepend the message with a varint of its length or
not. This boolean is used for internal purposes, but might also come in handy
if you want to stream multiple messages as described in
https://developers.google.com/protocol-buffers/docs/techniques#streaming.
The read procedure takes the message type as its second argument, in the
style of the ``streams`` module's ``read`` for plain types, so reading the
message above is ``stream.read(Example)``.
Analagously to the ``write`` procedure the reader also takes an
optional ``maxSize`` argument of the exact size of the message on the wire.
If the size is negative, the default, the stream is read until ``atEnd``
returns true, while a size of 0 is an empty message. If the stream ends
before ``maxSize`` bytes are read an ``IOError`` is raised.
``readInto`` reads into a message that already exists instead of returning a
new one, which is protobuf's merge behaviour. It mutates the message it is
given, so unless the message is a ``ref`` it has to be one you can mutate.
The ``len`` procedure is slightly simpler, it only
takes an instance of the message type and returns the size this message would
take on the wire, in bytes. This is used internally, but might have some
other applications elsewhere as well. Notice that this size might vary from
one instance of the type to another as varints can have multiple sizes,
repeated fields different amount of elements, and oneofs having different
choices to name a few.

Since the fields don't really have the names they appear to have, a regular
object initialiser wouldn't work. Instead every message type gets an ``init``
which takes the fields you want to set by name:

.. code-block:: nim

  var msg = Example.init(simpleField = 100'i32)

Naming a field the message doesn't have is a compile error listing the fields
it does have, and a value of the wrong type is caught the same way it would be
in an object constructor.

Enums
^^^^^
Enums are named by the block the same way messages are, and are always
declared as pure. So an enum defined like this:

.. code-block:: protobuf

  syntax = "proto3"; // The only syntax supported
  package our.package;
  enum Langs {
    UNIVERSAL = 0;
    NIM = 1;
    C = 2;
  }

named by a line ``type Langs* = our.package.Langs`` would end up with a type
like this:

.. code-block:: nim

  type
    Langs* {.pure.} = enum
      UNIVERSAL = 0, NIM = 1, C = 2

For internal use enums also generate a reader and writer procedure. These
are basically a wrapper around the reader and writer for a varint, only that
they convert to and from the enum type. Using these by themselves is seldom
useful.

OneOfs
^^^^^^
In order for oneofs to work with Nims type system they generate their own
type. This might change in the future. The helper type of a oneof is named by
the path of the oneof field itself, so it can be named and constructed like
any other type. All oneofs contain a field named ``option`` telling you which
member is set, of a generated enum of the member names. This is used to create
an object variant for each of the fields in the oneof. So a oneof defined like
this:

.. code-block:: protobuf

  syntax = "proto3"; // The only syntax supported
  package our.package;
  message ExampleMessage {
    oneof choice {
      int32 firstField = 1;
      string secondField = 2;
    }
  }

named by a block like this:

.. code-block:: nim

  protoSpec spec:
    type
      Example* = our.package.ExampleMessage
      Choice* = our.package.ExampleMessage.choice

Will generate the following message and oneof type, along with the enum the
discriminator uses:

.. code-block:: nim

  type
    ChoiceKind* {.pure.} = enum
      firstField, secondField
    Choice* = object
      case option: ChoiceKind
      of firstField: firstField: int32
      of secondField: secondField: string
    Example* = object
      choice: Choice

The enum is named after the name your block gave the oneof, plus ``Kind``, and
it lists the members in declaration order. Since it's the type of ``option``
its members can be written unqualified in a ``case``:

.. code-block:: nim

  case msg.choice.option
  of firstField:  echo msg.choice.firstField
  of secondField: echo msg.choice.secondField

The enum is pure, so a member whose name is also in scope as something else
has to be qualified — a member called ``handle`` clashes with
``system.handle``, and ``of ChoiceKind.handle:`` is then the way to write it.

A oneof holds exactly one member, so its ``init`` takes exactly one, and
fills in ``option`` for you:

.. code-block:: nim

  msg.choice = Choice.init(secondField = "hello")

Passing no member, more than one, or a name the oneof doesn't have is a
compile error.

Maps
^^^^
Map fields turn into Nim's standard ``Table`` type, keyed and valued with
the same type mapping used for regular fields. Since the ``tables`` module
is exported by this module they can be used without any extra imports. So a
message defined like this:

.. code-block:: protobuf

  syntax = "proto3"; // The only syntax supported
  package our.package;
  message ExampleMessage {
    map<string, int32> counts = 1;
  }

Would appear to be:

.. code-block:: nim

  type
    Example* = object
      counts: Table[string, int32]

Map fields behave like any other field with regards to ``has``, ``reset``,
and the ``init`` procedure, and are serialized in the format protoc uses,
so they are wire-compatible with other protobuf implementations. As per the
protobuf specification keys can be any integral, bool, or string type, and
values can be any type but another map.

Sharing message definitions
---------------------------
If you want to re-use the same message definitions in multiple places in
your code it's a good idea to create a module for your definition. This can
also be useful if you want to give protobuf's types names that suit your
program better, or if you want to hide particular messages or create extra
functionality. Starring a line in the block is all it takes:

.. code-block:: nim

  # snapstats.nim
  import protobuf

  proto "snapstats/v1.proto":
    type
      Series* = smartrg.almanac.snapstats.v1.Series
      Encoding* = smartrg.almanac.snapstats.v1.PointEncoding
      Internal = smartrg.almanac.snapstats.v1.Bookkeeping

.. code-block:: nim

  # consumer.nim
  import snapstats, streams

  var s = Series.init(name = "receive")
  stream.write s

``Series`` and ``Encoding`` cross the module boundary with their accessors,
``init``, ``read``, ``write``, ``len``, ``has``, and ``reset``; ``Internal``
and every type the block didn't name stay behind. Sub-messages and other
dependent types need no special handling — a type you didn't name still works
through the fields of the ones you did.

Limitations
-----------
This library is still in an early phase and has some limitations over the
official version of protobuf. Noticably it only supports the "proto3"
syntax, so no required fields. Option statements and field options are
parsed but ignored, meaning you can't set default values for enums and
can't control packing options. That being said it follows the proto3
specification and will pack all scalar fields. It also doesn't support
services.

Anything that isn't parsed must be removed from the specification before
it can be used with this library.

If you find yourself in need of these features then I'd suggest heading over
to https://github.com/oswjk/nimpb which uses the official protoc compiler
with an extension to parse the protobuf file.

Rationale
---------
Some might be wondering why I've decided to create this library. After all
the protobuf compiler is extensible and there are some other attempts at
using protobuf within Nim by using this. The reason is three-fold, first off
no-one likes to add an extra step to their compilation process. Running
``protoc`` before compiling isn't a big issue, but it's an extra
compile-time dependency and it's more work. By using a regular Nim macro
this is moved to a simple step in the compilation process. The only
requirement is Nim and this library meaning tools can be automatically
installed through nimble and still use protobuf. It also means that all of
Nims targets are supported, and sending data between code compiled to C and
Javascript should be a breeze and can share the exact same code for
generating the messages. This is not yet tested, but any issues arising
should be easy enough to fix. Secondly the programatic protobuf interface
created for some languages are not the best. Python for example has some
rather awkward and un-natural patterns for their protobuf library. By using
a Nim macro the code can be customised to Nim much better and has the
potential to create really native-feeling code resulting in a very nice
interface. And finally this has been an interesting project in terms of
pushing the macro system to do something most languages would simply be
incapable of doing. It's not only a showcase of how much work the Nim
compiler is able to do for you through its meta-programming, but has also
been highly entertaining to work on.

This file is automatically generated from the documentation found in
protobuf.nim. Use ``nim doc2 protobuf.nim`` to get the full documentation.
