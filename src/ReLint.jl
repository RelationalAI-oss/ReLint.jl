module ReLint

using CSTParser: CSTParser, EXPR
import InteractiveUtils

mutable struct LintMeta
    error
    LintMeta() = new(nothing)
    LintMeta(v) = new(v)
end

include("linting/extended_checks.jl")
include("interface.jl")
end