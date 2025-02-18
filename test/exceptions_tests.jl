@testset "Exception-related rules" begin
    @testset "Eliminate unnecessary rethrow(e)" begin
        source = raw"""
            function f()
                try
                    print("Hello")
                catch e
                    print("World")
                    # error handling code / error logging
                    rethrow(e)
                end
            end
            """
        @test count_lint_errors(source) == 1
        @test lint_test(source, "Line 2, column 5: Change `rethrow(e)` into `rethrow()`.")
    end

    @testset "Acceptable rethrow 1" begin
        source = raw"""
            function f()
                try
                    print("Hello")
                catch e
                    print("World")
                    e2 = Exception("Error")
                    # error handling code / error logging
                    rethrow(e2)
                end
            end
            """
        # @test count_lint_errors(source) == 0
        @test lint_test(source, "Lined 2, column 5: Change `rethrow(e)` into `rethrow()`.")

    end

    @testset "Acceptable rethrow 2" begin
        source = raw"""
            function f()
                try
                    print("Hello")
                catch e
                    print("World")
                    e2 = Exception("Error")
                    # error handling code / error logging
                    rethrow()
                end
            end
            """
        # @test count_lint_errors(source) == 0
        @test lint_test(source, "Lined 2, column 5: Change `rethrow(e)` into `rethrow()`.")

    end
end