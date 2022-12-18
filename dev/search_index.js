var documenterSearchIndex = {"docs":
[{"location":"reference/api/#API-Reference","page":"API","title":"API Reference","text":"","category":"section"},{"location":"reference/api/","page":"API","title":"API","text":"Exported symbols:","category":"page"},{"location":"reference/api/","page":"API","title":"API","text":"@ga\nKVector\nBivector\nTrivector\nQuadvector\ncodegen_expression","category":"page"},{"location":"reference/api/#Main-usage","page":"API","title":"Main usage","text":"","category":"section"},{"location":"reference/api/","page":"API","title":"API","text":"@ga\nKVector\nBivector\nTrivector\nQuadvector","category":"page"},{"location":"reference/api/#SymbolicGA.@ga","page":"API","title":"SymbolicGA.@ga","text":"@ga <sig> <flatten> <T> <ex>\n@ga <sig> <flatten or T> <ex>\n@ga <sig> <ex>\n\nGenerate Julia code which implements the computation of geometric elements from ex in an algebra defined by a signature sig (see SymbolicGA.Signature).\n\nSupported syntax:\n\nsig: Integer literal or tuple of 1, 2 or 3 integer literals corresponding to the number of positive, negative and degenerate basis vectors respectively, where unspecified integers default to zero.\nflatten: Symbol literal.\nT: Any arbitrary expression which evaluates to a type or to nothing.\nex: Any arbitrary expression that can be parsed algebraically.\n\nSee also: codegen_expression.\n\nExpression parsing\n\nex can be a single statement or a block, and uses a domain-specific language to facilitate the construction of algebraic expressions. ex is logically divided into two sections: a definition section, which defines bindings, and a final algebraic expression, which will be the object of the evaluation. It is processed in three phases:\n\nA definition phase, in which bindings are defined with one or several statements for use in the subsequent phase;\nAn expansion phase, where identified bindings in the final algebraic expression are expanded. The defined bindings include the ones priorly defined and a set of built-in bindings.\nAn evaluation phase, in which the core algebraic expression is simplified and translated into a Julia expression.\n\nBinding definitions\n\nAll statements prior to the last can define new variables or functions with the following syntax and semantics:\n\nVariables are either declared with <lhs::Symbol> = <rhs::Any> or with <lhs::Symbol>::<type>, the latter being expanded to <lhs> = <lhs>::<type>.\nFunctions are declared with a standard short or long form function definition <name>(<args...>) = <rhs> or function <name>(<args...>) <rhs> end, and are restricted to simple forms to encode simple semantics. The restrictions are as follows:\nwhere clauses and output type annotations are not supported.\nFunction arguments must be untyped, e.g. f(x, y) is allowed but not f(x::Vector, y::Vector).\nFunction arguments must not be reassigned; it is assumed that any occurence of symbols declared as arguments will reference these arguments. For example, f(x, y) = x + y assumes that x + y actually means \"perform + on the first and second function argument\". Therefore, f(x, y) = (x = 2; x) + y will be likely to cause bugs. To alleviate this restriction, use codegen_expression with a suitable [SymbolicGA.VariableInfo] with function entries that contain specific calls to `:($(@arg <i>)).\n\nBinding expansion\n\nReferences and functions are expanded in a fairly straightforward copy-paste manner, where references are replaced with their right-hand side and function calls with their bodies with their arguments interpolated. Simple checks are put in place to allow for self-referencing bindings for references, such as x = x::T, leading to a single expansion of such a pattern in the corresponding expression subtree.\n\nAlgebraic evaluation\n\nTODO\n\nSee SymbolicGA.VariableInfo for more information regarding the expansion of such variables and functions.\n\n\n\n\n\n","category":"macro"},{"location":"reference/api/#SymbolicGA.KVector","page":"API","title":"SymbolicGA.KVector","text":"KVector{K,T,D,N}\n\nGeometric K-vector with eltype T with N elements in a geometric algebra of dimension D.\n\nThe constructors KVector{K,D}(elements...) and KVector{K,D}(elements::NTuple) will automatically infer T from the arguments and N from K and D.\n\nExamples\n\njulia> KVector{1,3}(1.0, 2.0, 3.0)\nKVector{1, Float64, 3, 3}(1.0, 2.0, 3.0)\n\njulia> KVector{2,3}(1.0, 2.0, 3.0)\nBivector{Float64, 3, 3}(1.0, 2.0, 3.0)\n\njulia> KVector{4,4}(1.0)\nQuadvector{Float64, 4, 1}(1.0)\n\n\n\n\n\n","category":"type"},{"location":"reference/api/#SymbolicGA.Bivector","page":"API","title":"SymbolicGA.Bivector","text":"Bivector{T,D,N}\n\nAlias for KVector{2,T,D,N}\n\n\n\n\n\n","category":"type"},{"location":"reference/api/#SymbolicGA.Trivector","page":"API","title":"SymbolicGA.Trivector","text":"Trivector{T,D,N}\n\nAlias for KVector{3,T,D,N}\n\n\n\n\n\n","category":"type"},{"location":"reference/api/#SymbolicGA.Quadvector","page":"API","title":"SymbolicGA.Quadvector","text":"Quadvector{T,D,N}\n\nAlias for KVector{4,T,D,N}\n\n\n\n\n\n","category":"type"},{"location":"reference/api/#Expression-generation","page":"API","title":"Expression generation","text":"","category":"section"},{"location":"reference/api/","page":"API","title":"API","text":"codegen_expression\nSymbolicGA.VariableInfo\nSymbolicGA.Signature\nSymbolicGA.@arg","category":"page"},{"location":"reference/api/#SymbolicGA.codegen_expression","page":"API","title":"SymbolicGA.codegen_expression","text":"codegen_expression(sig, ex; flatten::Symbol = :nested, T = nothing, varinfo::Optional{VariableInfo} = nothing)\n\nParse ex as an algebraic expression and generate a Julia expression which represents the corresponding computation. sig can be a SymbolicGA.Signature or a signature integer, tuple or tuple expression adhering to semantics of @ga. See @ga for more information regarding the parsing and semantics applied to ex.\n\nParameters\n\nflatten controls whether the components should be nested (:nested) or flattened (:flattened). In short, setting this option to :flattened always returns a single tuple of components, even multiple geometric entities are present in the output; while :nested will return a tuple of multiple elements if several geometric entities result from the computation.\nT specifies what type to use when reconstructing geometric entities from tuple components with construct. If set to nothing with a :nested mode (default), then an appropriate KVector will be used depending on which type of geometric entity is returned; if multiple entities are present, a tuple of KVectors will be returned. With a :flattened mode, T will be set to :Tuple if unspecified.\nvarinfo is a user-provided SymbolicGA.VariableInfo which controls what expansions are carried out on the raw Julia expression before conversion to an algebraic expression.\n\n\n\n\n\n","category":"function"},{"location":"reference/api/#SymbolicGA.VariableInfo","page":"API","title":"SymbolicGA.VariableInfo","text":"VariableInfo(; refs = Dict{Symbol,Any}(), funcs = Dict{Symbol,Any}(), warn_override = true)\n\nStructure holding information about bindings which either act as references (simple substitutions) or as functions, which can be called with arguments. This allows a small domain-specific language to be used when constructing algebraic expressions.\n\nReferences are lhs::Symbol => rhs pairs where the left-hand side simply expands to the right-hand side during parsing. Right-hand sides which include lhs are supported, such that references of the form x = x::Vector are allowed, but will be expanded only once. Functions are name::Symbol => body pairs where rhs must refer to their arguments with Expr(:argument, <literal::Int>) expressions. Recursion is not supported and will lead to a StackOverflowError. See @arg.\n\nMost built-in functions and symbols are implemented using this mechanism. If warn_override is set to true, overrides of such built-in functions will trigger a warning.\n\n\n\n\n\n","category":"type"},{"location":"reference/api/#SymbolicGA.Signature","page":"API","title":"SymbolicGA.Signature","text":"Signature{P,N,D}\n\nSignature of an Euclidean or pseudo-Euclidean space.\n\nThis signature encodes a space with a metric such that the first P basis vectors square to 1, the following N to -1 and the following D to 0. The metric evaluates to zero between two distinct basis vectors.\n\n\n\n\n\n","category":"type"},{"location":"reference/api/#SymbolicGA.@arg","page":"API","title":"SymbolicGA.@arg","text":"@arg <literal::Integer>\n\nConvenience macro to construct expressions of the form Expr(:argument, i) used within function definitions for SymbolicGA.VariableInfo.\n\n\n\n\n\n","category":"macro"},{"location":"reference/api/#Interface-methods","page":"API","title":"Interface methods","text":"","category":"section"},{"location":"reference/api/","page":"API","title":"API","text":"SymbolicGA.getcomponent\nSymbolicGA.construct","category":"page"},{"location":"reference/api/#SymbolicGA.getcomponent","page":"API","title":"SymbolicGA.getcomponent","text":"getcomponent(collection, i::Int)\ngetcomponent(collection)\n\nFor geometric elements, retrieve the ith component of a geometric element backed by collection, using a linear index in the range 1:cumsum(nelements(signature, g) for g in grades) where signature is the signature used for the algebra and grades the grades of the geometric element.\n\nFor example, a bivector in a geometric algebra with signature (3, 0, 0) has three components, and therefore will use indices from 1 to 3. This falls back to getindex(collection, i), therefore most collections won't need to extend this method.\n\nScalars and antiscalars are obtained with getcomponent(scalar), which defaults to the identity function.\n\n\n\n\n\n","category":"function"},{"location":"reference/api/#SymbolicGA.construct","page":"API","title":"SymbolicGA.construct","text":"construct(T, components::Tuple)\n\nConstruct an instance of T from a tuple of components.\n\nDefaults to T(components).\n\n\n\n\n\n","category":"function"},{"location":"#SymbolicGA.jl","page":"Home","title":"SymbolicGA.jl","text":"","category":"section"},{"location":"#Status","page":"Home","title":"Status","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"This package is currently in heavy development. The source code and public API may change at any moment. Use at your own risk.","category":"page"}]
}
