using Argus

# Rule disabling
# ==============

"""
    ReLintDisabler <: CommentDisabler

Type for the ReLint-specific rule disabler. See `relint_disabler`.
"""
struct ReLintDisabler <: CommentDisabler end
const relint_disabler = ReLintDisabler()

"""
    relint_disabler([rule::Rule,] line::AbstractString)

ReLint-specific rule disabler. Allows disabling rules in source code via comments of the
form `# lint-disable[: [(<rule-name>|<rule-message>), ]+]?`. The rules are disabled for the
annotated node.

See also: `Argus.default_disabler`
"""
relint_disabler(line::AbstractString) = is_disable_all_comment(line)
function relint_disabler(rule::Rule, line::AbstractString)
    is_disable_comment(line) || return false
    is_disable_all_comment(line) && return true
    is_disable_rule_comment(line, rule) && return true
    return false
end

is_disable_comment(str::AbstractString) =
    startswith(str, "# lint-disable-next-line")
is_disable_all_comment(str::AbstractString) = str == "# lint-disable-next-line"
function is_disable_rule_comment(str::AbstractString, rule::Rule)
    is_disable_comment(str) || return false
    split_command_from_rules = split(str, ":")
    length(split_command_from_rules) == 2 || return false
    rules_list = strip.(split(split_command_from_rules[2], ","))
    rule.name in rules_list && return true
    # Allow disabling by rule description as well.
    return startswith(rule.description, lstrip(split_command_from_rules[2]))
end

include("utils.jl")
include("recommendations.jl")
include("violations.jl")
include("fatal.jl")

all_rules() = [
    values(RECOMMENDATIONS)...,
    values(VIOLATIONS)...,
    values(FATAL_VIOLATIONS)...,
]
