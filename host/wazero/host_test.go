// Host buffer growth, shrinking results and retained name pointers (2026-10-03).
package main

import (
	"context"
	"fmt"
	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/experimental"
	"os"
	"testing"
)

func TestGrowingHostBuffer(t *testing.T) {
	fixture := os.Getenv("LW_LINEAR_HOST_FIXTURE")
	if fixture == "" {
		t.Skip("run checks/linear-host-check.sh to compile the fixture")
	}
	ctx := context.Background()
	r := wazero.NewRuntimeWithConfig(ctx, wazero.NewRuntimeConfigCompiler().WithCoreFeatures(api.CoreFeaturesV2|experimental.CoreFeaturesTailCall|experimental.CoreFeaturesExceptionHandling))
	defer r.Close(ctx)
	calls := 0
	_, e := r.NewHostModuleBuilder("env").NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, p, n, b, c uint32) uint32 {
		name, ok := m.Memory().Read(p, n)
		if !ok || string(name) != "X" {
			panic("name payload pointer corrupted")
		}
		calls++
		if calls == 1 {
			if c != 0 {
				panic("initial probe was not zero capacity")
			}
			return 65537
		}
		if calls == 2 {
			if c != 65537 {
				panic("first allocated capacity incorrect")
			}
			return 131073
		}
		if calls == 3 {
			if c != 131073 {
				panic("retry capacity incorrect")
			}
			if !m.Memory().Write(b, []byte("ABC")) {
				panic("write failed")
			}
			return 3
		}
		panic("extra host call")
	}).Export("getenv").Instantiate(ctx)
	if e != nil {
		panic(e)
	}
	b, e := os.ReadFile(fixture)
	if e != nil {
		panic(e)
	}
	m, e := r.Instantiate(ctx, b)
	if e != nil {
		panic(e)
	}
	result, e := m.ExportedFunction("probe").Call(ctx)
	if e != nil || len(result) != 1 || result[0] != 3 || calls != 3 {
		panic(fmt.Sprintf("result %v %v calls %d", result, e, calls))
	}
	ptr, e := m.ExportedFunction("object").Call(ctx)
	if e != nil {
		panic(e)
	}
	value, ok := m.Memory().Read(uint32(ptr[0])+16, 3)
	if !ok || string(value) != "ABC" {
		panic("returned bytes corrupted")
	}
	t.Log("PASS host-buffer prototype retries growth and shrinks logical length; GC disabled")
}
