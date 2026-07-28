## This is a pure Nim implementation of protobuf, meaning that it doesn't rely
## on the ``protoc`` compiler. The entire implementation is based on a block
## that takes a file or a string containing the proto3 format as specified at
## https://developers.google.com/protocol-buffers/docs/proto3, along with a list
## of the types you want to use from it. It then produces procedures to read,
## write, and calculate the length of a message, along with types to hold the
## data in your Nim program. The data types are intended to be as close as
## possible to what you would normally use in Nim, making it feel very natural
## to use these types in your program in contrast to some protobuf
## implementations. Protobuf 3 however has all fields as optional fields, this
## means that the types generated have a little bit of special sauce going on
## behind the scenes. This will be explained in a later section. The entire
## read/write structure is built on top of the Stream interface from the
## ``streams`` module, meaning it can be used directly with anything that uses
## streams.
##
## Example
## -------
## To whet your appetite the following example shows how this protobuf block can
## be used to generate the required code and read and write protobuf messages.
## This example can also be found in the examples folder. Note that it is also
## possible to read the protobuf specification from a file with ``proto``.
##
## .. code-block:: nim
##
##   import protobuf, streams
##
##   # Define our protobuf specification and generate Nim code to use it
##   const spec = """
##   syntax = "proto3";
##
##   message ExampleMessage {
##     int32 number = 1;
##     string text = 2;
##     SubMessage nested = 3;
##     message SubMessage {
##       int32 a_field = 1;
##     }
##   }
##   """
##
##   # Every line names one type from the specification. The names are yours to
##   # pick, the paths on the right are the ones the specification uses.
##   protoSpec spec:
##     type
##       ExampleMessage* = ExampleMessage
##       SubMessage* = ExampleMessage.SubMessage
##
##   # Create our message
##   var msg = new ExampleMessage
##   msg.number = 10
##   msg.text = "Hello world"
##   msg.nested = SubMessage.init(aField = 100)
##
##   # Write it to a stream
##   var stream = newStringStream()
##   stream.write msg
##
##   # Read the message from the stream and output the data, if it's all present
##   stream.setPosition(0)
##   var readMsg = stream.read(ExampleMessage)
##   if readMsg.has(number, text, nested) and readMsg.nested.has(aField):
##     echo readMsg.number
##     echo readMsg.text
##     echo readMsg.nested.aField
##
## The specification more commonly lives in its own file, in which case ``proto``
## takes the path, resolved relative to the Nim file containing the block:
##
## .. code-block:: nim
##
##   proto "example.proto":
##     type ExampleMessage* = ExampleMessage
##
## Editing the specification recompiles the module that reads it.
##
## Naming and visibility
## ---------------------
## The body of the block is a list of ``type Name = some.proto.Path``
## declarations. The path on the right is interpreted against the specification
## and is always the full path: the package, then any enclosing messages, then
## the type. A specification without a ``package`` statement has bare paths. The
## name on the left is what the type is called in your program, and starring it
## exports it exactly as starring any other Nim type does.
##
## You only name what you use. Types you leave out are still generated, so they
## still work as the types of fields — the only thing you can't do with them is
## declare or construct one, because they have no name you can reach:
##
## .. code-block:: nim
##
##   proto "example.proto":
##     type Report* = app.Report      # app.Chart is left unnamed
##
##   let report = stream.read(Report)
##   echo report.chart.title          # fine, reached through the field
##   report.chart.title = "signal"    # also fine
##   let c = Chart.init()             # won't compile, there is no such name
##
## Because starring a line exports procs alongside the type, a block with a
## starred line has to appear at top level, where Nim allows export markers.
##
## An unstarred line names a type only inside the module holding the block, and
## a block with no starred line at all exports nothing, which keeps a module's
## specification entirely to itself.
##
## Generated code
## --------------
## Since all the code is generated from the macro on compile-time and not stored
## anywhere the generated code is made to be deterministic and easy to
## understand. If you would like to see the code however you can pass
## ``-d:echoProtobuf`` switch on compile-time and the macro will output the
## generated code.
##
## Optional fields
## ^^^^^^^^^^^^^^^
## As mentioned earlier protobuf 3 makes all fields optional. This means that
## each field can either exist or not exist in a message. In many other protobuf
## implementations you notice this by having to use special getter or setter
## procs for field access. This library generates such getters and setters for
## every field, but since Nim resolves ``msg.field`` and ``msg.field = x``
## through them automatically it looks just like normal Nim code, except from
## one thing, the call to
## ``has``. Whenever a field is set to something it will register its presence
## in the object. Then when you access the field Nim will first check if it is
## present or not, throwing a runtime ``ValueError`` if it isn't set. If you
## want to remove a value already set in an object you simply call ``reset``
## with the name of the field as seen in example 3. To check if a value exists
## or not you can call ``has`` on it as seen in the above example. Since it's a
## varargs call you can simply add all the fields you require in a single check.
## In the below sections we will have a look at what the protobuf macro outputs.
## Since the actual field names are hidden behind this abstraction the following
## sections will show what the objects "feel" like they are defined as. Notice
## also that since the fields don't actually have these names a regular object
## initialiser wouldn't work, therefore you have to use the "init" procs created
## as seen in the above example.
##
## Since every field tracks its presence this way, the proto3 ``optional``
## keyword is accepted and simply behaves like a regular field: a field that
## is explicitly set to its default value is written out, and ``has`` tells
## you whether it was present.
##
## One consequence of the generated accessors is that their names live in the
## module holding the block: a top-level variable in that module can't share a
## name with a field, and a field can't share a name with a generated procedure
## such as ``write`` or ``len``.
##
## Messages
## ^^^^^^^^
## A message becomes a ``ref object`` under the name your block gives it. So for
## a specification like this:
##
## .. code-block:: protobuf
##
##   syntax = "proto3"; // The only syntax supported
##   package our.package;
##   message ExampleMessage {
##       int32 simpleField = 1;
##   }
##
## a block naming it
##
## .. code-block:: nim
##
##   proto "example.proto":
##     type Example* = our.package.ExampleMessage
##
## produces a type that would appear to be:
##
## .. code-block:: nim
##
##   type
##     Example* = ref object
##       simpleField: int32
##
## Messages also generate a reader, writer, and length procedure to read,
## write, and get the length of a message on the wire respectively. They are
## named ``read``, ``write``, and ``len`` for every message and tell each other
## apart by their types alone, so there are no generated names to remember.
## The write procedure takes two arguments plus an optional third parameter,
## the ``Stream`` to write to, an instance of the message type to write, and a
## boolean telling it to prepend the message with a varint of its length or
## not. This boolean is used for internal purposes, but might also come in handy
## if you want to stream multiple messages as described in
## https://developers.google.com/protocol-buffers/docs/techniques#streaming.
## The read procedure takes the message type as its second argument, in the
## style of the ``streams`` module's ``read`` for plain types, so reading the
## message above is ``stream.read(Example)``.
## Analagously to the ``write`` procedure the reader also takes an
## optional ``maxSize`` argument of the exact size of the message on the wire.
## If the size is negative, the default, the stream is read until ``atEnd``
## returns true, while a size of 0 is an empty message. If the stream ends
## before ``maxSize`` bytes are read an ``IOError`` is raised.
## ``readInto`` reads into a message that already exists instead of returning a
## new one, which is protobuf's merge behaviour.
## The ``len`` procedure is slightly simpler, it only
## takes an instance of the message type and returns the size this message would
## take on the wire, in bytes. This is used internally, but might have some
## other applications elsewhere as well. Notice that this size might vary from
## one instance of the type to another as varints can have multiple sizes,
## repeated fields different amount of elements, and oneofs having different
## choices to name a few.
##
## Since the fields don't really have the names they appear to have, a regular
## object initialiser wouldn't work. Instead every message type gets an ``init``
## which takes the fields you want to set by name:
##
## .. code-block:: nim
##
##   var msg = Example.init(simpleField = 100'i32)
##
## Naming a field the message doesn't have is a compile error listing the fields
## it does have, and a value of the wrong type is caught the same way it would be
## in an object constructor.
##
## Enums
## ^^^^^
## Enums are named by the block the same way messages are, and are always
## declared as pure. So an enum defined like this:
##
## .. code-block:: protobuf
##
##   syntax = "proto3"; // The only syntax supported
##   package our.package;
##   enum Langs {
##     UNIVERSAL = 0;
##     NIM = 1;
##     C = 2;
##   }
##
## named by a line ``type Langs* = our.package.Langs`` would end up with a type
## like this:
##
## .. code-block:: nim
##
##   type
##     Langs* {.pure.} = enum
##       UNIVERSAL = 0, NIM = 1, C = 2
##
## For internal use enums also generate a reader and writer procedure. These
## are basically a wrapper around the reader and writer for a varint, only that
## they convert to and from the enum type. Using these by themselves is seldom
## useful.
##
## OneOfs
## ^^^^^^
## In order for oneofs to work with Nims type system they generate their own
## type. This might change in the future. The helper type of a oneof is named by
## the path of the oneof field itself, so it can be named and constructed like
## any other type. All oneofs contain a field named ``option`` telling you which
## member is set, of a generated enum of the member names. This is used to create
## an object variant for each of the fields in the oneof. So a oneof defined like
## this:
##
## .. code-block:: protobuf
##
##   syntax = "proto3"; // The only syntax supported
##   package our.package;
##   message ExampleMessage {
##     oneof choice {
##       int32 firstField = 1;
##       string secondField = 2;
##     }
##   }
##
## named by a block like this:
##
## .. code-block:: nim
##
##   protoSpec spec:
##     type
##       Example* = our.package.ExampleMessage
##       Choice* = our.package.ExampleMessage.choice
##
## Will generate the following message and oneof type, along with the enum the
## discriminator uses:
##
## .. code-block:: nim
##
##   type
##     ChoiceKind* {.pure.} = enum
##       firstField, secondField
##     Choice* = object
##       case option: ChoiceKind
##       of firstField: firstField: int32
##       of secondField: secondField: string
##     Example* = ref object
##       choice: Choice
##
## The enum is named after the name your block gave the oneof, plus ``Kind``, and
## it lists the members in declaration order. Since it's the type of ``option``
## its members can be written unqualified in a ``case``:
##
## .. code-block:: nim
##
##   case msg.choice.option
##   of firstField:  echo msg.choice.firstField
##   of secondField: echo msg.choice.secondField
##
## The enum is pure, so a member whose name is also in scope as something else
## has to be qualified — a member called ``handle`` clashes with
## ``system.handle``, and ``of ChoiceKind.handle:`` is then the way to write it.
##
## A oneof holds exactly one member, so its ``init`` takes exactly one, and
## fills in ``option`` for you:
##
## .. code-block:: nim
##
##   msg.choice = Choice.init(secondField = "hello")
##
## Passing no member, more than one, or a name the oneof doesn't have is a
## compile error.
##
## Maps
## ^^^^
## Map fields turn into Nim's standard ``Table`` type, keyed and valued with
## the same type mapping used for regular fields. Since the ``tables`` module
## is exported by this module they can be used without any extra imports. So a
## message defined like this:
##
## .. code-block:: protobuf
##
##   syntax = "proto3"; // The only syntax supported
##   package our.package;
##   message ExampleMessage {
##     map<string, int32> counts = 1;
##   }
##
## Would appear to be:
##
## .. code-block:: nim
##
##   type
##     Example* = ref object
##       counts: Table[string, int32]
##
## Map fields behave like any other field with regards to ``has``, ``reset``,
## and the ``init`` procedure, and are serialized in the format protoc uses,
## so they are wire-compatible with other protobuf implementations. As per the
## protobuf specification keys can be any integral, bool, or string type, and
## values can be any type but another map.
##
## Sharing message definitions
## ---------------------------
## If you want to re-use the same message definitions in multiple places in
## your code it's a good idea to create a module for your definition. This can
## also be useful if you want to give protobuf's types names that suit your
## program better, or if you want to hide particular messages or create extra
## functionality. Starring a line in the block is all it takes:
##
## .. code-block:: nim
##
##   # snapstats.nim
##   import protobuf
##
##   proto "snapstats/v1.proto":
##     type
##       Series* = smartrg.almanac.snapstats.v1.Series
##       Encoding* = smartrg.almanac.snapstats.v1.PointEncoding
##       Internal = smartrg.almanac.snapstats.v1.Bookkeeping
##
## .. code-block:: nim
##
##   # consumer.nim
##   import snapstats, streams
##
##   var s = Series.init(name = "receive")
##   stream.write s
##
## ``Series`` and ``Encoding`` cross the module boundary with their accessors,
## ``init``, ``read``, ``write``, ``len``, ``has``, and ``reset``; ``Internal``
## and every type the block didn't name stay behind. Sub-messages and other
## dependent types need no special handling — a type you didn't name still works
## through the fields of the ones you did.
##
## Limitations
## -----------
## This library is still in an early phase and has some limitations over the
## official version of protobuf. Noticably it only supports the "proto3"
## syntax, so no required fields. Option statements and field options are
## parsed but ignored, meaning you can't set default values for enums and
## can't control packing options. That being said it follows the proto3
## specification and will pack all scalar fields. It also doesn't support
## services.
##
## Anything that isn't parsed must be removed from the specification before
## it can be used with this library.
##
## If you find yourself in need of these features then I'd suggest heading over
## to https://github.com/oswjk/nimpb which uses the official protoc compiler
## with an extension to parse the protobuf file.
##
## Rationale
## ---------
## Some might be wondering why I've decided to create this library. After all
## the protobuf compiler is extensible and there are some other attempts at
## using protobuf within Nim by using this. The reason is three-fold, first off
## no-one likes to add an extra step to their compilation process. Running
## ``protoc`` before compiling isn't a big issue, but it's an extra
## compile-time dependency and it's more work. By using a regular Nim macro
## this is moved to a simple step in the compilation process. The only
## requirement is Nim and this library meaning tools can be automatically
## installed through nimble and still use protobuf. It also means that all of
## Nims targets are supported, and sending data between code compiled to C and
## Javascript should be a breeze and can share the exact same code for
## generating the messages. This is not yet tested, but any issues arising
## should be easy enough to fix. Secondly the programatic protobuf interface
## created for some languages are not the best. Python for example has some
## rather awkward and un-natural patterns for their protobuf library. By using
## a Nim macro the code can be customised to Nim much better and has the
## potential to create really native-feeling code resulting in a very nice
## interface. And finally this has been an interesting project in terms of
## pushing the macro system to do something most languages would simply be
## incapable of doing. It's not only a showcase of how much work the Nim
## compiler is able to do for you through its meta-programming, but has also
## been highly entertaining to work on.

import streams, strutils, sequtils, macros, tables, algorithm, sets
import std/editdistance
import protobuf/private/[parse, decldef, basetypes]
export basetypes
export macros
export strutils
export streams
export tables

type ValidationError = object of Defect

template ValidationAssert(statement: bool, error: string) =
  if not statement:
    raise newException(ValidationError, error)

type
  ProtoNames = object
    ## Maps the fully qualified dotted name of every type in a specification
    ## to the Nim name it is generated under. Types named by a line in the
    ## proto block get that name and are exported if the line is starred,
    ## everything else gets a hidden ``proto_`` prefixed name.
    nim: Table[string, string]
    exported: HashSet[string]
    oneofs: HashSet[string]
    anyExported: bool

proc hiddenName(dotted: string, oneof = false): string =
  ## The name a type is generated under when no line in the block names it.
  ## The prefix is what keeps it from colliding with the names the block
  ## declares, which a specification without a package would otherwise do
  ## for every type it defines.
  "proto_" & dotted.replace(".", "_") & (if oneof: "_OneOf" else: "")

proc collectTypeNames(node: ProtoNode, acc: var seq[tuple[path: string, oneof: bool]]) =
  ## Gathers the addressable types of an expanded specification: messages,
  ## enums, and the helper type of every oneof field.
  case node.kind:
  of ProtoDef:
    for package in node.packages:
      collectTypeNames(package, acc)
  of Package:
    for message in node.messages:
      collectTypeNames(message, acc)
    for enu in node.packageEnums:
      collectTypeNames(enu, acc)
  of Message:
    acc.add (path: node.messageName, oneof: false)
    for enu in node.definedEnums:
      collectTypeNames(enu, acc)
    for field in node.fields:
      if field.kind == Oneof:
        acc.add (path: field.oneofName, oneof: true)
    for nested in node.nested:
      collectTypeNames(nested, acc)
  of Enum:
    acc.add (path: node.enumName, oneof: false)
  else: discard

proc initProtoNames(proto: ProtoNode): ProtoNames =
  var found: seq[tuple[path: string, oneof: bool]] = @[]
  collectTypeNames(proto, found)
  result.nim = initTable[string, string]()
  result.exported = initHashSet[string]()
  result.oneofs = initHashSet[string]()
  for entry in found:
    result.nim[entry.path] = hiddenName(entry.path, entry.oneof)
    if entry.oneof:
      result.oneofs.incl entry.path

proc nimName(names: ProtoNames, dotted: string): string =
  if names.nim.hasKey(dotted): names.nim[dotted] else: hiddenName(dotted)

proc optionName(names: ProtoNames, oneofDotted: string): string =
  ## The discriminator enum of a oneof has no path in the specification, so its
  ## name is derived from the name the block gave the oneof. An unnamed oneof
  ## keeps a hidden name here too.
  if names.nim.hasKey(oneofDotted) and
      names.nim[oneofDotted] != hiddenName(oneofDotted, oneof = true):
    names.nim[oneofDotted] & "Kind"
  else:
    "proto_" & oneofDotted.replace(".", "_") & "_Option"

proc typeIdent(names: ProtoNames, dotted: string): NimNode =
  newIdentNode(names.nimName(dotted))

proc optionIdent(names: ProtoNames, oneofDotted: string): NimNode =
  newIdentNode(names.optionName(oneofDotted))

proc optionValue(names: ProtoNames, oneofDotted, member: string): NimNode =
  ## The discriminator enum is pure, so its members are always qualified in
  ## generated code.
  nnkDotExpr.newTree(names.optionIdent(oneofDotted), newIdentNode(member))

proc defIdent(names: ProtoNames, dotted: string): NimNode =
  ## The name of a type at its definition site, starred if the line that
  ## named it was starred.
  result = newIdentNode(names.nimName(dotted))
  if dotted in names.exported:
    result = nnkPostfix.newTree(newIdentNode("*"), result)

proc maybeExport(names: ProtoNames, name: string): NimNode =
  ## Procs are exported when the block names at least one type publicly;
  ## a block that keeps everything private pushes no overloads onto
  ## importing modules.
  result = newIdentNode(name)
  if names.anyExported:
    result = nnkPostfix.newTree(newIdentNode("*"), result)

proc maybeExportAccQuoted(names: ProtoNames, name: string): NimNode =
  ## Setters are named ``field=``, which has to be accent-quoted before it
  ## can carry an export marker.
  if names.anyExported:
    nnkPostfix.newTree(newIdentNode("*"), nnkAccQuoted.newTree(newIdentNode(name)))
  else:
    newIdentNode(name)

proc getTypes(message: ProtoNode, parent = ""): seq[string] =
  result = @[]
  case message.kind:
    of ProtoDef:
      for package in message.packages:
        result = result.concat package.getTypes(parent)
    of Package:
      let name = (if parent != "": parent & "." else: "") & (if message.packageName == "": "" else: message.packageName)
      for definedEnum in message.packageEnums:
        ValidationAssert(definedEnum.kind == Enum, "Field for defined enums contained something else than a message")
        result.add name & "." & definedEnum.enumName
      for innerMessage in message.messages:
        result = result.concat innerMessage.getTypes(name)
    of Message:
      let name = (if parent != "": parent & "." else: "") & message.messageName
      for definedEnum in message.definedEnums:
        ValidationAssert(definedEnum.kind == Enum, "Field for defined enums contained something else than a message")
        result.add name & "." & definedEnum.enumName
      for innerMessage in message.nested:
        result = result.concat innerMessage.getTypes(name)
      result.add name
    else: ValidationAssert(false, "Unknown kind: " & $message.kind)

proc verifyAndExpandTypes(node: ProtoNode, validTypes: seq[string], parent: seq[string] = @[]) =
  case node.kind:
    of Field:
      block fieldBlock:
        #node.name = parent.join(".") & "." & node.name
        if node.map:
          ValidationAssert(node.keyType in ["int32", "int64", "uint32", "uint64", "sint32", "sint64",
            "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string"],
            "Map key type must be an integral, bool, or string type: " & node.keyType)
        if node.protoType notin ["int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32",
          "fixed64", "sfixed32", "sfixed64", "bool", "bytes", "enum", "float", "double", "string"]:
          if node.protoType[0] != '.':
            var depth = parent.len
            while depth > 0:
              if parent[0 ..< depth].join(".") & "." & node.protoType in validTypes:
                node.protoType = parent[0 ..< depth].join(".") & "." & node.protoType
                break fieldBlock
              depth -= 1
            if node.protoType in validTypes:
              break fieldBlock
          else:
            if node.protoType[1 .. ^1] in validTypes:
              node.protoType = node.protoType[1 .. ^1]
              break fieldBlock
            var depth = 0
            while depth < parent.len:
              if parent[depth .. ^1].join(".") & "." & node.protoType[1 .. ^1] in validTypes:
                node.protoType = parent[depth .. ^1].join(".") & "." & node.protoType[1 .. ^1]
                break fieldBlock
              depth += 1
          ValidationAssert(false, "Type not recognized: " & parent.join(".") & "." & node.protoType)
    of Enum:
      node.enumName = (if parent.len != 0: parent.join(".") & "." else: "") & node.enumName
    of Oneof:
      for field in node.oneof:
        verifyAndExpandTypes(field, validTypes, parent)
      node.oneofName = parent.join(".") & "." & node.oneofName
    of Message:
      var name = parent & node.messageName
      for field in node.fields:
        verifyAndExpandTypes(field, validTypes, name)
      for definedEnum in node.definedEnums:
        verifyAndExpandTypes(definedEnum, validTypes, name)
      for subMessage in node.nested:
        verifyAndExpandTypes(subMessage, validTypes, name)
      node.messageName = name.join(".")
    of ProtoDef:
      for node in node.packages:
        var name = parent.concat(if node.packageName == "": @[] else: node.packageName.split("."))
        for enu in node.packageEnums:
          verifyAndExpandTypes(enu, validTypes, name)
        for message in node.messages:
          verifyAndExpandTypes(message, validTypes, name)

    else: ValidationAssert(false, "Unknown kind: " & $node.kind)

proc verifyReservedAndUnique(message: ProtoNode) =
  ValidationAssert(message.kind == Message, "ProtoBuf messages field contains something else than messages")
  var
    usedNames: seq[string] = @[]
    usedIndices: seq[int] = @[]
  for field in message.fields:
    ValidationAssert(field.kind == Field or field.kind == Oneof, "Field for defined fields contained something else than a field")
    for field in (if field.kind == Field: @[field] else: field.oneof):
      ValidationAssert(field.name notin usedNames, "Field name already used")
      ValidationAssert(field.number notin usedIndices, "Field number already used")
      usedNames.add field.name
      usedIndices.add field.number
      for value in message.reserved:
        ValidationAssert(value.kind == Reserved, "Field for reserved values contained something else than a reserved value")
        case value.reservedKind:
          of String:
            ValidationAssert(value.strVal != field.name, "Field name in list of reserved names")
          of Number:
            ValidationAssert(value.intVal != field.number, "Field index in list of reserved indices")
          of Range:
            ValidationAssert(not(field.number >= value.startVal and field.number <= value.endVal), "Field index in list of reserved indices")
  for m in message.nested:
    verifyReservedAndUnique(m)

proc enumReadName(dotted: string): string =
  ## Enum wire helpers are named from the hidden name even when a line in
  ## the block names the enum, so they stay stable and unexported either way.
  "read_" & hiddenName(dotted)

proc registerEnums(typeMapping: var Table[string, tuple[kind, write, read: NimNode, wire: int]], names: ProtoNames, node: ProtoNode) =
  case node.kind:
  of Enum:
    typeMapping[node.enumName] = (kind: names.typeIdent(node.enumName), write: newIdentNode("write"), read: newIdentNode(enumReadName(node.enumName)), wire: 0)
  of Message:
    for message in node.nested:
      registerEnums(typeMapping, names, message)
    for enu in node.definedEnums:
      registerEnums(typeMapping, names, enu)
  of ProtoDef:
    for node in node.packages:
      for message in node.messages:
        registerEnums(typeMapping, names, message)
      for enu in node.packageEnums:
        registerEnums(typeMapping, names, enu)
  else:
    discard

proc findIgnoreStyle*(arr: openarray[string], field: string): int =
  for idx, fld in arr:
    if fld[0] == field[0]:
      if cmpIgnoreStyle(fld[0..^1], field[0..^1]) == 0:
        return idx
  return -1


proc genAccessors(names: ProtoNames, typeName: NimNode, fieldName: string, fieldType: NimNode, idx: int): NimNode {.compileTime.} =
  ## Generates the getter and setter for a field. These are plain procs, so
  ## field access needs no experimental features and tooling like nimsuggest
  ## can see the field names. The getter returns a var location so that
  ## elements of repeated and map fields can be modified in place.
  let
    getter = names.maybeExport(fieldName)
    setter = names.maybeExportAccQuoted(fieldName & "=")
    private = newIdentNode("private_" & fieldName)
    idxLit = newLit(idx)
    errorMsg = newLit("Field \"" & fieldName & "\" isn't initialized")
    m = newIdentNode("m")
    value = newIdentNode("value")
  result = quote do:
    proc `getter`(`m`: `typeName`): var `fieldType` =
      if not `m`.fields.contains(`idxLit`):
        raise newException(ValueError, `errorMsg`)
      `m`.`private`
    proc `setter`(`m`: `typeName`, `value`: `fieldType`) =
      `m`.fields.incl(`idxLit`)
      `m`.`private` = `value`

proc genOneofHelpers(names: ProtoNames, typeName, optionType: NimNode, memberNames: openarray[string]): NimNode {.compileTime.} =
  ## Generates the ``init`` of a oneof type, which takes the one member to set
  ## by name and fills in the discriminator itself, so no user code has to know
  ## what position a member was declared in.
  let
    initName = names.maybeExport("init")
    res = newIdentNode("result")
    typeStr = newLit($typeName)
    optionStr = newLit($optionType)
    membersJoined = newLit(memberNames.join(";"))
  result = quote do:
    macro `initName`(T: typedesc[`typeName`], x: varargs[untyped]): untyped =
      if x.len != 1:
        error("A oneof holds exactly one member, got " & $x.len & " of them", x)
      x[0].expectKind(nnkExprEqExpr)
      x[0][0].expectKind(nnkIdent)
      let
        members = `membersJoined`.split(';')
        idx = members.findIgnoreStyle($x[0][0])
      if idx == -1:
        error("Couldn't find member \"" & $x[0][0] & "\" in oneof, it has " &
          `membersJoined`.split(';').join(", "), x[0])
      `res` = nnkObjConstr.newTree(
        bindSym(`typeStr`),
        nnkExprColonExpr.newTree(
          newIdentNode("option"),
          nnkDotExpr.newTree(bindSym(`optionStr`), newIdentNode(members[idx]))
        ),
        nnkExprColonExpr.newTree(
          newIdentNode(members[idx]),
          x[0][1]
        )
      )

proc genHelpers(names: ProtoNames, typeName: NimNode, fieldNames: openarray[string]): NimNode {.compileTime.} =
  ## Generates the ``init`` macro and, for messages with fields, the ``has``
  ## and ``reset`` macros. All three dispatch on the message type rather than
  ## carrying it in their name, so they are reached through whatever name the
  ## proto block gave the type.
  let
    initName = names.maybeExport("init")
    hasName = names.maybeExport("has")
    resetName = names.maybeExport("reset")
    i = genSym(nskForVar)
    typeStr = newLit($typeName)
    res = newIdentNode("result")
    fieldsSym = genSym(nskVar)
    fieldsLen = fieldNames.len - 1
    # NOTE: the field names are passed as a single ';'-joined string instead
    # of an array literal. Iterating a quote-interpolated array literal
    # inside these macros crashes the Nim 2.x VM ("index out of bounds, the
    # container is empty").
    fieldsJoined = newLit(fieldNames.join(";"))
  var
    # A name the message doesn't have is a mistake, not something to drop
    # quietly
    initialiserCases = quote do:
      case normalize($`i`[0]):
      else:
        error("Couldn't find field \"" & $`i`[0] & "\" in object, it has " &
          `fieldsJoined`.split(';').join(", "), `i`)
  var j = 0
  for field in fieldNames:
    let
      newFieldStr = "private_" & field
    initialiserCases.insert(1, (quote do:
      case 0:
      of normalize(`field`):
        `fieldsSym`.add nnkCall.newTree(
            nnkBracketExpr.newTree(
              newIdentNode("range"),
              nnkInfix.newTree(
                newIdentNode(".."),
                newLit(0),
                newLit(`fieldsLen`)
              )
            ),
            newLit(`j`)
          )
        `res`.add nnkExprColonExpr.newTree(
          newIdentNode(`newFieldStr`),
          `i`[1]
        )
    )[1])
    j += 1
  if fieldNames.len > 0:
    result = quote do:
      # bindSym resolves the message type in the module that generated it, so
      # the expansion works at a call site that cannot name the type at all
      macro `initName`(T: typedesc[`typeName`], x: varargs[untyped]): untyped =
        `res` = nnkObjConstr.newTree(
          bindSym(`typeStr`)
        )
        var `fieldsSym` = newNimNode(nnkCurly)
        for `i` in x:
          `i`.expectKind(nnkExprEqExpr)
          `i`[0].expectKind(nnkIdent)
          `initialiserCases`
        `res`.add nnkExprColonExpr.newTree(
          newIdentNode("fields"),
          `fieldsSym`
        )

      macro `hasName`(obj: `typeName`, fields: varargs[untyped]): untyped =
        `res` = newLit(true)
        for field in fields:
          let
            fname = $field
            idx = `fieldsJoined`.split(';').findIgnoreStyle(fname)
          assert idx != -1, "Couldn't find field \"" & fname & "\" in object"
          `res` = nnkInfix.newTree(
            newIdentNode("and"),
            nnkCall.newTree(
              newIdentNode("contains"),
              nnkDotExpr.newTree(
                obj,
                newIdentNode("fields")
              ),
              newLit(idx)
            ),
            `res`
          )

      macro `resetName`(obj: `typeName`, field: untyped): untyped =
        let
          fname = $field
          newField = newIdentNode("private_" & fname)
          idx = `fieldsJoined`.split(';').find(fname)
          objCache = genSym(nskLet)
        assert idx != -1, "Couldn't find field in object"
        `res` = nnkStmtList.newTree(
          nnkLetSection.newTree(
            nnkIdentDefs.newTree(
              objCache,
              newEmptyNode(),
              obj
            )
          ),
          nnkCall.newTree(
            newIdentNode("excl"),
            nnkDotExpr.newTree(
              objCache,
              newIdentNode("fields")
            ),
            newLit(idx)
          ),
          nnkCall.newTree(
            newIdentNode("reset"),
            nnkDotExpr.newTree(
              objCache,
              newField
            )
          )
        )
  else:
    result = quote do:
      macro `initName`(T: typedesc[`typeName`], x: varargs[untyped]): untyped =
        if x.len != 0:
          error(`typeStr` & " has no fields, got " & $x.len & " of them", x)
        `res` = nnkObjConstr.newTree(
          bindSym(`typeStr`)
        )

proc generateCode(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], names: ProtoNames, proto: ProtoNode): NimNode {.compileTime.} =
  var typeHelpers = newStmtList()
  proc fieldType(protoType: string): NimNode =
    if typeMapping.hasKey(protoType): typeMapping[protoType].kind else: names.typeIdent(protoType)
  proc generateTypes(node: ProtoNode, parent: var NimNode) =
    case node.kind:
    of Field:
      if node.map:
        parent.add(nnkIdentDefs.newTree(
          newIdentNode("private_" & node.name),
          nnkBracketExpr.newTree(
            newIdentNode("Table"),
            fieldType(node.keyType),
            fieldType(node.protoType),
          ),
          newEmptyNode()
        ))
      elif node.repeated:
        parent.add(nnkIdentDefs.newTree(
          newIdentNode("private_" & node.name),
          nnkBracketExpr.newTree(
            newIdentNode("seq"),
            fieldType(node.protoType),
          ),
          newEmptyNode()
        ))
      else:
        parent.add(nnkIdentDefs.newTree(
          newIdentNode("private_" & node.name),
          fieldType(node.protoType),
          newEmptyNode()
        ))
    of EnumVal:
      parent.add(
        nnkEnumFieldDef.newTree(
          newIdentNode(node.fieldName),
          newIntLitNode(node.num)
        )
      )
    of Enum:
      var currentEnum = nnkTypeDef.newTree(
        nnkPragmaExpr.newTree(
          names.defIdent(node.enumName),
          nnkPragma.newTree(newIdentNode("pure"))
        ),
        newEmptyNode()
      )
      var enumBlock = nnkEnumTy.newTree(newEmptyNode())
      # Nim enums must be declared in ascending order, protobuf enums can
      # declare their values (including negative ones) in any order
      for enumVal in node.values.sortedByIt(it.num):
        generateTypes(enumVal, enumBlock)
      currentEnum.add(enumBlock)
      parent.add(currentEnum)
    of OneOf:
      # The discriminator is an enum of the member names, so both reading and
      # constructing a oneof name the member instead of counting declarations
      var optionValues = nnkEnumTy.newTree(newEmptyNode())
      for field in node.oneof:
        optionValues.add newIdentNode(field.name)
      var optionName = names.optionIdent(node.oneofName)
      if node.oneofName in names.exported:
        optionName = nnkPostfix.newTree(newIdentNode("*"), optionName)
      parent.add(nnkTypeDef.newTree(
        nnkPragmaExpr.newTree(
          optionName,
          nnkPragma.newTree(newIdentNode("pure"))
        ),
        newEmptyNode(),
        optionValues
      ))
      # A oneof type has no accessors, users read and construct its fields
      # directly, so those fields carry the export marker themselves
      var cases = nnkRecCase.newTree(
          nnkIdentDefs.newTree(
            names.maybeExport("option"),
            names.optionIdent(node.oneofName),
            newEmptyNode()
          )
        )
      var curCase = 0
      for field in node.oneof:
        var caseBody = newNimNode(nnkRecList)
        if field.repeated:
          caseBody.add(nnkIdentDefs.newTree(
            names.maybeExport(field.name),
            nnkBracketExpr.newTree(
              newIdentNode("seq"),
              fieldType(field.protoType),
            ),
            newEmptyNode()
          ))
        else:
          caseBody.add(nnkIdentDefs.newTree(
            names.maybeExport(field.name),
            fieldType(field.protoType),
            newEmptyNode()
          ))
        cases.add(
          nnkOfBranch.newTree(
            names.optionValue(node.oneofName, field.name),
            caseBody
          )
        )
        curCase += 1
      parent.add(
        nnkTypeDef.newTree(
          names.defIdent(node.oneofName),
          newEmptyNode(),
          nnkObjectTy.newTree(
            newEmptyNode(),
            newEmptyNode(),
            nnkRecList.newTree(
              cases
            )
          )
        )
      )
      typeHelpers.add genOneofHelpers(names, names.typeIdent(node.oneofName),
        names.optionIdent(node.oneofName), node.oneof.mapIt(it.name))
    of Message:
      var currentMessage = nnkTypeDef.newTree(
        names.defIdent(node.messageName),
        newEmptyNode()
      )
      var messageBlock = nnkRecList.newNimNode()
      messageBlock.add(nnkIdentDefs.newTree(
        newIdentNode("protoUnknownFields"),
        newIdentNode("string"),
        newEmptyNode()
      ))
      if node.fields.len > 0:
        messageBlock.add(nnkIdentDefs.newTree(
          newIdentNode("fields"),
          nnkBracketExpr.newTree(
            newIdentNode("set"),
            nnkBracketExpr.newTree(
              newIdentNode("range"),
              nnkInfix.newTree(
                newIdentNode(".."),
                newLit(0),
                newLit(node.fields.len - 1)
              )
            )
          ),
          newEmptyNode()
        ))
        var fields = newSeq[string](node.fields.len)
        let typeIdent = names.typeIdent(node.messageName)
        for i, field in node.fields:
          if field.kind == Field:
            generateTypes(field, messageBlock)
            fields[i] = field.name.replace(".", "_")
            typeHelpers.add genAccessors(names, typeIdent, fields[i], copyNimTree(messageBlock[^1][1]), i)
          else:
            generateTypes(field, parent)
            let
              oneofType = names.typeIdent(field.oneofName)
              oneofName = field.oneofName.rsplit({'.'}, 1)[1]
            messageBlock.add(nnkIdentDefs.newTree(
              newIdentNode("private_" & oneofName),
              oneofType,
              newEmptyNode()
            ))
            fields[i] = oneofName
            typeHelpers.add genAccessors(names, typeIdent, oneofName, oneofType, i)
        typeHelpers.add genHelpers(names, typeIdent, fields)
      else:
        typeHelpers.add genHelpers(names, names.typeIdent(node.messageName), @[])

      currentMessage.add(nnkRefTy.newTree(nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), messageBlock)))
      parent.add(currentMessage)
      for definedEnum in node.definedEnums:
        generateTypes(definedEnum, parent)
      for subMessage in node.nested:
        generateTypes(subMessage, parent)
    of ProtoDef:
      for node in node.packages:
        for message in node.messages:
          generateTypes(message, parent)
        for enu in node.packageEnums:
          generateTypes(enu, parent)
    else:
      echo "Unsupported kind: " & $node.kind
      discard
  proc generateFieldLen(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, field: NimNode, res: NimNode = newIdentNode("result")): NimNode =
    result = newStmtList()
    if node.map:
      # Each entry is written as a length-delimited pseudo-message with
      # key = 1 and value = 2, so size the entries with synthetic fields.
      let
        keyField = ProtoNode(kind: Field, number: 1, protoType: node.keyType, name: "key")
        valueField = ProtoNode(kind: Field, number: 2, protoType: node.protoType, name: "value")
        keySym = genSym(nskForVar)
        valueSym = genSym(nskForVar)
        entrySizeSym = genSym(nskVar)
        entryDesc = newLit(getVarIntLen(node.number shl 3 or 2))
        keyLen = generateFieldLen(typeMapping, keyField, keySym, entrySizeSym)
        valueLen = generateFieldLen(typeMapping, valueField, valueSym, entrySizeSym)
      result.add(quote do:
        for `keySym`, `valueSym` in `field`.pairs:
          var `entrySizeSym` = 0
          `keyLen`
          `valueLen`
          `res` += `entryDesc` + getVarIntLen(`entrySizeSym`.int64) + `entrySizeSym`
      )
      return
    let fieldDesc = newLit(getVarIntLen(node.number shl 3 or (if not node.repeated and typeMapping.hasKey(node.protoType): typeMapping[node.protoType].wire else: 2)))
    result.add(quote do:
      `res` += `fieldDesc`
    )
    if typeMapping.hasKey(node.protoType):
      case typeMapping[node.protoType].wire:
      of 1:
        if node.repeated:
          result.add(quote do:
            `res` += getVarIntLen((8*`field`.len).int64) + 8*`field`.len
          )
        else:
          result.add(quote do:
            `res` += 8
          )
      of 5:
        if node.repeated:
          result.add(quote do:
            `res` += getVarIntLen((4*`field`.len).int64) + 4*`field`.len
          )
        else:
          result.add(quote do:
            `res` += 4
          )
      of 2:
        if node.repeated:
          result.add(quote do:
            for i in `field`:
              `res` += i.len
              `res` += getVarIntLen(i.len.int64)
            `res` += `fieldDesc`*(`field`.len-1)
          )
        else:
          result.add(quote do:
            `res` += getVarIntLen(`field`.len.int64)
            `res` += `field`.len
          )
      of 0:
        let
          iVar = nskForVar.genSym()
          varInt = if node.repeated: nnkBracketExpr.newTree(field, iVar) else: field
          # sint fields are ZigZag encoded, their length must be taken from
          # the encoded value
          lenProc = newIdentNode(if node.protoType in ["sint32", "sint64"]: "getSVarIntLen" else: "getVarIntLen")
          packedSize = genSym(nskVar)
          outerBody = if node.repeated: (quote do:
            var `packedSize` = 0
            for `iVar` in 0..`field`.high:
              `packedSize` += `lenProc`(`varInt`)
            `res` += getVarIntLen(`packedSize`.int64) + `packedSize`
          ) else: (quote do:
            `res` += `lenProc`(`varInt`)
          )
        result.add(outerBody)
      else:
        echo "Unable to create code"
        #raise newException(AssertionError, "Unable to generate code, wire type '" & $typeMapping[field.protoType].wire & "' not supported")
    else:
      if node.repeated:
        result.add(quote do:
          for i in `field`:
            `res` += i.len
            `res` += getVarIntLen(i.len.int64)
          `res` += `fieldDesc`*(`field`.len-1)
        )
      else:
        result.add(quote do:
          `res` += getVarIntLen(`field`.len.int64)
          `res` += `field`.len
        )

  proc generateReadStmt(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], protoType: string, stream: NimNode): NimNode =
    if typeMapping.hasKey(protoType):
      let protoRead = typeMapping[protoType].read
      quote do: `stream`.`protoRead`()
    else:
      # Messages are always length-delimited on the wire, and their reader
      # dispatches on the type rather than carrying it in its name
      let messageType = names.typeIdent(protoType)
      quote do:
        `stream`.read(`messageType`, `stream`.protoReadInt64())

  proc generateFieldRead(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, stream, field: NimNode, parent: NimNode): NimNode =
    # References to `fieldSpec` bind to the tag read by the surrounding
    # message reader, it is deliberately not hygienic.
    result = newStmtList()
    let fieldSpec = newIdentNode("fieldSpec")
    if node.map:
      let
        keyType = fieldType(node.keyType)
        valueType = fieldType(node.protoType)
        keyWire = newLit(typeMapping[node.keyType].wire.uint64)
        valueWire = newLit(if typeMapping.hasKey(node.protoType): typeMapping[node.protoType].wire.uint64 else: 2'u64)
        keySym = genSym(nskVar)
        valueSym = genSym(nskVar)
        keyRead = generateReadStmt(typeMapping, node.keyType, stream)
        valueRead = generateReadStmt(typeMapping, node.protoType, stream)
        # A message value that appears again within an entry is merged
        valueMerge = if typeMapping.hasKey(node.protoType):
            quote do:
              `valueSym` = `valueRead`
          else:
            quote do:
              if `valueSym`.isNil:
                `valueSym` = `valueRead`
              else:
                `stream`.readInto(`valueSym`, `stream`.protoReadInt64())
      result.add(quote do:
        if (`fieldSpec` and 0b111'u64) != 2'u64:
          raise newException(ValueError, "Wrong wire type for map field")
        let
          entryLen = `stream`.protoReadInt64()
          endPos = `stream`.getPosition() + entryLen
        var `keySym`: `keyType`
        var `valueSym`: `valueType`
        while `stream`.getPosition() < endPos:
          let entrySpec = `stream`.protoReadTag()
          case (entrySpec shr 3).int64:
          of 1:
            if (entrySpec and 0b111'u64) != `keyWire`:
              raise newException(ValueError, "Wrong wire type for map key")
            `keySym` = `keyRead`
          of 2:
            if (entrySpec and 0b111'u64) != `valueWire`:
              raise newException(ValueError, "Wrong wire type for map value")
            `valueMerge`
          else:
            `stream`.protoSkipField(entrySpec)
        when `valueSym` is ref:
          # An entry may omit its value; default-initialise it like protoc does
          if `valueSym`.isNil:
            `valueSym` = new `valueType`
        if not `parent`.has(`field`):
          `parent`.`field` = initTable[`keyType`, `valueType`]()
        `parent`.`field`[`keySym`] = `valueSym`
      )
    elif node.repeated:
      if typeMapping.hasKey(node.protoType) and node.protoType != "string" and node.protoType != "bytes":
        # Repeated scalars must accept both the packed and the unpacked encoding
        let
          protoRead = typeMapping[node.protoType].read
          scalarWire = newLit(typeMapping[node.protoType].wire.uint64)
        result.add(quote do:
          if not `parent`.has(`field`):
            `parent`.`field` = @[]
          if (`fieldSpec` and 0b111'u64) == 2'u64:
            let
              packedLen = `stream`.protoReadInt64()
              endPos = `stream`.getPosition() + packedLen
            while `stream`.getPosition() < endPos:
              `parent`.`field`.add(`stream`.`protoRead`())
          elif (`fieldSpec` and 0b111'u64) == `scalarWire`:
            `parent`.`field`.add(`stream`.`protoRead`())
          else:
            raise newException(ValueError, "Wrong wire type for repeated field")
        )
      else:
        let readStmt = generateReadStmt(typeMapping, node.protoType, stream)
        result.add(quote do:
          if (`fieldSpec` and 0b111'u64) != 2'u64:
            raise newException(ValueError, "Wrong wire type for field")
          if not `parent`.has(`field`):
            `parent`.`field` = @[]
          `parent`.`field`.add(`readStmt`)
        )
    else:
      if typeMapping.hasKey(node.protoType):
        let
          expectedWire = newLit(typeMapping[node.protoType].wire.uint64)
          readStmt = generateReadStmt(typeMapping, node.protoType, stream)
          target = nnkAsgn.newTree(nnkDotExpr.newTree(parent, field), readStmt)
        result.add(quote do:
          if (`fieldSpec` and 0b111'u64) != `expectedWire`:
            raise newException(ValueError, "Wrong wire type for field")
          `target`
        )
      else:
        # A message field that appears again is merged with the previous value
        let messageType = names.typeIdent(node.protoType)
        result.add(quote do:
          if (`fieldSpec` and 0b111'u64) != 2'u64:
            raise newException(ValueError, "Wrong wire type for field")
          if `parent`.has(`field`):
            `stream`.readInto(`parent`.`field`, `stream`.protoReadInt64())
          else:
            `parent`.`field` = `stream`.read(`messageType`, `stream`.protoReadInt64())
        )

  proc generateFieldWrite(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, stream, field: NimNode): NimNode =
    # Write field number and wire type
    result = newStmtList()
    if node.map:
      let
        keyField = ProtoNode(kind: Field, number: 1, protoType: node.keyType, name: "key")
        valueField = ProtoNode(kind: Field, number: 2, protoType: node.protoType, name: "value")
        keySym = genSym(nskForVar)
        valueSym = genSym(nskForVar)
        entrySizeSym = genSym(nskVar)
        entryDesc = newLit(node.number shl 3 or 2)
        keyLen = generateFieldLen(typeMapping, keyField, keySym, entrySizeSym)
        valueLen = generateFieldLen(typeMapping, valueField, valueSym, entrySizeSym)
        keyWrite = generateFieldWrite(typeMapping, keyField, stream, keySym)
        valueWrite = generateFieldWrite(typeMapping, valueField, stream, valueSym)
      result.add(quote do:
        for `keySym`, `valueSym` in `field`.pairs:
          `stream`.protoWriteInt64(`entryDesc`)
          var `entrySizeSym` = 0
          `keyLen`
          `valueLen`
          `stream`.protoWriteInt64(`entrySizeSym`)
          `keyWrite`
          `valueWrite`
      )
      return
    let fieldWrite = nnkCall.newTree(
        newIdentNode("protoWriteInt64"),
        stream,
        newLit(node.number shl 3 or (if not node.repeated and typeMapping.hasKey(node.protoType): typeMapping[node.protoType].wire else: 2))
      )
    # If the field is repeated or has a repeated wire type, write it's length
    if typeMapping.hasKey(node.protoType) and node.protoType != "string" and node.protoType != "bytes":
      result.add(fieldWrite)
      if node.repeated:
        case typeMapping[node.protoType].wire:
        of 1:
          # Write 64bit * len
          result.add(quote do:
            `stream`.protoWriteInt64(8*`field`.len)
          )
        of 5:
          # Write 32bit * len
          result.add(quote do:
            `stream`.protoWriteInt64(4*`field`.len)
          )
        of 2:
          # Write len
          result.add(quote do:
            var bytes = 0
            for i in 0..`field`.high:
              bytes += `field`[i].len
            `stream`.protoWriteInt64(bytes)
          )
        of 0:
          # Sum varint lengths and write them, using the ZigZag encoded
          # length for sint fields
          let getVarIntLen = newIdentNode(if node.protoType in ["sint32", "sint64"]: "getSVarIntLen" else: "getVarIntLen")
          result.add(quote do:
            var bytes = 0
            for i in 0..`field`.high:
              bytes += `getVarIntLen`(`field`[i])
            `stream`.protoWriteInt64(bytes)
          )
        else:
          echo "Unable to create code"
      let
        iVar = nskForVar.genSym()
        varInt = if node.repeated: nnkBracketExpr.newTree(field, iVar) else: field
        innerBody = nnkCall.newTree(
          typeMapping[node.protoType].write,
          stream,
          varInt
        )
        outerBody = if node.repeated: (quote do:
          for `iVar` in 0..`field`.high:
            `innerBody`
        ) else: innerBody
      result.add(outerBody)
    else:
      let
        iVar = nskForVar.genSym()
        varInt = if node.repeated: nnkBracketExpr.newTree(field, iVar) else: field
        protoWrite = if typeMapping.hasKey(node.protoType): typeMapping[node.protoType].write else: newEmptyNode()
        innerBody = if typeMapping.hasKey(node.protoType):
          quote do:
            `fieldWrite`
            `stream`.`protoWrite`(`varInt`)
        else:
          # Messages are always written with their length prefixed
          quote do:
            `fieldWrite`
            `stream`.write(`varInt`, true)
        outerBody = if node.repeated: (quote do:
          for `iVar` in 0..`field`.high:
            `innerBody`
        ) else: innerBody
      result.add(outerBody)

  proc generateProcs(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, decls: var NimNode, impls: var NimNode) =
    case node.kind:
      of Message:
        let
          readName = names.maybeExport("read")
          readIntoName = names.maybeExport("readInto")
          writeName = names.maybeExport("write")
          lenName = names.maybeExport("len")
          messageType = names.typeIdent(node.messageName)
          res = newIdentNode("result")
          s = newIdentNode("s")
          o = newIdentNode("o")
          t = newIdentNode("T")
          maxSize = newIdentNode("maxSize")
          writeSize = newIdentNode("writeSize")
          fieldSpec = newIdentNode("fieldSpec")
        # readInto merges from the stream into an existing message, which is
        # both the reading backend and protobuf's message merge semantics. A
        # negative maxSize reads until the end of the stream, 0 is an empty
        # message. read takes the message type as a typedesc so that every
        # message shares the one name.
        var procDecls = quote do:
          proc `readIntoName`(`s`: Stream, `o`: `messageType`, `maxSize`: int64 = -1)
          proc `readName`(`s`: Stream, `t`: typedesc[`messageType`], `maxSize`: int64 = -1): `messageType`
          proc `writeName`(`s`: Stream, `o`: `messageType`, `writeSize` = false)
          proc `lenName`(`o`: `messageType`): int
        var procImpls = quote do:
          proc `readIntoName`(`s`: Stream, `o`: `messageType`, `maxSize`: int64 = -1) =
            let startPos = `s`.getPosition()
            while not `s`.atEnd and (`maxSize` < 0 or `s`.getPosition() < startPos + `maxSize`):
              let
                `fieldSpec` = `s`.protoReadTag()
                fieldNumber = `fieldSpec` shr 3
              case fieldNumber.int64:
            if `maxSize` > 0 and `s`.getPosition() != startPos + `maxSize`:
              raise newException(IOError, "Stream ended before end of message")
          proc `readName`(`s`: Stream, `t`: typedesc[`messageType`], `maxSize`: int64 = -1): `messageType` =
            `res` = new `messageType`
            `s`.readInto(`res`, `maxSize`)
          proc `writeName`(`s`: Stream, `o`: `messageType`, `writeSize` = false) =
            if `writeSize`:
              `s`.protoWriteInt64(`o`.len)
          proc `lenName`(`o`: `messageType`): int
        procImpls[3][6] = newStmtList()
        for field in node.fields:
          generateProcs(typeMapping, field, procDecls, procImpls)
        # Unknown fields are captured on read and emitted again on write
        procImpls[0][6][1][1][1].add(nnkElse.newTree(nnkStmtList.newTree(
          newCall(newIdentNode("protoCaptureField"), s, fieldSpec,
            nnkDotExpr.newTree(o, newIdentNode("protoUnknownFields"))))))
        procImpls[2][6].add(quote do:
          if `o`.protoUnknownFields.len > 0:
            `s`.write(`o`.protoUnknownFields)
        )
        procImpls[3][6].add(quote do:
          `res` += `o`.protoUnknownFields.len
        )
        for enumType in node.definedEnums:
          generateProcs(typeMapping, enumType, procDecls, procImpls)
        for message in node.nested:
          generateProcs(typeMapping, message, decls, impls)
        decls.add procDecls
        impls.add procImpls
      of OneOf:
        let
          oneofName = newIdentNode(node.oneofname.rsplit({'.'}, 1)[1])
          oneofType = names.typeIdent(node.oneofName)
          readTarget = newIdentNode("o")
        for i in 0..node.oneof.high:
          let oneof = node.oneof[i]
          let optionVal = names.optionValue(node.oneofName, oneof.name)
          if typeMapping.hasKey(oneof.protoType) or oneof.repeated:
            impls[0][6][1][1][1].add(nnkOfBranch.newTree(newLit(oneof.number),
              nnkStmtList.newTree(
                nnkAsgn.newTree(nnkDotExpr.newTree(readTarget, oneofName),
                  quote do: `oneofType`(option: `optionVal`)
                ),
                generateFieldRead(typeMapping, oneof, impls[0][3][1][0], newIdentNode(oneof.name), nnkDotExpr.newTree(readTarget, oneofName))
              )
            ))
          else:
            # A message member is merged when the same field appears again,
            # and replaced when the oneof last held a different member
            let
              memberName = newIdentNode(oneof.name)
              memberType = names.typeIdent(oneof.protoType)
              stream = impls[0][3][1][0]
              fieldSpec = newIdentNode("fieldSpec")
            impls[0][6][1][1][1].add(nnkOfBranch.newTree(newLit(oneof.number),
              nnkStmtList.newTree(quote do:
                if (`fieldSpec` and 0b111'u64) != 2'u64:
                  raise newException(ValueError, "Wrong wire type for field")
                if `readTarget`.has(`oneofName`) and `readTarget`.`oneofName`.option == `optionVal`:
                  `stream`.readInto(`readTarget`.`oneofName`.`memberName`, `stream`.protoReadInt64())
                else:
                  `readTarget`.`oneofName` = `oneofType`(option: `optionVal`)
                  `readTarget`.`oneofName`.`memberName` = `stream`.read(`memberType`, `stream`.protoReadInt64())
              )
            ))
        var
          oneofWriteBlock = nnkCaseStmt.newTree(
              nnkDotExpr.newTree(nnkDotExpr.newTree(impls[2][3][2][0], oneofName), newIdentNode("option"))
            )
          oneofLenBlock = nnkCaseStmt.newTree(
              nnkDotExpr.newTree(nnkDotExpr.newTree(impls[3][3][1][0], oneofName), newIdentNode("option"))
            )

        let parent = impls[2][3][2][0]
        for i in 0..node.oneof.high:
          oneofWriteBlock.add(nnkOfBranch.newTree(
              names.optionValue(node.oneofName, node.oneof[i].name),
              generateFieldWrite(typeMapping, node.oneof[i], impls[2][3][1][0],
                nnkDotExpr.newTree(nnkDotExpr.newTree(parent, oneofName), newIdentNode(node.oneof[i].name))
              )
            )
          )
        impls[2][6].add(quote do:
          if `parent`.has(`oneofName`):
            `oneofWriteBlock`
        )
        let lenParent = impls[3][3][1][0]
        for i in 0..node.oneof.high:
          oneofLenBlock.add(nnkOfBranch.newTree(
              names.optionValue(node.oneofName, node.oneof[i].name),
              generateFieldLen(typeMapping, node.oneof[i],
                nnkDotExpr.newTree(nnkDotExpr.newTree(lenParent, oneofName), newIdentNode(node.oneof[i].name))
              )
            )
          )
        impls[3][6].add(quote do:
          if `lenParent`.has(`oneofName`):
            `oneofLenBlock`
        )
      of Field:
        impls[0][6][1][1][1].add(nnkOfBranch.newTree(newLit(node.number),
          generateFieldRead(typeMapping, node, impls[0][3][1][0], newIdentNode(node.name), newIdentNode("o"))
        ))
        let
          field = newIdentNode(node.name)
          parent = impls[2][3][2][0]
          lenParent = impls[3][3][1][0]
          fieldWrite = generateFieldWrite(typeMapping, node, impls[2][3][1][0], nnkDotExpr.newTree(parent, field))
          fieldLen = generateFieldLen(typeMapping, node, nnkDotExpr.newTree(lenParent, field))
        impls[2][6].add(quote do:
          if `parent`.has(`field`):
            `fieldWrite`
        )
        impls[3][6].add(quote do:
          if `lenParent`.has(`field`):
            `fieldLen`
        )
      of Enum:
        # Enum wire helpers are named from the hidden name and stay
        # unexported whether or not a line in the block names the enum
        let
          readName = newIdentNode(enumReadName(node.enumName))
          enumType = names.typeIdent(node.enumName)
          s = newIdentNode("s")
          o = newIdentNode("o")
          e = newIdentNode("e")
        decls.add quote do:
          proc `readName`(`s`: Stream): `enumType`
          proc write(`s`: Stream, `o`: `enumType`)
          proc getVarIntLen(`e`: `enumType`): int
        impls.add quote do:
          proc `readName`(`s`: Stream): `enumType` =
              `s`.protoReadInt64().`enumType`
          proc write(`s`: Stream, `o`: `enumType`) =
            `s`.protoWriteInt64(`o`.int64)
          proc getVarIntLen(`e`: `enumType`): int =
            getVarIntLen(`e`.int64)
      of ProtoDef:
        for node in node.packages:
          for message in node.messages:
            generateProcs(typeMapping, message, decls, impls)
          for packageEnum in node.packageEnums:
            generateProcs(typeMapping, packageEnum, decls, impls)
      else:
        echo "Unsupported kind: " & $node.kind
        discard

  var
    typeBlock = nnkTypeSection.newTree()
    forwardDeclarations = newStmtList()
    implementations = newStmtList()
  proto.generateTypes(typeBlock)
  generateProcs(typeMapping, proto, forwardDeclarations, implementations)
  result = quote do:
    `typeBlock`
    `typeHelpers`
    `forwardDeclarations`
    `implementations`

proc protoPath(node: NimNode): string {.compileTime.} =
  ## Flattens the right hand side of a line in a proto block. The path is
  ## data interpreted against the specification, not a Nim expression, so it
  ## is only ever a chain of identifiers.
  case node.kind:
  of nnkIdent, nnkSym, nnkAccQuoted:
    $node
  of nnkDotExpr:
    protoPath(node[0]) & "." & protoPath(node[1])
  else:
    error("Expected a proto path such as my.package.MyMessage, got " &
      node.repr, node)
    ""

proc parseProtoBlock(body: NimNode): seq[tuple[name: string, exported: bool, path: string, src: NimNode]] {.compileTime.} =
  ## Reads the ``type Name[*] = some.proto.Path`` lines of a proto block.
  ## Any number of one-line declarations and multi-definition type sections
  ## may be mixed.
  result = @[]
  for stmt in (if body.kind == nnkStmtList: body else: newStmtList(body)):
    case stmt.kind:
    of nnkCommentStmt: continue
    of nnkTypeSection:
      for def in stmt:
        if def.kind != nnkTypeDef:
          error("Only type declarations belong in a proto block", def)
        if def[1].kind != nnkEmpty:
          error("A proto block type can't take generic parameters", def)
        var
          nameNode = def[0]
          exported = false
        if nameNode.kind == nnkPragmaExpr:
          error("A proto block type can't take pragmas", nameNode)
        if nameNode.kind == nnkPostfix:
          exported = true
          nameNode = nameNode[1]
        result.add (name: $nameNode, exported: exported,
          path: protoPath(def[2]), src: def)
    else:
      error("Only type declarations belong in a proto block, got " &
        $stmt.kind, stmt)

proc suggestions(names: ProtoNames, path: string): string {.compileTime.} =
  ## Points at the closest known paths when a line names something the
  ## specification doesn't define.
  let leaf = path.rsplit({'.'}, 1)[^1]
  var exact: seq[string] = @[]
  for known in names.nim.keys:
    if known.rsplit({'.'}, 1)[^1] == leaf:
      exact.add known
  if exact.len == 0:
    var best = 0
    for known in names.nim.keys:
      let distance = editDistance(known, path)
      if exact.len == 0 or distance < best:
        exact = @[known]
        best = distance
      elif distance == best:
        exact.add known
  if exact.len == 0: "" else: ", did you mean " & exact.sorted.join(", ") & "?"

proc applyProtoBlock(names: var ProtoNames, body: NimNode) {.compileTime.} =
  ## Gives the types named by the block their Nim names, leaving everything
  ## else under its hidden name.
  var takenPaths = initTable[string, string]()
  var takenNames = initTable[string, string]()
  for line in parseProtoBlock(body):
    if not names.nim.hasKey(line.path):
      error("The specification has no type " & line.path &
        names.suggestions(line.path), line.src)
    if takenPaths.hasKey(line.path):
      error(line.path & " is already named " & takenPaths[line.path], line.src)
    if takenNames.hasKey(line.name):
      error("The name " & line.name & " is already used for " &
        takenNames[line.name], line.src)
    takenPaths[line.path] = line.name
    takenNames[line.name] = line.path
    names.nim[line.path] = line.name
    if line.exported:
      names.exported.incl line.path
      names.anyExported = true
  # The discriminator enum of a named oneof takes a derived name, which must not
  # land on a name the block already declared
  for oneof in names.oneofs:
    let derived = names.optionName(oneof)
    if takenNames.hasKey(derived):
      error("The discriminator enum of the oneof " & oneof & " is named " &
        derived & ", which this block already uses for " & takenNames[derived] &
        ". Rename one of them.", body)

proc parseImpl(protoParsed: ProtoNode, body: NimNode): NimNode {.compileTime.} =
  var validTypes = protoParsed.getTypes()
  protoParsed.verifyAndExpandTypes(validTypes)

  var names = initProtoNames(protoParsed)
  names.applyProtoBlock(body)

  var typeMapping = {
    "int32": (kind: newIdentNode("int32"), write: newIdentNode("protoWriteint32"), read: newIdentNode("protoReadint32"), wire: 0),
    "int64": (kind: newIdentNode("int64"), write: newIdentNode("protoWriteint64"), read: newIdentNode("protoReadint64"), wire: 0),
    "uint32": (kind: newIdentNode("uint32"), write: newIdentNode("protoWriteuint32"), read: newIdentNode("protoReaduint32"), wire: 0),
    "uint64": (kind: newIdentNode("uint64"), write: newIdentNode("protoWriteuint64"), read: newIdentNode("protoReaduint64"), wire: 0),
    "sint32": (kind: newIdentNode("int32"), write: newIdentNode("protoWritesint32"), read: newIdentNode("protoReadsint32"), wire: 0),
    "sint64": (kind: newIdentNode("int64"), write: newIdentNode("protoWritesint64"), read: newIdentNode("protoReadsint64"), wire: 0),
    "fixed32": (kind: newIdentNode("uint32"), write: newIdentNode("protoWritefixed32"), read: newIdentNode("protoReadfixed32"), wire: 5),
    "fixed64": (kind: newIdentNode("uint64"), write: newIdentNode("protoWritefixed64"), read: newIdentNode("protoReadfixed64"), wire: 1),
    "sfixed32": (kind: newIdentNode("int32"), write: newIdentNode("protoWritesfixed32"), read: newIdentNode("protoReadsfixed32"), wire: 5),
    "sfixed64": (kind: newIdentNode("int64"), write: newIdentNode("protoWritesfixed64"), read: newIdentNode("protoReadsfixed64"), wire: 1),
    "bool": (kind: newIdentNode("bool"), write: newIdentNode("protoWritebool"), read: newIdentNode("protoReadbool"), wire: 0),
    "float": (kind: newIdentNode("float32"), write: newIdentNode("protoWritefloat"), read: newIdentNode("protoReadfloat"), wire: 5),
    "double": (kind: newIdentNode("float64"), write: newIdentNode("protoWritedouble"), read: newIdentNode("protoReaddouble"), wire: 1),
    "string": (kind: newIdentNode("string"), write: newIdentNode("protoWritestring"), read: newIdentNode("protoReadstring"), wire: 2),
    "bytes": (kind: parseExpr("seq[uint8]"), write: newIdentNode("protoWritebytes"), read: newIdentNode("protoReadbytes"), wire: 2)
  }.toTable

  typeMapping.registerEnums(names, protoParsed)
  result = generateCode(typeMapping, names, protoParsed)
  when defined(echoProtobuf):
    echo result.toStrLit

macro protoSpec*(spec: static[string], body: untyped): untyped =
  ## Generates the code for the protobuf specification contained in the
  ## ``spec`` argument, which is the specification itself and not a path to
  ## it. Each ``type Name = some.proto.Path`` line of the body names one of
  ## the generated types; a starred line exports it. Types the body doesn't
  ## name are still generated, under a name that can't be reached, and stay
  ## usable through the fields of the types that are named.
  ##
  ## Use ``proto`` instead when the specification lives in a file.
  parseImpl(parseToDefinition(spec), body)

macro proto*(path: static[string], body: untyped): untyped =
  ## Generates the code for the protobuf specification found at ``path``,
  ## which is resolved relative to the file containing the block. Editing the
  ## specification recompiles the module. See ``protoSpec`` for what the body
  ## of the block means.
  ##
  ## .. code-block:: nim
  ##
  ##   proto "snapstats/v1.proto":
  ##     type Series* = smartrg.almanac.snapstats.v1.Series
  newCall(bindSym"protoSpec", newCall(bindSym"staticRead", newLit(path)), body)
