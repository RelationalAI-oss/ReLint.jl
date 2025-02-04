@testset "Lint context" begin
    using StaticLint: LintContext, UseOfStaticThreads, LogStatementsMustBeSafe, UnsafeRule

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

        @test count_lint_errors(source; context=LintContext(["LogStatementsMustBeSafe"])) == 0
        @test count_lint_errors(source; context=LintContext(["UnsafeRule"])) == 1
    end
end