# Test fixtures for new ReLint rules - these should NOT trigger warnings

# ConstGlobalMissingTypeRule - valid patterns
const MAX_RETRIES = 3  # const is fine
global typed_global::Int = 42  # typed global is fine

# IsNothingPerformanceRule - valid patterns
function check_value_correct(x)
    # In Compiler code, use === nothing instead
    if x === nothing
        return 0
    end
    return x
end

function check_value_isa(x)
    # Or use isa Nothing
    if x isa Nothing
        return 0
    end
    return x
end

# In non-Compiler code, isnothing() is fine
function api_check(x)
    if isnothing(x)  # OK in API code
        return 0
    end
    return x
end

# MissingAutoHashEqualsRule - valid patterns
using AutoHashEquals

@auto_hash_equals struct GoodPoint
    x::Int
    y::Int
end

struct _PrivateStruct  # Private structs (prefix _) don't need it
    x::Int
end

# NotFullyParameterizedConstructorRule - valid pattern
function process_data_correctly(items)
    results = []
    for item in items
        # Use maker function instead of constructor
        push!(results, make_some_type(item))
    end
    return results
end

# ClosureCaptureByValueRule - valid pattern
function outer_function_correct(x)
    # Capture by value using let
    inner = let x = x
        () -> x + 1
    end
    if x < 0
        x = -x
    end
    return inner()
end
