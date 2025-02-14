using ReLint: require_pass, pass_of, LogStatementsMustBeSafe, UnusedFunction

@testset "Pass" begin
    @testset "Basic properties of passes" begin
        @test !require_pass(LogStatementsMustBeSafe())
        @test require_pass(UnusedFunction())
        @test pass_of(UnusedFunction()) == :global
    end

    @testset "Unused function" begin
        source = """
            # unused function
            function f()
                @async 1 + 2
            end

            # unused function
            g() = 42

            # used function
            h() = 12

            # unused function
            zork() = h() + 1
            """
        context = LintContext()

        @test isempty(context.global_markers)
        result = run_lint_on_text(source; context)

        @test haskey(context.passes, UnusedFunction)
        @test context.passes[UnusedFunction] == :global

        @test haskey(context.global_markers, :defined_function)

        defined_functions = context.global_markers[:defined_function]
        @test !isempty(defined_functions)

        for x in ["f"]
            @test x in defined_functions
        end
    end
end
