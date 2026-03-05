module ReLint

using Argus
using JuliaSyntax
using CSTParser: CSTParser, EXPR
import InteractiveUtils

mutable struct LintMeta
    error
    LintMeta() = new(nothing)
    LintMeta(v) = new(v)
end

include("linting/argus-rules.jl")
include("linting/extended_checks.jl")
include("interface.jl")
end
