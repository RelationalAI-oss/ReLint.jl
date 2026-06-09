using ReLint
using Argus: Rule, @pattern
using Test

include(joinpath(@__DIR__, "common.jl"))

include(joinpath(@__DIR__, "interface.jl"))
include(joinpath(@__DIR__, "fatal.jl"))
include(joinpath(@__DIR__, "violations.jl"))
include(joinpath(@__DIR__, "recommendations.jl"))
