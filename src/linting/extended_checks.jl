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
    return [values(RECOMMENDATIONS)...,
            values(VIOLATIONS)...,
            values(FATAL_VIOLATIONS)...]
end
