if isempty(ARGS) || length(ARGS) == 1
    error("provide package path as argument")
end

using BenchmarkTools
using Serialization

import ReLint
b = redirect_stdout(devnull) do
    @benchmark ReLint.run_lint(ARGS[2])
end

serialize(ARGS[1], b)
