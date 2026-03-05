using Argus

general = RuleGroup("general")
recommendation = RuleGroup("recommendation")
violation = RuleGroup("violation")
fatal = RuleGroup("fatal")

@define_rule_in_group general "error" begin
    description = """
    Use custom exception instead of the generic `error()`.
    """

    pattern = @pattern error({_}...)
end

@define_rule_in_group general "in" begin
    description = """
    Use `tin(item,collection)` instead of the Julia's `in` or `∈`.
    """

    pattern = @pattern ~or(
        in({_}, {_}),
        ∈({_}, {_})
    )
end

@define_rule_in_group general "haskey" begin
    description = """
    Use `thaskey(dict,key)` instead of the Julia's `haskey`.
    """

    pattern = @pattern haskey({_}, {_})
end

# StringInterpolationRule
# TODO: `trivia` flag.
# @define_rule_in_group general "string-interpolation" begin
#     description = raw"""
#     Use $(x) instead of $x ([explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#string-interpolation)).
#     """

#     pattern = @pattern ...
# end

# ReturnTypeAnnotationRule
@define_rule_in_group general "return-type-annotation" begin
    description = """
    Avoid return type annotations `function foo()::Type`.
    Return type annotations can hurt performance by forcing type conversions.
    [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#type-annotations).
    """

    pattern = @pattern ~or(
        function ({f}({args}...)::{ret_type}) {_}... end,
        {_:::funcall}::{ret_type} = {_}
    )
end

# GeneratedRule
@define_rule_in_group fatal "generated" begin
    description = """
    Don't use `@generated`
    """

    pattern = @pattern @generated {_}...
end

# LogStatementsMustBeSafe
#
# TODO: Syntax classes with parameters (e.g. macrocall(r"@info|@warn|@error|@debug")).
@define_syntax_class :log_macro "log macro" begin
    @pattern begin
        {m:::macrocall}
        @fail [:m] begin
            log_macro_names = r"@info|@warn|@error|@debug"
            !startswith(m.name, log_macro_names)
        end ""
    end
end
@define_syntax_class :safe_macro_arg "safe macro argument" begin
    # Safe literal.
    @pattern begin
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
    end
    # Argument wrapped in `@safe`.
    @pattern ~or(@safe({args}...),
                 SafeLogging.@safe({args}...),
                 $SafeLogging.@safe({args}...))
    # Assignment with safe rhs.
    @pattern {_} = {arg:::safe_macro_arg}
end
# TODO: Rewrite with `not` pattern?
@define_rule_in_group fatal "unsafe-logging" begin
    description = """
    Unsafe logging statement. You must enclose variables and strings with `@safe(...)`.
    """

    pattern = @pattern begin
        {log_macro:::log_macro}
        @fail [:log_macro] begin
            for s in log_macro.args
                c = Argus.SYNTAX_CLASS_REGISTRY[:safe_macro_arg]
                is_successful(syntax_match(c, s)) || return false
            end
            return true
        end "log macro call with no unsafe args";
    end
end

# AssertionStatementsMustBeSafe
#
# TODO: Syntax classes with parameters (e.g. macrocall(r"@assert|@dassert")).
@define_syntax_class :assert_macro "assert macro" begin
    @pattern begin
        {m:::macrocall}
        @fail [:m] begin
            assert_macro_names = r"@assert|@dassert"
            !startswith(m.name, assert_macro_names)
        end ""
    end
end
@define_rule_in_group fatal "unsafe-assert" begin
    description = """
    Unsafe assertion statement. You must enclose the message with `@safe(...)`.
    """

    pattern = @pattern begin
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
end

# NonFrontShapeAPIUsageRule

# MustNotUseShow
#
# TODO: Template.
@define_rule_in_group fatal "show" begin
    description = """
    Do not use `@show`, use `@info` instead.
    """

    pattern = @pattern @show {_}...
end

# NoinlineAndLiteralRule
#
# TODO: Splatting.
@define_syntax_class :noinline_with_non_lit_or_id_args "@nonline call with non lit or id args" begin
    # Call or dotcall.
    @pattern begin
        ~or(
            @noinline(({_})({args}...)),
            @noinline(({_}).({args}...)),
        )
        @fail [:args] begin
            for s in args.src
                k = kind(s)
                k == JuliaSyntax.K"parameters" && break
                JuliaSyntax.is_literal(s) || JuliaSyntax.is_identifier(s) || k == JuliaSyntax.K"char" || k == JuliaSyntax.K"string" ||
                    return false
            end
            return true
        end ""
    end
    # Call or dotcall with kwargs.
    @pattern begin
        ~or(
            @noinline(({_})({args}...; {kwargs}...)),
            @noinline(({_}).({args}...; {kwargs}...))
        )
        @fail [:args, :kwargs] begin
            for s in args.src
                k = kind(s)
                JuliaSyntax.is_literal(s) || JuliaSyntax.is_identifier(s) || k == JuliaSyntax.K"char" || k == JuliaSyntax.K"string" ||
                    return false
            end
            for kws in kwargs.src
                k = kind(kws)
                JuliaSyntax.is_literal(kws) || JuliaSyntax.is_identifier(kws) || k == JuliaSyntax.K"char" || k == JuliaSyntax.K"string" ||
                    k == JuliaSyntax.K"=" && (JuliaSyntax.is_literal(kws.children[2]) || JuliaSyntax.is_identifier(kws.children[2])) ||
                    return false
            end
            return true
        end ""
    end
    # Macrocall.
    @pattern begin
        @noinline({c:::macrocall})
        @fail [:c] begin
            for s in c.args
                k = kind(s)
                JuliaSyntax.is_literal(s) || JuliaSyntax.is_identifier(s) || #k == Kind("char") || k == Kind("string") ||
                    return false
            end
            return true
        end ""
    end
end
# TODO: Support for allowing match if the source and pattern differ only by a flag
#       (e.g. INFIX_FLAG).
@define_rule_in_group fatal "noinline-literal" begin
    description = """
    For call-site `@noinline` call, all args must be literals or identifiers only. \
    Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086).
    """

    pattern = @pattern {n:::noinline_with_non_lit_or_id_args}
end

# NoReturnInAnonymousFunctionRule
