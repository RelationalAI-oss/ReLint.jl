@testset "Noinline" begin
    using ReLint

    source = raw"""
        function with_errors()
            @noinline g(x.a)
            @noinline g("$(x)")
            @noinline h(g(x))
            @noinline i(1 + 2)
        end

        function without_errors()
            @noinline g(1, 2, 3, "abc", 'a')
        end
        """
    @test count_lint_errors(source) == 4
    @test lint_test(source, "Line 2, column 5: `@noinline` must be used with literals only.")
    @test lint_test(source, "Line 3, column 5: `@noinline` must be used with literals only.")
    @test lint_test(source, "Line 4, column 5: `@noinline` must be used with literals only.")
    @test lint_test(source, "Line 5, column 5: `@noinline` must be used with literals only.")
end