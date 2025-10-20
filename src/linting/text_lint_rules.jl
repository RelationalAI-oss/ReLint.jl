abstract type LineLintRule <: LintRule end
abstract type LineRecommendationLintRule <: LineLintRule end
abstract type LineViolationLintRule <: LineLintRule end
abstract type LineFatalLintRule <: LineLintRule end

# Line rules
struct TodoPrRule <: LineFatalLintRule end
struct TodoJiraIssueRule <: LineViolationLintRule end

function check(t::TodoPrRule, line::String, markers::Dict{Symbol,String})
    !isnothing(match(r"TODO\s?\(PR\)", line)) && return true, "`TODO (PR)` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue."
    !isnothing(match(r"TODO PR", line)) && return true, "`TODO PR` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue."
    return false, ""
end

function check(t::TodoJiraIssueRule, line::String, markers::Dict{Symbol,String})
    (contains(line, "TODO") && !contains(line, r"TODO\s?\(RAI-\d+\)")) &&
        return true, "`TODO` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue."
    return false, ""
end