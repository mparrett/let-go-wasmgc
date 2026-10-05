// Semantic probes for numeric representations and managed failures (2026-10-03).
package main

import (
	"context"
	"os"
	"testing"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/experimental"
)

func TestRepresentationProbes(t *testing.T) {
	path := os.Getenv("LW_LINEAR_REPRESENTATION_FIXTURE")
	if path == "" {
		t.Skip("run checks/linear-representation-check.sh to compile the fixture")
	}
	ctx := context.Background()
	r := wazero.NewRuntimeWithConfig(ctx, wazero.NewRuntimeConfigCompiler().WithCoreFeatures(api.CoreFeaturesV2|experimental.CoreFeaturesTailCall|experimental.CoreFeaturesExceptionHandling))
	defer r.Close(ctx)
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	m, err := r.Instantiate(ctx, b)
	if err != nil {
		t.Fatal(err)
	}
	expected := map[string]uint64{
		"fixnum": 3, "nullable": 0, "field": 1, "nil": 0,
		"test-fixnum": 1, "test-nil": 1, "test-bool": 1, "test-wrong": 0, "test-invalid": 0,
		"new-int": ^uint64(6), "new-list-kind": 2, "new-list-count": 42, "new-subtype": 1,
		"null-yes": 1, "null-zero": 0, "null-bool": 0, "nonnull-zero": 1, "nonnull-error-kind": 26,
		"new-arr-len": 7, "new-arr-zero": 0, "new-arr-type": 1, "new-arr-grow": 65536,
		"copy-overlap": 42, "copy-ref": 35, "copy-bounds": 26, "copy-empty-end": 1,
		"signed-max": 1073741823, "signed-min": 3221225472, "signed-minus-one": 4294967295,
		"get-byte": 253, "get-bounds": 26, "func-index": 1, "tail-code": 19,
		"same-nil": 1, "same-fixnum": 1, "different-box": 0, "set-field": 42, "call-code": 23, "call-nil-error": 26,
		"data-byte": 66, "data-len": 0, "data-bounds": 26, "filled-byte": 251, "filled-ref": 35, "get-ref": 35, "fixed-byte": 253, "fixed-ref": 43,
		"test-abstract-array": 1, "test-abstract-struct": 1, "test-array-reject-struct": 0, "test-struct-reject-array": 0, "test-array-nullable": 1, "cast-array-length": 3, "test-function-value-domain": 0,
		"stack-bool": 1, "stack-test": 1, "stack-fixnum": 4294967289, "stack-field-set": 42, "stack-byte": 253, "mixed-stack-byte": 252, "stack-ref": 35,
		"cast-branch-hit": 1, "cast-branch-miss": 1, "cast-branch-index": 1, "cast-fail-branch": 1, "cast-evaluate-once": 1, "cast-stack-branch": 1,
	}
	for name, want := range expected {
		t.Run(name, func(t *testing.T) {
			f := m.ExportedFunction(name)
			if f == nil {
				t.Fatalf("missing probe %s", name)
			}
			result, err := f.Call(ctx)
			if err != nil || len(result) != 1 || result[0] != want {
				t.Fatalf("got %v (%v), want %d", result, err, want)
			}
		})
	}
}
