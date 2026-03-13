@testset "Violations" begin

    @testset "`@async`" begin
        source = """
            function f()
                @async 1 + 2
            end

            function f()
                Threads.@async 1 + 2
            end
            """

        @test lint_has_error_test(source)
        @test count_lint_errors(source) == 2
        @test lint_test(source,
            "Line 2, column 5: Use `@spawn` instead of `@async`.")
        @test lint_test(source,
            "Line 6, column 5: Use `@spawn` instead of `@async`.")
    end

    @testset "Initializing with function" begin
        let
            source = """
                const x = Threads.nthreads()
                const y = Deployment.is_local_deployment()
                const z = is_local_deployment()
                const u = foo() # Allowed

                function f()
                    if Deployment.is_local_deployment()
                        print("It is all good!")
                    end
                    return x + Threads.nthreads()
                end
                """
            @test count_lint_errors(source) == 3
            @test lint_test(source,
                            "Line 1, column 1: `Threads.nthreads()` should not be used in a constant variable.")
            @test lint_test(source,
                            "Line 2, column 1: `is_local_deployment()` should not be used in a constant variable.")
            @test lint_test(source,
                            "Line 3, column 1: `is_local_deployment()` should not be used in a constant variable.")
        end
        let
            source = """
                function f()
                    return Threads.nthreads()
                end
                """
            @test !lint_has_error_test(source)
        end
    end

end
