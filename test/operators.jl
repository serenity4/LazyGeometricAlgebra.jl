using LazyGeometricAlgebra: codegen_expression, postwalk, traverse, blade_left_complement, blade_right_complement, dimension
using Combinatorics: combinations

all_blades(sig::Signature) = [blade(indices) for indices in combinations(1:dimension(sig))]

function annotate_variables(ex, types::Dict{Symbol,<:Any})
  already_annotated = Set{Symbol}()
  traverse(ex) do ex
    Meta.isexpr(ex, :(::)) && isa(ex.args[1], Symbol) && push!(already_annotated, ex.args[1])
    nothing
  end
  postwalk(ex) do ex
    isa(ex, Symbol) || return ex
    !in(ex, already_annotated) && haskey(types, ex) && return :($ex::$(types[ex]))
    ex
  end
end

function generate(sig, types, ex)
  generated_ex = codegen_expression(sig, QuoteNode(:nested), nothing, annotate_variables(ex, types))
  ex = Expr(:block)
  for (k, v) in variables
    push!(ex.args, :($k = $v))
  end
  push!(ex.args, generated_ex)
  eval(ex)
end

types = Dict(:A => :Vector, :B => :Vector, :C => :Vector)
variables = Dict(:A => (1, 2, 3), :B => (10, 2, 30), :C => (10, 200, 3))

@testset "Operators" begin
  @testset "Associativity" begin
    @test generate(3, types, :(A + (B + C))) == generate(3, types, :((A + B) + C))
    @test generate(3, types, :(A * (B * C))) == generate(3, types, :((A * B) * C))
  end

  @testset "Distributivity" begin
    @test generate(3, types, :(A * (B + C))) == generate(3, types, :(A * B + A * C))
    @test generate(3, types, :(A ∧ (B + C))) == generate(3, types, :(A ∧ (B + C)))
  end

  @testset "Jacobi identity" begin
    lhs = @ga 4 :flatten Vector begin
      A = 1.3::e1 + 2.7::e12
      B = 0.7::e3 + 1.1::e123 + 3.05::e
      C = 0.7::e4 + 0.1::e2 + 1.59::e23 + 1.1::e124 + 3.05::e1234
      A × (B × C)
    end

    rhs = @ga 4 :flatten Vector begin
      A = 1.3::e1 + 2.7::e12
      B = 0.7::e3 + 1.1::e123 + 3.05::e
      C = 0.7::e4 + 0.1::e2 + 1.59::e23 + 1.1::e124 + 3.05::e1234
      -(B × (C × A) + C × (A × B))
    end

    @test all(lhs .≈ rhs)
  end

  @testset "Complements" begin
    for sig in [Signature.(2:3); Signature(3, 0, 1); Signature(4, 1); Signature.(6:10)]
      @test all(all_blades(sig)) do b
        (b ∧ blade_right_complement(sig, b) == antiscalar(sig)) &
          (blade_left_complement(sig, b) ∧ b == antiscalar(sig))
      end
    end
  end

  @testset "De Morgan laws" begin
    global variables = Dict(:A => (1, 2, 3, 4), :B => (10, 2, 30, 4), :C => (10, 200, 30, 400))
    _eval(ex) = generate((3, 0, 1), types, ex)
    @test _eval(:(right_complement(exterior_product(A, B)))) == _eval(:(exterior_antiproduct(right_complement(A), right_complement(B))))
    @test _eval(:(right_complement(exterior_antiproduct(A, B)))) == _eval(:(exterior_product(right_complement(A), right_complement(B))))
    @test _eval(:(left_complement(exterior_product(A, B)))) == _eval(:(exterior_antiproduct(left_complement(A), left_complement(B))))
    @test _eval(:(left_complement(exterior_antiproduct(A, B)))) == _eval(:(exterior_product(left_complement(A), left_complement(B))))
  end
end;
