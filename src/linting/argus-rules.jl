using Argus

# Rule metadata
# =============

# TODO: `string_literal` syntax class
@define_rule_hook :exclude_files begin
    args = @pattern [{files}...]

    pre_check = @check [:files] begin
        file_names = map(s -> s.children[1].val, files.src)
        if current_file() in file_names
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
    [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#type-annotations).
    """,
    @pattern ~or(
        function ({f}({args}...)::{ret_type}) {_}... end,
        {_:::funcall}::{ret_type} = {_}
    )
)

# Violation rules
# ===============

VIOLATIONS = RuleGroup("violations")

# TODO: Template for `@spawn`.
VIOLATIONS["`@async`"] = Rule(
    "`@async`",
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
            ~fail([:m], !in(m.name, ["@match", "@matchrule"]), "")
        )))
    )),
    Dict(
        :only_in_dir => "src/Compiler"
    )
)

VIOLATIONS["error"] = Rule(
    "error",
    "Use custom exception instead of the generic `error()`.",
    @pattern error({_}...)
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
            @fail [:m] begin
                log_macro_names = r"@info|@warn|@error|@debug"
                !startswith(m.name, log_macro_names)
            end ""
        end
    ]
))

register_syntax_class!(:safe_macro_arg, SyntaxClass(
    "safe macro argument",
    [
        # Safe literal.
        (@pattern begin
             {arg}
             @fail [:arg] begin
                 s = arg.src
                 k = kind(s)
                 # Strings are not safe.
                 k == K"string" || endswith(string(k), "String") && return true
                 # `nothing` is safe.
                 !isnothing(s.data.val) && s.data.val == :nothing && return false
                 # Chars and literals other than strings are safe.
                 (JuliaSyntax.is_literal(s) || k == K"char") && return false
                 # Anything else is not safe.
                 return true
             end ""
         end),
        # Argument wrapped in `@safe`.
        (@pattern ~or(@safe({args}...),
                      SafeLogging.@safe({args}...),
                      $SafeLogging.@safe({args}...))),
        # Assignment with safe rhs.
        (@pattern {_} = {arg:::safe_macro_arg})
    ]
))
# TODO: Rewrite with `not` pattern?
FATAL_VIOLATIONS["unsafe-logging"] = Rule(
    "unsafe-logging",
    "Unsafe logging statement. You must enclose variables and strings with `@safe(...)`.",
    @pattern begin
        {log_macro:::log_macro}
        @fail [:log_macro] begin
            for s in log_macro.args
                c = Argus.SYNTAX_CLASS_REGISTRY[:safe_macro_arg]
                is_successful(syntax_match(c, s)) || return false
            end
            return true
        end "log macro call with no unsafe args";
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
            @fail [:m] begin
                assert_macro_names = r"@assert|@dassert"
                !startswith(m.name, assert_macro_names)
            end ""
        end
    ]
))
FATAL_VIOLATIONS["unsafe-assert"] = Rule(
    "unsafe-assert",
    "Unsafe assertion statement. You must enclose the message with `@safe(...)`.",
    @pattern begin
        {assert_macro:::assert_macro}
        @fail [:assert_macro] begin
            # Assert macro call with one argument is safe (the matching fails).
            length(assert_macro.args) == 1 && return true
            for s in assert_macro.args[2:end]
                c = Argus.SYNTAX_CLASS_REGISTRY[:safe_macro_arg]
                is_successful(syntax_match(c, s)) || return false
            end
            # All assert macro call arguments are safe.
            return true
        end "assert macro call with no unsafe args";
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
#
# TODO: Splatting.
register_syntax_class!(:noinline_with_non_lit_or_id_args, SyntaxClass(
    "@nonline call with non lit or id args",
    [
        # Call or dotcall.
        (@pattern begin
             ~or(
                 @noinline(({_})({args}...)),
                 @noinline(({_}).({args}...)),
             )
             @fail [:args] begin
                 for s in args.src
                     k = kind(s)
                     k == K"parameters" && break
                     JuliaSyntax.is_literal(s) ||
                         JuliaSyntax.is_identifier(s) ||
                         k == K"char" ||
                         k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                         k == K"..." ||
                         return false
                 end
                 return true
             end ""
         end),
        # Call or dotcall with kwargs.
        (@pattern begin
             ~or(
                 @noinline(({_})({args}...; {kwargs}...)),
                 @noinline(({_}).({args}...; {kwargs}...))
             )
             @fail [:args, :kwargs] begin
                 for s in args.src
                     k = kind(s)
                     JuliaSyntax.is_literal(s) ||
                         JuliaSyntax.is_identifier(s) ||
                         k == K"char" ||
                         k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                         k == K"..." ||
                         return false
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
                         return false
                 end
                 return true
             end ""
         end),
        # Macrocall.
        (@pattern begin
             @noinline({c:::macrocall})
             @fail [:c] begin
                 for s in c.args
                     k = kind(s)
                     JuliaSyntax.is_literal(s) ||
                         JuliaSyntax.is_identifier(s) ||
                         k == JuliaSyntax.K"char" ||
                         k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                         k == K"..." ||
                         return false
                 end
                 return true
             end ""
         end),
        # Infix call.
        (@pattern begin
             ~or(@noinline({i:::infix_call}),
                 @noinline({i:::infix_dotcall}))
             @fail [:i] begin
                 # Check lhs.
                 s = i.lhs.src
                 k = kind(s)
                 JuliaSyntax.is_literal(s) ||
                     JuliaSyntax.is_identifier(s) ||
                     k == K"char" ||
                     k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                     k == K"..." ||
                     return false
                 # Check rhs.
                 s = i.rhs.src
                 k = kind(s)
                 JuliaSyntax.is_literal(s) ||
                     JuliaSyntax.is_identifier(s) ||
                     k == K"char" ||
                     k == K"string" && all(c -> isa(c.data.val, String), s.children) ||
                     k == K"..." ||
                     return false
                 return true
             end ""
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
             @fail [:f] begin
                 isempty(f.args.src) && return true
                 do_node = f.args.src[end]
                 return !(kind(do_node) == K"do" &&
                     kind(do_node.children[2].children[end]) == K"return")
             end ""
         end),
        (@pattern begin
             {m:::macrocall}
             @fail [:m] begin
                 isempty(m.args) && return true
                 do_node = m.args[end]
                 return !(kind(do_node) == K"do" &&
                     kind(do_node.children[2].children[end]) == K"return")
             end ""
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
