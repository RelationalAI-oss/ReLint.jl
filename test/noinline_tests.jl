@testset "Noinline" begin
    using ReLint

    source = raw"""
        function with_errors()
            @noinline g(x.a)
            @noinline g("$(x)")
            @noinline h(g(x))
            @noinline i(1 + 2)
            @noinline h(x) + 1
            @noinline @eval 1 + 1
            @noinline g(x[1])
            @noinline g(x[:a])
            @noinline (1:10) .+ 4
        end

        function without_errors()
            @noinline g(x)
            @noinline g(1, 2, 3, "abc", 'a')
            @noinline 1 + 1
            @noinline x[1]
        end

        @noinline function no_error(x::Int=y.a)
            (@noinline dv_isgreater(seek_key, upper_bounds)) && return false, i
            return 42
        end
        """

    @test count_lint_errors(source) == 9
    @test lint_test(source, "Line 2, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 3, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 4, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 5, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 6, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 7, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 8, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 9, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    @test lint_test(source, "Line 10, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
end
