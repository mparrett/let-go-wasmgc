# corpus/poly-native

Topics: `corpus:lang/types`.

Native let-go's type hierarchy on the GC lane, checked against native lg: a type's ancestors are only its built-in interfaces and what derive and register-type-parent! gave it, and isa? compares vectors by equality. The llvm lane composes types (a Type's C3 ancestry, element-wise isa? on vectors, as Clojure) and twins these cases in corpus/poly-clj.
