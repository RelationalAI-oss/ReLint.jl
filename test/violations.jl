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

    @testset "Array with no specific type" begin
        let
            source = """
            function f()
                x = []
                y = String[]
                return vcat(x, y)
            end
            """
            # No error because this tmp file is not in the src/Compiler
            @test !lint_has_error_test(source)
        end

        let
            source = """
            function f()
                x = []
                y = String[]
                return vcat(x, y)
            end
            """
            @test lint_test(
                source,
                "Line 2, column 9: Need a specific Array type to be provided.",
                directory = "src/Compiler/")
        end

        let
            source = """
            function f()
                @matchrule bindings_empty() =
                    Bindings([], _::Missing) => CoreBindings([])

                @matchrule and_to_true() =
                    And([], annos) => BoolConstant(true, annos)

                @matchrule and_singleton() =
                    And([f], annos) => f

                @match CoreRelAbstract(bs2, [], as2) = e2

                @matchrule and_to_true() =
                    And([], annos) => BoolConstant(true, annos)

                @matchrule exists_empty() =
                    Exists(e, _) where is_definitely_empty_expr(e) =>
                        slice_to_false(input_val)
                f = []
            end
            """
            count_errors = count_lint_errors(source; directory = "src/Compiler/")
            @test count_errors == 1
            @test lint_test(
                source,
                "Line 19, column 9: Need a specific Array type to be provided.";
                directory = "src/Compiler")
        end
    end

end
