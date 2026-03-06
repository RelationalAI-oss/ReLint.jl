using ReLint
using Test
using ReLint: convert_offset_to_line_from_lines

include(joinpath(@__DIR__, "common.jl"))

# include(joinpath(@__DIR__, "line_rules_tests.jl"))
# include(joinpath(@__DIR__, "file_exclusion_tests.jl"))
include(joinpath(@__DIR__, "noinline_tests.jl"))
include(joinpath(@__DIR__, "safe_logging_tests.jl"))
# include(joinpath(@__DIR__, "lint_context_tests.jl"))
# include(joinpath(@__DIR__, "rai_rules_tests.jl"))
# include(joinpath(@__DIR__, "test_new_rules.jl"))

