using Argus

include("utils.jl")
include("recommendations.jl")
include("violations.jl")
include("fatal.jl")
include("text_lint_rules.jl")

all_rules() = [
    values(RECOMMENDATIONS)...,
    values(VIOLATIONS)...,
    values(FATAL_VIOLATIONS)...
]
