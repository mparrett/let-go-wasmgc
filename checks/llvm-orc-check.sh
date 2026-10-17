#!/usr/bin/env bash
# ORC object reuse must preserve process semantics and reject incompatible IR.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
runner=$(bash checks/build-orc-runner.sh)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 - "$PWD" "$llvm" "$runner" "$t" "$LG" <<'PY'
import os, re, shutil, subprocess, sys
from pathlib import Path

root, llvm, runner, tmp, lg = sys.argv[1:]
t = Path(tmp)
cache = t / 'cache'
base = dict(os.environ, LW_ORC_CACHE_DIR=str(cache), LW_ORC_STATS='1',
            LW_ORC_OPT_LEVEL='2', LW_ORC_CACHE='1', ORC_CHECK_VALUE='first',
            ORC_CHECK_FILE=str(t / 'data'), ORC_CHECK_EXIT='0')
(t / 'data').write_text('A')
def run(args, env=None, status=0):
    p = subprocess.run(list(map(str, args)), env=env or base, capture_output=True)
    assert p.returncode == status, (args, p.returncode, p.stdout.decode(errors='replace'), p.stderr.decode(errors='replace'))
    return p
def stats(p):
    rows = re.findall(rb'orc-cache hits=(\d+) misses=(\d+) writes=(\d+) invalid=(\d+)', p.stderr)
    assert len(rows) == 1, p.stderr.decode(errors='replace')
    return tuple(map(int, rows[0]))
def miss(p):
    h, m, w, i = stats(p)
    assert h == 0 and m > 0 and w > 0, (h, m, w, i)
def hit(p):
    h, m, w, i = stats(p)
    assert h > 0 and m == 0 and w == 0 and i == 0, (h, m, w, i)
def orc(path, env=None, status=0, arg='argument'):
    return run([runner, path, 'program', arg], env, status)
source = Path(root) / 'checks/fixtures/orc/process.c'
bc, ll, exe = t/'process.bc', t/'process.ll', t/'process'
run([llvm+'/clang', '-O2', '-emit-llvm', '-c', source, '-o', bc])
run([llvm+'/llvm-dis', bc, '-o', ll])
run([llvm+'/clang', '-O2', source, '-o', exe])
native = run([exe, 'program', 'argument'])
interpreted = run([llvm+'/lli', '-O2', bc, 'program', 'argument'])
cold = orc(bc)
assert native.stdout == interpreted.stdout == cold.stdout, (native.stdout, interpreted.stdout, cold.stdout)
assert b'initialized=37' in cold.stdout and cold.stdout.endswith(b'destructor\n'), cold.stdout
miss(cold)
relocated = t/'relocated.bc'
shutil.copyfile(bc, relocated)
warm = orc(relocated)
hit(warm)
assert warm.stdout == native.stdout

# Cache entries contain code, never results, arguments, environment or files.
(t/'data').write_text('B')
changed_env = dict(base, ORC_CHECK_VALUE='second', ORC_CHECK_EXIT='7')
fresh = orc(bc, changed_env, status=7, arg='different')
hit(fresh)
expected = run([exe, 'program', 'different'], changed_env, status=7)
assert fresh.stdout == expected.stdout, (fresh.stdout, expected.stdout)
assert b'env=second file=66' in fresh.stdout and b'argv2=different' in fresh.stdout
print('ORC: AOT/lli parity, constructors/destructors, relocated warm hit, fresh process inputs and exit status')

text = orc(ll)
miss(text)
assert text.stdout == orc(bc).stdout
hit(orc(ll))
changed_bc = t/'changed.bc'
run([llvm+'/clang', '-O2', '-DVALUE=2', '-emit-llvm', '-c', source, '-o', changed_bc])
changed = orc(changed_bc)
miss(changed)
assert b'value=2 ' in changed.stdout
miss(orc(bc, dict(base, LW_ORC_OPT_LEVEL='1')))
hit(orc(bc))
disabled_cache = t/'disabled-cache'
disabled = orc(bc, dict(base, LW_ORC_CACHE='0', LW_ORC_CACHE_DIR=str(disabled_cache)))
ds = stats(disabled)
assert ds[0] == ds[2] == 0 and not list(disabled_cache.glob('*.objcache')), ds
print('ORC: text IR, source/config invalidation, prior configuration reuse, disabled cache')

# Isolate corruption tests so each one has a single unambiguous cache entry.
repair_cache = t/'repair-cache'
repair_env = dict(base, LW_ORC_CACHE_DIR=str(repair_cache))
miss(orc(bc, repair_env))
entries = list(repair_cache.glob('*.objcache'))
assert len(entries) == 1, entries
entry = entries[0]
payload = bytearray(entry.read_bytes())
assert payload
payload[-1] ^= 0x55
entry.write_bytes(payload)
repaired = orc(bc, repair_env)
miss(repaired)
assert stats(repaired)[3] > 0
hit(orc(bc, repair_env))
entry.write_bytes(entry.read_bytes()[:7])
truncated = orc(bc, repair_env)
miss(truncated)
assert stats(truncated)[3] > 0
hit(orc(bc, repair_env))
concurrent_env = dict(base, LW_ORC_CACHE_DIR=str(t/'concurrent-cache'))
children = [subprocess.Popen([runner, str(bc), 'program', 'argument'], env=concurrent_env,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
for child in children:
    out, err = child.communicate()
    assert child.returncode == 0, (child.returncode, err)
    assert out == repaired.stdout, (out, repaired.stdout)
hit(orc(bc, concurrent_env))
print('ORC: corrupt/truncated object recovery and concurrent writers')

# Optimization can remove symbols advertised by the parsed module. The warm
# materialization interface must match the optimized object, just as on cold.
discarded = t/'discarded.ll'
discarded.write_text('define linkonce_odr i32 @unused() { ret i32 9 }\n'
                     'define i32 @main(i32 %argc, ptr %argv) { ret i32 0 }\n')
miss(orc(discarded))
hit(orc(discarded))
print('ORC: warm object handles definitions discarded by optimization')

for name, text in [('malformed', 'define i32 @main( {'),
                   ('main-global', '@main = global i32 0\n'),
                   ('main-void', 'define void @main(i32 %argc, ptr %argv) { ret void }\n'),
                   ('main-fastcc', 'define fastcc i32 @main(i32 %argc, ptr %argv) { ret i32 0 }\n'),
                   ('foreign-triple', re.sub(r'target triple = "[^"]+"', 'target triple = "wasm32-unknown-unknown"', ll.read_text())),
                   ('foreign-layout', re.sub(r'target datalayout = "[^"]+"', 'target datalayout = "e-p:32:32"', ll.read_text()))]:
    path = t/(name+'.ll')
    path.write_text(text)
    bad = subprocess.run([runner, str(path)], env=base, capture_output=True)
    assert bad.returncode != 0 and bad.stderr, (name, bad.returncode, bad.stderr)
    if name.startswith('main-'):
        assert bad.returncode > 0 and b'main' in bad.stderr.lower(), (name, bad.returncode, bad.stderr)
print('ORC: malformed IR, incompatible main ABI and foreign target/layout rejected')

# Exercise the actual frontend/host-bitcode runner in separate temporary dirs.
program = Path(root)/'checks/fixtures/analysis-reuse/boxing.lg'
env = dict(base, LW_DRIVER_ARGS='--no-rt', LW_ORC_CACHE_DIR=str(t/'program-cache'))
env.pop('LW_NATIVE_JIT', None)
native_lg = run([lg, program], env)
aot = run(['bash', 'checks/native-run.sh', program], env)
jit_env = dict(env, LW_NATIVE_JIT='orc')
first = run(['bash', 'checks/native-run.sh', program], jit_env)
second = run(['bash', 'checks/native-run.sh', program], jit_env)
miss(first)
hit(second)
lli = run(['bash', 'checks/native-run.sh', program], dict(env, LW_NATIVE_JIT='lli'))
assert native_lg.stdout == aot.stdout == first.stdout == second.stdout == lli.stdout
print('ORC: real compiler program matches native/AOT/lli and hits across fresh temporary directories')
if os.environ.get('LLVM_ORC_EXTENDED') == '1':
    for name in ['closures', 'unbox-catch', 'fixnum-edges', 'gc-churn']:
        program = Path(root)/'corpus/llvm'/f'{name}.lg'
        if name == 'gc-churn':
            scaled = t/'gc-churn.lg'
            content = program.read_text()
            assert '(churn 400000)' in content
            scaled.write_text(content.replace('(churn 400000)', '(churn 20000)'))
            program = scaled
        ext = dict(base, LW_DRIVER_ARGS='--no-rtlib',
                   LW_ORC_CACHE_DIR=str(t/f'extended-{name}'), LG_HEAP_BYTES='1048576')
        ext.pop('LW_NATIVE_JIT', None)
        oracle = run([lg, program], ext)
        aot = run(['bash', 'checks/native-run.sh', program], ext)
        jit = dict(ext, LW_NATIVE_JIT='orc')
        cold = run(['bash', 'checks/native-run.sh', program], jit)
        warm = run(['bash', 'checks/native-run.sh', program], jit)
        miss(cold)
        hit(warm)
        assert oracle.stdout == aot.stdout == cold.stdout == warm.stdout, name
        print(f'ORC extended: {name} native/AOT/cold/warm parity')
print('llvm-orc: OK')
PY
