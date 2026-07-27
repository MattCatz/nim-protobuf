# Builds the official protobuf conformance_test_runner, which nixpkgs doesn't
# ship. Usage: nix-build runner.nix -o runner
{ pkgs ? import <nixpkgs> {} }:

pkgs.protobuf.overrideAttrs (old: {
  pname = "conformance-test-runner";
  cmakeFlags = (old.cmakeFlags or []) ++ [ "-Dprotobuf_BUILD_CONFORMANCE=ON" ];
  buildInputs = (old.buildInputs or []) ++ [ pkgs.jsoncpp ];
  doCheck = false;
  postInstall = (old.postInstall or "") + ''
    find . -maxdepth 3 -name conformance_test_runner -type f -exec install -m755 {} $out/bin/ \;
  '' + pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
    install_name_tool -add_rpath $out/lib $out/bin/conformance_test_runner
  '';
})
