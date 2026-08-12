FATAL_VIOLATIONS = RuleGroup("fatal violations")

# GeneratedRule
FATAL_VIOLATIONS["@generated"] = Rule(
    "@generated",
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
                 kind(do_node) == K"do" || return false
                 isempty(do_node.children[2].children) && return false
                 return kind(do_node.children[2].children[end]) == K"return"
             end
         end),
        (@pattern begin
             {m:::macrocall}
             @when [:m] begin
                 isempty(m.args) && return false
                 do_node = m.args[end]
                 kind(do_node) == K"do" || return false
                 isempty(do_node.children[2].children) && return false
                 return kind(do_node.children[2].children[end]) == K"return"
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

FATAL_VIOLATIONS["TODO PR"] = Rule(
    "TODO PR",
    "Use `TODO (RAI-XXXXX)` instead of `TODO PR` to refer to a Jira issue.",
    @comment r"TODO \(?PR\)?[\S\s]*"
)
