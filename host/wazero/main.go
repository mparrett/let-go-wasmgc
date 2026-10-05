// Linear target runner, added 2026-10-03.
package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
	"unsafe"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/experimental"
)

type host struct {
	fd      int32
	argv    []string
	input   []byte
	started time.Time
}

func stdinPending() bool {
	var n int32
	request := uintptr(0x4004667f)
	if runtime.GOOS == "linux" {
		request = 0x541b
	}
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, os.Stdin.Fd(), request, uintptr(unsafe.Pointer(&n)))
	return e == 0 && n > 0
}
func keySize(b []byte) (int, bool) {
	if len(b) == 0 {
		return 0, false
	}
	if b[0] == 27 {
		if len(b) == 1 {
			return 1, true
		}
		if b[1] == '[' {
			for i := 2; i < len(b); i++ {
				if b[i] >= 0x40 && b[i] <= 0x7e {
					return i + 1, false
				}
			}
			return len(b), true
		}
		if b[1] == 'O' {
			if len(b) < 3 {
				return len(b), true
			}
			return 3, false
		}
		return 1, false
	}
	if !utf8.FullRune(b) {
		return len(b), true
	}
	_, n := utf8.DecodeRune(b)
	return n, false
}
func (h *host) refill() bool {
	b := make([]byte, 256)
	n, e := os.Stdin.Read(b)
	if n > 0 {
		h.input = append(h.input, b[:n]...)
		return true
	}
	if e != nil && e != io.EOF {
		panic(e)
	}
	return false
}
func (h *host) readKey() []byte {
	if len(h.input) == 0 && !h.refill() {
		return nil
	}
	for {
		n, partial := keySize(h.input)
		if partial && stdinPending() && h.refill() {
			continue
		}
		b := append([]byte(nil), h.input[:n]...)
		h.input = h.input[n:]
		return b
	}
}

func bytesAt(m api.Module, ptr, n uint32) []byte {
	b, ok := m.Memory().Read(ptr, n)
	if !ok {
		panic("host memory access out of bounds")
	}
	return b
}
func (h *host) output(fd int32, b []byte) {
	var w io.Writer = os.Stdout
	if fd == 2 {
		w = os.Stderr
	}
	if fd != 1 && fd != 2 {
		return
	}
	if _, e := w.Write(b); e != nil {
		panic(e)
	}
}
func copyResult(m api.Module, value string, present bool, ptr, cap uint32) uint32 {
	if !present {
		return ^uint32(0)
	}
	b := []byte(value)
	if uint32(len(b)) <= cap && !m.Memory().Write(ptr, b) {
		panic("host memory access out of bounds")
	}
	return uint32(len(b))
}
func (h *host) instantiate(ctx context.Context, r wazero.Runtime) error {
	env := r.NewHostModuleBuilder("env")
	env.NewFunctionBuilder().WithFunc(func(v int64) { h.output(h.fd, []byte(strconv.FormatInt(v, 10))) }).Export("print_i64")
	env.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, p, n uint32) { h.output(h.fd, bytesAt(m, p, n)) }).Export("print_str")
	env.NewFunctionBuilder().WithFunc(func() { h.output(h.fd, []byte("\n")) }).Export("print_nl")
	env.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, fd int32, p, n uint32) uint32 {
		if fd != 2 {
			fd = h.fd
		}
		h.output(fd, bytesAt(m, p, n))
		return n
	}).Export("write")
	env.NewFunctionBuilder().WithFunc(func(ms int64) {
		if ms > 0 {
			time.Sleep(time.Duration(ms) * time.Millisecond)
		}
	}).Export("sleep")
	env.NewFunctionBuilder().WithFunc(func() int64 { return time.Since(h.started).Nanoseconds() }).Export("nanotime")
	env.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, p, n, b, c uint32) uint32 {
		v, ok := os.LookupEnv(string(bytesAt(m, p, n)))
		return copyResult(m, v, ok, b, c)
	}).Export("getenv")
	env.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, p, n, j, l uint32) { _ = bytesAt(m, p, n); _ = bytesAt(m, j, l) }).Export("emit")
	env.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, p, n, b, c uint32) uint32 {
		_ = bytesAt(m, p, n)
		return ^uint32(0)
	}).Export("url_param")
	env.NewFunctionBuilder().WithFunc(func() uint32 { return uint32(len(h.argv)) }).Export("argc")
	env.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, i, b, c uint32) uint32 {
		if i >= uint32(len(h.argv)) {
			return ^uint32(0)
		}
		return copyResult(m, h.argv[i], true, b, c)
	}).Export("arg")
	if _, e := env.Instantiate(ctx); e != nil {
		return e
	}
	term := r.NewHostModuleBuilder("term")
	term.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, p, c uint32) uint32 {
		b := h.readKey()
		if uint32(len(b)) > c {
			b = b[:c]
		}
		if !m.Memory().Write(p, b) {
			panic("host memory access out of bounds")
		}
		return uint32(len(b))
	}).Export("read_key")
	term.NewFunctionBuilder().WithFunc(func() uint32 {
		if len(h.input) > 0 || stdinPending() {
			return 1
		}
		return 0
	}).Export("key_pending")
	term.NewFunctionBuilder().WithGoModuleFunction(api.GoModuleFunc(func(_ context.Context, _ api.Module, stack []uint64) {
		size := struct{ Rows, Cols, X, Y uint16 }{}
		_, _, e := syscall.Syscall(syscall.SYS_IOCTL, os.Stdout.Fd(), syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&size)))
		stack[0], stack[1] = 80, 24
		if e == 0 && size.Cols > 0 && size.Rows > 0 {
			stack[0], stack[1] = uint64(size.Cols), uint64(size.Rows)
		}
	}), nil, []api.ValueType{api.ValueTypeI32, api.ValueTypeI32}).Export("size")
	term.NewFunctionBuilder().WithFunc(func(_ context.Context, m api.Module, p, n uint32) uint32 { h.output(h.fd, bytesAt(m, p, n)); return n }).Export("write")
	_, e := term.Instantiate(ctx)
	return e
}
func run() int {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: wazero-runner module.wasm program.lg [args...]")
		return 2
	}
	ctx := context.Background()
	r := wazero.NewRuntimeWithConfig(ctx, wazero.NewRuntimeConfigCompiler().WithCoreFeatures(api.CoreFeaturesV2|experimental.CoreFeaturesTailCall|experimental.CoreFeaturesExceptionHandling))
	defer r.Close(ctx)
	argv := append([]string{os.Getenv("LG")}, strings.Fields(os.Getenv("LG_ARGS"))...)
	argv = append(argv, os.Args[2:]...)
	h := &host{fd: 1, argv: argv, started: time.Now()}
	if e := h.instantiate(ctx, r); e != nil {
		fmt.Fprintln(os.Stderr, "error:", e)
		return 1
	}
	b, e := os.ReadFile(os.Args[1])
	if e != nil {
		fmt.Fprintln(os.Stderr, "error:", e)
		return 1
	}
	m, e := r.InstantiateWithConfig(ctx, b, wazero.NewModuleConfig().WithStartFunctions())
	if e != nil {
		fmt.Fprintln(os.Stderr, "error:", e)
		return 1
	}
	f := m.ExportedFunction("lw run")
	if f == nil {
		fmt.Fprintln(os.Stderr, "error: missing linear entry wrapper")
		return 1
	}
	result, e := f.Call(ctx)
	if e == nil && len(result) == 2 && result[0] == 0 {
		return 0
	}
	h.fd = 2
	fmt.Fprint(os.Stderr, "error: ")
	if e == nil && len(result) == 2 && result[0] == 1 {
		_, e = m.ExportedFunction("lw report").Call(ctx, result[1])
		if e != nil {
			fmt.Fprint(os.Stderr, e)
		}
	} else {
		reported := false
		if f := m.ExportedFunction("lw trap"); f != nil {
			v, te := f.Call(ctx)
			reported = te == nil && len(v) == 1 && v[0] != 0
		}
		if !reported {
			fmt.Fprint(os.Stderr, e)
		}
	}
	fmt.Fprintln(os.Stderr)
	return 1
}
func main() { os.Exit(run()) }
