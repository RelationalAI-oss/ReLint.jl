using StaticLint: StaticLint, run_lint_on_text, comp, convert_offset_to_line,
    convert_offset_to_line_from_lines, MarkdownFormat, PlainFormat,
    fetch_value, has_values

using StaticLint: LintResult
import CSTParser
using Test
using JSON3

# Reset the caches before running the tests.
StaticLint.reset_static_lint_caches()

function lint_test(source::String, expected_substring::String; verbose=true, directory::String = "")
    io = IOBuffer()
    run_lint_on_text(source; io, directory)
    output = String(take!(io))
    result = contains(output, expected_substring)
    if verbose && !result
        printstyled("EXPECTED:\n$(expected_substring)\n\n", color=:green)
        printstyled("OUTPUT:\n$(output)\n\n", color=:red)
    end
    return result
end

function count_lint_errors(source::String, verbose=false; directory::String = "")
    io = IOBuffer()
    run_lint_on_text(source; io, directory)
    result = String(take!(io))
    all_lines = split(result, "\n")

    verbose && @info result
    # We remove decorations
    return length(filter(l->startswith(l, "Line "), all_lines))
end


function lint_has_error_test(source::String, verbose=false; directory::String = "")
    io = IOBuffer()
    run_lint_on_text(source; io, directory)
    result = String(take!(io))
    all_lines = split(result, "\n")

    verbose && @info result
    # We remove decorations
    return any(l->startswith(l, "Line "), all_lines)
end

# FOR FUTURE WORK
# @testset "string interpolation" begin
#     source = raw"""$(@async 1 + 2)"""
#     @test lint_has_error_test(source)
# end

@testset "forbidden macros" begin
    @testset "@async 01" begin
        source = """
            function f()
                @async 1 + 2
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 5: Use `@spawn` instead of `@async`.")
    end

    @testset "@async 02" begin
        source = """
            function f()
                Threads.@async 1 + 2
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 5: Use `@spawn` instead of `@async`.")
    end

    @testset "@cfunction" begin
        source = """
            function f()
                @cfunction(_readwrite_cb, Cvoid, (Ptr{Cvoid}, ))
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 5: Macro `@cfunction` should not be used.")
    end

    @testset "@lock, @threads, @generated" begin
        source = """
        function mark_transaction_as_database_creation!(kv::SpcsKV, transaction_id::String)
            @lock kv.latch begin
                push!(kv.create_database_transactions, transaction_id)
            end


            Threads.@threads for (e, v) in slots
                @test e[] == v
                free_slot!(pool, Blob{Nothing}(e))
            end
            return nothing
        end

        @generated function _empty_vector(::Type{T}) where {T}
            vec = T[]
            return vec
        end

        try
            @sync begin
                @spawn_pager_bg_task RAI_PagerCore.add_to_cache!(conf, page)
                @span_no_threshold "eot_rootmarker_write_to_blob" write_marker_to_cloud(
                    conf, page, rootinfo
                )
            end
        catch
            Threads.@sync begin
                1 + 2
            end
            nothing
        end
        """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 5: `@lock` should be used with extreme caution")
        @test lint_test(source,
            "Line 7, column 5: `@threads` should be used with extreme caution.")
        @test lint_test(source,
           "Line 14, column 1: `@generated` should be used with extreme caution.")
        @test lint_test(source,
            "Line 20, column 5: `@sync` should be used with extreme caution.")
        @test lint_test(source,
            "Line 27, column 5: `@sync` should be used with extreme caution.")
    end
end

@testset "forbidden functions" begin
    @testset "Initializing a const variable with functions" begin
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
            "Line 1, column 11: `Threads.nthreads()` should not be used in a constant variable.")
        @test lint_test(source,
            "Line 2, column 11: `Deployment.is_local_deployment()` should not be used in a constant variable.")
        @test lint_test(source,
            "Line 3, column 11: `is_local_deployment()` should not be used in a constant variable.")
    end

    @testset "nthreads() not as a const" begin
        source = """
            function f()
                return Threads.nthreads()
            end
            """
        @test !lint_has_error_test(source)
    end

    @testset "finalizer with do-end" begin
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

    @testset "finalizer without do-end" begin
        source = """
            function f(x)
                finalizer(q->nothing, x)
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 5: `finalizer(_,_)` should not be used.")
    end

    @testset "finalizer with do-end 02" begin
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

    @testset "destructor with do-end 02" begin
        source = """
            destructor("hello") do x
                println("hello ")
                println("world")
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 1, column 1: Destructors should be used with extreme caution")
    end

    @testset "ccall" begin
        source = """
            function rusage(who:: RUsageWho = RUSAGE_SELF)
                ru = Vector{RUsage}(undef, 1)
                ccall(:getrusage, Cint, (Cint, Ptr{Cvoid}), who, ru)
                return ru[1]
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 3, column 5: `ccall` should be used with extreme caution.")
    end

    @testset "ccall 02" begin
        source = """
            function _pread_async!(fd::Integer, buffer::Ptr{UInt8}, count::Integer, offset::Integer)::UInt64
                uv_filesystem_request, uv_buffer_descriptor = _prepare_libuv_async_call(buffer, count)

                ccall(:uv_fs_read, Int32,
                            (Ptr{Cvoid}, Ptr{Cvoid}, Int32, Ptr{Cvoid}, UInt32, Int64, Ptr{Cvoid}),
                            Base.eventloop(), uv_filesystem_request, fd, uv_buffer_descriptor, UInt32(1), offset,
                            @cfunction(_readwrite_cb, Cvoid, (Ptr{Cvoid}, ))
                            )
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 4, column 5: `ccall` should be used with extreme caution.")
    end

    @testset "pointer_from_objref 01" begin
        source = """
            function f(x)
                return pointer_from_objref(v)
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 12: `pointer_from_objref` should be used with extreme caution.")
    end

    @testset "pointer_from_objref 02" begin
        source = """
            function _reinterpret_with_size0(::Type{T1}, value::T2; checked::Bool=true) where {T1<:Tuple,T2<:Tuple}
                checked && _check_valid_reinterpret_with_size0(T1, T2)
                v = Ref(value)
                GC.@preserve v begin
                    ptr = pointer_from_objref(v)
                    return Base.unsafe_load(reinterpret(Ptr{T1}, ptr))
                end
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 5, column 15: `pointer_from_objref` should be used with extreme caution.")
    end

    @testset "pointer_from_objref 03" begin
        source = raw"""
            function vertex_name(c::Any)
                return "v$(UInt64(pointer_from_objref(c)))"
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 23: `pointer_from_objref` should be used with extreme caution.")
    end

    @testset "Semaphore" begin
        source = """
            function foo()
                return Semaphore(10)
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 12: `Semaphore` should be used with extreme caution.")
    end

    @testset "ReentrantLock" begin
        source = """
            const lock = ReentrantLock()
            function foo()
                lock2 = ReentrantLock()
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 3, column 13: `ReentrantLock` should be used with extreme caution.")
        @test lint_test(source,
            "Line 1, column 14: `ReentrantLock` should be used with extreme caution.")
    end

    @testset "SpinLock" begin
        source = """
            struct _SyncDict{Dict}
                lock::Base.Threads.SpinLock
                dict::Dict

                function _SyncDict{Dict}() where {Dict}
                    new{Dict}(Base.Threads.SpinLock(), Dict())
                end
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 6, column 19: `SpinLock` should be used with extreme caution.")
    end

    @testset "unlock" begin
        source = """
            function clear(fs::SimulatedFs)
                if fs.noop_mode
                    return nothing
                end
                for partition in fs.partitions
                    lock = trylock(partition.lock)
                    lock || error("SimFs partition locked on clear")
                    for (k, entry) in partition.entries
                        lock = trylock(entry.lock)
                        lock || error("SimFs entry locked on clear")
                        Blobs.free(entry.buf.data)
                        unlock(entry.lock)
                    end
                    empty!(partition.entries)
                    unlock(partition.lock)
                end
                @atomic fs.used_bytes = 0
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 15, column 9: `unlock` should be used with extreme caution.")
    end

    @testset "yield, sleep, map, Future, wait" begin
        source = """
            function wait_for_cooldown(count::UInt64, counts::HistogramCounts)
                while count != @atomic counts.total_observations
                    yield()
                    sleep(0.011)
                end
            end

            function use_of_map()
                s = open("/tmp/mmap.bin")
                m = read(s, Int)
                n = read(s, Int)
                A2 = mmap(s, Matrix{Int}, (m,n))
                A3 = Mmap.mmap(s, Matrix{Int}, (m,n))
                fut1 = Future{Any}() do f nothing end
                fut2 = Future{Nothing}(()->nothing)
                fut3 = Future(()->nothing)

                wait(TaskTreeJoin())
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 3, column 9: `yield` should be used with extreme caution.")
        @test lint_test(source,
            "Line 4, column 9: `sleep` should be used with extreme caution.")
        @test lint_test(source,
            "Line 12, column 10: `mmap` should be used with extreme caution.")
        @test lint_test(source,
            "Line 13, column 10: `mmap` should be used with extreme caution.")
        @test lint_test(source,
            "Line 14, column 12: `Future` should be used with extreme caution.")
        @test lint_test(source,
            "Line 15, column 12: `Future` should be used with extreme caution.")
        @test lint_test(source,
            "Line 16, column 12: `Future` should be used with extreme caution.")
        @test lint_test(source,
            "Line 18, column 5: `wait` should be used with extreme caution.")
    end

    @testset "@inbounds, Atomic, Ptr, remove_page, Channel, ErrorException" begin
        source = """
            function f()
                fut = Future{Any}()
                r1 = fetch(fut)

                @inbounds begin
                    at_end(iter) && return 0
                    i = 1
                    set_from_tuple!(columns_tuple, 1, iter_tuple(iter))
                    while next!(iter) && i < cap
                        i += 1
                        set_from_tuple!(columns_tuple, i, iter_tuple(iter))
                    end
                    return i
                end
                num_created1 = Threads.Atomic{Int}(0);
                num_created2 = Atomic{Int}(0);
                num_created3 = Atomic(0);

                pointer(page) == Ptr{Nothing}(0) && return
            end

            function _clear_pager!(pager)
                for (pid, _) in pager.owned_pages
                    remove_page(pager, pid)
                end
            end

            function foo()
                ch1 = Channel()
                ch2 = Channel(10)

                a() = sum(i for i in 1:1000);
                b = Task(a);

                e = ErrorException("failure")
                return (ch1, ch2)
            end

            function bar(x)
                throw(ErrorException("My error"))
            end

            bar() = error("My fault")
            """

        @test lint_test(source, "Line 5, column 5: `@inbounds` should be used with extreme caution.")

        @test lint_test(source, "Line 15, column 20: `Atomic` should be used with extreme caution.")
        @test lint_test(source, "Line 16, column 20: `Atomic` should be used with extreme caution.")
        @test lint_test(source, "Line 17, column 20: `Atomic` should be used with extreme caution.")

        @test lint_test(source, "Line 19, column 22: `Ptr` should be used with extreme caution.")

        @test lint_test(source, "Line 24, column 9: `remove_page` should be used with extreme caution.")

        @test lint_test(source, "Line 29, column 11: `Channel` should be used with extreme caution.")
        @test lint_test(source, "Line 30, column 11: `Channel` should be used with extreme caution.")

        @test lint_test(source, "Line 33, column 9: `Task` should be used with extreme caution.")

        @test lint_test(source, "Line 40, column 11: Use custom exception instead of the generic `ErrorException`")
        @test lint_test(source, "Line 43, column 9: Use custom exception instead of the generic `error()`")

    end

    @testset "Array with no specific type 01" begin
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

    @testset "Array with no specific type 02" begin
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

    @testset "Array with no specific type 03" begin
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
            end
            """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 2, column 9: Use `tin(item,collection)` instead of the Julia's `in`")
        @test lint_test(source,
            "Line 3, column 9: Use `tin(item,collection)` instead of the Julia's `in`")
        @test lint_test(source,
            "Line 4, column 9: Use `tequal(dict,key)` instead of the Julia's `equal`.")
        @test lint_test(source,
            "Line 5, column 9: Use `thaskey(dict,key)` instead of the Julia's `haskey`.")
        @test lint_test(source,
            "Line 6, column 9: `uv_` functions should be used with extreme caution.")
        @test lint_test(source,
            "Line 7, column 9: Use `tin(item,collection)` instead of the Julia's `in` or `∈`.")
        @test lint_test(source,
            "Line 8, column 9: Use `tin(item,collection)` instead of the Julia's `in` or `∈`.")
    end

    @testset "Splatting" begin
        @test lint_test("f(x...) + 10",
            "Line 1, column 1: Splatting (`...`) should be used with extreme caution. Splatting from dynamically sized containers could result in severe performance degradation.")

        @test lint_test("hcat([f(x) for x in r]...)",
            "Line 1, column 1: Splatting (`...`) should not be used with dynamically sized containers. This may result in performance degradation. See https://github.com/RelationalAI/RAIStyle#splatting for more information.")
    end
end

@testset "Comparing AST to templates" begin
    t(s1, s2) = comp(CSTParser.parse(s1), CSTParser.parse(s2))
    @test t("Threads.nthreads()", "Threads.nthreads()")
    @test !t("QWEThreads.nthreads()", "Threads.nthreads()")
    @test !t("Threads.nthreads()", "QWEThreads.nthreads()")
    @test !t("Threads.nthreads()", "Threads.qwenthreads()")

    @test t("1 + 2", "1+2")
    @test t("1 + 2", "1+hole_variable")
    @test t("hole_variable + hole_variable", "1 + hole_variable")
    @test t("hole_variable + 1", "1 + hole_variable")

    @test t("@async hole_variable", "@async begin 1 + 2 end")

    @test t("finalizer(y, x)", "finalizer(hole_variable, hole_variable)")
    @test t("finalizer(q->nothing, x)", "finalizer(hole_variable, hole_variable)")
    @test t("finalizer(x) do hole_variable hole_variable end",
            "finalizer(x) do x
                ref[] = 3
            end")

    @test !t("foo()", "foo(hole_variable)")
    @test !t("foo()", "foo(x)")

    @test t("foo(x, y)", "foo(hole_variable, hole_variable)")
    @test !t("foo(x, y, z)", "foo(hole_variable, hole_variable)")
    @test t("foo(x, y, z)", "foo(hole_variable, hole_variable_star)")

    @test t("foo(x, y, z)", "foo(hole_variable_star)")
    @test t("foo()", "foo(hole_variable_star)")

    @test t("Semaphore(10)", "Semaphore(hole_variable)")
    # Ideally, the next line should pass.
    # @test t("foo(x, y, z)", "foo(hole_variable, hole_variable, hole_variable, hole_variable_star)")

    source = """
            finalizer("hello") do x
                println("hello ")
            end
            """
    @test t(source, "finalizer(hole_variable) do hole_variable hole_variable_star end")

    @test t("unlock(hole_variable)", "unlock(12)")

    # Generics
    @test t("Future{Nothing}()", "Future{hole_variable}()")
    @test t("Future{T}()", "Future{hole_variable}(hole_variable_star)")
    @test t("Future{T}(()->nothing)", "Future{hole_variable}(hole_variable_star)")
    @test !t("Future()", "Future{hole_variable}(hole_variable_star)")
    @test !t("Future{Any}() do f nothing end", "Future{hole_variable}(hole_variable_star)")

    # Partial matching
    @test t("foo", "foo")
    @test t("fooQQQ", "foo")
    @test t("QQQfoo", "foo")
    @test t("QQQfooQQQ", "foo")

    @test !t("foo", "foobar")
    @test t("fooQQQ", "foobar")
    @test t("QQQfoo", "barfoo")
    @test t("QQQfooQQQ", "barfoozork")

    @test !t("foo", "foo_bar")
    @test t("fooQQQ", "foo_bar")
    @test t("QQQfoo", "bar_foo")
    @test t("QQQfooQQQ", "bar_foo_zork")

    @test t("foo(x, QQQzork)", "foo(x, zork)")
    @test t("foo(x, QQQzork)", "foo(x, blah_zork)")

    # in keyword
    @test t("in(hole_variable,hole_variable)", "in(x,y)")
    @test t("x in y", "hole_variable in hole_variable")

    # Splatting
    @test t("f(a...)", "hole_variable(hole_variable_star...)")
    @test t("hcat([f(x) for x in r]...)", "hole_variable([hole_variable(hole_variable_star) for hole_variable in hole_variable]...)")

    # Named variable holes
    @test t("1 + 2", "1+hole_variableA")
    @test t("1 + 2", "1+hole_variableB")
    @test t("1 + 2 + 2", "1+hole_variableA+hole_variableA")
    @test !t("1 + 2 + 2", "1+hole_variableA+hole_variableB")
    @test t("1 + 2 + 3", "1+hole_variableA+hole_variableB")
    @test t("1 + 2 + 3 + 2", "1+hole_variableA+hole_variable +hole_variableA")
    @test t("1 + 2 + 3 + 2 + 10", "1+hole_variableA+hole_variable +hole_variableA + hole_variable_star")

    @test !t("""
        if x == 1
            return 12
        elseif x== 2
            return "Reachable_branch"
        end
        """, """
        if hole_variableA == hole_variableB
            hole_variable
        elseif hole_variableA == hole_variableB
            hole_variable
        end
        """)

    @test t("""
        if x == 1
            return 12
        elseif x== 1
            return "Reachable_branch"
        end
        """, """
        if hole_variableA == hole_variableB
            hole_variable
        elseif hole_variableA == hole_variableB
            hole_variable
        end
        """)


    @test t("""
        if x == 1
            println("hello")
            return 12
        elseif x== 1
            println("world")
            return "Reachable_branch"
        end
        """, """
        if hole_variableA == hole_variableB
            hole_variable
        elseif hole_variableA == hole_variableB
            hole_variable
        end
        """)

    # LINT_STRING
    @test t("\"LINT_STRING\"", "\"this is a string\"")
    @test !t("\"LINT_STRING\"", "1 + 2")
    @test t("\"this is a string\"", "\"LINT_STRING\"")
    @test !t("1 + 2", "\"LINT_STRING\"")
    @test t("\"1 + 2\"", "\"LINT_STRING\"")

    # LINT_STRING_WITH_INTERPOLATION
    @test !t("\"1 + 2\"", "\"LINT_STRING_WITH_INTERPOLATION\"")
    @test t(raw"\"foo $x\"", "\"LINT_STRING_WITH_INTERPOLATION\"")
    @test t(raw"@warnv_safe_to_log 1 \"logged! $(a_variable)\"", "@warnv_safe_to_log hole_variable \"LINT_STRING_WITH_INTERPOLATION\"")
    @test !t(raw"@warnv_safe_to_log 1 \"logged! (a_variable)\"", "@warnv_safe_to_log hole_variable \"LINT_STRING_WITH_INTERPOLATION\"")

    # @test t(raw"\"($x)\"", "\"LINT_STRING\"")

end

@testset "unsafe functions" begin
    @testset "No error 01" begin
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

    @testset "Some errors 01" begin
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
            "Line 2, column 5: An `unsafe_` function should be called only from an `unsafe_` function.")
    end

    @testset "Some errors 02" begin
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
            "Line 2, column 5: An `unsafe_` function should be called only from an `unsafe_` function.")
    end

    @testset "No error 02" begin
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

@testset "offset to line" begin
    source = """
        function f()
            return Threads.nthreads()
        end
        """
    @test_throws BoundsError convert_offset_to_line(-1, source)
    @test_throws BoundsError convert_offset_to_line(length(source) + 2, source)

    @test convert_offset_to_line(10, source) == (1, 10, nothing)
    @test convert_offset_to_line(20, source) == (2, 7, nothing)
    @test convert_offset_to_line(42, source) == (2, 29, nothing)
    @test convert_offset_to_line(46, source) == (3, 3, nothing)

end

@testset "Fetching values from AST" begin
    @test fetch_value(CSTParser.parse("f"), :IDENTIFIER) == "f"
    @test fetch_value(CSTParser.parse("f()"), :IDENTIFIER) == "f"
    @test fetch_value(CSTParser.parse("begin f(g()) end"), :IDENTIFIER) == "f"

    source = """
            struct _SyncDict{Dict}
                lock::Base.Threads.SpinLock
                dict::Dict

                function _SyncDict{Dict}() where {Dict}
                    new{Dict}(Base.Threads.SpinLock(), Dict())
                end
            end
            """
    @test fetch_value(CSTParser.parse(source), :IDENTIFIER) == "_SyncDict"

end

@testset "Formatter" begin
    source = """
           const x = Threads.nthreads()
           function f()
               return x
           end
           """

    @testset "Plain 02" begin
        io = IOBuffer()
        run_lint_on_text(source; io=io)
        result = String(take!(io))

        expected = r"""
            ---------- \H+
            Line 1, column 11: `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            1 potential threat is found: 0 fatal violation, 1 violation and 0 recommendation
            ----------
            """
        @test !isnothing(match(expected, result))
    end

    @testset "Markdown 02" begin
        io = IOBuffer()
        run_lint_on_text(source; io=io, formatter=MarkdownFormat())
        result = String(take!(io))

        expected = r"""
             - \*\*Line 1, column 11:\*\* `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            """
        @test !isnothing(match(expected, result))
    end

    @testset "Markdown 03 - with github information" begin
        formatter = MarkdownFormat("axb-example-with-lint-errors", "RelationalAI/raicode")
        io = IOBuffer()

        run_lint_on_text(
            source;
            io,
            formatter,
            directory="/src/Compiler/")
        result = String(take!(io))

        expected = r"""
             - \*\*\[Line 1, column 11:\]\(https://github\.com/RelationalAI/raicode/blob/axb-example-with-lint-errors/\H+/src/Compiler/tmp_julia_file\.jl#L1\)\*\* `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            """
        @test !isnothing(match(expected, result))
    end

    @testset "Markdown 04 - with github information" begin
        formatter = MarkdownFormat("axb-example-with-lint-errors", "RelationalAI/raicode")
        io = IOBuffer()
        run_lint_on_text(
            source;
            io,
            formatter,
            directory="src/Compiler/")
        result = String(take!(io))
        expected = r"""
             - \*\*\[Line 1, column 11:\]\(https://github\.com/RelationalAI/raicode/blob/axb-example-with-lint-errors/\H+/src/Compiler/tmp_julia_file\.jl#L1\)\*\* `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            """
        @test !isnothing(match(expected, result))
    end
end

@testset "Run several times on same file" begin
    mktempdir() do dir
        open(joinpath(dir, "foo.jl"), "w") do io
            write(io, "function f()\n  @async 1 + 1\nend\n")
            flush(io)

            @test has_values(StaticLint.run_lint(dir; io), 1, 1, 0)
            @test has_values(StaticLint.run_lint(dir; io), 1, 1, 0)
            @test has_values(StaticLint.run_lint(dir; io), 1, 1, 0)
            @test has_values(StaticLint.run_lint(dir; io), 1, 1, 0)
        end
    end
end

@testset "Linting multiple files" begin
    @testset "No errors" begin
        local result_is_empty = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @spawn 1 + 1\nend\n")
                    write(io2, "function g()\n  @spawn 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    StaticLint.run_lint(dir; io=str, formatter=StaticLint.MarkdownFormat())
                    result = String(take!(str))
                    result_is_empty = isempty(result)
                end
            end
        end
        @test result_is_empty
    end

    @testset "Two files with errors" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2, "function g()\n  @async 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    StaticLint.run_lint(dir; io=str, formatter=StaticLint.MarkdownFormat())

                    result = String(take!(str))

                    expected = r"""
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with errors" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2, "function g()\n  finalizer(\"hello\") do x nothing\nend\n")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_output = IOBuffer()
                    stream_workflowcommand = IOBuffer()
                    StaticLint.generate_report([file1, file2], output_file; json_output, stream_workflowcommand)

                    # Checking the Workflow command
                    stream_workflowcommand_report = String(take!(stream_workflowcommand))
                    wc_lines = split(stream_workflowcommand_report, "\n")
                    @test length(wc_lines) == 3
                    @test isempty(wc_lines[end])
                    @test contains(wc_lines[1], "foo.jl,line=2,col=3::Use `@spawn` instead of `@async`.")

                    # Checking the JSON
                    json_report = JSON3.read(String(take!(json_output)))
                    @test json_report[:source] == "StaticLint"
                    @test json_report[:data][:files_count] == 2

                    @test json_report[:data][:violation_count] == 1
                    @test json_report[:data][:recommandation_count] == 1

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    # First violations across files, then recommendations across files
                    expected = r"""
                        ## Static code analyzer report
                        \*\*Output of the \[StaticLint\.jl code analyzer\]\(https://github\.com/RelationalAI/StaticLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+


                        <details>
                        <summary>For PR Reviewer \(1\)</summary>

                         - \*\*Line 2, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+\

                        </details>

                        🚨\*\*In total, 1 rule violation and 1 PR reviewer recommendation are found over 2 Julia files\*\*🚨
                        """
                    result_matching = !isnothing(match(expected, result))
                    # DEBUG:
                    !result_matching && @info result
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with errors 02" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function g()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")
                    write(io2, "function f()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_output = IOBuffer()
                    StaticLint.generate_report([file1, file2], output_file; json_output, stream_workflowcommand=devnull)

                    json_report = JSON3.read(String(take!(json_output)))
                    @test json_report[:source] == "StaticLint"
                    @test json_report[:data][:files_count] == 2

                    @test json_report[:data][:recommandation_count] == 2
                    @test json_report[:data][:violation_count] == 2

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    # First violations across files, then recommendations across files
                    expected = r"""
                        ## Static code analyzer report
                        \*\*Output of the \[StaticLint\.jl code analyzer\]\(https://github\.com/RelationalAI/StaticLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+

                        <details>
                        <summary>For PR Reviewer \(2\)</summary>

                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+
                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+

                        </details>

                        🚨\*\*In total, 2 rule violations and 2 PR reviewer recommendations are found over 2 Julia files\*\*🚨
                        """
                    result_matching = !isnothing(match(expected, result))
                    # DEBUG:
                    !result_matching && @info result
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with errors 02 - JSON report" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function g()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")
                    write(io2, "function f()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_filename = tempname()
                    @test !isfile(json_filename)
                    # json_io = IOBuffer()
                    StaticLint.generate_report([file1, file2], output_file; json_filename, stream_workflowcommand=devnull)

                    @test isfile(json_filename)
                    json_content = open(io->read(io, String), json_filename)
                    json_report = JSON3.read(json_content)

                    @test json_report[:source] == "StaticLint"
                    @test json_report[:data][:files_count] == 2

                    @test json_report[:data][:recommandation_count] == 2
                    @test json_report[:data][:violation_count] == 2

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    # First violations across files, then recommendations across files
                    expected = r"""
                        ## Static code analyzer report
                        \*\*Output of the \[StaticLint\.jl code analyzer\]\(https://github\.com/RelationalAI/StaticLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+

                        <details>
                        <summary>For PR Reviewer \(2\)</summary>

                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+
                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+

                        </details>

                        🚨\*\*In total, 2 rule violations and 2 PR reviewer recommendations are found over 2 Julia files\*\*🚨
                        """
                    result_matching = !isnothing(match(expected, result))
                    # DEBUG:
                    !result_matching && @info result
                end
            end
        end
        @test result_matching
    end

    @testset "No modified julia file" begin
        output_file = tempname()
        json_output = IOBuffer()
        StaticLint.generate_report(String[], output_file; json_output, stream_workflowcommand=devnull)

        json_report = JSON3.read(String(take!(json_output)))
        @test json_report[:source] == "StaticLint"
        @test json_report[:data][:files_count] == 0

        @test json_report[:data][:recommandation_count] == 0
        @test json_report[:data][:violation_count] == 0


        expected = r"""
            ## Static code analyzer report
            \*\*Output of the \[StaticLint\.jl code analyzer\]\(https://github\.com/RelationalAI/StaticLint\.jl\).+\*\*
            Report creation time \(UTC\): \H+
            No Julia file is modified or added in this PR.
            """
        result = open(io->read(io, String), output_file)

        result_matching = !isnothing(match(expected, result))
        @test result_matching
    end

    @testset "No result with no julia file" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.txt")
            open(file1, "w") do io1
                write(io1, "Hello World\n")
                flush(io1)

                output_file = tempname()
                json_output = IOBuffer()
                StaticLint.generate_report([file1], output_file; json_output, stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_output)))
                @test json_report[:source] == "StaticLint"
                @test json_report[:data][:files_count] == 0
                @test json_report[:data][:recommandation_count] == 0
                @test json_report[:data][:violation_count] == 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end


                expected = r"""
                    ## Static code analyzer report
                    \*\*Output of the \[StaticLint\.jl code analyzer\]\(https://github\.com/RelationalAI/StaticLint\.jl\).+\*\*
                    Report creation time \(UTC\): \H+
                    No Julia file is modified or added in this PR.
                    """
                result_matching = !isnothing(match(expected, result))
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with no errors" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function f()\n  @spawn 1 + 1\nend\n")
                    write(io2, "function g()\n  @spawn 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_output = IOBuffer()
                    StaticLint.generate_report([file1, file2], output_file; json_output, stream_workflowcommand=devnull)

                    json_report = JSON3.read(String(take!(json_output)))
                    @test json_report[:source] == "StaticLint"
                    @test json_report[:data][:files_count] == 2
                    @test json_report[:data][:recommandation_count] == 0
                    @test json_report[:data][:violation_count] == 0

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    expected = r"""
                        ## Static code analyzer report
                        \*\*Output of the \[StaticLint\.jl code analyzer\]\(https://github\.com/RelationalAI/StaticLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                        🎉No potential threats are found over 2 Julia files.👍
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of 1 file with no errors" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n  @spawn 1 + 1\nend\n")
                flush(io1)

                output_file = tempname()
                json_output = IOBuffer()
                StaticLint.generate_report([file1], output_file; json_output, stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_output)))
                @test json_report[:source] == "StaticLint"
                @test json_report[:data][:files_count] == 1

                @test json_report[:data][:recommandation_count] == 0
                @test json_report[:data][:violation_count] == 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end

                expected = r"""
                    ## Static code analyzer report
                    \*\*Output of the \[StaticLint\.jl code analyzer\]\(https://github\.com/RelationalAI/StaticLint\.jl\).+\*\*
                    Report creation time \(UTC\): \H+
                    🎉No potential threats are found over 1 Julia file.👍
                    """
                result_matching = !isnothing(match(expected, result))
            end
        end
        @test result_matching
    end

    @testset "Report generation of 1 file with 1 error and github info" begin
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n  @async 1 + 1\nend\n")
                flush(io1)

                output_file = tempname()
                json_io = IOBuffer()
                StaticLint.generate_report(
                    [file1],
                    output_file;
                    json_output=json_io,
                    github_repository="RelationalAI/raicode",
                    branch_name="axb-foo-bar",
                    file_prefix_to_remove="var/",
                    stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_io)))
                @test json_report[:source] == "StaticLint"
                @test json_report[:data][:files_count] == 1

                @test json_report[:data][:violation_count] == 1
                @test json_report[:data][:recommandation_count] == 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end

                # Remove the first folder to address an issue of GitHub Action
                # (See MarkdownFormat for more information)
                corrected_file_name = StaticLint.remove_prefix_from_filename(file1, "var/")

                expected = " - **[Line 2, column 3:]" *
                    "(https://github.com/RelationalAI/raicode/blob/axb-foo-bar/$(corrected_file_name)" *
                    "#L2)** Use `@spawn` instead of `@async`."
                if !occursin(expected, result)
                    @info "didn't match" expected result
                end
                @test occursin(expected, result)
            end
        end
    end

    @testset "Report generation of all the folder" begin
        # This is a slow test
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n  @async 1 + 1\nend\n")
                flush(io1)

                output_file = tempname()
                json_io = IOBuffer()
                StaticLint.generate_report(
                    [file1], # Ignored because of analyze_all_file_found_locally
                    output_file;
                    json_output=json_io,
                    github_repository="RelationalAI/raicode",
                    branch_name="axb-foo-bar",
                    file_prefix_to_remove="var/",
                    analyze_all_file_found_locally=true, # OVERRIDE THE PROVIDED SET OF FILES
                    stream_workflowcommand=devnull
                )

                json_report = JSON3.read(String(take!(json_io)))

                @test json_report[:source] == "StaticLint"
                @test json_report[:data][:files_count] >= 2
                @test json_report[:data][:violation_count] >= 0
                @test json_report[:data][:recommandation_count] >= 0
                @test json_report[:data][:fatalviolations_count] >= 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end
                last_line = filter(!isempty, split(result, "\n"))[end]
                @test last_line != "No Julia file is modified or added in this PR."
            end
        end
    end

    @testset "Limiting report" begin
        # this tests create a Julia file with 100 violations, the report should mention
        # 100 violations, however only (an arbitrary) 30 are reported.
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n")
                for _ in 1:100
                    write(io1, "    @async 1 + 1\n")
                end
                write(io1, "end\n")
                flush(io1)

                output_file = tempname()
                json_output = IOBuffer()
                StaticLint.generate_report([file1], output_file; json_output, stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_output)))
                @test json_report[:source] == "StaticLint"
                @test json_report[:data][:files_count] == 1
                @test json_report[:data][:recommandation_count] == 0
                @test json_report[:data][:violation_count] == 100

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end
                all_lines = split(result, "\n")
                lines_count = length(all_lines)
                @test lines_count < 70

                @test all_lines[end-2] == "⚠️Only a subset of the violations and recommandations are here reported⚠️"
                @test all_lines[end-1] == "🚨**In total, 100 rule violations and 0 PR reviewer recommendation are found over 1 Julia file**🚨"
                @test all_lines[end] == ""
            end
        end
    end

    @testset "Diamond between files" begin
        mktempdir() do dir
            open(joinpath(dir, "leaf.jl"), "w") do io
                write(io, "function f()\n  @async 1 + 1\nend\n")
            end

            open(joinpath(dir, "bar.jl"), "w") do io
                write(io, "include(\"leaf.jl\")\n")
            end

            str = IOBuffer()
            result = StaticLint.run_lint(dir; io=str, formatter=StaticLint.MarkdownFormat())
            @test result.files_count == 2
            @test result.violations_count == 1
            @test result.recommendations_count == 0
        end
    end
end

@testset "Running on a directory" begin
    @testset "Non empty directory" begin
        local r
        r = LintResult()

        formatters = [StaticLint.PlainFormat(), StaticLint.MarkdownFormat()]
        for formatter in formatters
            mktempdir() do dir
                open(joinpath(dir, "foo.jl"), "w") do io
                    write(io, "function f()\n  @async 1 + 1\nend\n")
                    flush(io)
                    str = IOBuffer()
                    append!(r, StaticLint.run_lint(dir; io=str, formatter))
                end
            end
        end
        @test (r.violations_count + r.recommendations_count) == 2
    end

    @testset "Empty directory" begin
        mktempdir() do dir
            @test StaticLint.run_lint(dir) == LintResult()
        end
    end
end

@testset "Locally disabling lint" begin
    @testset "lint-disable-lint" begin
        @test convert_offset_to_line(17, """
            function f()
                @async 1 + 2 # lint-disable-line
            end
            """) == (2, 4, "lint-disable-line")
        @test !lint_has_error_test("""
            function f()
                @async 1 + 2 # lint-disable-line
            end
            """)
        @test !lint_has_error_test("""
            function f()
                @async 1 + 2 # lint-disable-line: Use `@spawn` instead of `@async`.
            end
            """)
        @test !lint_has_error_test("""
            function f()
                @async 1 + 2 #lint-disable-line: Use `@spawn` instead of `@async`.
            end
            """)
        @test !lint_has_error_test("""
            function f()
                @async 1 + 2 #lint-disable-line:Use `@spawn` instead of `@async`.
            end
            """)
        @test lint_has_error_test("""
            function f()
                @async 1 + 2 #lint-disable-line: not working `@spawn` instead of `@async`.
            end
            """)
        @test !lint_has_error_test("""
            function f()
                @async 1 + 2 #lint-disable-line
            end
            """)

        @test !lint_has_error_test("""
            function f()
                @async 1 + 2 #  lint-disable-line
            end
            """)

        @test lint_has_error_test("""
            function f()
                @async 1 + 2 #  lint-disable-line
                @async 1 + 3
            end
            """)
    end
    @testset "lint-disable-next-line" begin
        @test !lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2
            end
            """)
        @test !lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2
            end
            """)

        @test !lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2
            end
            """)

        @test lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2

                @async 1 + 3
            end
            """)
        @test lint_has_error_test("""
            function f()
                @async 1 + 2
                # lint-disable-next-line

                @async 1 + 3
            end
            """)
        @test lint_has_error_test("""
            function f()
                @async 1 + 2
                # lint-disable-next-line
                @async 1 + 3
            end
            """)

        source = """
            function f()
                # lint-disable-next-line
                @async 1 + 2

                @async 1 + 3
            end
            """
        source_lines = split(source, "\n")
        @test convert_offset_to_line_from_lines(46, source_lines) == (3, 4, "lint-disable-line")
        @test convert_offset_to_line_from_lines(64, source_lines) == (5, 4, nothing)
    end

    @testset "Locally disabling rule 01" begin
        source = """
        function f()
            # lint-disable-next-line: Use `@spawn` instead of `@async`.
            @async 1 + 1
        end
        """
        source_lines = split(source, "\n")
        @test convert_offset_to_line_from_lines(30, source_lines) == (2, 17, nothing)
        @test convert_offset_to_line_from_lines(91, source_lines) == (3, 14, "lint-disable-line: Use `@spawn` instead of `@async`.")

        @test !lint_has_error_test(source)
    end

    @testset "Locally disabling rule 02" begin
        source = """
        function f()
            # lint-disable-next-line: Use `@spawn` instead of `@async`.
            @async unsafe_foo(12)
        end
        """
        source_lines = split(source, "\n")
        @test convert_offset_to_line_from_lines(30, source_lines) == (2, 17, nothing)
        @test convert_offset_to_line_from_lines(91, source_lines) == (3, 14, "lint-disable-line: Use `@spawn` instead of `@async`.")

        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 3, column 12: An `unsafe_` function should be called only from an `unsafe_` function.")
    end

    @testset "Locally disabling rule 03" begin
        source = """
        function f()
            # lint-disable-next-line: An `unsafe_` function
            @async unsafe_foo(42)
        end
        """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 3, column 5: Use `@spawn` instead of `@async`.")
    end

    @testset "Locally disabling rule 04" begin
        source = """
        function f()
            # lint-disable-next-line:Use `@spawn` instead of `@async`.
            @async 1 + 1
        end
        """
        source_lines = split(source, "\n")
        @test convert_offset_to_line_from_lines(30, source_lines) == (2, 17, nothing)
        @test convert_offset_to_line_from_lines(91, source_lines) == (3, 15, "lint-disable-line: Use `@spawn` instead of `@async`.")

        @test !lint_has_error_test(source)
    end

    @testset "Locally disabling rule 05" begin
        source = """
        function f()
            # lint-disable-next-line:  Use `@spawn` instead of `@async`.
            @async 1 + 1
        end
        """
        source_lines = split(source, "\n")
        @test convert_offset_to_line_from_lines(30, source_lines) == (2, 17, nothing)
        @test convert_offset_to_line_from_lines(91, source_lines) == (3, 13, "lint-disable-line: Use `@spawn` instead of `@async`.")

        @test !lint_has_error_test(source)
    end
end

@testset "Relaxing unused bindings" begin
    # @test lint_test("""
    #        function f(a::Int64, b, c)
    #            local x
    #            return 42
    #        end
    #        """, "Line 2, column 11: Variable has been assigned but not used")

    @test !lint_has_error_test("""
           function f(a::Int64, b, c)
               local _
               return 42
           end
           """)

    @test !lint_has_error_test("""
           function f(a::Int64, b, c)
               local _x
               return 42
           end
           """)
end

# This rule is disabled per default. To add it, need to modify reset_recommentation_dict!()
# @testset "IncorrectCallArgs" begin
#     source = """
#                f(x) = 1
#                f(1, 2)
#                """
#     @test lint_test(source, "Line 2, column 1: Possible method call error: f.")
# end

@testset "Branch" begin
    @testset "Reachable branches" begin
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

    @testset "Unreachable branches" begin
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

    @testset "Unreachable branches 02" begin
        source = """
            function f(x)
                if x <= 1
                    return 12
                elseif x <= 1
                    return "Unreachable_branch"
                end
            end
            """
        @test lint_test(source, "Line 2, column 5: Unreachable branch.")
    end
end

@testset "Resetting StaticLint caches" begin
    source = """
    function f()
        @async 1 + 1
    end
    function g()
        @lock Lock() begin
            1 + 1
        end
    end
    """

    run_lint_on_text(source; io=IOBuffer())

    @test !isempty(StaticLint.check_cache)
    StaticLint.reset_static_lint_caches()
    @test isempty(StaticLint.check_cache)
end

@testset "Recommentation separated from violations" begin
    source = """
    function f()
        @async 1 + 1
    end
    function g()
        @lock Lock() begin
            1 + 1
        end
    end
    """
    io=IOBuffer()
    run_lint_on_text(source; io)

    result = String(take!(io))
    expected = r"""
    ---------- \H+
    Line 2, column 5: Use `@spawn` instead of `@async`\. \H+
    Line 5, column 5: `@lock` should be used with extreme caution\. \H+
    2 potential threats are found: 0 fatal violation, 1 violation and 1 recommendation
    ----------
    """
    @test !isnothing(match(expected, result))
end

@testset "Checking string interpolation" begin

    # ERRORS
    source_with_error = raw"""
    function f(conf)
        @INFO "($conf.container.baseurl)"
    end
    """

    source_with_error2 = raw"""
    function f(conf)
        @INFO "$conf.container.baseurl"
    end
    """

    source_with_error3 = raw"""
    function f(conf)
        @INFO "this string contains an error $conf.container.baseurl indeed!"
    end
    """

    source_with_error4 = raw"""
    function f(conf)
        @INFO "this string contains an error $conf .container.baseurl indeed!"
    end
    """

    source_with_error5 = raw"""
    function f(engine_name)
        @INFO "Issuing delete request for engine $engine_name..."
    end
    """

    source_with_error6 = raw"""
    function f()
        Source("model/$name", "model/$name",  read(joinpath(@__DIR__, "models", "$name.rel"), String))
    end
    """

    source_with_error7 = raw"""
    function f()
        path = "$dir/$name.csv"
    end
    """

    @test lint_test(source_with_error, raw"Line 2, column 11: Use $(x) instead of $x ")
    @test lint_test(source_with_error2, raw"Line 2, column 11: Use $(x) instead of $x ")
    @test lint_test(source_with_error3, raw"Line 2, column 11: Use $(x) instead of $x ")
    @test lint_test(source_with_error4, raw"Line 2, column 11: Use $(x) instead of $x ")
    @test lint_test(source_with_error5, raw"Line 2, column 11: Use $(x) instead of $x ")

    @test lint_test(source_with_error6, raw"Line 2, column 12: Use $(x) instead of $x ")
    @test lint_test(source_with_error6, raw"Line 2, column 27: Use $(x) instead of $x ")
    @test lint_test(source_with_error6, raw"Line 2, column 77: Use $(x) instead of $x ")

    @test lint_test(source_with_error7, raw"Line 2, column 12: Use $(x) instead of $x ")

    # NO ERROR
    source_without_error = raw"""
    function f(conf)
        @INFO "$(conf.container.baseurl)"
    end
    """

    source_without_error2 = raw"""
    function f(conf)
        @INFO "this string contains an error $(conf.container.baseurl) indeed!"
    end
    """

    source_without_error3 = raw"""
    function f()
        _profile_filename = "profile-$(timestamp).pb.gz"
    end
    """

    @test count_lint_errors(source_without_error) == 0
    @test count_lint_errors(source_without_error2) == 0
    @test count_lint_errors(source_without_error3) == 0
end

@testset "Arithmetic LintResult" begin
    l1 = LintResult()
    l2 = LintResult(1, 2, 3)
    l3 = LintResult(10, 20, 30)
    l6 = LintResult(10, 20, 30, 40)
    l4 = LintResult(10, 20, 30, 40, ["foo.jl"], 100, [])
    l5 = LintResult(10, 20, 30, 40, ["foo2.jl"], 250)


    @test l1 == l1
    @test l1 == LintResult()
    # @test (l1 + l2) == l2
    # @test (l3 + l2) == LintResult(11, 22, 33)
    @test l4 != l5
    @test l3 != l4
    @test l3 != l5

    append!(l4, l5)
    @test l4 == LintResult(20, 40, 60, 80, ["foo.jl", "foo2.jl"], 350)
end

@testset "RelPath Front-End" begin
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
        "Line 2, column 25: Usage of `RelPath` API method `split_path` is not allowed in this context.";
        directory="/src/Compiler/Front"
    )
end

@testset "Shapes outside Front-End" begin
    source = """
        function get_relation_infos(rt::Runtime, name::Symbol, shape::Shape)
            idb_overloads = Front.idb_overloads_for_shape(rt, shape)
            return idb_overloads
        end

        function get_relation_values(rt::Runtime, name::Symbol)
            return get_relation_values(rt, name, Front.shape_splat(Shape))
        end
    """

    @test count_lint_errors(source; directory="/src/Execution") == 3
    @test count_lint_errors(source; directory="/src/FrontCompiler") == 0

    @test lint_test(source,
        "Line 1, column 67: Usage of `Shape` is not allowed outside of the Front-end Compiler and FFI.";
        directory="/src/Execution"
    )

    @test lint_test(source,
        "Line 7, column 46: Usage of `shape_splat` Shape API method is not allowed outside of the Front-end Compiler and FFI.";
        directory="/src/Execution"
    )
end

# @testset "Check on @warnv_safe_to_log" begin
#     source = raw"""
#     function pm_check_mutable_pages(bytes::Int)
#         pm = PAGER_MONITOR

#         max_pages = (@atomic pm.mutable_pages_running_max)
#         max_bytes = (@atomic pm.mutable_bytes_running_max)
#         if max_bytes >= bytes
#             @warnv_safe_to_log 0 "[Pager] Too many mutable pages \
#                 detected: $max_pages pages weighting $max_bytes bytes"

#             @ensure @warnv_safe_to_log 2 "[Pager] Too many mutable pages \
#                 detected: $max_pages pages weighting $max_bytes bytes"

#             @ensure @warnv_safe_to_log 0 "no interpolation"

#             mutable_report = pm_generate_mutable_pages_report!()
#             if !isnothing(mutable_report)
#                 @warnv_safe_to_log 0 mutable_report
#             end
#             return false
#         end

#         return true
#     end
#     """
#     @test lint_test(source, "Line 7, column 9: Safe warning log has interpolation.")
#     @test lint_test(source, "Line 10, column 17: Safe warning log has interpolation.")
# end

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
    @test lint_test(source, "Line 2, column 5: Use `Threads.@threads :dynamic` instead of `Threads.@threads :static`.")
    @test lint_test(source, "Line 6, column 5: Use `Threads.@threads :dynamic` instead of `Threads.@threads :static`.")
end

@testset "Unsafe logging" begin
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

@testset "PreCommit format" begin
    @testset "No fatal violation" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2, "function g()\n  @async 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    result = StaticLint.run_lint(dir; io=str, formatter=StaticLint.PreCommitFormat())
                    StaticLint.print_summary(StaticLint.PreCommitFormat(), str, result)

                    result = String(take!(str))

                    expected = r"""
                        2 potential threats are found: 0 fatal violation, 2 violations and 0 recommendation
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end

    @testset "With fatal violations" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\n  @warn \"blah\"\nend\n")
                    write(io2, "function g()\n  @async 1 + 1\n  @info \"blah\"\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    result = StaticLint.run_lint(dir; io=str, formatter=StaticLint.PreCommitFormat())
                    StaticLint.print_summary(StaticLint.PreCommitFormat(), str, result)

                    result = String(take!(str))

                    expected = r"""
                        Line 3, column 3: Unsafe logging statement\. You must enclose variables and strings with `@safe\(\.\.\.\)`\. \H+/bar.jl
                        Line 3, column 3: Unsafe logging statement\. You must enclose variables and strings with `@safe\(\.\.\.\)`\. \H+/foo.jl
                        4 potential threats are found: 2 fatal violations, 2 violations and 0 recommendation
                        Note that the list above only show fatal violations
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end
end