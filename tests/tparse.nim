import "../src/protobuf"

# Check to see that everything parses. Should add some more testing to verify
# that it actually creates the correct result.
# The path of the block is relative to this file, but the `import` inside the
# specification is resolved against the working directory, so this test has to
# be compiled from the root of the repository.
proto "parse.prot":
  type
    SearchRequest* = test.package.SearchRequest
    Corpus* = test.package.Corpus
    # types from the imported file, which has no package of its own, so their
    # paths are bare. The nested one shares its leaf name with the top-level
    # one, which is exactly what full paths are for.
    NatLangs* = NatLangs
    ThirdNatLangs* = Third.NatLangs

echo "All good!"
