module ReLint

using Argus
using JuliaSyntax

mutable struct LintMeta
    error
    LintMeta() = new(nothing)
    LintMeta(v) = new(v)
end

include("linting/extended_checks.jl")
include("interface.jl")

function __init__()
    include(joinpath(@__DIR__, "linting/argus-rules.jl"))
end

end
