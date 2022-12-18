"""
    KVector{K,T,D,N}

Geometric `K`-vector with eltype `T` with `N` elements in a geometric algebra of dimension `D`.

The constructors `KVector{K,D}(elements...)` and `KVector{K,D}(elements::NTuple)` will automatically infer `T` from the arguments and `N` from `K` and `D`.

# Examples

```jldoctest
julia> KVector{1,3}(1.0, 2.0, 3.0)
KVector{1, Float64, 3, 3}(1.0, 2.0, 3.0)

julia> KVector{2,3}(1.0, 2.0, 3.0)
Bivector{Float64, 3, 3}(1.0, 2.0, 3.0)

julia> KVector{4,4}(1.0)
Quadvector{Float64, 4, 1}(1.0)
```
"""
struct KVector{K,T,D,N}
  elements::NTuple{N,T}
  function KVector{K,D}(elements::NTuple{N,T}) where {K,T,D,N}
    (0 ≤ K ≤ D) || error("Cannot construct $K-vector in a geometric algebra of dimension $D")
    N === binomial(D, K) || error("Expected ", binomial(D, K), " elements, got $N")
    new{K,T,D,N}(elements)
  end
  KVector{K,D}(elements::Tuple) where {K,D} = KVector{K,D}(promote(elements...))
end

KVector{K,D}(xs...) where {K,D} = KVector{K,D}(xs)

"""
    Bivector{T,D,N}

Alias for `KVector{2,T,D,N}`
"""
const Bivector{T,D,N} = KVector{2,T,D,N}
"""
    Trivector{T,D,N}

Alias for `KVector{3,T,D,N}`
"""
const Trivector{T,D,N} = KVector{3,T,D,N}
"""
    Quadvector{T,D,N}

Alias for `KVector{4,T,D,N}`
"""
const Quadvector{T,D,N} = KVector{4,T,D,N}

@forward KVector.elements (Base.iterate, Base.firstindex, Base.lastindex)

Base.isapprox(x::KVector, y::KVector) = grade(x) == grade(y) && all(isapprox.(x, y))

Base.getindex(kvec::KVector) = only(kvec.elements)
Base.getindex(kvec::KVector, indices) = kvec.elements[indices]

Base.eltype(::Type{<:KVector{<:Any,T}}) where {T} = T
Base.length(::Type{<:KVector{<:Any,<:Any,<:Any,N}}) where {N} = N

grade(::Type{<:KVector{K}}) where {K} = K

for f in (:(Base.eltype), :(Base.length), :grade)
  @eval $f(kvec::KVector) = $f(typeof(kvec))
end

Base.convert(::Type{NTuple{N,T}}, kvec::KVector{<:Any,T,<:Any,N}) where {T,N} = kvec.elements

Base.show(io::IO, kvec::KVector) = print(io, typeof(kvec), '(', join(kvec.elements, ", "), ')')
