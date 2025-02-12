using ReLint
using CSTParser, Test
using ReLint: convert_offset_to_line_from_lines, check_all

include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "pass_tests.jl"))
include(joinpath(@__DIR__, "lint_context_tests.jl"))
include(joinpath(@__DIR__, "rai_rules_tests.jl"))

