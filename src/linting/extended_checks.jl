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


mutable struct LintContext
    rules_to_run::Vector{DataType}

    global_markers::Dict{Symbol,Any}
    local_markers::Dict{Symbol,Any}

    passes::Dict{DataType,Symbol}

    function LintContext(dts_as_str::Vector{String})
        dt = DataType[]
        for dt_as_str in dts_as_str
            ind = findfirst(t -> nameof(t) == Symbol(dt_as_str), all_extended_rule_types[])
            isnothing(ind) && error("Specified non-existing rule")
            push!(dt, all_extended_rule_types[][ind])
        end
        return LintContext(dt)
    end

    function LintContext(s::Vector{DataType})
        return new(s, Dict{Symbol,String}(), Dict{Symbol,String}(), Dict{DataType,Symbol}())
    end
    LintContext(s::Vector{Any}) = LintContext(convert(Vector{DataType}, s))
    LintContext() = LintContext(all_extended_rule_types[])
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

function fetch_value(x::EXPR, tag::Symbol)
    if headof(x) == tag
        return x.val
    else
        isnothing(x.args) && return nothing
        for i in 1:length(x.args)
            r = fetch_value(x.args[i], tag)
            isnothing(r) || return r
        end
        return nothing
    end
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

function check_all(
    x::EXPR,
    context::LintContext = LintContext()
)
    # Setting up the markers
    if headof(x) === :const
        context.local_markers[:const] = fetch_value(x, :IDENTIFIER)
    end

    if headof(x) === :function
        context.local_markers[:function] = fetch_value(x, :IDENTIFIER)
    end

    if headof(x) === :macrocall
        id = fetch_value(x, :IDENTIFIER)
        if !isnothing(id)
            context.local_markers[:macrocall] = id
        end
    end

    for T in context.rules_to_run
        check_with_process(T, x, context)
        if haserror(x) && x.meta.error isa LintRuleReport
            lint_rule_report = x.meta.error
            if haskey(context.local_markers, :filename)
                lint_rule_report.file = context.local_markers[:filename]
            end
        end
    end

    if x.args !== nothing
        for i in 1:length(x.args)
            check_all(x.args[i], context)
        end
    end

    # Do some cleaning
    headof(x) === :const && delete!(context.local_markers, :const)
    headof(x) === :function && delete!(context.local_markers, :function)
    headof(x) === :macrocall && delete!(context.local_markers, :macrocall)
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
abstract type RecommendationLintRule <: LintRule end
abstract type ViolationLintRule <: LintRule end
abstract type FatalLintRule <: LintRule end

struct AsyncRule <: ViolationLintRule end
struct CcallRule <: RecommendationLintRule end
struct Pointer_from_objrefRule <: RecommendationLintRule end
struct InitializingWithFunctionRule <: ViolationLintRule end
struct FinalizerRule <: RecommendationLintRule end
struct CFunctionRule <: RecommendationLintRule end
struct DestructorRule <: RecommendationLintRule end
struct UnlockRule <: RecommendationLintRule end
struct YieldRule <: RecommendationLintRule end
struct SleepRule <: RecommendationLintRule end
struct MmapRule <: RecommendationLintRule end
struct InboundsRule <: RecommendationLintRule end
struct PtrRule <: RecommendationLintRule end
struct ArrayWithNoTypeRule <: ViolationLintRule end
struct ThreadsRule <: RecommendationLintRule end
struct GeneratedRule <: RecommendationLintRule end
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
struct NonFrontShapeAPIUsageRule <: ViolationLintRule end
struct InterpolationInSafeLogRule <: RecommendationLintRule end
struct UseOfStaticThreads <: ViolationLintRule end
struct LogStatementsMustBeSafe <: FatalLintRule end

struct UnusedFunction <: ViolationLintRule end

# const all_extended_rule_types = Ref{Vector{DataType}}(
#     vcat(
#         InteractiveUtils.subtypes(RecommendationLintRule),
#         InteractiveUtils.subtypes(ViolationLintRule),
#         InteractiveUtils.subtypes(FatalLintRule),
#         )
# )

const all_extended_rule_types = Ref{Vector{DataType}}(
    vcat(
        InteractiveUtils.subtypes(RecommendationLintRule),
        InteractiveUtils.subtypes(ViolationLintRule),
        InteractiveUtils.subtypes(FatalLintRule),
        )
)

# template -> EXPR to be compared
const check_cache = Dict{String, CSTParser.EXPR}()

function reset_static_lint_caches()
    empty!(check_cache)
    all_extended_rule_types[] = vcat(
        InteractiveUtils.subtypes(RecommendationLintRule),
        InteractiveUtils.subtypes(ViolationLintRule),
        InteractiveUtils.subtypes(FatalLintRule),
        )
    return nothing
end

function get_oracle_ast(template_code::String)
    get!(check_cache, template_code, CSTParser.parse(template_code))
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

function check_with_process(T::DataType, x::EXPR, context::LintContext)
    check(T(), x, context)
end

# Useful for rules that do not need markers
check(t::Any, x::EXPR, context::LintContext) = check(t, x)

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

check(t::CcallRule, x::EXPR) = generic_check(t, x, "ccall(hole_variable, hole_variable, hole_variable, hole_variable_star)", "`ccall` should be used with extreme caution.")
check(t::Pointer_from_objrefRule, x::EXPR) = generic_check(t, x, "pointer_from_objref(hole_variable)", "`pointer_from_objref` should be used with extreme caution.")

function check(t::InitializingWithFunctionRule, x::EXPR, context::LintContext)
    # If we are not in a const statement, then we exit this function.
    haskey(context.local_markers, :const) || return
    generic_check(t, x, "Threads.nthreads()", "`Threads.nthreads()` should not be used in a constant variable.")
    generic_check(t, x, "is_local_deployment()", "`is_local_deployment()` should not be used in a constant variable.")
    generic_check(t, x, "Deployment.is_local_deployment()", "`Deployment.is_local_deployment()` should not be used in a constant variable.")
end

check(t::CFunctionRule, x::EXPR) = generic_check(t, x, "@cfunction(hole_variable, hole_variable_star)", "Macro `@cfunction` should not be used.")

function check(t::DestructorRule, x::EXPR)
    error_msg = "Destructors should be used with extreme caution."
    generic_check(t, x, "destructor(hole_variable, hole_variable)", error_msg)
    generic_check(t, x, "destructor(hole_variable) do hole_variable hole_variable_star end", error_msg)
end

check(t::UnlockRule, x::EXPR) = generic_check(t, x, "unlock(hole_variable)")
check(t::YieldRule, x::EXPR) = generic_check(t, x, "yield()")
check(t::SleepRule, x::EXPR) = generic_check(t, x, "sleep(hole_variable)")
function check(t::MmapRule, x::EXPR)
    generic_check(t, x, "mmap(hole_variable_star)")
    generic_check(t, x, "Mmap.mmap(hole_variable_star)", "`mmap` should be used with extreme caution.")
end

check(t::InboundsRule, x::EXPR) = generic_check(t, x, "@inbounds hole_variable")

check(t::PtrRule, x::EXPR) = generic_check(t, x, "Ptr{hole_variable}(hole_variable)")

function check(t::ArrayWithNoTypeRule, x::EXPR, context::LintContext)
    haskey(context.local_markers, :filename) || return
    contains(context.local_markers[:filename], "src/Compiler") || return

    haskey(context.local_markers, :macrocall) && context.local_markers[:macrocall] == "@match" && return
    haskey(context.local_markers, :macrocall) && context.local_markers[:macrocall] == "@matchrule" && return

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

function check(t::ErrorExceptionRule, x::EXPR)
    generic_check(
        t,
        x,
        "ErrorException(hole_variable_star)",
        "Use custom exception instead of the generic `ErrorException`.")
end

function check(t::ErrorRule, x::EXPR)
    generic_check(
        t,
        x,
        "error(hole_variable)",
        "Use custom exception instead of the generic `error()`.")
end

function check(t::UnsafeRule, x::EXPR, context::LintContext)
    haskey(context.local_markers, :function) || return
    isnothing(match(r"_unsafe_.*", context.local_markers[:function])) || return
    isnothing(match(r"unsafe_.*", context.local_markers[:function])) || return

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

function check(t::SplattingRule, x::EXPR)
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

function check(t::RelPathAPIUsageRule, x::EXPR, context::LintContext)
    haskey(context.local_markers, :filename) || return
    contains(context.local_markers[:filename], "src/Compiler/Front") || return

    generic_check(t, x, "hole_variable::RelPath", "Usage of type `RelPath` is not allowed in this context.")
    generic_check(t, x, "RelPath(hole_variable)", "Usage of type `RelPath` is not allowed in this context.")
    generic_check(t, x, "RelPath(hole_variable, hole_variable)", "Usage of type `RelPath` is not allowed in this context.")
    generic_check(t, x, "split_path(hole_variable)", "Usage of `RelPath` API method `split_path` is not allowed in this context.")
    generic_check(t, x, "drop_first(hole_variable)", "Usage of `RelPath` API method `drop_first` is not allowed in this context.")
    generic_check(t, x, "relpath_from_signature(hole_variable)", "Usage of method `relpath_from_signature` is not allowed in this context.")
end

function check(t::NonFrontShapeAPIUsageRule, x::EXPR, context::LintContext)
    haskey(context.local_markers, :filename) || return
    # In the front-end and in FFI, we are allowed to refer to `Shape`
    contains(context.local_markers[:filename], "src/FrontCompiler") && return
    contains(context.local_markers[:filename], "src/FFI") && return
    contains(context.local_markers[:filename], "src/FrontIR") && return
    # Also, allow usages in tests
    contains(context.local_markers[:filename], "test/") && return
    # Also, allow usages of the name `Shape` in `packages/` although they refer to a different thing.
    contains(context.local_markers[:filename], "packages/RAI_Protos/src/proto/metadata.proto") && return
    contains(context.local_markers[:filename], "packages/RAI_Protos/src/gen/relationalai/protocol/metadata_pb.jl") && return

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

function all_arguments_are_safe(x::EXPR)
    is_safe_macro_call(y) =
        y.head == :macrocall && y.args[1].head == :IDENTIFIER && y.args[1].val == "@safe"

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

    for arg in x.args[2:end]
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

function check(t::LogStatementsMustBeSafe, x::EXPR, context::LintContext)
    if haskey(context.local_markers, :filename)
        contains(context.local_markers[:filename], "test/") && return
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
        # isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        all_arguments_are_safe(x) || seterror!(x, LintRuleReport(t, error_msg))
    end
end


# TO DELETE
# abstract type AbstractPass end
# abstract type AbstractFunctionPass <: AbstractPass end
# abstract type AbstractFilePass <: AbstractPass end
# # Any subtype of AbstractGlobalPass is run before checking, global
# abstract type AbstractGlobalPass <: AbstractPass end
# Per default a lint rule does not require a pass

pass_of(t::LintRule) = :none # Return :none, :global, :file, :function
require_pass(t::LintRule) = pass_of(t) != :none
pass!(t::Any, x::EXPR, context::LintContext) = nothing



pass_of(t::UnusedFunction) = :global
function pass!(t::UnusedFunction, x::EXPR, context::LintContext)
    # Pass already done
    # haskey(context.passes, typeof(t)) && return

    if !haskey(context.global_markers, :defined_function)
        context.global_markers[:defined_function] = Set()
    end

    if headof(x) === :function
        function_name = fetch_value(x, :IDENTIFIER)
        push!(context.global_markers[:defined_function], function_name)
    end

    # We recurse over the AST
    if x.args !== nothing
        for i in 1:length(x.args)
            pass!(t, x.args[i], context)
        end
    end
end



function check(t::UnusedFunction, x::EXPR, context::LintContext)

    # We hit a function call. We need to check if this call is in the current context.
    if x.head == :call && x.args[1].head == :IDENTIFIER
    end
end
