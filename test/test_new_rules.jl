# Tests for newly implemented ReLint rules

using Test
using ReLint

# Include common test utilities
include(joinpath(@__DIR__, "common.jl"))

@testset "ConstGlobalMissingTypeRule" begin
    # Should trigger warning - untyped global
    code1 = """
    global my_state = 0
    """
    # Test would go here when ReLint is properly set up
    # @test check_violations(code1, ConstGlobalMissingTypeRule) > 0

    # Should NOT trigger - typed global
    code2 = """
    global my_state::Int = 0
    """
    # @test check_violations(code2, ConstGlobalMissingTypeRule) == 0

    # Should NOT trigger - const
    code3 = """
    const MY_CONSTANT = 42
    """
    # @test check_violations(code3, ConstGlobalMissingTypeRule) == 0
end

@testset "IsNothingPerformanceRule" begin
    # Should trigger in Compiler directory
    code1 = """
    # filename: src/Compiler/foo.jl
    function process(x)
        if isnothing(x)
            return
        end
    end
    """
    # Would need to set markers[:filename] appropriately

    # Should NOT trigger in normal code
    code2 = """
    # filename: src/API/foo.jl
    function process(x)
        if isnothing(x)
            return
        end
    end
    """

    # Preferred pattern
    code3 = """
    # filename: src/Compiler/foo.jl
    function process(x)
        if x === nothing
            return
        end
    end
    """
end

@testset "MissingAutoHashEqualsRule" begin
    # Should trigger - public struct without @auto_hash_equals
    code1 = """
    struct Point
        x::Int
        y::Int
    end
    """

    # Should NOT trigger - has @auto_hash_equals
    code2 = """
    @auto_hash_equals struct Point
        x::Int
        y::Int
    end
    """

    # Should NOT trigger - private struct
    code3 = """
    struct _InternalPoint
        x::Int
        y::Int
    end
    """

    # Should NOT trigger - mutable
    code4 = """
    mutable struct MutablePoint
        x::Int
        y::Int
    end
    """
end

@testset "NotFullyParameterizedConstructorRule" begin
    # Only triggers in src/Compiler/ directory

    @testset "Should trigger - constructor in loop" begin
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
            "Avoid not-fully-parameterized constructor `ColumnarVector(...)` in loops",
            directory="src/Compiler/")
    end

    @testset "Should trigger - Vector constructor in loop" begin
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
            "Avoid not-fully-parameterized constructor `Vector(...)` in loops",
            directory="src/Compiler/")
    end

    @testset "Should trigger - Dict constructor in while loop" begin
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
            "Avoid not-fully-parameterized constructor `Dict(...)` in loops",
            directory="src/Compiler/")
    end

    @testset "Should NOT trigger - fully parameterized constructor" begin
        source = """
        function process(columns_list)
            results = Vector{ColumnarVector{Int,Vector{Int}}}()
            for columns in columns_list
                push!(results, ColumnarVector{Int,Vector{Int}}(columns))
            end
            return results
        end
        """
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end

    @testset "Should NOT trigger - maker function" begin
        source = """
        function process(columns_list)
            results = Any[]
            for columns in columns_list
                push!(results, make_columnar_vector(columns))
            end
            return results
        end
        """
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end

    @testset "Should NOT trigger - constructor outside loop" begin
        source = """
        function process(columns)
            return ColumnarVector(columns)
        end
        """
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end

    @testset "Should NOT trigger - not in Compiler directory" begin
        source = """
        function process(columns_list)
            results = []
            for columns in columns_list
                push!(results, ColumnarVector(columns))
            end
            return results
        end
        """
        # Should not trigger outside src/Compiler/
        @test !lint_has_error_test(source, directory="src/API/")
    end

    @testset "Should NOT trigger - lowercase function (not constructor)" begin
        source = """
        function process(items)
            results = Any[]
            for item in items
                push!(results, process_item(item))
            end
            return results
        end
        """
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end
end

@testset "ClosureCaptureByValueRule" begin
    # Only triggers in src/Compiler/ directory
    # This is a recommendation, not a violation

    @testset "Should NOT trigger - short-form nested function (not yet supported)" begin
        # Short-form function definitions like `inner() = x + 1` are not
        # currently detected due to AST structure complexity
        source = """
        function outer(x)
            inner() = x + 1
            return inner()
        end
        """
        # This test documents current limitation
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end

    @testset "Should trigger - lambda function" begin
        source = """
        function create_adder(n)
            adder = x -> x + n
            return adder
        end
        """
        @test lint_test(source,
            "Nested function may capture variables by reference",
            directory="src/Compiler/")
    end

    @testset "Should trigger - anonymous function with do block" begin
        source = """
        function process(data)
            map(data) do item
                item * 2
            end
        end
        """
        @test lint_test(source,
            "Nested function may capture variables by reference",
            directory="src/Compiler/")
    end

    @testset "Should NOT trigger - full function definition (not yet supported)" begin
        # Full function...end nested functions are not detected due to
        # marker timing issues. They would need special handling.
        source = """
        function outer(x, y)
            function inner(z)
                return x + y + z
            end
            return inner(10)
        end
        """
        # This test documents that we DON'T detect full function...end yet
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end

    @testset "Should trigger - lambda closure with mutation" begin
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
            "Nested function may capture variables by reference",
            directory="src/Compiler/")
    end

    @testset "Should trigger - multiple nested functions" begin
        source = """
        function outer(n)
            add_n = x -> x + n
            multiply_n = x -> x * n
            return add_n(5) + multiply_n(3)
        end
        """
        # Should trigger for both closures (may be multiple times due to AST traversal)
        @test count_lint_errors(source, directory="src/Compiler/") >= 2
    end

    @testset "Should NOT trigger - not in Compiler directory" begin
        source = """
        function outer(x)
            inner() = x + 1
            return inner()
        end
        """
        # Should not trigger outside src/Compiler/
        @test !lint_has_error_test(source, directory="src/API/")
    end

    @testset "Should NOT trigger - no nested function (top-level)" begin
        source = """
        function standalone(x)
            return x + 1
        end
        """
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end

    @testset "Should NOT trigger - function call (not definition)" begin
        source = """
        function outer(items)
            return map(process_item, items)
        end
        """
        @test !lint_has_error_test(source, directory="src/Compiler/")
    end

    @testset "Recommended pattern - let binding" begin
        # This still triggers because we can't detect let bindings yet,
        # but documents the intended pattern
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
        # Note: This will still trigger a warning because the rule is conservative
        # It recommends let-binding but doesn't check if it's already there
        @test lint_test(source,
            "Nested function may capture variables by reference",
            directory="src/Compiler/")
    end
end

# Integration test - verify rules are registered
@testset "Rule Registration" begin
    # Check that new rules are in the rule list
    all_rule_names = string.(nameof.(ReLint.all_rules()))

    @test "ConstGlobalMissingTypeRule" in all_rule_names
    @test "IsNothingPerformanceRule" in all_rule_names
    @test "MissingAutoHashEqualsRule" in all_rule_names
    @test "NotFullyParameterizedConstructorRule" in all_rule_names
    @test "ClosureCaptureByValueRule" in all_rule_names
end
