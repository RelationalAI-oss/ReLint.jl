if isempty(ARGS) || length(ARGS) == 1
    error("provide package path as argument")
end

import Pkg
benchmarktools_added = "BenchmarkTools" in keys(Pkg.project().dependencies)
serialization_added = "Serialization" in keys(Pkg.project().dependencies)
redirect_stdout(devnull) do
    benchmarktools_added || Pkg.add("BenchmarkTools")
    serialization_added || Pkg.add("Serialization")
end

using BenchmarkTools, Serialization

import ReLint
b = redirect_stdout(devnull) do
    @benchmark ReLint.run_lint(ARGS[2])
end

serialize(ARGS[1], b)

redirect_stdout(devnull) do
    benchmarktools_added || Pkg.rm("BenchmarkTools"; mode=Pkg.PKGMODE_MANIFEST)
    serialization_added || Pkg.rm("Serialization"; mode=Pkg.PKGMODE_MANIFEST)
end
