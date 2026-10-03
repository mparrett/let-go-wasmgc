// gen prints hash parity vectors: one TSV row per value,
//
//	kind <TAB> value-as-edn <TAB> vm.HashValue(value) as decimal uint32
//
// built from let-go's real pkg/vm, so a wasm port of the hash functions can
// be checked row by row. Run: go run . > vectors.tsv
//
// Every row is also checked against the type's own Hash() (when it has one);
// a disagreement aborts the run rather than writing a table that hides it.
package main

import (
	"fmt"
	"math"
	"math/rand/v2"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/nooga/let-go/pkg/vm"
)

// letgoDir must match the replace directive in go.mod; the header records
// its HEAD so the table names the code that produced it.
const letgoDir = "~/let-go"

type row struct {
	kind string
	v    vm.Value
	edn  string // override when String() is not readable back (NaN, Inf)
}

var rows []row

func add(kind string, v vm.Value) { rows = append(rows, row{kind: kind, v: v}) }

func vec(vs ...vm.Value) vm.Value  { return vm.NewArrayVector(vs) }
func list(vs ...vm.Value) vm.Value { return vm.NewList(vs) }
func kw(s string) vm.Value         { return vm.Keyword(s) }
func i(n int64) vm.Value           { return vm.Int(n) }

func pmap(kvs ...vm.Value) *vm.PersistentMap { return vm.NewPersistentMap(kvs) }

func bigint(s string) vm.Value {
	b, ok := vm.NewBigIntFromString(s)
	if !ok {
		panic("bad bigint " + s)
	}
	return b
}

func bigdec(s string) vm.Value {
	b, ok := vm.NewBigDecimalFromString(s)
	if !ok {
		panic("bad bigdec " + s)
	}
	return b
}

// ident draws a lowercase identifier of 1..12 chars, with '-' and '.' inside,
// so generated keywords/symbols cover odd and even byte lengths.
func ident(r *rand.Rand) string {
	const alpha = "abcdefghijklmnopqrstuvwxyz0123456789-."
	n := 1 + r.IntN(12)
	b := make([]byte, n)
	b[0] = byte('a' + r.IntN(26))
	for j := 1; j < n; j++ {
		b[j] = alpha[r.IntN(len(alpha))]
	}
	if b[n-1] == '.' || b[n-1] == '-' {
		b[n-1] = 'z'
	}
	return string(b)
}

func corpus() {
	r := rand.New(rand.NewPCG(0x1e7, 0x60))

	add("nil", vm.NIL)
	add("bool", vm.TRUE)
	add("bool", vm.FALSE)

	for _, n := range []int64{0, 1, -1, 2, 97, 1<<31 - 1, 1 << 31, 1<<31 + 1,
		1 << 32, 1 << 62, math.MaxInt64, math.MinInt64} {
		add("int", i(n))
	}
	for range 50 {
		add("int", i(int64(r.Uint64())))
	}

	for _, f := range []float64{0.0, math.Copysign(0, -1), 1.0, -1.0, 0.1, 1.5,
		-2.5, 97.0, 1e300, 1e-300} {
		add("float", vm.Float(f))
	}
	rows = append(rows,
		row{kind: "float", v: vm.Float(math.NaN()), edn: "##NaN"},
		row{kind: "float", v: vm.Float(math.Inf(1)), edn: "##Inf"},
		row{kind: "float", v: vm.Float(math.Inf(-1)), edn: "##-Inf"})

	for _, s := range []string{"", "a", "ab", "abc", "abcd",
		strings.Repeat("0123456789", 10), "héllo", "日本語", "emoji 😀!",
		"tab\there", "quote\"back\\slash", "line\nbreak", "foo/bar", ":a"} {
		add("string", vm.String(s))
	}

	// Keywords and symbols are stored without the colon; the namespace is
	// part of the same string ("foo/bar").
	fixed := []string{"a", "ab", "abc", "foo", "foo/bar", "xsofy.world/player",
		"x", "héllo", "日本"}
	for _, s := range fixed {
		add("keyword", kw(s))
	}
	for j := range 20 {
		s := ident(r)
		if j%3 == 0 {
			s = ident(r) + "/" + s
		}
		add("keyword", kw(s))
	}
	for _, s := range fixed {
		add("symbol", vm.Symbol(s))
	}
	for j := range 20 {
		s := ident(r)
		if j%3 == 0 {
			s = ident(r) + "/" + s
		}
		add("symbol", vm.Symbol(s))
	}

	for _, c := range []rune{'a', 'A', 'z', '0', ' ', '\n', '\t', 'é', '日', '😀'} {
		add("char", vm.Char(c))
	}

	add("ratio", vm.NewRatioFromInts(1, 2))
	add("ratio", vm.NewRatioFromInts(-3, 4))
	add("ratio", vm.NewRatioFromInts(22, 7))
	add("bigint", bigint("1"))
	add("bigint", bigint("-5"))
	add("bigint", bigint("9223372036854775807"))
	add("bigint", bigint("123456789012345678901234567890"))
	add("bigint", bigint("-123456789012345678901234567890"))
	add("bigdec", bigdec("1.5"))
	add("bigdec", bigdec("0.1"))
	add("bigdec", bigdec("100"))

	add("vector", vec())
	add("vector", vec(i(1)))
	add("vector", vec(i(1), i(2), i(3)))
	add("vector", vec(kw("a"), vm.String("b"), i(3)))
	add("vector", vec(vm.NIL))
	add("vector", vec(i(1), vec(i(2), vec(i(3), vm.NewPersistentSet([]vm.Value{kw("a")}))),
		pmap(kw("k"), list(i(1), i(2)))))
	big := make([]vm.Value, 40)
	for j := range big {
		big[j] = i(int64(j))
	}
	add("vector", vm.NewArrayVector(big))
	// PersistentVector is what a vector with metadata becomes; same EDN.
	add("pvector", vm.NewPersistentVector(nil))
	add("pvector", vm.NewPersistentVector([]vm.Value{i(1), i(2), i(3)}))
	add("pvector", vm.NewPersistentVector(big))

	add("list", list())
	add("list", list(vm.NIL))
	add("list", list(i(1)))
	add("list", list(i(1), i(2), i(3)))
	add("list", list(vm.Symbol("+"), i(1), list(kw("a"), vm.String("b"))))

	add("map", pmap())
	add("map", pmap(kw("a"), i(1)))
	ab := pmap(kw("a"), i(1), kw("b"), i(2))
	ba := pmap(kw("b"), i(2), kw("a"), i(1))
	if ab.Hash() != ba.Hash() {
		fail("map hash depends on insertion order: %d vs %d", ab.Hash(), ba.Hash())
	}
	add("map", ab)
	add("map/rev", ba) // same map, reverse insertion order; same hash asserted above
	add("map", pmap(i(1), i(1), i(2), i(2))) // every k == v: XOR cancels
	nine := make([]vm.Value, 0, 18)
	for j := range 9 {
		nine = append(nine, kw(fmt.Sprintf("k%d", j)), i(int64(j)))
	}
	add("map", pmap(nine...))
	thousand := make([]vm.Value, 0, 2000)
	for j := range 1000 {
		thousand = append(thousand, i(int64(j)), kw(fmt.Sprintf("v%d", j)))
	}
	add("map", pmap(thousand...))
	thousandRev := make([]vm.Value, 0, 2000)
	for j := 999; j >= 0; j-- {
		thousandRev = append(thousandRev, i(int64(j)), kw(fmt.Sprintf("v%d", j)))
	}
	if pmap(thousand...).Hash() != pmap(thousandRev...).Hash() {
		fail("1000-key map hash depends on insertion order")
	}
	add("map", pmap(vec(i(1), i(2)), vm.String("vec-key"), vm.NIL, vm.TRUE))

	add("set", vm.NewPersistentSet(nil))
	add("set", vm.NewPersistentSet([]vm.Value{i(1)}))
	add("set", vm.NewPersistentSet([]vm.Value{i(1), i(2), i(3)}))
	add("set", vm.NewPersistentSet([]vm.Value{kw("a"), vm.String("a"), vm.Symbol("a"), vm.Char('a')}))
	add("set", vm.NewPersistentSet(big))

	add("mapentry", vm.MapEntry{Key: kw("a"), Value: i(1)})
	add("mapentry", vm.MapEntry{Key: vm.String("k"), Value: vec(i(1))})
}

func fail(f string, a ...any) {
	fmt.Fprintf(os.Stderr, "gen: "+f+"\n", a...)
	os.Exit(1)
}

func main() {
	corpus()
	sha, err := exec.Command("git", "-C", letgoDir, "rev-parse", "--short", "HEAD").Output()
	if err != nil {
		fail("git rev-parse: %v", err)
	}
	dirty := ""
	if st, _ := exec.Command("git", "-C", letgoDir, "status", "--porcelain", "--untracked-files=no").Output(); len(st) > 0 {
		dirty = "-dirty"
	}
	fmt.Printf("# let-go %s%s, generated %s by corpus/hash/gen.go (go run . > vectors.tsv)\n",
		strings.TrimSpace(string(sha)), dirty, time.Now().Format("2006-01-02"))
	fmt.Println("# kind\tedn\thash  (hash = vm.HashValue, decimal uint32)")
	for _, rw := range rows {
		h := vm.HashValue(rw.v)
		if hv, ok := rw.v.(vm.Hashable); ok && hv.Hash() != h {
			fail("%s %s: Hash()=%d but HashValue=%d", rw.kind, rw.v, hv.Hash(), h)
		}
		edn := rw.edn
		if edn == "" {
			edn = rw.v.String()
		}
		if strings.ContainsAny(edn, "\t\n") {
			fail("%s: EDN contains tab/newline: %q", rw.kind, edn)
		}
		fmt.Printf("%s\t%s\t%d\n", rw.kind, edn, h)
	}
}
