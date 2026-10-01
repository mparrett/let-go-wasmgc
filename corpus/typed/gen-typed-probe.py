# Typed, non-constant probe for P1.1's inline (typed) emission. The opmatrix
# corpus's typed lines are folded by optimize-fn before the backend sees them.
# Operands here are (unchecked-add i V) with i a loop counter (:int, always 0
# at runtime), so the op is typed :int and cannot fold.
vals=[0,1,-1,2,-7,2147483648,-2147483648,4294967296,4611686018427387904,9223372036854775807,-9223372036854775808,3037000500]
cnts=[0,1,31,32,63,64,-1,-64,65]
ops2=["bit-and","bit-or","bit-xor","bit-and-not","quot","unchecked-add","unchecked-subtract","unchecked-multiply","<",">="]
sh=["bit-shift-left","bit-shift-right","unsigned-bit-shift-right"]
out=[]
for n,op in enumerate(ops2+sh):
    bs = cnts if op in sh else vals
    lines=[f'(let [a (unchecked-add i {a}) b (unchecked-add i {b})] (println "{op}" a b ({op} a b)))'
           for a in vals for b in bs if not (op=="quot" and b==0)]
    out.append(f"(defn t{n} [] (loop [i 0] (when (< i 1)\n  " + "\n  ".join(lines) + f"\n  (recur (inc i)))))\n(t{n})")
lines=[f'(let [a (unchecked-add i {a})] (println "bit-not/neg" a (bit-not a) (- a)))' for a in vals]
out.append("(defn tn [] (loop [i 0] (when (< i 1)\n  " + "\n  ".join(lines) + "\n  (recur (inc i)))))\n(tn)")
# typed uncaught divide by zero: the third quot divides by (- 2 2)
out.append("(defn tz [] (loop [i 0 acc 0] (if (< i 3) (recur (inc i) (+ acc (quot 10 (- 2 i)))) acc)))\n(println (tz))")
open("typed-probe.lg","w").write("\n".join(out)+"\n")
