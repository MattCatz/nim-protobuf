# Protobuf conformance suite

Runs the official protobuf conformance suite against this library:

    ./run.sh

`run.sh` builds `conformance_test_runner` from the protobuf source via nix
(`runner.nix` — nixpkgs only ships protoc), compiles the testee with the
nixpkgs nim, and runs the binary wire-format tests. Extra nim flags (like
`--path` to combparser) can be passed through the `NIMFLAGS` environment
variable.

The testee (`testee.nim`) speaks the runner's length-prefixed stdio protocol
using message definitions this library generated from `conformance.proto` —
so the conformance plumbing itself round-trips through the code under test.

`conformance.proto` is a verbatim copy of the upstream file (protobuf
v31.1). `test_messages_proto3.proto` is a trimmed copy with identical field
numbers and types; its header comment lists exactly what was removed and
why. JSON, text-format, proto2, and editions tests are skipped: the library
only supports the proto3 binary format.

Known failures are tracked in `failure_list.txt` with an explanation. The
suite fails if a test outside that list fails, or if a listed test starts
passing, so it can be used as a regression gate.
