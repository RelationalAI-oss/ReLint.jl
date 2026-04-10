using ReLint
using Test

include(joinpath(@__DIR__, "common.jl"))

include(joinpath(@__DIR__, "fatal.jl"))
include(joinpath(@__DIR__, "violations.jl"))
include(joinpath(@__DIR__, "recommendations.jl"))

# include(joinpath(@__DIR__, "lint_context_tests.jl"))
include(joinpath(@__DIR__, "interface.jl"))
