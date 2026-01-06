#################################################################################
# This file contains many specific and extended rules for Lint.
# You probably needs to modify this files if:
#   - you wish to add a new lint rule
#   - document an existing rule
#
# If you wish to add a new Lint rule, you need:
#   1. Define a new type, subtype of RecommendationLintRule or ViolationLintRule
#   2. Write a new function function check(t::YOUR_NEW_TYPE, x::EXPR)
#   3. Add your unit tests in rai_rules_tests.jl
#   4. Restart your REPL if you use it
#
# If you wish to modify the report produced by Lint, interface.jl
# is probably the place to start, not this file.
#################################################################################


# abstract type LintFileExclusion end

struct LintContext
    rules_to_run::Vector{DataType}
    regex_exclusions #::Vector{LintFileExclusion}

    function LintContext(dts_as_str::Vector{String})
        dt = DataType[]
        for dt_as_str in dts_as_str
            ind = findfirst(t -> nameof(t) == Symbol(dt_as_str), all_rules())
            isnothing(ind) && error("Non-existing rule: $(dt_as_str)")
            push!(dt, all_rules()[ind])
        end
        return new(dt, [])
    end

    LintContext(s::Vector{DataType}) = new(s, [])
    LintContext(s::Vector{Any}) = new(convert(Vector{DataType}, s) , [])
    LintContext() = new(all_rules(), [])
    LintContext(a, b) = new(a, b)
end

#################################################################################
# UTILITY FUNCTIONS
#################################################################################
headof(x::EXPR) = x.head
valof(x::EXPR) = x.val
# kindof(t::Tokens.AbstractToken) = t.kind
parentof(x::EXPR) = x.parent
errorof(x::EXPR) = errorof(x.meta)
errorof(x) = x
haserror(m::LintMeta) = m.error !== nothing
haserror(x::EXPR) = hasmeta(x) && haserror(x.meta)
hasmeta(x::EXPR) = x.meta isa LintMeta

function seterror!(x::EXPR, e)
    if !hasmeta(x)
        x.meta = LintMeta()
    end
    x.meta.error = e
end

# Calling fetch_value with recursion_depth = 0 means no recursion will happen
function fetch_value(x::EXPR, tag::Symbol, should_get_value::Bool=true, recursion_depth::Int=-1, skip_head::Bool=false)
    if headof(x) == tag && !skip_head
        # @info x
        if should_get_value
            return x.val
        else # return the AST
            return x
        end
    else
        isnothing(x.args) && return nothing
        iszero(recursion_depth) && return nothing
        for i in 1:length(x.args)
            r = fetch_value(x.args[i], tag, should_get_value, recursion_depth-1, false)
            isnothing(r) || return r
        end
        return nothing
    end
end

function fetch_values(x::EXPR, tag::Symbol, should_get_value::Bool=true)
    # TODO!!!
end

function collect_lint_report(x::EXPR, isquoted=false, errs=Tuple{Int,EXPR}[], pos=0)
    if haserror(x)
        push!(errs, (pos, x))
    end

    for i in 1:length(x)
        collect_lint_report(x[i], isquoted, errs, pos)
        pos += x[i].fullspan
    end

    errs
end

ast_rules(context::LintContext) = filter(t -> t <: ASTLintRule, context.rules_to_run)
line_rules(context::LintContext) = filter(t -> t <: LineLintRule, context.rules_to_run)

# TODO: Need to be careful here. We actually need a linked list of markers, and not
# a dictionary.
function check_all(
    x::EXPR,
    markers::Dict{Symbol,String} =Dict{Symbol,String}(),
    context::LintContext=LintContext()
)
    # Setting up the markers
    if headof(x) === :const
        markers[:const] = fetch_value(x, :IDENTIFIER)
    end

    if headof(x) === :function
        markers[:function] = fetch_value(x, :IDENTIFIER)
    end

    if headof(x) === :macro
        markers[:macro] = fetch_value(x, :IDENTIFIER)
    end

    if headof(x) === :macrocall
        id = fetch_value(x, :IDENTIFIER)
        if !isnothing(id)
            markers[:macrocall] = id
        end
    end

    if typeof(x) == EXPR && typeof(x.head) == EXPR && headof(x.head) === :OPERATOR && x.head.val == "->"
        markers[:anonymous_function] = "anonymous"
    end

    if headof(x) === :do
        markers[:anonymous_function] = "anonymous"
    end

    # Track loop context for NotFullyParameterizedConstructorRule
    if headof(x) === :for || headof(x) === :while
        markers[:in_loop] = "true"
    end

    for T in ast_rules(context)
        check_with_process(T, x, markers)
        if haserror(x) && x.meta.error isa LintRuleReport
            lint_rule_report = x.meta.error
            if haskey(markers, :filename)
                lint_rule_report.file = markers[:filename]
            end
        end
    end

    if x.args !== nothing
        for i in 1:length(x.args)
            check_all(x.args[i], markers, context)
        end
    end

    # Do some cleaning
    headof(x) === :const && delete!(markers, :const)
    headof(x) === :function && delete!(markers, :function)
    headof(x) === :macrocall && delete!(markers, :macrocall)
    headof(x) === :macro && delete!(markers, :macro)
    typeof(x) == EXPR &&
        typeof(x.head) == EXPR &&
        headof(x.head) === :OPERATOR &&
        x.head.val == "->" &&
        delete!(markers, :anonymous_function)
    headof(x) === :do && delete!(markers, :anonymous_function)
    (headof(x) === :for || headof(x) === :while) && delete!(markers, :in_loop)
end


function is_named_hole_variable(x::CSTParser.EXPR)
    return x.head == :IDENTIFIER &&
            startswith(x.val, "hole_variable") &&
            x.val != "hole_variable_star" &&
            length(x.val) > length("hole_variable")
end

function is_hole_string(x::CSTParser.EXPR)
    return x.head == :STRING && startswith(x.val, "LINT_STRING")
end

function is_hole_string_with_interpolation(x::CSTParser.EXPR)
    return x.head == :STRING && startswith(x.val, "LINT_STRING_WITH_INTERPOLATION")
end

function is_hole_variable(x::CSTParser.EXPR)
    return x.head == :IDENTIFIER && startswith(x.val, "hole_variable")
end

function is_hole_variable_star(x::CSTParser.EXPR)
    return x.head == :IDENTIFIER && x.val == "hole_variable_star"
end

comp(x, y) = x == y
raw_comp(x, y, named_variable_holes) = x == y

struct BothCannotHaveStarException <: Exception
    msg::String
end

comp_value(x, y) = x == y
function comp_value(x::String, y::String)
    is_there_any_star_marker = contains(x, "QQQ") || contains(y, "QQQ")
    !is_there_any_star_marker && return x == y

    contains(x, "QQQ") && contains(y, "QQQ") &&
        throw(BothCannotHaveStarException("Cannot both $x and $y have a star marker"))
    if contains(x, "QQQ")
        reg_exp = Regex(replace(x, "QQQ" => ".*"))
        return !isnothing(match(reg_exp, y))
    else
        reg_exp = Regex(replace(y, "QQQ" => ".*"))
        return !isnothing(match(reg_exp, x))
    end
end

function raw_comp(
    x::CSTParser.EXPR,
    y::CSTParser.EXPR,
    named_variable_holes::Vector
)
    # @info "debug:" x y
    # Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)

    # If we bump into some named hole variables, then we record it.
    if is_named_hole_variable(x)
        push!(named_variable_holes, (x.val, y))
    end
    if is_named_hole_variable(y)
        push!(named_variable_holes, (y.val, x))
    end

    # If one of element to be compared is a hole, then we have a match!
    (is_hole_variable(x) || is_hole_variable(y)) && return true

    if is_hole_string_with_interpolation(x)
        if y.head == :string && !isnothing(y.args)
            return true
        else
            return false
        end
    end
    if is_hole_string_with_interpolation(y)
        if x.head == :string && !isnothing(x.args)
            return true
        else
            return false
        end
    end

    (is_hole_string(x) && y.head == :STRING) && return true
    (is_hole_string(y) && x.head == :STRING) && return true


    result = raw_comp(x.head, y.head, named_variable_holes) && comp_value(x.val, y.val)
    !result && return false

    min_length = min(length(x), length(y))

    for i in 1:min_length
        raw_comp(x[i], y[i], named_variable_holes) || return false
        (is_hole_variable_star(x[i]) || is_hole_variable_star(y[i])) && return true
    end

    length(x) == length(y) && return true

    if length(x) == min_length
        return is_hole_variable_star(y[min_length + 1])
    end

    if length(y) == min_length
        return is_hole_variable_star(x[min_length + 1])
    end

    return false
end

function comp(x::CSTParser.EXPR, y::CSTParser.EXPR)
    named_variable_holes = Vector()
    result = raw_comp(x, y, named_variable_holes)

    # If there is no or only one named variable hole, then we can exit
    length(named_variable_holes) <= 1 && return result

    all_hole_names = Set(first.(named_variable_holes))
    hole_names_to_values = Dict{String, CSTParser.EXPR}()
    # Else, we need to check that values under a unique named hole is the same
    for k in all_hole_names
        # Retrieve all the value for the named hole k
        relevant = filter(tp->first(tp) == k, named_variable_holes)
        relevant = map(tp->tp[2], relevant)

        # If there are more than 1 value for a given named hole k, then there is no match.
        first_relevant = relevant[1]
        all_others = relevant[2:end]
        all(r -> comp(first_relevant, r), all_others) || return false

        hole_names_to_values[k] = first_relevant
    end

    # Utility functions
    remove!(a, item) = deleteat!(a, findall(x->x==item, a))
    remove(a, item) = deleteat!(copy(a), findall(x->x==item, a))

    # At this point, we know that all the values for each named hole are the same.
    # We now need to check if values for each named holes are different.
    # If some values for two different named holes are the same, then there is no match
    nh_values = collect(values(hole_names_to_values))
    for v in nh_values
        all_to_check = remove(nh_values, v)
        any(k -> comp(k, v), all_to_check) && return false
    end
    return true
end

#################################################################################
# EXTENDED LINT RULES
#################################################################################
abstract type LintRule end
abstract type ASTLintRule <: LintRule end
abstract type RecommendationLintRule <: ASTLintRule end
abstract type ViolationLintRule <: ASTLintRule end
abstract type FatalLintRule <: ASTLintRule end

# AST rules
struct AsyncRule <: ViolationLintRule end
struct CcallRule <: RecommendationLintRule end
struct InitializingWithFunctionRule <: ViolationLintRule end
struct FinalizerRule <: RecommendationLintRule end
struct CFunctionRule <: RecommendationLintRule end
struct UnlockRule <: RecommendationLintRule end
struct YieldRule <: RecommendationLintRule end
struct SleepRule <: RecommendationLintRule end
struct InboundsRule <: RecommendationLintRule end
struct ArrayWithNoTypeRule <: ViolationLintRule end
struct ThreadsRule <: RecommendationLintRule end
struct GeneratedRule <: FatalLintRule end
struct SyncRule <: RecommendationLintRule end
struct RemovePageRule <: ViolationLintRule end
struct TaskRule <: ViolationLintRule end
struct ErrorExceptionRule <: ViolationLintRule end
struct ErrorRule <: ViolationLintRule end
struct UnsafeRule <: ViolationLintRule end
struct InRule <: ViolationLintRule end
struct HasKeyRule <: ViolationLintRule end
struct EqualRule <: ViolationLintRule end
struct UvRule <: ViolationLintRule end
struct SplattingRule <: RecommendationLintRule end
struct UnreachableBranchRule <: ViolationLintRule end
struct StringInterpolationRule <: ViolationLintRule end
struct RelPathAPIUsageRule <: ViolationLintRule end
struct InterpolationInSafeLogRule <: RecommendationLintRule end
struct UseOfStaticThreads <: ViolationLintRule end
struct LogStatementsMustBeSafe <: FatalLintRule end
struct AssertionStatementsMustBeSafe <: FatalLintRule end
struct NonFrontShapeAPIUsageRule <: FatalLintRule end
struct MustNotUseShow <: FatalLintRule end
struct NoinlineAndLiteralRule <: FatalLintRule end
struct NoReturnInAnonymousFunctionRule <: FatalLintRule end
struct NoImportRule <: ViolationLintRule end
struct NotImportingRAICodeRule <: ViolationLintRule end
struct BareUsingRule <: ViolationLintRule end
struct UntypedArrayComprehensionRule <: ViolationLintRule end
# TODO: The RAI Style Guide recommends against return type annotations, but this rule
# is not currently enforced. See: https://github.com/RelationalAI/RAIStyle#type-annotations (There was previously a rule for this, but
# it was removed in PR #75.)
struct StringConcatenationRule <: RecommendationLintRule end
struct NoGlobalVariablesRule <: RecommendationLintRule end
struct ConstGlobalMissingTypeRule <: ViolationLintRule end
struct IsNothingPerformanceRule <: RecommendationLintRule end
struct MissingAutoHashEqualsRule <: RecommendationLintRule end
struct NotFullyParameterizedConstructorRule <: ViolationLintRule end
struct ClosureCaptureByValueRule <: RecommendationLintRule end

include("text_lint_rules.jl")

const all_extended_rule_types = Ref{Vector{DataType}}(
    vcat(
        InteractiveUtils.subtypes(RecommendationLintRule),
        InteractiveUtils.subtypes(ViolationLintRule),
        InteractiveUtils.subtypes(FatalLintRule),
    )
)

const all_text_lint_rule_types = Ref{Vector{DataType}}(
    vcat(
        InteractiveUtils.subtypes(LineRecommendationLintRule),
        InteractiveUtils.subtypes(LineViolationLintRule),
        InteractiveUtils.subtypes(LineFatalLintRule),
    )
)

function all_rules()
    return vcat(all_extended_rule_types[], all_text_lint_rule_types[])
end

# template -> EXPR to be compared
const check_cache = Dict{String, CSTParser.EXPR}()

function reset_static_lint_caches()
    empty!(check_cache)
    all_extended_rule_types[] = vcat(
        InteractiveUtils.subtypes(RecommendationLintRule),
        InteractiveUtils.subtypes(ViolationLintRule),
        InteractiveUtils.subtypes(FatalLintRule),
    )

    all_text_lint_rule_types[] = vcat(
        InteractiveUtils.subtypes(LineRecommendationLintRule),
        InteractiveUtils.subtypes(LineViolationLintRule),
        InteractiveUtils.subtypes(LineFatalLintRule),
    )
    return nothing
end

function get_oracle_ast(template_code::String)
    get!(()->CSTParser.parse(template_code), check_cache, template_code)
    return check_cache[template_code]
end

does_match(x::EXPR, template_code::String) = comp(x, get_oracle_ast(template_code))

function generic_check(t::LintRule, x::EXPR, template_code::String, error_msg::String)
    generic_check(typeof(t), x, template_code, error_msg)
end

function generic_check(T::DataType, x::EXPR, template_code::String, error_msg::String)
    does_match(x, template_code) && seterror!(x, LintRuleReport(T(), error_msg))
end

function generic_check(t::LintRule, x::EXPR, template_code::String)
    generic_check(typeof(t), x, template_code)
end

function generic_check(T::DataType, x::EXPR, template_code::String)
    keyword = first(split(template_code, ['(', '{', ' ']))
    return generic_check(T, x, template_code, "`$(keyword)` should be used with extreme caution.")
end

function check_with_process(T::DataType, x::EXPR, markers::Dict{Symbol,String})
    check(T(), x, markers)
end

# Useful for rules that do not need markers
check(t::Any, x::EXPR, markers::Dict{Symbol,String}) = check(t, x)

# The following function defines rules that are matched on the input Julia source code
# Each rule comes with a pattern that is checked against the abstract syntax tree
function check(t::FinalizerRule, x::EXPR)
    error_msg = "`finalizer(_,_)` should not be used."
    generic_check(t, x, "finalizer(hole_variable, hole_variable)", error_msg)
    generic_check(t, x, "finalizer(hole_variable) do hole_variable hole_variable_star end", error_msg)
end

function check(t::AsyncRule, x::EXPR)
    msg = "Use `@spawn` instead of `@async`."
    generic_check(t, x, "@async hole_variable", msg)
    generic_check(t, x, "Threads.@async hole_variable", msg)
end

check(t::CcallRule, x::EXPR) = generic_check(t, x, "ccall(hole_variable_star)", "`ccall` should be used with extreme caution.")

function check(t::InitializingWithFunctionRule, x::EXPR, markers::Dict{Symbol,String})
    # If we are not in a const statement, then we exit this function.
    haskey(markers, :const) || return
    generic_check(t, x, "Threads.nthreads()", "`Threads.nthreads()` should not be used in a constant variable.")
    generic_check(t, x, "is_local_deployment()", "`is_local_deployment()` should not be used in a constant variable.")
    generic_check(t, x, "Deployment.is_local_deployment()", "`Deployment.is_local_deployment()` should not be used in a constant variable.")
end

check(t::CFunctionRule, x::EXPR) = generic_check(t, x, "@cfunction(hole_variable, hole_variable_star)", "Macro `@cfunction` should not be used.")

check(t::UnlockRule, x::EXPR) = generic_check(t, x, "unlock(hole_variable)")
check(t::YieldRule, x::EXPR) = generic_check(t, x, "yield()")
check(t::SleepRule, x::EXPR) = generic_check(t, x, "sleep(hole_variable)")

check(t::InboundsRule, x::EXPR) = generic_check(t, x, "@inbounds hole_variable")

function check(t::ArrayWithNoTypeRule, x::EXPR, markers::Dict{Symbol,String})
    haskey(markers, :filename) || return
    contains(markers[:filename], "src/Compiler") || return

    haskey(markers, :macrocall) && markers[:macrocall] == "@match" && return
    haskey(markers, :macrocall) && markers[:macrocall] == "@matchrule" && return

    generic_check(t, x, "[]", "Need a specific Array type to be provided.")
end

function check(t::ThreadsRule, x::EXPR)
    msg = "`@threads` should be used with extreme caution."
    generic_check(t, x, "Threads.@threads hole_variable", msg)
    generic_check(t, x, "@threads hole_variable", msg)
end

check(t::GeneratedRule, x::EXPR) = generic_check(t, x, "@generated hole_variable")

function check(t::SyncRule, x::EXPR)
    msg = "`@sync` should be used with extreme caution."
    generic_check(t, x, "@sync hole_variable", msg)
    generic_check(t, x, "Threads.@sync hole_variable", msg)
end

check(t::RemovePageRule, x::EXPR) = generic_check(t, x, "remove_page(hole_variable,hole_variable)")
check(t::TaskRule, x::EXPR) = generic_check(t, x, "Task(hole_variable)")

function check(t::ErrorExceptionRule, x::EXPR, markers::Dict{Symbol,String})
    haskey(markers, :filename) || return
    contains(markers[:filename], "test.jl") && return
    contains(markers[:filename], "tests.jl") && return
    contains(markers[:filename], "bench/") && return
    contains(markers[:filename], "Vectorized/Test") && return
    generic_check(
        t,
        x,
        "ErrorException(hole_variable_star)",
        "Use custom exception instead of the generic `ErrorException`.")
end

function check(t::ErrorRule, x::EXPR, markers::Dict{Symbol,String})
    haskey(markers, :filename) || return
    contains(markers[:filename], "test.jl") && return
    contains(markers[:filename], "tests.jl") && return
    contains(markers[:filename], "bench/") && return
    contains(markers[:filename], "Vectorized/Test") && return
    generic_check(
        t,
        x,
        "error(hole_variable)",
        "Use custom exception instead of the generic `error()`.")
end

function check(t::UnsafeRule, x::EXPR, markers::Dict{Symbol,String})
    haskey(markers, :function) || return
    isnothing(match(r"_unsafe_.*", markers[:function])) || return
    isnothing(match(r"unsafe_.*", markers[:function])) || return

    generic_check(
        t,
        x,
        "unsafe_QQQ(hole_variable_star)",
        "An `unsafe_` function should be called only from an `unsafe_` function.")
    generic_check(
        t,
        x,
        "_unsafe_QQQ(hole_variable_star)",
        "An `unsafe_` function should be called only from an `unsafe_` function.")
end

function check(t::InRule, x::EXPR)
    msg = "Use `tin(item,collection)` instead of the Julia's `in` or `∈`."
    generic_check(t, x, "in(hole_variable,hole_variable)", msg)
    generic_check(t, x, "hole_variable in hole_variable", msg)

    generic_check(t, x, "∈(hole_variable,hole_variable)", msg)
    generic_check(t, x, "hole_variable ∈ hole_variable", msg)
end

function check(t::HasKeyRule, x::EXPR)
    msg = "Use `thaskey(dict,key)` instead of the Julia's `haskey`."
    generic_check(t, x, "haskey(hole_variable,hole_variable)", msg)
end

function check(t::EqualRule, x::EXPR)
    msg = "Use `tequal(dict,key)` instead of the Julia's `equal`."
    generic_check(t, x, "equal(hole_variable,hole_variable)", msg)
end

function check(t::UvRule, x::EXPR)
    generic_check(
        t,
        x,
        "uv_QQQ(hole_variable_star)",
        "`uv_` functions should be used with extreme caution.")
end

function check(t::SplattingRule, x::EXPR, markers::Dict{Symbol,String})
    contains(markers[:filename], "test.jl") && return
    contains(markers[:filename], "tests.jl") && return
    haskey(markers, :macro) && return

    generic_check(
        t,
        x,
        "hole_variable(hole_variable_star...)",
        "Splatting (`...`) should be used with extreme caution. Splatting from dynamically sized containers could result in severe performance degradation. Splatting from statically-sized tuples is usually okay. This lint rule cannot determine if this is dynamic or static, so please check carefully. See https://github.com/RelationalAI/RAIStyle#splatting for more information.")

    generic_check(
        t,
        x,
        "hole_variable([hole_variable(hole_variable_star) for hole_variable in hole_variable]...)",
        "Splatting (`...`) should not be used with dynamically sized containers. This may result in performance degradation. See https://github.com/RelationalAI/RAIStyle#splatting for more information.")
end

function check(t::UnreachableBranchRule, x::EXPR)
    generic_check(
        t,
        x,
        "if hole_variableA \
            hole_variable \
         elseif hole_variableA \
            hole_variable \
         end",
        "Unreachable branch.")
    generic_check(
        t,
        x,
        "if hole_variableA \
            hole_variable \
        elseif hole_variable \
            hole_variable\
        elseif hole_variableA \
            hole_variable \
        end",
        "Unreachable branch.")
end

function check(t::StringInterpolationRule, x::EXPR)
    # We are interested only in string with interpolation, which begins with x.head==:string
    x.head == :string || return

    error_msg = raw"Use $(x) instead of $x ([explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#string-interpolation))."
    # We iterate over the arguments of the CST String to check for STRING: (
    # if we find one, this means the string was incorrectly interpolated

    # The number of interpolations is the same than $ in trivia and arguments
    dollars_count = length(filter(q->q.head == :OPERATOR && q.val == raw"$", x.trivia))

    open_parent_count = length(filter(q->q.head == :LPAREN, x.trivia))
    open_parent_count != dollars_count && seterror!(x, LintRuleReport(t, error_msg))
end

function check(t::RelPathAPIUsageRule, x::EXPR, markers::Dict{Symbol,String})
    haskey(markers, :filename) || return
    contains(markers[:filename], "src/Compiler/Front") || return

    generic_check(t, x, "hole_variable::RelPath", "Usage of type `RelPath` is not allowed in this context.")
    generic_check(t, x, "RelPath(hole_variable)", "Usage of type `RelPath` is not allowed in this context.")
    generic_check(t, x, "RelPath(hole_variable, hole_variable)", "Usage of type `RelPath` is not allowed in this context.")
    generic_check(t, x, "split_path(hole_variable)", "Usage of `RelPath` API method `split_path` is not allowed in this context.")
    generic_check(t, x, "drop_first(hole_variable)", "Usage of `RelPath` API method `drop_first` is not allowed in this context.")
    generic_check(t, x, "relpath_from_signature(hole_variable)", "Usage of method `relpath_from_signature` is not allowed in this context.")
end

function check(t::NonFrontShapeAPIUsageRule, x::EXPR, markers::Dict{Symbol,String})
    haskey(markers, :filename) || return
    # In the front-end and in FFI, we are allowed to refer to `Shape`
    contains(markers[:filename], "src/FrontCompiler") && return
    contains(markers[:filename], "packages/RAI_FrontCompiler") && return
    contains(markers[:filename], "src/FFI") && return
    # We're allowing this for serialization.
    contains(markers[:filename], "src/Database") && return
    contains(markers[:filename], "packages/Shapes") && return
    contains(markers[:filename], "packages/RAI_FrontIR") && return
    # Also, allow usages in tests
    contains(markers[:filename], "test/") && return
    # Also, allow usages of the name `Shape` in `packages/` although they refer to a different thing.
    contains(markers[:filename], "packages/RAI_Protos/src/proto/metadata.proto") && return
    contains(markers[:filename], "packages/RAI_Protos/src/gen/relationalai/protocol/metadata_pb.jl") && return

    generic_check(t, x, "shape_term(hole_variable_star)", "Usage of `shape_term` Shape API method is not allowed outside of the Front-end Compiler and FFI.")
    generic_check(t, x, "Front.shape_term(hole_variable_star)", "Usage of `shape_term` Shape API method is not allowed outside of the Front-end Compiler and FFI.")
    generic_check(t, x, "shape_splat(hole_variable_star)", "Usage of `shape_splat` Shape API method is not allowed outside of the Front-end Compiler and FFI.")
    generic_check(t, x, "Front.shape_splat(hole_variable_star)", "Usage of `shape_splat` Shape API method is not allowed outside of the Front-end Compiler and FFI.")
    generic_check(t, x, "ffi_shape_term(hole_variable_star)", "Usage of `ffi_shape_term` is not allowed outside of the Front-end Compiler and FFI.")
    generic_check(t, x, "Shape", "Usage of `Shape` is not allowed outside of the Front-end Compiler and FFI.")
end

function check(t::InterpolationInSafeLogRule, x::EXPR)
    generic_check(t, x, "@warnv_safe_to_log hole_variable \"LINT_STRING_WITH_INTERPOLATION\"", "Safe warning log has interpolation.")
end

function check(t::UseOfStaticThreads, x::EXPR)
    msg = "Use `Threads.@threads :dynamic` instead of `Threads.@threads :static`. Static threads must not be used as generated tasks will not be able to migrate across threads."
    generic_check(t, x, "@threads :static hole_variable_star", msg)
    generic_check(t, x, "Threads.@threads :static hole_variable_star", msg)
end

function all_arguments_are_safe(x::EXPR; skip_first_arg::Bool=false)

    is_safe_macro_call(y) =
        (y.head == :macrocall && y.args[1].head == :IDENTIFIER && y.args[1].val == "@safe") ||
        (y.head == :macrocall &&
         y.args[1].head isa EXPR &&
         y.args[1].head.head == :OPERATOR &&
         y.args[1].args[1].args[1].val == "SafeLogging" &&
         y.args[1].args[2].args[1].val == "@safe")

    is_safe_literal(x) = x.head in [:NOTHING,
                                    :INTEGER,
                                    :FLOAT,
                                    :TRUE,
                                    :FALSE,
                                    :HEXINT,
                                    :BININT,
                                    :CHAR,
                                    :OCTINT
                                    ]

    first_index = skip_first_arg ? 4 : 2
    for arg in x.args[first_index:end]
        # This is safe
        if is_safe_macro_call(arg) || is_safe_literal(arg)
            continue
        elseif arg.head isa CSTParser.EXPR && arg.head.head == :OPERATOR && arg.head.val == "=" &&
                    (is_safe_macro_call(arg.args[2]) || is_safe_literal(arg.args[2]))
            continue
        else
            # @info x arg
            # isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
            return false
        end
    end
    return true
end

function check(t::LogStatementsMustBeSafe, x::EXPR, markers::Dict{Symbol,String})
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "bench/") && return
    end

    error_msg = "Unsafe logging statement. You must enclose variables and strings with `@safe(...)`."

    # @info and its friends
    if x.head == :macrocall && x.args[1].head == :IDENTIFIER && startswith(x.args[1].val, "@info")
        all_arguments_are_safe(x) || seterror!(x, LintRuleReport(t, error_msg))
    end

    # @debug and its friends
    if x.head == :macrocall && x.args[1].head == :IDENTIFIER && startswith(x.args[1].val, "@debug")
        all_arguments_are_safe(x) || seterror!(x, LintRuleReport(t, error_msg))
    end

    # @error and its friends
    if x.head == :macrocall && x.args[1].head == :IDENTIFIER && startswith(x.args[1].val, "@error")
        all_arguments_are_safe(x) || seterror!(x, LintRuleReport(t, error_msg))
    end

    # @warn and its friends
    if x.head == :macrocall && x.args[1].head == :IDENTIFIER && startswith(x.args[1].val, "@warn")
        all_arguments_are_safe(x) || seterror!(x, LintRuleReport(t, error_msg))
    end
end

function check(t::AssertionStatementsMustBeSafe, x::EXPR, markers::Dict{Symbol,String})
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
    end

    error_msg = "Unsafe assertion statement. You must enclose the message `@safe(...)`."

    # @assert and its friends
    if x.head == :macrocall &&
        x.args[1].head == :IDENTIFIER &&
        (startswith(x.args[1].val, "@assert") || startswith(x.args[1].val, "@dassert"))

        all_arguments_are_safe(x; skip_first_arg=true) || seterror!(x, LintRuleReport(t, error_msg))
    end
end

function check(t::MustNotUseShow, x::EXPR)
    msg = "Do not use `@show`, use `@info` instead."
    generic_check(t, x, "@show hole_variable", msg)
end


function all_arguments_are_literal_or_identifier(x::EXPR)
    is_literal(x) = x.head in [:NOTHING,
        :INTEGER,
        :FLOAT,
        :TRUE,
        :FALSE,
        :HEXINT,
        :BININT,
        :CHAR,
        :OCTINT,
        :STRING
        ]
    is_identifier(x) = x.head == :IDENTIFIER
    is_splatting(x) = x.head isa EXPR && x.head.head == :OPERATOR && x.head.val == "..."
    is_literal_or_identifier_or_splatting(x) =
        if x.head == :parameters || x.head == :kw
            all(is_literal_or_identifier_or_splatting, x.args)
        else
            is_literal(x) || is_identifier(x) || is_splatting(x)
        end

    return all(is_literal_or_identifier_or_splatting, x.args[2:end])
end

function check(t::NoinlineAndLiteralRule, x::EXPR)
    if does_match(x, "@noinline hole_variable(hole_variable_star) = hole_variable_star")
        return
    end

    if x.head == :macrocall &&
        x.args[1].head == :IDENTIFIER &&
        x.args[1].val == "@noinline"

        # Are we in a function definition?
        function_def = fetch_value(x, :function, false)
        isnothing(function_def) || return

        # Retrieve function call below the @noinline macro
        fct_call = fetch_value(x, :call, false, 1)

        msg = "For call-site `@noinline` call, all args must be literals or identifiers only. \
        Pull complex args out to top-level. [RAI-35086](https://relationalai.atlassian.net/browse/RAI-35086)."

        # We found no function call, check for a macro call then
        if isnothing(fct_call)
            macro_call = fetch_value(x, :macrocall, false, -1, true)

            # If we have not found a macro call, then we merely exit.
            # could happen with `@noinline 42` for example
            isnothing(macro_call) && return

            # We found a macro call
            seterror!(x, LintRuleReport(t, msg))
        else
            # We found a function call, check if all arguments are literals or identifiers
            all_arguments_are_literal_or_identifier(fct_call) || seterror!(x, LintRuleReport(t, msg))
        end
    end
end

function check(t::NoReturnInAnonymousFunctionRule, x::EXPR, markers::Dict{Symbol,String})
    # No need to check for returns in anonymous function in tests
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
    end

    haskey(markers, :anonymous_function) || return
    msg = "Anonymous function must not have `return` [Explanation](https://github.com/RelationalAI/RAIStyle#returning-from-a-closure)."
    generic_check(t, x, "return hole_variable", msg)
end

function check(t::NoImportRule, x::EXPR, markers::Dict{Symbol,String})
    msg = "Imports must be specified using `using` and not `import` [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#module-imports)."
    generic_check(t, x, "import hole_variable", msg)

    # Arbitrary number of hole variables
    # TODO: This is hacky and it deserves a better solution.
    for i in 1:15
        s = join(["hole_variable" for _ in 1:i], ", ")
        u = "import hole_variable : $(s)"
        generic_check(t, x, u, msg)
    end
end

function check(t::NotImportingRAICodeRule, x::EXPR, markers::Dict{Symbol,String})
    msg = "Importing RAICode should be avoided (when possible)."
    generic_check(t, x, "using RAICode", msg)

    # Arbitrary number of hole variables
    # TODO: This is hacky and it deserves a better solution.
    for i in 1:15
        s = join(["hole_variable" for _ in 1:i], ", ")
        u = "using RAICode : $(s)"
        generic_check(t, x, u, msg)
    end
end

function check(t::BareUsingRule, x::EXPR, markers::Dict{Symbol,String})
    # Skip test files - bare using is allowed in tests
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    msg = "Use `using Foo: Foo` or `using Foo: specific_function` instead of bare `using Foo`. [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#module-imports)."
    generic_check(t, x, "using hole_variable", msg)
end

function check(t::UntypedArrayComprehensionRule, x::EXPR, markers::Dict{Symbol,String})
    # Only check in Compiler directory - this is where type stability matters most
    if haskey(markers, :filename)
        !contains(markers[:filename], "src/Compiler/") && return
    end

    msg = "Need a specific Array type to be provided. Use `T[x for x in xs]` instead of `[x for x in xs]`. [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#type-annotations)."

    # Pattern: [comprehension] without type prefix
    # This catches [x for x in xs] but not T[x for x in xs]
    generic_check(t, x, "[hole_variable for hole_variable in hole_variable]", msg)
end

function check(t::StringConcatenationRule, x::EXPR, markers::Dict{Symbol,String})
    # Skip test files
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    msg = "Prefer string interpolation or `string()` over `*` for string concatenation. Use `\"\$(a)\$(b)\"` instead of `a * b`. [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#strings)."

    # Pattern: "string" * something or something * "string"
    generic_check(t, x, "\"LINT_STRING\" * hole_variable", msg)
    generic_check(t, x, "hole_variable * \"LINT_STRING\"", msg)
end

function check(t::NoGlobalVariablesRule, x::EXPR, markers::Dict{Symbol,String})
    # Skip test files
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    msg = "Avoid non-const global variables. Use `const` for immutable globals or pass values as function arguments. [Explanation](https://github.com/RelationalAI/RAIStyle?tab=readme-ov-file#global-variables)."

    # Pattern: global variable assignment without const
    # Matches: x = value, global x = value
    generic_check(t, x, "global hole_variable = hole_variable", msg)
end

function check(t::ConstGlobalMissingTypeRule, x::EXPR, markers::Dict{Symbol,String})
    # Skip test files
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    # Detect global assignments
    # AST structure from debug: global keyword followed by assignment
    # global untyped = val: x[1] = GLOBAL, x[2] = (= IDENTIFIER val)
    # global typed::T = val: x[1] = GLOBAL, x[2] = (= (:: IDENTIFIER T) val)
    if headof(x) === :global && length(x) >= 2
        # Skip the GLOBAL keyword (x[1]), look at the assignment (x[2])
        assignment = x[2]

        # Check if this is an assignment (headof contains "=")
        head_str = string(headof(assignment))
        if contains(head_str, "=") && length(assignment) >= 1
            lhs = assignment[1]  # Left-hand side of assignment

            # Check if lhs is just an identifier (no type annotation)
            # If headof(lhs) === :IDENTIFIER, it's untyped
            # If headof(lhs) contains "::", it's typed
            if headof(lhs) === :IDENTIFIER
                # This is an untyped global like: global x = value
                msg = "Global variable must have type annotation: `global x::Type = value`. Use `const` for immutable globals. [Explanation](https://github.com/RelationalAI/RAIStyle#global-variables)"
                seterror!(x, LintRuleReport(t, msg))
            end
            # If headof(lhs) contains "::", it's typed - OK, don't error
        end
    end
end

function check(t::IsNothingPerformanceRule, x::EXPR, markers::Dict{Symbol,String})
    # Only check in performance-critical directories
    if haskey(markers, :filename)
        performance_critical = contains(markers[:filename], "src/Compiler/") ||
                             contains(markers[:filename], "packages/Salsa/")
        !performance_critical && return
    else
        return
    end

    # Skip test files
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    msg = "In performance-critical code, prefer `x === nothing` or `x isa Nothing` over `isnothing(x)`. [Explanation](https://github.com/RelationalAI/RAIStyle#isnothing-vs-isa-nothing-vs--nothing)"

    generic_check(t, x, "isnothing(hole_variable)", msg)
end

function check(t::MissingAutoHashEqualsRule, x::EXPR, markers::Dict{Symbol,String})
    # Only check struct definitions
    if headof(x) !== :struct
        return
    end

    # Skip test files - testing often uses simple structs without equality
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    # Get the struct name
    struct_name = fetch_value(x, :IDENTIFIER)
    isnothing(struct_name) && return

    # Skip private structs (start with underscore)
    startswith(struct_name, "_") && return

    # Check if there's an @auto_hash_equals macro before this struct
    # This is a simplified check - in practice, we'd need to track macros in markers
    # For now, emit a recommendation for all non-private structs

    msg = "Consider using `@auto_hash_equals` for struct `$(struct_name)` if it will be used as a dictionary key or set member. Skip this if the struct is a bits type or requires custom equality. [Explanation](https://github.com/RelationalAI/RAIStyle#struct-equality)"

    # This is a recommendation, not a hard error, so we'll be conservative
    # Only warn for non-bits types (though detecting bits types requires more analysis)
    seterror!(x, LintRuleReport(t, msg))
end

function check(t::NotFullyParameterizedConstructorRule, x::EXPR, markers::Dict{Symbol,String})
    # Only check in performance-critical code
    if haskey(markers, :filename)
        !contains(markers[:filename], "src/Compiler/") && return
    else
        return
    end

    # Skip test files
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    # Check if we're in a loop
    if !haskey(markers, :in_loop)
        return
    end

    # Detect constructor calls (capitalized function names)
    if headof(x) === :call
        # Get the function being called
        func_expr = x[1]

        # Extract function name from different patterns
        func_name = nothing
        if headof(func_expr) === :IDENTIFIER
            func_name = valof(func_expr)
        elseif headof(func_expr) === :curly
            # Fully parameterized like Vector{Int}(...) - this is OK
            return
        end

        # If we have a function name and it starts with capital letter (constructor pattern)
        if !isnothing(func_name) && occursin(r"^[A-Z]", func_name)
            # This is likely a not-fully-parameterized constructor call in a loop
            msg = "Avoid not-fully-parameterized constructor `$(func_name)(...)` in loops. Use a maker function instead for better performance. [Explanation](https://github.com/RelationalAI/RAIStyle#super-costly-dynamic-dispatches)"
            seterror!(x, LintRuleReport(t, msg))
        end
    end
end

function check(t::ClosureCaptureByValueRule, x::EXPR, markers::Dict{Symbol,String})
    # Only check in performance-critical directories
    if haskey(markers, :filename)
        !contains(markers[:filename], "src/Compiler/") && return
    else
        return
    end

    # Skip test files
    if haskey(markers, :filename)
        contains(markers[:filename], "test/") && return
        contains(markers[:filename], "test.jl") && return
    end

    # Detect nested function definitions (closures)
    # We want to find function definitions that occur INSIDE other functions
    # Pattern 1: Lambda function: f = x -> ...
    # Pattern 2: Short-form function: f() = ...
    # Pattern 3: Anonymous functions are marked separately
    # Note: Full function definitions (function f() end) are problematic because
    # the :function marker is set BEFORE checking, so we can't distinguish top-level
    # from nested just by checking the marker. Skip those for now.

    is_nested_function = false

    # Only check if we're inside a function
    if !haskey(markers, :function)
        return
    end

    if headof(x) === :(=)
        # Check for anonymous function assignment: f = x -> ...
        # or short form function: f() = ...
        if length(x) >= 2
            rhs = x[2]
            if headof(rhs) === :(->)
                # Lambda function - definitely a closure
                is_nested_function = true
            elseif headof(x[1]) === :call
                # Short form function definition - definitely nested
                is_nested_function = true
            end
        end
    elseif haskey(markers, :anonymous_function)
        # Anonymous functions (do blocks, etc.) - these are closures
        is_nested_function = true
    end

    if is_nested_function
        # We found a nested function - recommend considering let-binding
        # Note: This is a recommendation, not an error, as capture-by-reference is sometimes correct
        msg = "Nested function may capture variables by reference, causing boxing and type instability. Consider using `let x = x` to capture by value for better performance. [Explanation](https://github.com/RelationalAI/RAIStyle#closure-capture-performance)"
        seterror!(x, LintRuleReport(t, msg))
    end
end
