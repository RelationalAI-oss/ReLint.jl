RECOMMENDATIONS = RuleGroup("recommendations")

# CcallRule
RECOMMENDATIONS["ccall"] = Rule(
    "ccall",
    "`ccall` should be used with extreme caution.",
    @pattern ccall({_}...)
)

# FinalizerRule
RECOMMENDATIONS["finalizer"] = Rule(
    "finalizer",
    "`finalizer(_,_)` should not be used.",
    @pattern finalizer({_}...)
)

# CFunctionRule
RECOMMENDATIONS["@cfunction"] = Rule(
    "@cfunction",
    "`@cfunction` should not be used.",
    @pattern @cfunction({_}...)
)

# UnlockRule
RECOMMENDATIONS["unlock"] = Rule(
    "unlock",
    "`unlock` should be used with extreme caution.",
    @pattern unlock({_})
)

# YieldRule
RECOMMENDATIONS["yield"] = Rule(
    "yield",
    "`yield` should be used with extreme caution.",
    @pattern yield()
)

# SleepRule
RECOMMENDATIONS["sleep"] = Rule(
    "sleep",
    "`sleep` should be used with extreme caution.",
    @pattern sleep({_})
)

# InboundsRule
RECOMMENDATIONS["@inbounds"] = Rule(
    "@inbounds",
    "`@inbounds` should be used with extreme caution.",
    @pattern @inbounds({_})
)

# ThreadsRule
RECOMMENDATIONS["@threads"] = Rule(
    "@threads",
    "`@threads` should be used with extreme caution.",
    @pattern ~or(@threads({_}), Threads.@threads({_}))
)

# SyncRule
RECOMMENDATIONS["@sync"] = Rule(
    "@sync",
    "`@sync` should be used with extreme caution.",
    @pattern ~or(@sync({_}), Threads.@sync({_}))
)

# SplattingRule
RECOMMENDATIONS["splatting"] = Rule(
    "splatting",
    """
    Splatting (`...`) should be used with extreme caution. Splatting from dynamically \
    sized containers could result in severe performance degradation. Splatting from \
    statically-sized tuples is usually okay.""",
    (@pattern ~and(
        {_}(@esc(({_}...)..., 1)),
        ~not(~inside({_:::macrodef}))
    )),
    Dict(
        :exclude_files => ["test.jl", "tests.jl"]
    )
)

# InterpolationInSafeLogRule
RECOMMENDATIONS["interpolation in `@warnv_safe_to_log`"] = Rule(
    "interpolation in `@warnv_safe_to_log`",
    "Safe warning log has interpolation.",
    @pattern @warnv_safe_to_log {_} "$({_}...)$({x:::identifier})$({_}...)"
)

# ReturnTypeAnnotationRule
RECOMMENDATIONS["return type annotation"] = Rule(
    "return type annotation",
    """
    Avoid return type annotations `function foo()::Type`. \
    Return type annotations can hurt performance by forcing type conversions.""",
    (@pattern ~and(
        ~or(
            function ({f}({args}...)::{ret_type}) {_}... end,
            {_:::funcall}::{ret_type} = {_}
        ),
        ~not(~inside(@derived {_}...))
    )),
    Dict(
        :exclude_files => ["test/", "test.jl"]
    )
)

# StringConcatenationRule
RECOMMENDATIONS["string concatenation"] = Rule(
    "string concatenation",
    """
    Prefer string interpolation or `string()` over `*` for string concatenation. \
    Use `\"\$(a)\$(b)\"` instead of `a * b`.""",
    (@pattern ~or(
        {_:::string} * {_},
        {_} * {_:::string}
    )),
    Dict(
        :exclude_files => ["test/", "test.jl"]
    )
)

# NoGlobalVariablesRule
#
# Removed because it is too similar to "non-const untyped global" in `VIOLATIONS`.

# IsNothingPerformanceRule
RECOMMENDATIONS["isnothing"] = Rule(
    "isnothing",
    """
    In performance-critical code, prefer `x === nothing` or `x isa Nothing` over \
    `isnothing(x)`""",
    (@pattern isnothing({_})),
    Dict(
        :only_in_dirs => ["src/Compiler/", "packages/Salsa/"],
        :exclude_files => ["test/", "test.jl"]
    )
)

# ClosureCaptureByValueRule
RECOMMENDATIONS["closure capture by reference"] = Rule(
    "closure capture by reference",
    """
    Nested function may capture variables by reference, causing boxing and type \
    instability. Consider using `let x = x` to capture by value for better performance.""",
    (@pattern ~and(
        ~or(
            ({_}...) -> {_},  # Anonymous function.
            {_}({_}...) do {x}...  # `do` block.
                {_}...
            end,
            {_:::fundef}  # Function definition
        ),
        ~inside({_:::fundef}),
        ~not(~inside(let {_}...
            {_}...
        end))
    )),
    Dict(
        :only_in_dirs => ["src/Compiler/"],
        :exclude_files => ["test/", "test.jl"]
    )
)

# AccessingENVRuleq
RECOMMENDATIONS["mutating ENV"] = Rule(
    "mutating ENV",
    """
    Mutating `ENV` is not thread-safe, only do so in a single-threaded context.""",
    @pattern ~or(
        ENV[{_}] = {_},
        ~and(
            {mutating_fun}(ENV, {_}...),
            ~when([:mutating_fun],
                  mutating_fun.name in ["pop!", "delete!", "setindex!", "get!", "push!"])
        )
    )
)
