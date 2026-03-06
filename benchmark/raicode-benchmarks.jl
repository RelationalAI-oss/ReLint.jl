using BenchmarkTools
import Git

const git = Git.git()

const RAICODE_DIR = if !isnothing(ARGS[1]) && isdir(ARGS[1])
    joinpath(ARGS[1], "src")
else
    const TMP_DIR = mktempdir()
    # Clone `raicode`.
    run(pipeline(`$git clone https://github.com/RelationalAI/raicode.git $TMP_DIR`,
                 stdout=devnull))

    joinpath(TMP_DIR, "raicode/src")
end

function run_benchmarks(io=stdout)
    # Setup worktree main branch.
    run(pipeline(`$git worktree add ../main-with-modified-tests main-with-modified-tests`,
                 stdout=devnull))
    # Run benchmarks.
    b_main = try
        benchmark_branch("../main-with-modified-tests")
    catch err
        run(`$git worktree remove ../main-with-modified-tests`)
        rethrow(err)
    end
    b_argus = benchmark_branch()
    # Print results.
    println(io, "Benchmarks on `main`:")
    println(io, b_main)
    println(io)
    println(io, "Benchmarks on `iulia/argus`:")
    println(io, b_argus)
    println(io)
    println(io, "Comparison (`iulia/argus` vs `main`):")
    println(io, judge(median(b_argus), median(b_main)))
    # Clean up.
    run(`$git worktree remove ../main-with-modified-tests`)

    return nothing
end

function benchmark_branch(branch_path::String=pwd())
    # Save current directory so we can get back to it.
    current_dir = pwd()
    # Switch to `branch_path` and run the benchmark there.
    cd(branch_path)
    @eval using ReLint
    b = redirect_stdout(devnull) do
        @benchmark ReLint.run_lint(RAICODE_DIR)
    end
    # Return to the original directory.
    cd(current_dir)

    return b
end

run_benchmarks()
