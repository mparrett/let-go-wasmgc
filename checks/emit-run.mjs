// checks/emit-run.mjs — run a module rt/wasm/emit.lg produced (stage 3a, row
// P10.1) and print what native lg would print.
//
//   node checks/emit-run.mjs <module.wasm | --hex HEX> <plan.json | --plan JSON>
//
// THE ABI (rt/wasm/emit.lg's header is the other half). The module has no
// imports. Every compiled fn takes and returns (ref null eq) values of the
// module's private rec group ($Int i64, $Float f64, $Bool i32), which JS
// cannot build or read, so boxing goes through the module's own exports:
//   "lw box_i" (i64 as a BigInt) / "lw box_f" (f64) / "lw box_b" (i32) -> a
//   boxed value; JS null is nil;
//   "lw kind" v -> 0 nil, 1 Int, 2 Float, 3 false, 4 true;
//   "lw unbox_i" v -> BigInt, "lw unbox_f" v -> Number.
// A fn with one arity is exported under its name, one with several as
// name/N; this runner tries name/N first, then name.
// Errors: a helper that raises sets the mutable global "lw err" to
// code + 256*ka + 4096*kb and traps; the runner resets it before each call,
// and on a trap maps it to native's two texts, the uncaught one (`error:
// <msg>` on stderr, exit 1) and the one ex-message returns once caught.
//
// THE PLAN: {"steps": [step ..]}, run in order; step = {"print": [item ..],
// "catch": [item ..] | null, "discard": bool}. A step evaluates every item
// first (println's arguments), then prints them joined by spaces, as
// println; "discard" evaluates and prints nothing (a top-level expression).
// If a call raises, "catch" items are printed instead (a
// (try (println ..) (catch Exception e (println .. (ex-message e)))) row),
// or, without "catch", the error ends the program as native's uncaught
// error does. item = {"s": text} | {"v": arg} (printed as native prints it)
// | {"call": export, "args": [arg ..]} | {"err": true} (the caught message);
// arg = {"i": "<int64 decimal>"} | {"f": "<float: decimal, Inf, -Inf, NaN,
// -0>"} | {"b": bool} | {"nil": true}.
import { readFileSync } from "node:fs";

const [, , modArg, modVal, planArg, planVal] = process.argv;
const bytes = modArg === "--hex" ? Buffer.from(modVal, "hex") : readFileSync(modArg);
const planText = modArg === "--hex"
  ? (planArg === "--plan" ? planVal : readFileSync(planArg, "utf8"))
  : (modVal === "--plan" ? planArg : readFileSync(modVal, "utf8"));
const plan = JSON.parse(planText);

const { instance } = await WebAssembly.instantiate(bytes, {});
const X = instance.exports;
const err = X["lw err"];

// let-go's Float.String() (pkg/vm/float.go): an integral finite value as
// FormatFloat 'f' with one decimal, else FormatFloat(f, 'g', -1, 64), whose
// shortest form switches to the exponent form below 1e-4 or from 1e6 on.
// JS's toExponential() gives the same shortest round-trip digits.
function goFloat(f) {
  if (Number.isNaN(f)) return "NaN";
  if (f === Infinity) return "+Inf";
  if (f === -Infinity) return "-Inf";
  if (Number.isInteger(f)) return (Object.is(f, -0) ? "-0" : BigInt(f).toString()) + ".0";
  const neg = f < 0;
  const [m, e] = Math.abs(f).toExponential().split("e");
  const digits = m.replace(".", "");
  const exp = parseInt(e, 10);
  let out;
  if (exp < -4 || exp >= 6) {
    const mant = digits.length > 1 ? digits[0] + "." + digits.slice(1) : digits;
    const ae = Math.abs(exp);
    out = mant + "e" + (exp < 0 ? "-" : "+") + (ae < 10 ? "0" + ae : String(ae));
  } else if (exp < 0) {
    out = "0." + "0".repeat(-exp - 1) + digits;
  } else {
    out = digits.slice(0, exp + 1).padEnd(exp + 1, "0") + "." + digits.slice(exp + 1);
  }
  return (neg ? "-" : "") + out;
}

function box(a) {
  if ("i" in a) return X["lw box_i"](BigInt(a.i));
  if ("f" in a) {
    const t = { Inf: Infinity, "-Inf": -Infinity, NaN: NaN, "-0": -0 }[a.f];
    return X["lw box_f"](t === undefined ? Number(a.f) : t);
  }
  if ("b" in a) return X["lw box_b"](a.b ? 1 : 0);
  return null;
}

function show(v) {
  switch (X["lw kind"](v)) {
    case 0: return "nil";
    case 1: return X["lw unbox_i"](v).toString();
    case 2: return goFloat(X["lw unbox_f"](v));
    case 3: return "false";
    case 4: return "true";
    default: return "#<unknown value>";
  }
}

const TYPE = ["nil", "let-go.lang.Int", "let-go.lang.Float", "let-go.lang.Boolean", "let-go.lang.Boolean"];
const STR = ["", "", "", "false", "true"];
const VERB = ["add", "subtract", "multiply", "divide", "quot", "rem", "mod", "compare"];
const BITOP = ["bit-and", "bit-or", "bit-xor", "bit-and-not", "bit-shift-left", "bit-shift-right",
  "unsigned-bit-shift-right", "bit-not"];

class LgError extends Error {
  constructor(msg, cmsg) { super(msg); this.cmsg = cmsg; }
}

// [uncaught text, ex-message text] for a value of "lw err"
function errorTexts(v) {
  const code = v & 15, sub = (v >> 4) & 15, ka = (v >> 8) & 15, kb = (v >> 12) & 15;
  const same = (m) => [m, m];
  switch (code) {
    case 1: return ["integer overflow", "ExecutionError: integer overflow"];
    case 2: return same("integer overflow");
    case 3: return same("divide by zero");
    case 4: return same(`cannot ${VERB[sub]} ${TYPE[ka]} and ${TYPE[kb]}`);
    case 5: return same(`cannot negate ${TYPE[ka]}`);
    case 6: return same(`zero? requires a number, got ${STR[ka]}`);
    case 7: return same("wasm.emit: / of two Ints yielding a Ratio (named limit)");
    case 8: return same("wasm.emit: (/ MinInt64 -1) is a BigInt (named limit)");
    case 9: return same(`${BITOP[sub]} expected Int`);
    default: return same(`emit-run: unknown error code ${v}`);
  }
}

function call(item) {
  const n = item.args.length;
  const f = X[`${item.call}/${n}`] ?? X[item.call];
  if (typeof f !== "function") throw new LgError(`emit-run: no export ${item.call} of ${n} args`, "");
  err.value = 0;
  try {
    return f(...item.args.map(box));
  } catch (e) {
    if (e instanceof WebAssembly.RuntimeError && err.value !== 0) {
      const [m, c] = errorTexts(err.value);
      throw new LgError(m, c);
    }
    if (e instanceof RangeError) throw new LgError("stack overflow", "stack overflow");
    throw new LgError(`wasm trap: ${e.message}`, `wasm trap: ${e.message}`);
  }
}

function render(items, caught) {
  return items.map((it) => {
    if ("s" in it) return it.s;
    if ("err" in it) return caught.cmsg;
    if ("v" in it) return show(box(it.v));
    return show(call(it));
  });
}

let out = "";
for (const step of plan.steps) {
  let parts;
  try {
    parts = render(step.print, null);
  } catch (e) {
    if (!(e instanceof LgError)) throw e;
    if (!step.catch) {
      process.stdout.write(out);
      process.stderr.write(`error: ${e.message}\n`);
      process.exit(1);
    }
    out += render(step.catch, e).join(" ") + "\n";
    continue;
  }
  if (!step.discard) out += parts.join(" ") + "\n";
}
process.stdout.write(out);
