@testset "Lint context" begin
    using StaticLint: LintContext, UseOfStaticThreads, LogStatementsMustBeSafe

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
    end

    @testset "Non-existing rule" begin
        dts_as_string = ["UseOfStaticThreads", "LogStatementsMustBeSafe", "DoesNotExist"]
        @test_throws ErrorException LintContext(dts_as_string)
    end
end