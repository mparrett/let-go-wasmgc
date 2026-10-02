#!/usr/bin/env bash
# P2.7: the lgb-roundtrip relation (run(P) == run(artifact(P))) with the emitted module as the artifact, over let-go/examples at 4e769212.
exec "$(dirname "$0")/run-corpus.sh" "$(dirname "$0")/../corpus/examples" "$@"
