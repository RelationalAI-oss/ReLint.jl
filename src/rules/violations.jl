VIOLATIONS = RuleGroup("violations")

# TODO: Template for `@spawn`.
VIOLATIONS["@async"] = Rule(
    "@async",
    "Use `@spawn` instead of `@async`.",
    @pattern ~or(@async({_}), Threads.@async({_}))
)

# TODO: Pattern variables in rule messages.
VIOLATIONS["initializing with `nthreads`"] = Rule(
    "initializing with `nthreads`",
    "`Threads.nthreads()` should not be used in a constant variable.",
    @pattern const {_} = Threads.nthreads()
)

VIOLATIONS["array with no specific type"] = Rule(
    "array with no specific type",
    "Need a specific Array type to be provided.",
    (@pattern ~and(
        [],
        ~not(~inside(~and(
            {m:::macrocall},
            ~when([:m], m.name in ["@match", "@matchrule"])
        )))
    )),
    Dict(
        :only_in_dirs => ["src/Compiler"]
    )
)

VIOLATIONS["Task"] = Rule(
    "Task",
    "`Task` should be used with extreme caution.",
    @pattern Task({_})
)

VIOLATIONS["ErrorException"] = Rule(
    "ErrorException",
    "Use custom exception instead of the generic `ErrorException`.",
    (@pattern ErrorException({_}...)),
    Dict(
        :exclude_files => ["test.jl", "tests.jl", "bench/", "Vectorized/Test"]
    )
)

VIOLATIONS["error"] = Rule(
    "error",
    "Use custom exception instead of the generic `error()`.",
    (@pattern error({_}...)),
    Dict(
        :exclude_files => ["test.jl", "tests.jl", "bench/", "Vectorized/Test"]
    )
)

register_syntax_class!(:unsafe_funcall, SyntaxClass(
    "`unsafe_*` function call",
    [
        @pattern begin
            {_f:::funcall}
            @when [:_f] startswith(_f.fun_name.name, r"_?unsafe_")
        end
    ]
))
VIOLATIONS["unsafe_ function"] = Rule(
    "unsafe_ function",
    "An `unsafe_` function should be called only from an `unsafe_` function.",
    @pattern ~and(
        {_:::unsafe_funcall},
        ~not(~inside(~or(
            {_:::unsafe_funcall} = {_},
            function ({_:::unsafe_funcall}) {_}... end
        )))
    )
)

# TODO: Find a way to express this in its most general form. Something like:
#
# @pattern ~or(
#     if {cond}
#         {_}...
#     (elseif {_} {_}...)...
#     elseif {cond}
#         {_}...
#     end,
#     if {cond}
#         {_}...
#     (elseif {_} {_}...)...
#     elseif {cond}
#         {_}...
#     else
#         {_}...
#     end
VIOLATIONS["unreachable branch"] = Rule(
    "unreachable branch",
    "Unreachable branch.",
    @pattern ~or(
        if {cond}
            {_}...
        elseif {cond}
            {_}...
        end,
        if {cond}
            {_}...
        elseif {cond}
            {_}...
        else
            {_}...
        end,
        if {cond}
            {_}...
        elseif {_}
            {_}...
        elseif {cond}
            {_}...
        end,
        if {cond}
            {_}...
        elseif {_}
            {_}...
        elseif {cond}
            {_}...
        else
            {_}...
        end
    )
)

VIOLATIONS["string interpolation"] = Rule(
    "string interpolation",
    "Use \$(x) instead of \$x.",
    @pattern ~and(
        "$({_}...)$({x:::identifier})$({_}...)",
        ~when([:x], !inside_parens(x.src))
    )
)

VIOLATIONS["static threads"] = Rule(
    "static threads",
    """
    Use `Threads.@threads :dynamic` instead of `Threads.@threads :static`. Static threads \
    must not be used as generated tasks will not be able to migrate across threads.""",
    @pattern ~or(
        (@threads :static {_}...),
        Threads.@threads :static {_}...
    )
)

VIOLATIONS["no import"] = Rule(
    "no import",
    "Imports must be specified with `using` and not `import`.",
    @pattern {_:::import}
)

VIOLATIONS["bare using"] = Rule(
    "bare using",
    "Use `using Foo: Foo` or `using Foo: specific_function` instead of bare `using Foo`.",
    (@pattern begin
         {u:::using}
         @when [:u] isempty(u.ids.src)
     end),
    Dict(
        :exclude_files => ["test/", "test.jl"]
    )
)

VIOLATIONS["untyped array comprehension"] = Rule(
    "untyped array comprehension",
    """
    Need a specific Array type to be provided. \
    Use `T[x for x in xs]` instead of `[x for x in xs]`.""",
    (@pattern [{_} for {_} in {_}]),
    Dict(
        :only_in_dirs => ["src/Compiler/"]
    )
)

register_syntax_class!(:const, SyntaxClass(
    "const assignment",
    [
        (@pattern const {_} = {_}),
        (@pattern const global {_} = {_})
    ]
))
VIOLATIONS["non-const untyped global"] = Rule(
    "non-const untyped global",
    """
    Global variable must have type annotation: `global x::Type = value`. \
    Use `const` for immutable globals.""",
    (@pattern ~and(
        :(global {_:::identifier} = {_}),
        ~not(~inside({_:::const}, 1))
    )),
    Dict(
        :exclude_files => ["test/", "test.jl"]
    )
)

register_syntax_class!(:loop, SyntaxClass(
    "`for` or `while` loop",
    [
        (@pattern (for {_} in {_}
            {_}...
        end)),
        (@pattern (for {_} = {_}
            {_}...
        end)),
        (@pattern (for {_} ∈ {_}
            {_}...
        end)),
        (@pattern while {_}
            {_}...
        end)
    ]
))
VIOLATIONS["not fully parametrised constructor"] = Rule(
    "not fully parametrised constructor",
    """
    Avoid not-fully-parameterized constructor in loops. \
    Use a maker function instead for better performance.""",
    (@pattern ~and(
        {id:::identifier}({_}...),
        ~inside({_:::loop}),
        ~when([:id], startswith(id.name, r"[A-Z]"))
    )),
    Dict(
        :only_in_dirs => ["src/Compiler"],
        :exclude_files => ["test/", "test.jl"]
    )
)
