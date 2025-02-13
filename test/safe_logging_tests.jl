@testset "Safe logging" begin
    @testset "Safe and unsafe logs" begin
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

    @testset "Safe and unsafe assertions" begin
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
end