#################################################################################
# This file contains many specific and extended rules for Lint.
# You probably needs to modify this files if:
#   - you wish to add a new lint rule
#   - document an existing rule
#
# If you wish to add a new Lint rule, you need:
#   1. Define a new type, subtype of RecommendationLintRule or ViolationLintRule
#   2. Write a new function function check(t::YOUR_NEW_TYPE, x::EXPR)
#   3. Add your unit tests in rai_rules_tests.jl
#   4. Restart your REPL if you use it
#
# If you wish to modify the report produced by Lint, interface.jl
# is probably the place to start, not this file.
#################################################################################


# abstract type LintFileExclusion end

struct LintContext
    rules_to_run::Vector{Rule}
    regex_exclusions #::Vector{LintFileExclusion}

    function LintContext(dts_as_str::Vector{String})
        dt = DataType[]
        for dt_as_str in dts_as_str
            ind = findfirst(t -> nameof(t) == Symbol(dt_as_str), all_rules())
            isnothing(ind) && error("Non-existing rule: $(dt_as_str)")
            push!(dt, all_rules()[ind])
        end
        return new(dt, [])
    end

    LintContext(s::Vector{Rule}) = new(s, [])
    # LintContext(s::Vector{Any}) = new(convert(Vector{DataType}, s) , [])
    LintContext() = new(all_rules(), [])
    LintContext(a, b) = new(a, b)
end

abstract type LintRule end
abstract type ASTLintRule <: LintRule end
abstract type RecommendationLintRule <: ASTLintRule end
abstract type ViolationLintRule <: ASTLintRule end
abstract type FatalLintRule <: ASTLintRule end

include("text_lint_rules.jl")

function all_rules()
    # return vcat(all_extended_rule_types[], all_text_lint_rule_types[])
    return [general["error"], general["in"], general["haskey"],
            fatal["unsafe-logging"], fatal["unsafe-assert"], fatal["noinline-lit-or-id"]]
end
