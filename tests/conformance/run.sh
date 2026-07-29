#!/usr/bin/env bash
# Runs the official protobuf conformance suite against protobuf-nim.
#
# The conformance_test_runner is built from the protobuf source via nix
# (runner.nix) since nixpkgs doesn't ship it. The testee is compiled with the
# nixpkgs nim. Pass extra nim flags (e.g. --path to combparser) in NIMFLAGS.
set -euo pipefail
cd "$(dirname "$0")"

nix-build runner.nix -o runner

nix-shell -p nim --run "nim c -d:release --hints:off --warnings:off \
  --maxLoopIterationsVM:1000000000 ${NIMFLAGS:-} -o:testee testee.nim"

# --enforce_recommended counts the recommended tests too. Without it the runner
# reports them as warnings that land in none of its totals, so a run could say
# "0 unexpected failures" while dozens of tests were failing unseen.
exec ./runner/bin/conformance_test_runner \
  --maximum_edition PROTO3 \
  --enforce_recommended \
  --failure_list failure_list.txt \
  ./testee "$@"
