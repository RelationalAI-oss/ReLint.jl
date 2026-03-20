using Argus

# Rule metadata
# =============

# TODO: `string_literal` syntax class
@define_rule_hook :exclude_files begin
    args = @pattern [{files}...]

    pre_check = @check [:files] begin
        file_names = map(s -> s.children[1].val, files.src)
        if any(contains.(current_file(), file_names))
            skip_match()
        end
    end

    post_check = nothing
end

@define_rule_hook :only_in_dir begin
    args = @pattern {dir}

    pre_check = @check [:dir] begin
        dir_name = dir.src.children[1].val
        if !contains(current_file(), dir_name)
            skip_match()
        end
    end

    post_check = nothing
end

# Recommendation rules
# ====================

RECOMMENDATIONS = RuleGroup("recommendations")

# ReturnTypeAnnotationRule
RECOMMENDATIONS["return-type-annotation"] = Rule(
    "return-type-annotation",
    """
    Avoid return type annotations `function foo()::Type`.
    Return type annotations can hurt performance by forcing type conversions.
    [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#type-annotations).""",
    @pattern ~or(
        function ({f}({args}...)::{ret_type}) {_}... end,
        {_:::funcall}::{ret_type} = {_}
    )
)

# Violation rules
# ===============

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
VIOLATIONS["initializing with `is_local_deployment`"] = Rule(
    "initializing with `is_local_deployment`",
    "`is_local_deployment()` should not be used in a constant variable.",
    @pattern ~or(
        :(const {_} = is_local_deployment()),
        :(const {_} = Deployment.is_local_deployment())
    )
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
        :only_in_dir => "src/Compiler"
    )
)

VIOLATIONS["in"] = Rule(
    "in",
    "Use `tin(item,collection)` instead of the Julia's `in` or `∈`.",
    @pattern ~or(
        in({_}, {_}),
        ∈({_}, {_})
    )
)

VIOLATIONS["haskey"] = Rule(
    "haskey",
    "Use `thaskey(dict,key)` instead of the Julia's `haskey`.",
    @pattern haskey({_}, {_})
)

VIOLATIONS["remove_page"] = Rule(
    "remove_page",
    "`remove_page` should be used with extreme caution.",
    @pattern remove_page({_}, {_})
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

# InRule

# HasKeyRule

# EqualRule

# UvRule

# UnreachableBranchRule

# StringInterpolationRule

# RelPathAPIUsageRule

# UseOfStaticThreads

# NoImportRule

# NotImportingRAICodeRule

# BareUsingRule

# UntypedArrayComprehensionRule

# ConstGlobalMissingTypeRule

# NotFullyParametrizedConstructorRule

# StringInterpolationRule
# TODO: `trivia` flag.
# VIOLATIONS["string-interpolation"] = Rule(
#     "string-interpolation",
#     raw"Use $(x) instead of $x ([explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#string-interpolation)).",
#     @pattern ...
# )

# Fatal rules
# ===========

FATAL_VIOLATIONS = RuleGroup("fatal violations")

# GeneratedRule
FATAL_VIOLATIONS["generated"] = Rule(
    "generated",
    "`@generated` should be used with extreme caution.",
    @pattern @generated {_}...
)

# LogStatementsMustBeSafe
#
# TODO: Syntax classes with parameters (e.g. macrocall(r"@info|@warn|@error|@debug")).
register_syntax_class!(:log_macro, SyntaxClass(
    "log macro",
    [
        @pattern begin
            {m:::macrocall}
            @when [:m] begin
                log_macro_names = r"@info|@warn|@error|@debug"
                startswith(m.name, log_macro_names)
            end
        end
    ]
))

register_syntax_class!(:safe_macro_arg, SyntaxClass(
    "safe macro argument",
    [
        # Safe literal.
        (@pattern begin
             {arg}
             @when [:arg] begin
                 s = arg.src
                 k = kind(s)
                 # Strings are not safe.
                 (k == K"string" || endswith(string(k), "String")) && return false
                 # `nothing` is safe.
                 !isnothing(s.data.val) && s.data.val == :nothing && return true
                 # Chars and literals other than strings are safe.
                 (JuliaSyntax.is_literal(s) || k == K"char") && return true
                 # Anything else is not safe.
                 return false
             end
         end),
        # Argument wrapped in `@safe`.
        (@pattern ~or(@safe({args}...),
                      SafeLogging.@safe({args}...),
                      $SafeLogging.@safe({args}...))),
        # Assignment with safe rhs.
        (@pattern {_} = {arg:::safe_macro_arg})
    ]
))

FATAL_VIOLATIONS["unsafe-logging"] = Rule(
    "unsafe-logging",
    """
    Unsafe logging statement. \
    You must enclose variables and strings with `@safe(...)`.""",
    @pattern begin
        {log_macro:::log_macro}
        @when [:log_macro] begin
            for s in log_macro.args
                c = Argus.SYNTAX_CLASS_REGISTRY[:safe_macro_arg]
                is_successful(syntax_match(c, s)) || return true
            end
            return false
        end
    end
)

# AssertionStatementsMustBeSafe
#
# TODO: Syntax classes with parameters (e.g. macrocall(r"@assert|@dassert")).
register_syntax_class!(:assert_macro, SyntaxClass(
    "assert macro",
    [
        @pattern begin
            {m:::macrocall}
            @when [:m] begin
                assert_macro_names = r"@assert|@dassert"
                startswith(m.name, assert_macro_names)
            end
        end
    ]
))
FATAL_VIOLATIONS["unsafe-assert"] = Rule(
    "unsafe-assert",
    """
    Unsafe assertion statement. \
    You must enclose the message with `@safe(...)`.""",
    @pattern begin
        {assert_macro:::assert_macro}
        @when [:assert_macro] begin
            # Assert macro call with one argument is safe.
            length(assert_macro.args) == 1 && return false
            for s in assert_macro.args[2:end]
                c = Argus.SYNTAX_CLASS_REGISTRY[:safe_macro_arg]
                is_successful(syntax_match(c, s)) || return true
            end
            # All assert macro call arguments are safe.
            return false
        end
    end
)

# NonFrontShapeAPIUsageRule

# MustNotUseShow
#
# TODO: Template.
FATAL_VIOLATIONS["show"] = Rule(
    "show",
    "Do not use `@show`, use `@info` instead.",
    @pattern @show {_}...
)

# NoinlineAndLiteralRule
register_syntax_class!(:noinline_with_non_lit_or_id_args, SyntaxClass(
    "@nonline call with non lit or id args",
    [
        # Call or dotcall.
        (@pattern begin
             ~or(
                 @noinline(({_})({args}...)),
                 @noinline(({_}).({args}...)),
             )
             @when [:args] begin
                 for s in args.src
                     k = kind(s)
                     k == K"parameters" && break
                     JuliaSyntax.is_literal(s) ||
                         JuliaSyntax.is_identifier(s) ||
                         k == K"char" ||
                         k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                         k == K"..." ||
                         return true
                 end
                 return false
             end
         end),
        # Call or dotcall with kwargs.
        (@pattern begin
             ~or(
                 @noinline(({_})({args}...; {kwargs}...)),
                 @noinline(({_}).({args}...; {kwargs}...))
             )
             @when [:args, :kwargs] begin
                 for s in args.src
                     k = kind(s)
                     JuliaSyntax.is_literal(s) ||
                         JuliaSyntax.is_identifier(s) ||
                         k == K"char" ||
                         k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                         k == K"..." ||
                         return true
                 end
                 for kws in kwargs.src
                     k = kind(kws)
                     JuliaSyntax.is_literal(kws) ||
                         JuliaSyntax.is_identifier(kws) ||
                         k == K"char" ||
                         k == K"string" ||
                         k == K"..." ||
                         k == K"=" && (JuliaSyntax.is_literal(kws.children[2]) ||
                         JuliaSyntax.is_identifier(kws.children[2])) ||
                         return true
                 end
                 return false
             end
         end),
        # Macrocall.
        (@pattern begin
             @noinline({c:::macrocall})
             @when [:c] begin
                 for s in c.args
                     k = kind(s)
                     JuliaSyntax.is_literal(s) ||
                         JuliaSyntax.is_identifier(s) ||
                         k == JuliaSyntax.K"char" ||
                         k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                         k == K"..." ||
                         return true
                 end
                 return false
             end
         end),
        # Infix call.
        (@pattern begin
             ~or(@noinline({i:::infix_call}),
                 @noinline({i:::infix_dotcall}))
             @when [:i] begin
                 # Check lhs.
                 s = i.lhs.src
                 k = kind(s)
                 JuliaSyntax.is_literal(s) ||
                     JuliaSyntax.is_identifier(s) ||
                     k == K"char" ||
                     k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                     k == K"..." ||
                     return true
                 # Check rhs.
                 s = i.rhs.src
                 k = kind(s)
                 JuliaSyntax.is_literal(s) ||
                     JuliaSyntax.is_identifier(s) ||
                     k == K"char" ||
                     k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                     k == K"..." ||
                     return true
                 return false
             end
         end)
    ]
))
# TODO: Support for allowing match if the source and pattern differ only by a flag
#       (e.g. INFIX_FLAG).
FATAL_VIOLATIONS["noinline with non-literal/identifier args"] = Rule(
    "noinline with non-literal/identifier args",
    """
    For call-site `@noinline` call, all args must be literals or identifiers only. \
    Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).
    """,
    @pattern {n:::noinline_with_non_lit_or_id_args}
)

# NoReturnInAnonymousFunctionRule
register_syntax_class!(:do_call_with_return, SyntaxClass(
    "do call with explicit `return`",
    [
        (@pattern begin
             {f:::funcall}
             @when [:f] begin
                 isempty(f.args.src) && return false
                 do_node = f.args.src[end]
                 return kind(do_node) == K"do" &&
                     kind(do_node.children[2].children[end]) == K"return"
             end
         end),
        (@pattern begin
             {m:::macrocall}
             @when [:m] begin
                 isempty(m.args) && return false
                 do_node = m.args[end]
                 return kind(do_node) == K"do" &&
                     kind(do_node.children[2].children[end]) == K"return"
             end
         end)
    ]
))

FATAL_VIOLATIONS["return in anonymous function"] = Rule(
    "return in anonymous function",
    "Anonymous function must not have `return` [Explanation](https://github.com/RelationalAI/RAIStyle#returning-from-a-closure).",
    @pattern ~or(
        ({_}...) -> begin
            {_}...
            return {_}...
        end,
        {_:::do_call_with_return}
    )
)
