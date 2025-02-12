@testset "Lint context" begin
    using ReLint: LintContext, UseOfStaticThreads, LogStatementsMustBeSafe, UnsafeRule

    @testset "Basic" begin
        @test isempty(LintContext(DataType[]).rules_to_run)

        dts = DataType[UseOfStaticThreads, LogStatementsMustBeSafe]
        c = LintContext(dts)
        @test length(c.rules_to_run) == 2
        @test c.rules_to_run == dts

        dts_as_string = ["UseOfStaticThreads", "LogStatementsMustBeSafe"]
        c = LintContext(dts_as_string)
        @test length(c.rules_to_run) == 2
        @test c.rules_to_run == dts

        @test iszero(LintContext([]).rules_to_run)

        c = LintContext(["LogStatementsMustBeSafe"])
        @test !isnothing(c.global_markers)
        @test !isnothing(c.local_markers)
        @test isempty(c.global_markers)
        @test isempty(c.local_markers)
    end

    @testset "Non-existing rule" begin
        dts_as_string = ["UseOfStaticThreads", "LogStatementsMustBeSafe", "DoesNotExist"]
        @test_throws ErrorException LintContext(dts_as_string)
    end

    @testset "Setting context or not" begin
        source = """
            function f()
                _unsafe_g()
            end

            function _unsafe_g()
                return 42
            end
            """
        @test count_lint_errors(source) == 1
        @test count_lint_errors(source; context=LintContext()) == 1
        @test count_lint_errors(source; context=LintContext([])) == 0
        @test count_lint_errors(source; context=LintContext([LogStatementsMustBeSafe])) == 0
        @test count_lint_errors(source; context=LintContext([UnsafeRule])) == 1

        isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        @test count_lint_errors(source; context=LintContext(["LogStatementsMustBeSafe"])) == 0
        @test count_lint_errors(source; context=LintContext(["UnsafeRule"])) == 1
    end

    @testset "File in a dir" begin
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io
                write(io, "function f()\n  @async 1 + 1\nend\n")
                flush(io)

                @test has_values(ReLint.run_lint(dir; io), 1, 1, 0)

                context=LintContext([])
                @test has_values(ReLint.run_lint(dir; io, context), 1, 0, 0)

            end
        end
    end
end