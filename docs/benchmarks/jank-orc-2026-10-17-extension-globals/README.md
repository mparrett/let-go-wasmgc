# Extension globals

The extension parser calls its `posix-ranges` map, but `lw-rt/globals` previously indexed only ordinary runtime files. Uncached LLVM treated the map as an unknown function; cached builds could retain a failing parser stub. The loader now evaluates and parses extension forms before indexing globals and uses the same forms for extension functions.

The regression is consolidated in `checks/fixtures/jank-reader/calls.lg`: dynamically constructed POSIX digit, alpha, and space regexes. Baseline run 80513 fails at the missing map signature. Uncached ORC run 41772 matches bytecode with reference checking. The isolated regex portion also matches through Wasm (73189); the whole calls group stops earlier on unsupported Wasm `any?` (45851). The loader identifier and snapshot guard passes (6118). Cached ORC run 85038 also matches; warm restoration run 56197 also matches.

## Bit operations as function values

After extension globals were registered, uncached evaluator lowering reached a separate missing-function error: `bit-not` and `bit-and-not` had opcode support but no runtime twins. Both now have boxed runtime implementations, native type/arity errors, and sequence adapters for calls beyond the fixed arity slots.

The existing calls fixture fails before the fix (26177) and matches under uncached ORC after it (88118), including signed limits, invalid operands, and high-arity errors. The existing core test group passes native comparison and a seeded generated check of complement involution and masking. Uncached definitions also match (40625), clearing the previously recorded evaluator table compile failure. The snapshot/identifier guard passes (61201). Evidence uses the `bit-values-*` and `definitions-uncached-*` prefixes.

The existing runtime evaluator program `corpus/eval/program/basic.lg` also matches uncached ORC (90130): program functions, core arithmetic, macros, atom updates, evaluated function definitions, and Var resolution. Its outputs use the `eval-basic-*` prefix.
