module ReLint

using Argus
using JuliaSyntax

all_rules() = [
    values(RECOMMENDATIONS)...,
    values(VIOLATIONS)...,
    values(FATAL_VIOLATIONS)...
]

include("interface.jl")

function __init__()
    include(joinpath(@__DIR__, "linting/argus-rules.jl"))
    include(joinpath(@__DIR__, "linting/text_lint_rules.jl"))
end

end
