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
            context = ReLint.LintContext([ReLint.VIOLATIONS["array with no specific type"]])
            count_errors = count_lint_errors(source; directory = "src/Compiler/", context)
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

    @testset "in, equal, haskey, uv_" begin
        source = """
            function f()
                x = 10 in [10]
                y = in(10, [10])
                z = equal(10, "hello")
                w = haskey(Dict(1=>1000), 1)
                a = uv_foo(10, 20)
                b = ∈(10, [10])
                c = 10 ∈ [10]

                # No error
                d = [x for x in 1:10]
                groupby_vars = [v for v in child_vars if !tin(v, sort_input.vars)]
            end
            """
        @test count_lint_errors(source) == 7
        @test lint_test(source,
                        """
                        Line 2, column 9: Use `tin(item,collection)` instead of \
                        the Julia's `in`""")
        @test lint_test(source,
                        """
                        Line 3, column 9: Use `tin(item,collection)` instead of \
                        the Julia's `in`""")
        @test lint_test(source,
                        """
                        Line 4, column 9: Use `tequal(dict,key)` instead of the \
                        Julia's `equal`.""")
        @test lint_test(source,
                        """
                        Line 5, column 9: Use `thaskey(dict,key)` instead of the \
                        Julia's `haskey`.""")
        @test lint_test(source,
                        """
                        Line 6, column 9: `uv_` functions should be used with \
                        extreme caution.""")
        @test lint_test(source,
                        """
                        Line 7, column 9: Use `tin(item,collection)` instead of \
                        the Julia's `in` or `∈`.""")
        @test lint_test(source,
                        """
                        Line 8, column 9: Use `tin(item,collection)` instead of \
                        the Julia's `in` or `∈`.""")
    end

    @testset "Unreachable branch" begin
        let
            source = """
            function f(x)
                if x == 1
                    return 12
                elseif x== 2
                    return "Reachable_branch"
                end
            end
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            function f(x)
                if x == 1
                    return 12
                elseif x== 1
                    return "Unreachable_branch"
                end
            end
            """
            @test lint_test(source, "Line 2, column 5: Unreachable branch.")
        end
        let
            source = """
            function f(x)
                if x <= 1
                    return 12
                elseif x <= 1
                    return "Unreachable_branch"
                end
                if x <= 1
                    return 12
                elseif x
                    if cond1
                       body1
                    elseif cond2
                       body2
                    elseif cond1
                        body3
                    else
                        body4
                    end
                end
            end
            """
            @test count_lint_errors(source) == 2
            @test lint_test(source, "Line 2, column 5: Unreachable branch.")
            @test lint_test(source, "Line 10, column 9: Unreachable branch.")
        end
    end

    @testset "String interpolation" begin
        source_with_error = raw"""
        @INFO "($a.b.c)"
        @INFO "$a.b.c"
        @INFO "this string contains an error $a.b indeed!"
        @INFO "this string contains an error $a .b.c indeed!"
        @INFO "Test $test..."
        Bla("bla/$blu",  read(joinpath(@__DIR__, "bla", "$blu.bli"), String))
        path = "$dir/$name.csv"
        cmd = `bla $blu bli`
        """
        @test count_lint_errors(source_with_error) == 10
        @test lint_test(source_with_error, raw"Line 1, column 7: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 2, column 7: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 3, column 7: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 4, column 7: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 5, column 7: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 6, column 5: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 6, column 49: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 7, column 8: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 7, column 8: Use $(x) instead of $x.")
        @test lint_test(source_with_error, raw"Line 8, column 7: Use $(x) instead of $x.")

        source_without_error = raw"""
        @INFO "$(a.b.c)"
        @INFO "this string contains an error $(a.b.c) indeed!"
        f = "bla-$(blu).pb.gz"
        cmd = `bla $(blu) bli`
        """
        @test count_lint_errors(source_without_error) == 0
    end

    @testset "RelPath front-end" begin
        source = """
        function rel_sig_from_relpath(path)
            (name, types) = split_path(path)
            return RelationSignature(name, types.elements)
        end

        function interpret(x, y, path)
            rest = drop_first(path)
            return RelPath(rest.elements[2:end])
        end

        function reverse(decl::EdbDecl)
            return relpath_from_signature(decl.signature)
        end

        function use_path(x, y::RelPath, z)
            return y.elements
        end
        """

        @test count_lint_errors(source; directory="/src/Compiler/Front") == 5
        @test count_lint_errors(source; directory="") == 0

        @test lint_test(source,
                        """
                        Line 2, column 21: Usage of `RelPath` API method `split_path` is \
                        not allowed in this context.""";
                        directory="/src/Compiler/Front")
    end

    @testset "Use of static threads" begin
        source = raw"""
        function f()
            Threads.@threads :static for _ in 1:10
                println("foo")
            end

            @threads :static for _ in 1:10
                println("foo")
            end

            Threads.@threads :dynamic for _ in 1:10
                println("foo")
            end
        end
        """
        @test lint_test(source,
                        """
                        Line 2, column 5: Use `Threads.@threads :dynamic` instead of \
                        `Threads.@threads :static`.""")
        @test lint_test(source,
                        """
                        Line 6, column 5: Use `Threads.@threads :dynamic` instead of \
                        `Threads.@threads :static`.""")
    end

    @testset "Forbid import" begin
        source = """
        import foobar
        import M: a
        import N: a, b

        using M: a
        """
        @test count_lint_errors(source) == 3
    end

    @testset "Forbid using RAICode" begin
        source = """
        using RAICode
        using RAICode: rai_rules_tests

        println("hello world")
        """
        @test count_lint_errors(source) == 3  # One extra from base `using`.
    end

    @testset "Forbid bare using" begin
        let
            source = """
            using LinearAlgebra
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            """
                            Line 1, column 1: Use `using Foo: Foo` or \
                            `using Foo: specific_function` instead of bare `using Foo`.""")
        end
        let
            source = """
            using Statistics
            using LinearAlgebra
            """
            @test count_lint_errors(source) == 2
            @test lint_test(source,
                            """
                            Line 1, column 1: Use `using Foo: Foo` or \
                            `using Foo: specific_function` instead of bare `using Foo`.""")
            @test lint_test(source,
                            """
                            Line 2, column 1: Use `using Foo: Foo` or \
                            `using Foo: specific_function` instead of bare `using Foo`.""")
        end
        let
            source = """
            using LinearAlgebra: LinearAlgebra
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            using Statistics: mean, std
            using LinearAlgebra: norm, dot
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            using LinearAlgebra
            using Statistics: mean, std
            using Base: show
            """
            @test count_lint_errors(source) == 1
            @test lint_test(source,
                            """
                            Line 1, column 1: Use `using Foo: Foo` or \
                            `using Foo: specific_function` instead of bare `using Foo`.""")
        end
        let
            source = """
            using Test
            using LinearAlgebra
            """
            # Note: This will only pass when running on a file with "test" in the path
            @test !lint_has_error_test(source; directory = "test/")
        end
    end

    @testset "Untyped array comprehensions" begin
        let
            source = """
            function f()
                x = [i for i in 1:10]
                return x
            end
            """
            @test lint_test(source,
                            "Line 2, column 9: Need a specific Array type to be provided.";
                            directory = "src/Compiler/")
        end
        let
            source = """
            function f()
                x = Int[i for i in 1:10]
                return x
            end
            """
            @test count_lint_errors(source; directory = "src/Compiler/") == 0
        end
        let
            source = """
            function f()
                x = [i for i in 1:10]
                return x
            end
            """
            @test count_lint_errors(source; directory = "src/Other/") == 0
        end
        let
            source = """
            function f()
                x = [i for i in 1:10]
                y = String[string(i) for i in 1:10]
                return (x, y)
            end
            """
            @test count_lint_errors(source; directory = "src/Compiler/") == 1
            @test lint_test(source,
                            "Line 2, column 9: Need a specific Array type to be provided.";
                            directory = "src/Compiler/")
        end
    end

    @testset "Non-const untyped global variables" begin
        let
            source = """
            global counter = 0
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 1, column 1: Global variable must have type annotation")
        end
        let
            source = """
            const global MAX_SIZE = 100
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            function f()
                x = 10
                return x
            end
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            global x = 1
            global y = 2
            const z = 3
            const global q = 3
            global yy::Int = 2
            """
            @test count_lint_errors(source) == 2
            @test lint_test(source,
                            "Line 1, column 1: Global variable must have type annotation")
            @test lint_test(source,
                            "Line 2, column 1: Global variable must have type annotation")
        end
    end

    @testset "NotFullyParameterizedConstructorRule" begin
        let
            source = """
            function process(columns_list)
                results = []
                for columns in columns_list
                    push!(results, ColumnarVector(columns))
                end
                return results
            end
            """
            @test lint_test(source,
                            """
                            Line 4, column 24: \
                            Avoid not-fully-parameterized constructor in loops""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function process(data_list)
                outputs = []
                for data in data_list
                    push!(outputs, Vector(data))
                end
                return outputs
            end
            """
            @test lint_test(source,
                            """
                            Line 4, column 24: \
                            Avoid not-fully-parameterized constructor in loops""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function build_dicts(items)
                results = []
                i = 1
                while i <= length(items)
                    push!(results, Dict(items[i]))
                    i += 1
                end
                return results
            end
            """
            @test lint_test(source,
                            """
                            Line 5, column 24: \
                            Avoid not-fully-parameterized constructor in loops""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function process(columns_list)
                results = Vector{ColumnarVector{Int,Vector{Int}}}()
                for columns in columns_list
                    push!(results, ColumnarVector{Int,Vector{Int}}(columns))
                end
                return results
            end
            """
            @test !lint_has_error_test(source; directory="src/Compiler/")
        end
        let
            source = """
            function process(columns_list)
                results = Any[]
                for columns in columns_list
                    push!(results, make_columnar_vector(columns))
                end
                return results
            end
            """
            @test !lint_has_error_test(source; directory="src/Compiler/")
        end
        let
            source = """
            function process(columns)
                return ColumnarVector(columns)
            end
            """
            @test !lint_has_error_test(source; directory="src/Compiler/")
        end
        let
            source = """
            function process(columns_list)
                results = T[]
                for columns in columns_list
                    push!(results, ColumnarVector(columns))
                end
                return results
            end
            """
            # Should not trigger outside src/Compiler/.
            @test !lint_has_error_test(source; directory="src/API/")
        end
        let
            source = """
            function process(items)
                results = Any[]
                for item in items
                    push!(results, process_item(item))
                end
                return results
            end
            """
            @test !lint_has_error_test(source; directory="src/Compiler/")
        end
    end

    @testset "TODO comments" begin
        context = ReLint.LintContext([ReLint.VIOLATIONS["TODO"]])
        @test lint_test("function f()\n # TODO (PR): fix this\n end",
                        """
                        Line 2, column 2: Use `TODO (RAI-XXXXX)` instead of `TODO` \
                        to refer to a Jira issue.""";
                        context)
        @test lint_test("function f()\n # TODO: fix this\n end",
                        """
                        Line 2, column 2: Use `TODO (RAI-XXXXX)` instead of `TODO` \
                        to refer to a Jira issue.""";
                        context)
        @test lint_test("function f()\n @info \"zork\" # TODO fix this\n end",
                        """
                        Line 2, column 15: Use `TODO (RAI-XXXXX)` instead of `TODO` \
                        to refer to a Jira issue.""";
                        context)

        @test !lint_has_error_test("function f()\n # TODO (RAI-121) okay\n end")
        @test !lint_has_error_test("function f()\n # fix this\n end"; context)
    end

end
