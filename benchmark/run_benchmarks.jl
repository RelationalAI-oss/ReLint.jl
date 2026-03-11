using BenchmarkTools, Serialization
import Pkg
import Git

const git = Git.git()

const BENCHMARK_DIR = if !isempty(ARGS) && isdir(ARGS[1])
    joinpath(ARGS[1], "src")
else
    const TMP_DIR = mktempdir()
    # Clone `Pluto`.
    run(pipeline(`$git clone https://github.com/JuliaPluto/Pluto.jl.git $TMP_DIR`,
                 stdout=devnull))
    joinpath(TMP_DIR, "Pluto.jl/src")
end

const MAIN_BRANCH = "main-with-modified-rules"

# Save current directory so we can get back to it.
const CURRENT_DIR = pwd()

# Setup benchmarking files.
const BENCHMARKS_FILE = joinpath(CURRENT_DIR, "benchmark/benchmark_path.jl")
const SERIALIZED_BENCHMARKS_FILE = mktemp()[1]

# Setup worktree main branch.
run(pipeline(`$git worktree add ../$(MAIN_BRANCH) $(MAIN_BRANCH)`,
             stdout=devnull))
# Run benchmarks on main branch.
b_main = try
    # Switch to `branch_path` and run the benchmark there.
    cd("../$(MAIN_BRANCH)")
    Pkg.activate("../$(MAIN_BRANCH)")
    redirect_stdout(devnull) do
        Pkg.instantiate()
    end
    run(`julia --project=. $(BENCHMARKS_FILE) $(SERIALIZED_BENCHMARKS_FILE) ../$(MAIN_BRANCH)`)
    deserialize(SERIALIZED_BENCHMARKS_FILE)
catch err
    run(`$git worktree remove ../$(MAIN_BRANCH)`)
    rethrow(err)
end
# Clean up.
cd(CURRENT_DIR)
run(`$git worktree remove ../$(MAIN_BRANCH)`)

# Run benchmarks on Argus branch.
Pkg.activate(CURRENT_DIR)
redirect_stdout(devnull) do
    Pkg.add(url="https://github.com/iuliadmtru/Argus.jl")
    Pkg.instantiate()
end
run(`julia --project=. $(BENCHMARKS_FILE) $(SERIALIZED_BENCHMARKS_FILE) $(CURRENT_DIR)`)
b_argus = deserialize(SERIALIZED_BENCHMARKS_FILE)

# Print results.
println("Benchmarks on `main`:")
println(b_main)
println()
println("Benchmarks on `iulia/argus`:")
println(b_argus)
println()
println("Comparison (`iulia/argus` vs `main`):")
println(judge(median(b_argus), median(b_main)))
