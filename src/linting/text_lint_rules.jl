abstract type LineLintRule <: LintRule end
abstract type LineRecommendationLintRule <: LineLintRule end
abstract type LineViolationLintRule <: LineLintRule end
abstract type LineFatalLintRule <: LineLintRule end

# Line rules
struct TodoPrRule <: LineViolationLintRule end

function check(t::TodoPrRule, line::String, markers::Dict{Symbol,String})
    !isnothing(match(r"TODO\s?\(PR\)", line)) && return true, "`TODO (PR)` found, use `TODO` instead."
    !isnothing(match(r"TODO PR", line)) && return true, "`TODO PR` found, use `TODO` instead."
    return false, ""
end