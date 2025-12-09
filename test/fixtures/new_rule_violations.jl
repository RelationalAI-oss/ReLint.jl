# Test fixtures for new ReLint rules - these should trigger warnings

# ConstGlobalMissingTypeRule violations
global untyped_global = 42  # Should warn: needs type annotation

# IsNothingPerformanceRule violations (in Compiler code)
# This would only trigger in src/Compiler/ directory
function check_value(x)
    if isnothing(x)  # Should warn in Compiler: use === nothing
        return 0
    end
    return x
end

# MissingAutoHashEqualsRule violations
struct Point  # Should warn: consider @auto_hash_equals
    x::Int
    y::Int
end

struct Location  # Should warn: consider @auto_hash_equals
    lat::Float64
    lon::Float64
end

# NotFullyParameterizedConstructorRule violations
# (Not fully implemented - would need loop detection)
function process_data(items)
    results = []
    for item in items
        # If ColumnarVector is parametric, this could be slow
        push!(results, SomeParametricType(item))
    end
    return results
end

# ClosureCaptureByValueRule violations
# (Not fully implemented - would need scope analysis)
function outer_function(x)
    inner = () -> x + 1  # Could benefit from let x = x
    if x < 0
        x = -x  # Mutates x
    end
    return inner()
end
