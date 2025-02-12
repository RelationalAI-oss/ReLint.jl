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

    end
end
