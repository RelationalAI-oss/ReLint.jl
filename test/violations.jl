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

    @testset "`remove_page`" begin
        source = """
        function _clear_pager!(pager)
            for (pid, _) in pager.owned_pages
                remove_page(pager, pid)
            end
        end
        """
        @test lint_test(source,
                        """
                        Line 3, column 9: \
                        `remove_page` should be used with extreme caution.""")
    end

    @testset "`Task`" begin
        source = """
        function foo()
            ch1 = Channel()
            ch2 = Channel(10)

            a() = sum(i for i in 1:1000);
            b = Task(a);

            return (ch1, ch2)
        end
        """
        @test lint_test(source,
                        "Line 6, column 9: `Task` should be used with extreme caution.")
    end

    @testset "`ErrorException`" begin
        source = """
        function foo()
            ch1 = Channel()
            ch2 = Channel(10)

            a() = sum(i for i in 1:1000);

            e = ErrorException("failure")
            return (ch1, ch2)
        end

        function bar(x)
            throw(ErrorException("My error"))
        end
        """
        @test lint_test(source,
                        """
                        Line 7, column 9: \
                        Use custom exception instead of the generic `ErrorException`.""")
        @test lint_test(source,
                        """
                        Line 12, column 11: \
                        Use custom exception instead of the generic `ErrorException`.""")
    end

    @testset "`error`" begin
        source = """
        bar() = error("My fault")
        """
        @test lint_test(source,
                        """
                        Line 1, column 9: \
                        Use custom exception instead of the generic `error()`.""")
    end

    @testset "`unsafe_` functions" begin
        
        let
            source = """
            function unsafe_f()
                unsafe_g()
            end

            function unsafe_g()
                return 42
            end
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            function f()
                unsafe_g()
            end

            function unsafe_g()
                return 42
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            """
                            Line 2, column 5: An `unsafe_` function \
                            should be called only from an `unsafe_` function.""")
        end
        let
            source = """
            function f()
                _unsafe_g()
            end

            function _unsafe_g()
                return 42
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            """
                            Line 2, column 5: An `unsafe_` function \
                            should be called only from an `unsafe_` function.""")
        end
        # TODO: Disabling.
        let
            source = """
            function f()
                # lint-disable-next-line
                _unsafe_g()
            end

            function _unsafe_g()
                return 42
            end
            """
            @test !lint_has_error_test(source)
        end
    end

end
