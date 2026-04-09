module ReLint

using Argus
using JuliaSyntax

include("interface.jl")

function __init__()
    include(joinpath(@__DIR__, "rules/rules.jl"))
end

end
