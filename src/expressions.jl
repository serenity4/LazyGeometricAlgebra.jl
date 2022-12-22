const GradeInfo = Union{Int,Vector{Int}}

@enum Head::UInt8 begin
  # Decorations.
  FACTOR
  BLADE
  KVECTOR
  MULTIVECTOR

  # Linear operations.
  ADDITION
  SUBTRACTION
  NEGATION # unused
  REVERSE
  ANTIREVERSE
  LEFT_COMPLEMENT
  RIGHT_COMPLEMENT

  # Products.
  GEOMETRIC_PRODUCT
  EXTERIOR_PRODUCT
  INTERIOR_PRODUCT
  COMMUTATOR_PRODUCT

  # Nonlinear operations.
  INVERSE
  EXPONENTIAL
end

function Head(head::Symbol)
  head === :factor && return FACTOR
  head === :blade && return BLADE
  head === :kvector && return KVECTOR
  head === :multivector && return MULTIVECTOR
  head === :+ && return ADDITION
  head === :- && return SUBTRACTION
  head === :reverse && return REVERSE
  head === :antireverse && return ANTIREVERSE
  head === :left_complement && return LEFT_COMPLEMENT
  head === :right_complement && return RIGHT_COMPLEMENT
  head === :⟑ && return GEOMETRIC_PRODUCT
  head === :∧ && return EXTERIOR_PRODUCT
  head === :● && return INTERIOR_PRODUCT
  head === :× && return COMMUTATOR_PRODUCT
  head === :inverse && return INVERSE
  head === :exp && return EXPONENTIAL
  error("Head '$head' is unknown")
end

mutable struct Expression
  head::Head
  grade::GradeInfo
  args::Vector{Any}
  function Expression(head::Head, args::AbstractVector; simplify = true, grade = nothing)
    ex = new()
    ex.head = head
    ex.args = args
    !isnothing(grade) && (ex.grade = grade)
    !simplify && return ex
    simplify!(ex, nothing)
  end
  Expression(head::Head, args...; simplify = true, grade = nothing) = Expression(head, collect(Any, args); simplify, grade)
end
# Can mutate arguments.
simplified(sig, head::Head, args...) = simplify!(Expression(head, args...; simplify = false), sig)
simplified(head::Head, args...) = simplified(nothing, head, args...)

function simplify!(ex::Expression, sig::Optional{Signature} = nothing)
  (; head, args) = ex
  # Simplify nested factor expressions.
  head === FACTOR && isexpr(args[1], FACTOR) && return simplify!(args[1]::Expression, sig)

  # Apply left and right complements.
  if head in (LEFT_COMPLEMENT, RIGHT_COMPLEMENT)
    isweightedblade(args[1]) && return weighted(simplified(sig, head, args[1][2]), args[1][1])
    args[1] == factor(0) && return args[1]
  end
  head === LEFT_COMPLEMENT && isblade(args[1]) && return blade_left_complement(sig::Signature, args[1])
  head === RIGHT_COMPLEMENT && isblade(args[1]) && return blade_right_complement(sig::Signature, args[1])

  if head === BLADE
    # Sort basis vectors.
    if !issorted(args)
      perm = sortperm(args)
      fac = isodd(parity(perm)) ? -1 : 1
      return simplified(sig, GEOMETRIC_PRODUCT, simplified(sig, FACTOR, fac), simplified(sig, BLADE, args[perm]))
    end

    # Apply metric.
    if !allunique(args)
      sig::Signature
      last = nothing
      fac = 1
      i = 1
      while length(args) ≥ 2
        i > lastindex(args) && break
        new = args[i]
        if !isnothing(last)
          if new == last
            m = metric(sig, last)
            iszero(m) && return scalar(0)
            fac *= m
            length(args) == 2 && return scalar(fac)
            deleteat!(args, i)
            deleteat!(args, i - 1)
            i = max(i - 2, 1)
            last = i < firstindex(args) ? nothing : args[i]
          else
            last = new
          end
        else
          last = new
        end
        i += 1
      end
      return weighted(simplified(sig, BLADE, args), fac)
    end
  end

  if head === SUBTRACTION
    # Simplify unary minus operator to a multiplication with -1.
    length(args) == 1 && return weighted(args[1], -1)
    # Transform binary minus expression into an addition.
    @assert length(args) == 2
    return simplified(sig, ADDITION, args[1], -args[2])
  end

  # Simplify whole expression to zero if a product term is zero.
  if head === GEOMETRIC_PRODUCT && any(isexpr(x, FACTOR) && x[1] == 0 for x in args)
    any(!isexpr(x, FACTOR) && !isexpr(x, BLADE, 0) for x in args) && @debug "Non-factor expression annihilated by a zero multiplication term" args
    return factor(0)
  end

  # Remove unit elements for multiplication and addition.
  did_remove = remove_unit_elements!(args, head)
  if did_remove
    head === GEOMETRIC_PRODUCT && isempty(args) && return scalar(1)
    head === ADDITION && isempty(args) && return scalar(0)
    return simplified(sig, head, args)
  end

  if in(head, (GEOMETRIC_PRODUCT, ADDITION))
    length(args) == 1 && return args[1]

    # Disassociate ⟑ and +.
    any(isexpr(head), args) && return disassociate1(args, head, sig)
  end

  if head === GEOMETRIC_PRODUCT
    # Collapse factors into one and put it at the front.
    nf = count(isexpr(FACTOR), args)
    if nf ≥ 2
      # Collapse all factors into one at the front.
      factors, nonfactors = filter(isexpr(FACTOR), args), filter(!isexpr(FACTOR), args)
      fac = collapse_factors(*, factors)
      length(args) == nf && return fac
      return simplified(sig, GEOMETRIC_PRODUCT, Any[fac; nonfactors])
    elseif nf == 1 && !isexpr(args[1], FACTOR)
      # Put the factor at the front.
      i = findfirst(isexpr(FACTOR), args)
      fac = args[i]::Expression
      deleteat!(args, i)
      pushfirst!(args, fac)
      return simplified(sig, GEOMETRIC_PRODUCT, args)
    end

    # Collapse all bases and blades into a single blade.
    nb = count(isexpr(BLADE), args)
    if nb > 1
      n = length(args)
      blade_args = []
      for i in reverse(eachindex(args))
        x = args[i]
        isexpr(x, BLADE) || continue
        for arg in reverse(x.args)
          pushfirst!(blade_args, arg::Int)
        end
        deleteat!(args, i)
      end
      ex = blade(sig, blade_args)
      # Return the blade if all the terms were collapsed.
      nb == n && return ex
      return simplified(sig, GEOMETRIC_PRODUCT, Any[args; ex])
    end
  end

  # Simplify addition of factors.
  head === ADDITION && all(isexpr(FACTOR), args) && return collapse_factors(+, args)

  # Group blade components over addition.
  if head === ADDITION
    indices = findall(x -> isblade(x) || isweightedblade(x), args)
    if !isempty(indices)
      blades = args[indices]
      if !allunique(basis_vectors(b) for b in blades)
        blade_weights = Dict{Vector{Int},Expression}()
        for b in blades
          vecs = basis_vectors(b)
          weight = isweightedblade(b) ? b.args[1] : factor(1)
          blade_weights[vecs] = haskey(blade_weights, vecs) ? blade_weights[vecs] + weight : weight
        end
        for (vecs, weight) in blade_weights
          fac = weight[1]
          if Meta.isexpr(fac, :call) && fac.args[1] === :+
            weight = simplify_addition(@view fac.args[2:end])
            if weight == factor(0)
              delete!(blade_weights, vecs)
            else
              blade_weights[vecs] = weight
            end
          end
        end
        new_args = args[setdiff(eachindex(args), indices)]
        append!(new_args, simplified(GEOMETRIC_PRODUCT, weight, blade(vecs)) for (vecs, weight) in blade_weights)
        return simplified(ADDITION, new_args)
      end
    end
  end


  # Simplify -1 factors.
  head === FACTOR && (args[1] = simplify_negations(args[1]))

  # Check that arguments make sense.
  n = expected_nargs(head)
  !isnothing(n) && @assert length(args) == n "Expected $n arguments for expression $head, $n were provided\nArguments: $args"
  @assert !isempty(args) || head === BLADE
  head === BLADE && @assert all(isa(i, Int) for i in args)
  head === FACTOR && @assert !isa(args[1], Expression) "`Expression` argument detected in FACTOR expression: $(args[1])"

  # Propagate complements over addition.
  head in (LEFT_COMPLEMENT, RIGHT_COMPLEMENT) && isexpr(args[1], ADDITION) && return simplified(sig, ADDITION, simplified.(sig, head, args[1]))

  # Distribute products over addition.
  head in (GEOMETRIC_PRODUCT, EXTERIOR_PRODUCT, INTERIOR_PRODUCT, COMMUTATOR_PRODUCT) && any(isexpr(arg, ADDITION) for arg in args) && return distribute1(args, head, sig)

  # Eagerly apply reversions.
  head in (REVERSE, ANTIREVERSE) && return apply_reverse_operators(ex, sig)

  # Expand common operators.
  # ========================

  # The exterior product is associative, no issues there.
  if head === EXTERIOR_PRODUCT
    n = sum(x -> grade(x::Expression)::Int, args)
    return project!(simplified(sig, GEOMETRIC_PRODUCT, args), n)
  end

  if head === INTERIOR_PRODUCT
    # The inner product must have only two operands, as no associativity law is available to derive a canonical binarization.
    # Homogeneous vectors are expected, so the grade should be known.
    r, s = grade(args[1]::Expression)::Int, grade(args[2]::Expression)::Int
    if (iszero(r) || iszero(s))
      (!iszero(r) || !iszero(s)) && @debug "Non-scalar expression annihilated in inner product with a scalar"
      return scalar(0)
    end
    return project!(simplified(sig, GEOMETRIC_PRODUCT, args), abs(r - s))
  end

  if head === COMMUTATOR_PRODUCT
    # The commutator product must have only two operands, as no associativity law is available to derive a canonical binarization.
    a, b = args[1]::Expression, args[2]::Expression
    return weighted(simplified(sig, SUBTRACTION, simplified(sig, GEOMETRIC_PRODUCT, a, b), simplified(sig, GEOMETRIC_PRODUCT, b, a)), 0.5)
  end

  if head === EXPONENTIAL
    # Find a closed form for the exponentiation, if available.
    a = args[1]::Expression
    (isblade(a) || isweightedblade(a)) && return expand_exponential(sig::Signature, a)
    # return expand_exponential(sig::Signature, a)
    isexpr(a, ADDITION) && return simplified(sig, GEOMETRIC_PRODUCT, simplified.(sig, EXPONENTIAL, a)...)
    throw(ArgumentError("Exponentiation is not supported for non-blade elements."))
  end

  if head === INVERSE
    a = args[1]::Expression
    isexpr(a, FACTOR) && return factor(scalar_inverse(a[1]))
    isweightedblade(a, 0) && return scalar(simplified(INVERSE, a[1]::Expression))
    isblade(a, 0) && return a
    sc = simplified(sig, GEOMETRIC_PRODUCT, simplified(REVERSE, a), a)
    isscalar(sc) || error("`reverse(A) ⟑ A` is not a scalar, suggesting that A is not a versor. Inversion is only supported for versors at the moment.")
    return simplified(GEOMETRIC_PRODUCT, simplified(REVERSE, a), simplified(INVERSE, sc))
  end

  ex.grade = infer_grade(head, args)::GradeInfo
  ex.args = args

  ex
end

function remove_unit_elements!(args, head)
  n = length(args)
  if head === GEOMETRIC_PRODUCT
    filter!(x -> !isexpr(x, FACTOR) || x[1] !== 1, args)
  elseif head === ADDITION
    filter!(x -> !isexpr(x, FACTOR) || x[1] !== 0, args)
  end
  did_remove = n > length(args)
  did_remove
end

function collapse_factors(f::F, args) where {F<:Function}
  @assert f === (*) || f === (+)
  unit = f === (*) ? one : zero
  isunit = f === (*) ? isone : iszero
  opaque_factors = Any[]
  value = unit(Int64)
  for fac in args
    if isopaquefactor(fac)
      push!(opaque_factors, fac.args[1])
    else
      value = f(value, fac.args[1])
    end
  end

  if !isempty(opaque_factors)
    flattened_factors = Any[]
    for fac in opaque_factors
      if Meta.isexpr(fac, :call) && fac.args[1] === Symbol(f)
        append!(flattened_factors, fac.args[2:end])
      else
        push!(flattened_factors, fac)
      end
    end
    !isunit(value) && push!(flattened_factors, value)
    length(flattened_factors) == 1 && return factor(flattened_factors[1])

    ex = Expr(:call)
    ex.args = flattened_factors
    pushfirst!(ex.args, Symbol(f))
    return factor(ex)
  end
  return factor(value)
end

function disassociate1(args, op::Head, sig::Optional{Signature})
  new_args = []
  for arg in args
    if isexpr(arg, op)
      append!(new_args, arg.args)
    else
      push!(new_args, arg)
    end
  end
  simplified(sig, op, new_args)
end

function distribute1(args, op::Head, sig::Optional{Signature})
  x, ys = args[1], @view args[2:end]
  base = isexpr(x, ADDITION) ? x.args : [x]
  for y in ys
    new_base = []
    yterms = isexpr(y, ADDITION) ? y.args : (y,)
    for xterm in base
      for yterm in yterms
        push!(new_base, simplified(sig, op, xterm, yterm))
      end
    end
    base = new_base
  end
  simplified(sig, ADDITION, base)
end

function simplify_negations(fac)
  if Meta.isexpr(fac, :call) && fac.args[1] === :*
    head, args... = fac.args
    n = count(x -> x == -1, args)
    if n > 1
      filter!(≠(-1), args)
      isodd(n) && pushfirst!(args, -1)
      isempty(args) && return 1
      length(args) == 1 && return args[1]
      return Expr(:call, head, args...)
    end
  end
  fac
end

function simplify_addition(args)
  counter = 0
  ids = Dict{Any,Int}()
  id_counts = Dict{Int,Int}()
  new_args = []
  for arg in args
    n = 1
    obj = arg
    if Meta.isexpr(arg, :call) && arg.args[1] === :*
      xs = arg.args[2:end]
      @assert length(xs) > 1
      filter!(xs) do y
        if isa(y, Int) || isa(y, Integer)
          n *= y
          return false
        end
        true
      end
      # Extract the object after extraction of integer factors.
      # Make sure that multiple arguments are stored such that ordering is not important,
      # and other orderings should give the same ID.
      obj = isempty(xs) ? 1 : length(xs) == 1 ? xs[1] : sort!(xs; by = hash)
    end
    id = get!(() -> (counter += 1), ids, obj)
    id_counts[id] = something(get(id_counts, id, nothing), 0) + n
  end
  for (x, id) in sort(collect(ids); by = last)
    n = id_counts[id]
    n == 0 && continue
    isa(x, Vector{Any}) && (x = Expr(:call, :*, x...))
    if n == 1
      push!(new_args, x)
    else
      push!(new_args, scalar_multiply(n, x))
    end
  end
  isempty(new_args) && return factor(0)
  length(new_args) == 1 && return factor(new_args[1])
  factor(Expr(:call, :+, new_args...))
end

function expected_nargs(head)
  in(head, (FACTOR, NEGATION, REVERSE, ANTIREVERSE, LEFT_COMPLEMENT, RIGHT_COMPLEMENT, INVERSE, EXPONENTIAL)) && return 1
  in(head, (INTERIOR_PRODUCT, COMMUTATOR_PRODUCT, SUBTRACTION)) && return 2
  nothing
end

function infer_grade(head::Head, args)
  head === FACTOR && return 0
  head === BLADE && return count(isodd, map(x -> count(==(x), args), unique(args)))
  if head === GEOMETRIC_PRODUCT
    @assert length(args) == 2 && isexpr(args[1], FACTOR)
    return grade(args[2]::Expression)
  end
  if in(head, (ADDITION, MULTIVECTOR))
    gs = Int64[]
    for arg in args
      append!(gs, grade(arg))
    end
    sort!(unique!(gs))
    length(gs) == 1 && return first(gs)
    return gs
  end
  if head === KVECTOR
    grades = map(args) do arg
      isa(arg, Expression) || error("Expected argument of type $Expression, got $arg")
      g = arg.grade
      isa(g, Int) || error("Expected grade to be known for argument $arg in $head expression")
      g
    end
    unique!(grades)
    length(grades) == 1 || error("Expected unique grade for k-vector expression, got grades $grades")
    return first(grades)
  end
  error("Cannot infer grade for unexpected $head expression with arguments $args")
end

# Empirical formula.
# If anyone has a better one, please let me know.
blade_right_complement(sig::Signature, b::Expression) = blade(sig, reverse!(setdiff(1:dimension(sig), b.args))) * factor((-1)^(
  isodd(sum(b; init = 0)) +
  (dimension(sig) ÷ 2) % 2 +
  isodd(dimension(sig)) & isodd(length(b))
))

# Exact formula derived from the right complement.
blade_left_complement(sig::Signature, b::Expression) = factor((-1)^(grade(b) * antigrade(sig, b))) * blade_right_complement(sig, b)

function project!(ex, g, level = 0)
  isa(ex, Expression) || return ex
  if all(isempty(intersect(g, g′)) for g′ in grade(ex))
    iszero(level) && @debug "Non-scalar expression annihilated in projection into grade(s) $g" ex
    return factor(0)
  end
  if isexpr(ex, ADDITION)
    for (i, x) in enumerate(ex)
      ex.args[i] = project!(x, g, level + 1)
    end
    return simplify!(ex)
  end
  ex
end

function apply_reverse_operators(ex::Expression, sig::Optional{Signature})
  orgex = ex
  prewalk(ex) do ex
    isexpr(ex, (REVERSE, ANTIREVERSE)) || return ex
    reverse_op = ex.head
    anti = reverse_op === ANTIREVERSE
    anti && sig::Signature
    ex = ex[1]
    @assert isa(ex, Expression) "`Expression` argument expected for `$reverse_op`."
    # Distribute over addition.
    isexpr(ex, (ADDITION, KVECTOR, MULTIVECTOR)) && return simplified(sig, ex.head, anti ? antireverse.(sig, ex) : reverse.(ex))
    !anti && in(ex.grade, (0, 1)) && return ex
    anti && in(antigrade(sig, ex.grade), (0, 1)) && return ex
    isexpr(ex, GEOMETRIC_PRODUCT) && return propagate_reverse(reverse_op, ex, sig)
    @assert isexpr(ex, BLADE) "Unexpected operator $(ex.head) encountered when applying $reverse_op operators."
    n = anti ? antigrade(sig, ex)::Int : grade(ex)::Int
    fac = (-1)^(n * (n - 1) ÷ 2)
    isone(fac) ? ex : -ex
  end
end

# grade(x) + antigrade(x) == dimension(sig)
antigrade(sig::Signature, g::Int) = dimension(sig) - g
antigrade(sig::Signature, g::Vector{Int}) = antigrade.(sig, g)
antigrade(sig::Signature, ex::Expression) = antigrade(sig, ex.grade)

function propagate_reverse(reverse_op, ex::Expression, sig::Optional{Signature})
  res = Any[]
  for arg in ex
    arg::Expression
    skip = isexpr(arg, FACTOR) || reverse_op === REVERSE ? in(arg.grade, (0, 1)) : in(antigrade(sig, arg.grade), (0, 1))
    skip ? push!(res, arg) : push!(res, simplified(sig, reverse_op, arg))
  end
  simplified(sig, ex.head, res)
end

function expand_exponential(sig::Signature, b::Expression)
  vs = basis_vectors(b)
  is_degenerate(sig) && any(iszero(metric(sig, v)) for v in vs) && return simplified(ADDITION, scalar(1), b)
  b² = simplified(sig, GEOMETRIC_PRODUCT, b, b)
  @assert isscalar(b²)
  α² = isweightedblade(b²) ? b²[1][1] : 1
  α = scalar_sqrt(scalar_abs(α²))
  # The sign may not be deducible from α² directly, so we compute it manually given metric simplifications and blade permutations.
  is_negative = isodd(count(metric(sig, v) == -1 for v in vs)) ⊻ iseven(length(vs))
  # Negative square: cos(α) + A * sin(α) / α
  # Positive square: cosh(α) + A * sinh(α) / α
  (s, c) = is_negative ? (scalar_sin, scalar_cos) : (scalar_sinh, scalar_cosh)
  simplified(sig, ADDITION, scalar(c(α)), simplified(sig, GEOMETRIC_PRODUCT, scalar(scalar_nan_to_zero(scalar_divide(s(α), α))), b))
end

scalar_exponential(x::Number) = exp(x)
scalar_exponential(x) = :($exp($x))
scalar_multiply(x::Number, y::Number) = x * y
scalar_multiply(x, y) = :($x * $y)
scalar_divide(x, y) = scalar_multiply(x, scalar_inverse(y))
scalar_nan_to_zero(x::Number) = isnan(x) ? 0 : x
scalar_nan_to_zero(x) = :($isnan($x) ? 0 : $x)
scalar_inverse(x::Number) = inv(x)
scalar_inverse(x) = :($inv($x))
scalar_cos(x::Number) = cos(x)
scalar_cos(x) = :($cos($x))
scalar_sin(x::Number) = sin(x)
scalar_sin(x) = :($sin($x))
scalar_cosh(x::Number) = cosh(x)
scalar_cosh(x) = :($cosh($x))
scalar_sinh(x::Number) = sinh(x)
scalar_sinh(x) = :($sinh($x))
scalar_sqrt(x::Number) = sqrt(x)
scalar_sqrt(x) = :($sqrt($x))
scalar_abs(x::Number) = abs(x)
scalar_abs(x) = :($abs($x))

# Basic interfaces.

Base.:(==)(x::Expression, y::Expression) = x.head == y.head && (!isdefined(x, :grade) || !isdefined(y, :grade) || x.grade == y.grade) && x.args == y.args
Base.getindex(x::Expression, args...) = x.args[args...]
Base.firstindex(x::Expression) = firstindex(x.args)
Base.lastindex(x::Expression) = lastindex(x.args)
Base.length(x::Expression) = length(x.args)
Base.iterate(x::Expression, args...) = iterate(x.args, args...)
Base.keys(x::Expression) = keys(x.args)
Base.view(x::Expression, args...) = view(x.args, args...)

# Introspection utilities.

isexpr(ex, head::Head) = isa(ex, Expression) && ex.head === head
isexpr(ex, heads) = isa(ex, Expression) && in(ex.head, heads)
isexpr(ex, head::Head, n::Int) = isa(ex, Expression) && isexpr(ex, head) && length(ex.args) == n
isexpr(heads) = ex -> isexpr(ex, heads)
grade(ex::Expression) = ex.grade::GradeInfo
isblade(ex, n = nothing) = isexpr(ex, BLADE) && (isnothing(n) || n == length(ex))
isscalar(ex::Expression) = isblade(ex, 0) || isweightedblade(ex, 0)
isweighted(ex) = isexpr(ex, GEOMETRIC_PRODUCT, 2) && isexpr(ex[1]::Expression, FACTOR)
isweightedblade(ex, n = nothing) = isweighted(ex) && isblade(ex[2]::Expression, n)
isopaquefactor(ex) = isexpr(ex, FACTOR) && isa(ex[1], Union{Symbol, Expr, QuoteNode})

function basis_vectors(ex::Expression)
  isweightedblade(ex) && return basis_vectors(ex[2]::Expression)
  isexpr(ex, BLADE) && return collect(Int, ex.args)
  error("Expected blade or weighted blade expression, got $ex")
end

function lt_basis_order(xinds, yinds)
  nx, ny = length(xinds), length(yinds)
  nx ≠ ny && return nx < ny
  for (xi, yi) in zip(xinds, yinds)
    xi ≠ yi && return xi < yi
  end
  false
end

# Helper functions.

factor(x) = Expression(FACTOR, x)
weighted(x, fac) = Expression(GEOMETRIC_PRODUCT, factor(fac), x)
scalar(fac) = factor(fac) * blade()
blade(xs...) = Expression(BLADE, xs...)
kvector(args::AbstractVector) = Expression(KVECTOR, args)
kvector(xs...) = kvector(collect(Any, xs))
multivector(args::AbstractVector) = Expression(MULTIVECTOR, args)
multivector(xs...) = multivector(collect(Any, xs))
Base.reverse(ex::Expression) = Expression(REVERSE, ex)
antireverse(sig::Signature, ex::Expression) = simplified(sig, ANTIREVERSE, ex)
antiscalar(sig::Signature, fac) = factor(fac) * antiscalar(sig)
antiscalar(sig::Signature) = blade(1:dimension(sig))

blade(sig::Optional{Signature}, xs...) = simplified(sig, BLADE, xs...)

⟑(x::Expression, args::Expression...) = Expression(GEOMETRIC_PRODUCT, x, args...)
Base.:(*)(x::Expression, args::Expression...) = Expression(GEOMETRIC_PRODUCT, x, args...)
Base.:(+)(x::Expression, args::Expression...) = Expression(ADDITION, x, args...)
Base.:(-)(x::Expression, args::Expression...) = Expression(SUBTRACTION, x, args...)
∧(x::Expression, y::Expression) = Expression(EXTERIOR_PRODUCT, x, y)
exterior_product(x::Expression, y::Expression) = Expression(EXTERIOR_PRODUCT, x, y)
exterior_product(sig::Signature, x::Expression, y::Expression) = simplified(sig, EXTERIOR_PRODUCT, x, y)

# Traversal/transformation utilities.

walk(ex::Expression, inner, outer) = outer(Expression(ex.head, filter!(!isnothing, inner.(ex.args))))
walk(ex, inner, outer) = outer(ex)
postwalk(f, ex) = walk(ex, x -> postwalk(f, x), f)
prewalk(f, ex) = walk(f(ex), x -> prewalk(f, x), identity)

function traverse(f, ex, ::Type{T} = Expression) where {T}
  f(ex) === false && return nothing
  !isa(ex, T) && return nothing
  for arg in ex.args
    traverse(f, arg, T)
  end
end

# Display.

function Base.show(io::IO, ex::Expression)
  isexpr(ex, BLADE) && return print(io, 'e', join(subscript.(ex)))
  isexpr(ex, FACTOR) && return print_factor(io, ex[1])
  if isexpr(ex, GEOMETRIC_PRODUCT) && isexpr(ex[end], BLADE)
    if length(ex) == 2 && isexpr(ex[1], FACTOR) && (!Meta.isexpr(ex[1][1], :call) || ex[1][1].args[1] == getcomponent)
      return print(io, ex[1], " ⟑ ", ex[end])
    else
      return print(io, '(', join(ex[1:(end - 1)], " ⟑ "), ") ⟑ ", ex[end])
    end
  end
  isexpr(ex, (GEOMETRIC_PRODUCT, ADDITION, MULTIVECTOR)) && return print(io, '(', Expr(:call, ex.head, ex.args...), ')')
  isexpr(ex, KVECTOR) && return print(io, Expr(:call, Symbol("kvector", subscript(ex.grade)), ex.args...))
  print(io, Expression, "(:", ex.head, ", ", join(ex.args, ", "), ')')
end

function print_factor(io, ex)
  Meta.isexpr(ex, :call) && in(ex.args[1], (:*, :+)) && return print(io, join((sprint(print_factor, arg) for arg in @view ex.args[2:end]), " $(ex.args[1]) "))
  Meta.isexpr(ex, :call, 3) && ex.args[1] === getcomponent && return print(io, Expr(:ref, ex.args[2:3]...))
  Meta.isexpr(ex, :call, 2) && ex.args[1] === getcomponent && isa(ex.args[2], Number) && return print(io, ex.args[2])
  Meta.isexpr(ex, :call, 2) && ex.args[1] === getcomponent && return print(io, Expr(:ref, ex.args[2]))
  print(io, ex)
end

"""
Return `val` as a subscript, used for printing `UnitBlade` and `Blade` instances.
"""
function subscript(val)
  r = div(val, 10)
  subscript_char(x) = Char(8320 + x)
  r > 0 ? string(subscript_char(r), subscript_char(mod(val, 10))) : string(subscript_char(val))
end
