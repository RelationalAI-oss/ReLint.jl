@testset "Recommendations" begin

    @testset "ccall" begin
        source = """
        function bla(x::T = DEFAULT)
            y = 1
            ccall(:bla, Cint, (Cint, Ptr{Cvoid}), x, y)
            ccall(:jl_print_task_backtraces, Cvoid, ())
            return x
        end
        """
        @test count_lint_errors(source) == 2
        @test lint_test(source,
                        "Line 3, column 5: `ccall` should be used with extreme caution.")
        @test lint_test(source,
                        "Line 4, column 5: `ccall` should be used with extreme caution.")
    end

    @testset "finalizer" begin
        let
            source = """
            function f(x)
                ref = Ref(1)
                x = ___MutableFoo(ref)
                finalizer(x) do x
                    ref[] = 3
                end
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 4, column 5: `finalizer(_,_)` should not be used.")

        end
        let
            source = """
            function f(x)
                finalizer(q->nothing, x)
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 2, column 5: `finalizer(_,_)` should not be used.")
        end
        let
            source = """
            finalizer("hello") do x
                println("hello ")
                println("world")
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 1, column 1: `finalizer(_,_)` should not be used.")
        end
    end

    @testset "@cfunction" begin
        source = """
        function f()
            @cfunction(_readwrite_cb, Cvoid, (Ptr{Cvoid}, ))
        end
        """
        @test lint_has_error_test(source)
        @test lint_test(source,
                        "Line 2, column 5: `@cfunction` should not be used.")
    end

    @testset "unlock, yield, sleep" begin
        source = """
            function wait_for_cooldown(count::UInt64, counts::HistogramCounts)
                while count != @atomic counts.total_observations
                    yield()
                    sleep(0.011)
                end
                unlock(bla)
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
                        "Line 3, column 9: `yield` should be used with extreme caution.")
        @test lint_test(source,
                        "Line 4, column 9: `sleep` should be used with extreme caution.")
        @test lint_test(source,
                        "Line 6, column 5: `unlock` should be used with extreme caution.")
    end

    @testset "@inbounds, @threads, @sync" begin
        source = """
        function f()
            @inbounds begin
                at_end(iter) && return 0
                i = 1
                while next!(iter)
                    i += 1
                end
                return i
            end
            Threads.@threads for (e, v) in slots
                @test e[] == v
                free_slot!(pool, Blob{Nothing}(e))
            end
            try
                @sync begin
                    bla
                end
            catch
                Threads.@sync begin
                    1 + 2
                end
                nothing
            end
        end
        """
        @test lint_test(source,
                        """
                        Line 2, column 5: `@inbounds` should be used with extreme \
                        caution.""")
        @test lint_test(source,
                        """
                        Line 10, column 5: `@threads` should be used with extreme \
                        caution.""")
        @test lint_test(source,
                        """
                        Line 15, column 9: `@sync` should be used with extreme \
                        caution.""")
        @test lint_test(source,
                        """
                        Line 19, column 9: `@sync` should be used with extreme \
                        caution.""")
    end

    @testset "Splatting" begin
        @test lint_test("f(x...) + 10",
                        """
                        Line 1, column 1: Splatting (`...`) should be used with extreme \
                        caution. Splatting from dynamically sized containers could result \
                        in severe performance degradation.""")

        @test lint_test("hcat([f(x) for x in r]...)",
                        """
                        Line 1, column 1: Splatting (`...`) should be used with extreme \
                        caution. Splatting from dynamically sized containers could result \
                        in severe performance degradation.""")

        source = raw"""
        macro infov(verbosity::Int64, msg, exs...)
            return quote
                if $(esc(:($DebugLevels.@should_emit_log($Logging.Info, $verbosity))))
                    $(Base.CoreLogging.logmsg_code((Base.CoreLogging.@_sourceinfo)..., :Info, msg, :(verbosity=$verbosity), exs...))
                end
            end
        end
        """
        @test count_lint_errors(source) == 0

        @test count_lint_errors("""macro foo(x...)\nzork(x...)\nend""") == 0
    end

    @testset "Return type annotations" begin
        @testset "function with return type annotation" begin
            source = """
            function foo(x::Int)::String
                return string(x)
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 1, column 1: Avoid return type annotations")
        end

        @testset "function without return type annotation is ok" begin
            source = """
            function foo(x::Int)
                return string(x)
            end
            """
            @test !lint_has_error_test(source)
        end

        @testset "multiple functions with annotations" begin
            source = """
            function foo(x::Int)::String
                return string(x)
            end

            function bar(y::Float64)::Int
                return round(Int, y)
            end

            function baz(z)
                return z + 1
            end
            """
            @test count_lint_errors(source) == 2
            @test lint_test(source,
                            "Line 1, column 1: Avoid return type annotations")
            @test lint_test(source,
                            "Line 5, column 1: Avoid return type annotations")
        end

        @testset "one-liner with return type" begin
            source = """
            foo(x::Int)::String = string(x)
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 1, column 1: Avoid return type annotations")
        end

        @testset "one-liner without return type" begin
            source = """
            foo(x::Int) = string(x)
            """
            @test !lint_has_error_test(source)
        end

        @testset "derived functions" begin
            source = """
            @derived v=1 function foo(x::Int)::String
                return string(x)
            end
            """
            @test !lint_has_error_test(source)
        end
    end

    @testset "String concatenation with *" begin
        let
            source = """
            function f()
                x = "hello" * " world"
                return x
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 2, column 9: Prefer string interpolation")
        end
        let
            source = """
            function f(name)
                msg = "Hello " * name
                return msg
            end
            """
            @test lint_has_error_test(source)
            @test lint_test(source,
                            "Line 2, column 11: Prefer string interpolation")
        end
        let
            source = raw"""
            function f(name)
                msg = "Hello $(name)"
                return msg
            end
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            function f(x, y)
                msg = string(x, y)
                return msg
            end
            """
            @test !lint_has_error_test(source)
        end
        let
            source = """
            function f()
                x = 2 * 3
                return x
            end
            """
            @test !lint_has_error_test(source)
        end
    end

    @testset "isnothing" begin
        let
            source = """
            function process(x)
                if isnothing(x)
                    return
                end
            end
            """
            @test count_lint_errors(source; directory="src/Bla/") == 0
            @test count_lint_errors(source; directory="src/Compiler/") == 1
            @test lint_test(source,
                            """
                            Line 2, column 8: In performance-critical code, prefer \
                            `x === nothing`""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function process(x)
                if x === nothing
                    return
                end
            end
            """
            @test count_lint_errors(source; directory="src/Compiler/") == 0
        end
    end

    @testset "ClosureCaptureByValueRule" begin
        let
            source = """
            function outer(x)
                inner() = x + 1
                return inner()
            end
            """
            @test lint_test(source,
                            """
                            Line 2, column 5: Nested function may capture variables \
                            by reference""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function create_adder(n)
                adder = x -> x + n
                return adder
            end
            """
            @test lint_test(source,
                            """
                            Line 2, column 13: Nested function may capture variables \
                            by reference""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function process(data)
                map(data) do item
                    item * 2
                end
            end
            """
            @test lint_test(source,
                            """
                            Line 2, column 5: Nested function may capture variables \
                            by reference""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function outer(x, y)
                function inner(z)
                    return x + y + z
                end
                return inner(10)
            end
            """
            @test lint_test(source,
                            """
                            Line 2, column 5: Nested function may capture variables \
                            by reference""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function main(x)
                f = () -> x + 1
                if x < 0
                    x = -x
                end
                return f()
            end
            """
            @test lint_test(source,
                            """
                            Line 2, column 9: Nested function may capture variables \
                            by reference""";
                            directory="src/Compiler/")
        end
        let
            source = """
            function outer(n)
                add_n = x -> x + n
                multiply_n = x -> x * n
                return add_n(5) + multiply_n(3)
            end
            """
            @test count_lint_errors(source; directory="src/Compiler/") == 2
        end
        let
            source = """
            function outer(x)
                inner() = x + 1
                return inner()
            end
            """
            @test !lint_has_error_test(source; directory="src/API/")
        end
        let
            source = """
            function standalone(x)
                return x + 1
            end
            """
            @test !lint_has_error_test(source; directory="src/Compiler/")
        end

        let
            source = """
            function outer(items)
                return map(process_item, items)
            end
            """
            @test !lint_has_error_test(source; directory="src/Compiler/")
        end
        let
            source = """
            function main(x)
                f = let x = x
                    () -> x + 1
                end
                if x < 0
                    x = -x
                end
                return f()
            end
            """
            @test !lint_has_error_test(source; directory="src/Compiler/")
        end
    end

    @testset "Mutating ENV" begin
        let
            source = raw"""
            function f(name)
                println("Env var: ", ENV["HOME"])
            end
            """
            @test !lint_has_error_test(source)
        end
        let
            source = raw"""
            function f(name)
                ENV["HOME"] = "/tmp"
                push!(ENV, "NEW_VAR" => "value")
                delete!(ENV, "HOME")
                setindex!(ENV, "/tmp", "HOME")
                get!(ENV, "/tmp", "HOME")
                pop!(ENV, "HOME")
            end
            """
            @test count_lint_errors(source) == 6
        end
    end

end
