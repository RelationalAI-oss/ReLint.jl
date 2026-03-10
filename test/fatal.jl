@testset "Fatal violations" begin

    @testset "`@generated`" begin
        source = """
        @generated function _empty_vector(::Type{T}) where {T}
            vec = T[]
            return vec
        end

        let x = y
            @generated f(z) = z
            f(x)
        end
        """

        @test lint_has_error_test(source)
        @test lint_test(source,
           "Line 1, column 1: `@generated` should be used with extreme caution.")
        @test lint_test(source,
           "Line 7, column 5: `@generated` should be used with extreme caution.")
    end

    @testset "Unsafe logging" begin
        let
            source = raw"""
            function f()
                @info "Unsafe logging $(x)"
                @info @safe("Unsafe logging") job
                @info @safe("Unsafe logging") my_value=job
                @info @safe("Unsafe logging") my_value=@safe(job) my_value2=job
                @info @safe("Unsafe logging") my_value=@safe(job) my_value=@safe(job2) my_value=@safe(job3) "$(x)"
                @info @safe("Unsafe logging") my_value=@safe(job) my_value=@safe(job2) my_value=@safe(job3) "$(x)"
                @debug_connection @safe("Unsafe logging") my_value=@safe(job) my_value=@safe(job2) my_value=@safe(job3) "$(x)"
                @warn_with_current_exceptions_safe_to_log @safe("Unsafe logging") my_value=@safe(job) my_value=@safe(job2) my_value=@safe(job3) "$(x)"
                @info "Unsafe logging"
                @info "Unsafe logging" my_value=@safe(job)
                @info "Unsafe logging" my_value=@safe(job) my_value=@safe(job2)
                @info "Unsafe logging" my_value=@safe(job) my_value=@safe(job2) my_value=@safe(job3)

                @info @safe("Safe logging $(x)")
                @info @safe("Safe logging")

                @warnv 1 @safe("Safe logging")

                @warnv 1 @safe("Safe logging with non-common literals") 0x12 'c' 0b0 0o0

                @infov 1 @safe(
                         "[Compilation] \
                         Creating a new BeTreeV2 specialization: $(K) and $(V) where eps = $(E) \n\
                         List of all encountered types so far \
                         (total: $(length(UNIQUE_BETREE_TYPES))): \n\
                         $(total_report)"
                     ) total = @safe(length(UNIQUE_BETREE_TYPES))

                @warnv(
                    0,
                    @safe("Precompiling: parse error: $(e)"),
                    precompile_statement=@safe(repr(statement)),
                    # Log the message that the exception would print, else JSONLogger logs each of
                    # the fields of the exception separately which is much less useful.
                    exception=@safe(sprint(showerror, e)),
                    maxlog=100,
                )
            end
            """
            @test count_lint_errors(source) == 12
            for line in 2:count_lint_errors(source) + 1
                @test lint_test(source, "Line $(line), column 5: Unsafe logging statement. You must enclose variables and strings with `@safe(...)`.")
            end
        end
        let
            source = raw"""
            macro foo()
                @info @safe("error_msg")
            end

            macro foo()
                @info $SafeLogging.@safe("error_msg")
            end
            """
            @test count_lint_errors(source) == 0
        end
    end

    @testset "Unsafe assertion" begin
        let
            source = raw"""
            function f()
                @assert 1 ==1 "this is an unsafe assertion"
                @assert 1 ==1 @safe("this is a safe assertion")
                @dassert3 1 == 1 # Okay
                @dassert3 1 == 1 "not okay"
                @dassert3 1 == 1 @safe("Okay")
            end
            """
            @test count_lint_errors(source) == 2
        end
        let
            source = raw"""
            macro spawn_periodic_task(name, period, expr, ending_expr=nothing)
                error_msg = "Periodic task name must be `@safe(\\\"name\\\")`, so it can be logged: $(__source__)"
                @dassert0 is_safe_expr_literal(name) @safe(error_msg)

                return quote
                    n = $(esc(name))
                    p = $(esc(period))
                    # And therefore n is safe to log.
                    @dassert0 n isa $SafeLoggable $SafeLogging.@safe($(error_msg))
                    n = string(n)
                end
            end
            """
            @test count_lint_errors(source) == 0
        end
    end

    @testset "`@show`" begin
        source = """
        function f()
            @show "foo"
            @show 1 + 1
        end
        """
        @test count_lint_errors(source) == 2
        @test lint_test(source,
                        "Line 2, column 5: Do not use `@show`, use `@info` instead.")
        @test lint_test(source,
                        "Line 3, column 5: Do not use `@show`, use `@info` instead.")
    end

    @testset "`@noinline` with non-literal/identifiers" begin
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
            @noinline get_page(pager, magic, pid; is_prefetch=check())
            @noinline get_page(pager, magic, pid; is_prefetch=1 + 2)
        end

        function without_errors()
            @noinline g(x)
            @noinline g(1, 2, 3, "abc", 'a')
            @noinline 1 + 1
            @noinline x[1]
            @noinline get_page(pager, magic, pid; is_prefetch=true)
            @noinline get_page(pager, magic, pid; is_prefetch=false)
            @noinline get_page(pager, magic, pid; is_prefetch)

            # lint-disable-next-line: Splatting (`...`)
            @noinline foo(x...)
            # lint-disable-next-line: Splatting (`...`)
            @noinline foo(x, y...)
            # lint-disable-next-line: Splatting (`...`)
            @noinline foo(x; kws...)
        end

        @noinline function no_error(x::Int=y.a)
            (@noinline dv_isgreater(seek_key, upper_bounds)) && return false, i
            return 42
        end

        @noinline foo() = 42
        @noinline bar(::Integer) = @assert false @safe("unreachable")
        @noinline _throw_empty_weight_list_exception() =
            throw(QueryEvaluatorInternalException(@safe("
                Adjacency matrix materialization within a graph primitive assumes a \
                non-empty weight list. For this exception to fire, some inconsistency must \
                have existed between the weight list and node and/or edge counts passed \
                to a graph primitive."
            )))

        @noinline get_page(pager, magic, pid; is_prefetch)

        """

        @test count_lint_errors(source) == 11
        @test lint_test(source, "Line 2, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 3, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 4, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 5, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 6, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 7, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 8, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 9, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 10, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 11, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
        @test lint_test(source, "Line 12, column 5: For call-site `@noinline` call, all args must be literals or identifiers only. Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).")
    end

    @testset "Return in anonymous functions" begin

        let
            source = raw"""
            function foo(f)
                f()
                return "foo"
            end

            foo(() -> begin return "anonymous function" end)
            foo() do ; return "anonymous function" end
            foo() do
                return "anonymous function"
            end

            macro bar(x)
                return :(($(x))())
            end
            @bar(() -> begin return "anonymous function" end)
            @bar() do
            return "blah"
            end
            @bar() do ; return "blah" end
            """
            @test count_lint_errors(source) == 6
            @test lint_test(source,
                            "Line 6, column 5: Anonymous function must not have `return` [Explanation](https")
            @test lint_test(source,
                            "Line 7, column 1: Anonymous function must not have `return` [Explanation](https")
            @test lint_test(source,
                            "Line 8, column 1: Anonymous function must not have `return` [Explanation](https")
            @test lint_test(source,
                            "Line 15, column 6: Anonymous function must not have `return` [Explanation](https")
            @test lint_test(source,
                            "Line 16, column 1: Anonymous function must not have `return` [Explanation](https")
            @test lint_test(source,
                            "Line 19, column 1: Anonymous function must not have `return` [Explanation](https")
        end
        let
            source = """
            @bar(() -> begin "anonymous function" end)
            function f()
                return 12
            end
            """
            @test count_lint_errors(source) == 0
        end
    end

end
