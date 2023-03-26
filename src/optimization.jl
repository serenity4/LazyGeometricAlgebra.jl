mutable struct RefinementMetrics
  reused::Int
  splits::Int
end

Base.show(io::IO, metrics::RefinementMetrics) = print(io, RefinementMetrics, '(', sprint(show_metrics, metrics), ")")
show_metrics(io::IO, metrics::RefinementMetrics) = print(io, metrics.reused, " reuses, ", metrics.splits, " splits")

struct IterativeRefinement
  # Having an vector of `ExpressionSpec` instead of `Expression`s
  # would allow lazy substitutions.
  # Lazy vs eager is in favor of lazy only if we intend to backtrack.
  # For now, we can directly mutate expressions.
  available::Dict{Int,Vector{Pair{ExpressionSpec,Expression}}}
  expressions::Vector{Expression}
  metrics::RefinementMetrics
end

function IterativeRefinement(exs::Vector{Expression})
  available = Dict{Int,Vector{Pair{ExpressionSpec,Expression}}}()
  for ex in exs
    make_available!(available, ex)
  end
  IterativeRefinement(available, exs, RefinementMetrics(0, 0))
end
IterativeRefinement(ex::Expression) = IterativeRefinement(gather_scalar_expressions!(Expression[], ex))

function make_available!(available::Dict{Int,Vector{Pair{ExpressionSpec,Expression}}}, ex::Expression)
  n = length(ex)
  available_n = get!(Vector{Pair{ExpressionSpec, Expression}}, available, n)
  spec = ExpressionSpec(ex)
  !in(available_n, spec => ex) && push!(available_n, spec => ex)
end
make_available!(iter::IterativeRefinement, ex::Expression) = make_available!(iter.available, ex)

function may_reuse(ex::Expression, available::ExpressionSpec)
  isexpr(ex, available.head) || return false
  may_reuse(ex, available.args)
end

function may_reuse(ex::Expression, available::Vector{<:Term})
  length(available) ≥ length(ex) && return false
   all(in(ex), available)
end

function optimize!(ex::Expression)
  iter = IterativeRefinement(ex)
  apply!(iter)
  # @info "Optimization metrics: $(sprint(show_metrics, iter.metrics))"
  ex
end

function gather_scalar_expressions!(exs::Vector{Expression}, ex::Expression)
  (; cache) = ex
  traverse(ex; retraversal = Retraversal(cache, Expr)) do ex
    isexpr(ex, (SCALAR_ADDITION, SCALAR_PRODUCT)) && !in(ex, exs) && push!(exs, ex)
    true
  end
  exs
end

function apply!(iter::IterativeRefinement)
  @assert allunique(iter.expressions)
  exploited = exploit!(iter)
  @debug "Exploited: $exploited ($(length(iter.expressions)) remaining)"
  explored = -1
  while length(iter.expressions) > 0 && (exploited ≠ 0 || explored ≠ 0)
    @assert allunique(iter.expressions)
    explored = explore!(iter)
    exploited = exploit!(iter)
    @debug "Exploited: $exploited ($(length(iter.expressions)) remaining), explored: $explored"
  end
end

function exploit!(iter::IterativeRefinement)
  exploited = 0
  while true
    exploited1 = reuse_available!(iter)
    exploited1 == 0 && return exploited
    exploited += exploited1
  end
  exploited
end

function reuse_available!(iter::IterativeRefinement)
  nreused = iter.metrics.reused
  # TODO: maybe do a 50/50 split instead of going for larger reuses first,
  # as it might yield more expressions that are split like 90/10 offering
  # a lesser potential for reuse.
  for (i, available) in sort(pairs(iter.available), by = first, rev = true)
    filter!(iter.expressions) do ex
      length(ex) ≤ 2 && return false
      length(ex) ≤ i && return true
      reuses = findall(x -> may_reuse(ex, x.first), available)
      isempty(reuses) && return true
      # TODO: use the split information to simulate what other reuses would be unlocked with the new split,
      # then choose the reuse with the greater potential among all possible reuses.
      (_, reused_ex) = available[first(reuses)]
      reused, split = simulate_reuse(ex, reused_ex)
      reuse!(ex, reused, iter)
      length(ex) > 2
    end
  end
  iter.metrics.reused - nreused
end

function explore!(iter::IterativeRefinement)
  nsplits = split_descending!(iter)
  filter!(x -> length(x) > 2, iter.expressions)
  nsplits
end

function split_descending!(iter::IterativeRefinement)
  lengths = unique(length(ex) for ex in iter.expressions)
  ref = iter.metrics.splits
  for n in sort!(lengths, rev = true)
    n ≤ 2 && return 0
    for ex in iter.expressions
      length(ex) == n || continue
      split!(ex, iter)
    end
    # Stop when at least 1 split has been performed.
    # This ensures that splits on large expressions can be
    # exploited before smaller expressions are split.
    nsplits = iter.metrics.splits - ref
    nsplits > 0 && return nsplits
  end
  0
end

function simulate_reuse(ex::Expression, reused::Expression)
  remaining = copy(reused.args)
  reused, split = Term[], Term[]
  for arg in ex
    if in(arg, remaining)
      push!(reused, arg)
      deleteat!(remaining, findfirst(x -> x === arg, remaining)::Int)
    else
      push!(split, arg)
    end
  end
  reused, split
end

function reuse!(ex::Expression, reused::Vector{Term})
  remaining = copy(reused)
  filter!(ex.args) do arg
    j = findfirst(x -> arg === x, remaining)
    isnothing(j) && return true
    deleteat!(remaining, j)
    false
  end
  @assert isempty(remaining)
  reused_ex = unsimplified_expression(ex.cache, ex.head, reused)
  push!(ex.args, reused_ex)
  @assert length(ex) > 1
  ex
end

function reuse!(ex::Expression, reused::Vector{Term}, iter::IterativeRefinement)
  n = length(ex)
  reused_ex = reuse!(ex, reused)
  make_available!(iter, ex)
  make_available!(iter, reused_ex)
  length(reused_ex) > 2 && !in(reused_ex, iter.expressions) && push!(iter.expressions, reused_ex)
  iter.metrics.reused += 1
  ex
end

function reusability_score(split::Vector{<:Term}, head::Head, iter::IterativeRefinement)
  count(ex -> isexpr(ex, head) && may_reuse(ex, split), iter.expressions)
end

function select(args, n)
  sampled = keytype(args)[]
  set = keys(args)
  while length(sampled) < n
    i = rand(set)
    !in(i, sampled) && push!(sampled, i)
  end
  args[sampled]
end

function find_split(ex::Expression, iter::IterativeRefinement)
  best = nothing
  best_score = 0
  n = length(iter.expressions)
  for i in reverse(2:(length(ex) - 1))
    generator = binomial(length(ex), i) ≤ 10 ? combinations(eachindex(ex.args), i) : (select(eachindex(ex.args), i) for _ in 1:10)
    for indices in generator
      set = ex.args[indices]
      score = reusability_score(set, ex.head, iter)
      score > 0.1n && return set
      if isnothing(best)
        best, best_score = set, score
      elseif best_score < score
        best, best_score = set, score
      end
    end
  end
  best::Vector{Term}
end

function split!(ex::Expression, iter::IterativeRefinement)
  split = find_split(ex, iter)
  iter.metrics.splits += 1
  reuse!(ex, split, iter)
  # Don't record the reuse.
  iter.metrics.reused -= 1
end