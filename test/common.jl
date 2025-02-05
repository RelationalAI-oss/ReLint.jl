using ReLint: ReLint, run_lint_on_text, comp, convert_offset_to_line,
    convert_offset_to_line_from_lines, MarkdownFormat, PlainFormat,
    fetch_value, has_values

using ReLint: LintResult, LintContext
import CSTParser
using Test
using JSON3

# Reset the caches before running the tests.
ReLint.reset_static_lint_caches()

function lint_test(source::String, expected_substring::String; verbose=true, directory::String = "", context::LintContext=LintContext())
    io = IOBuffer()
    run_lint_on_text(source; io, directory, context)
    output = String(take!(io))
    result = contains(output, expected_substring)
    if verbose && !result
        printstyled("EXPECTED:\n$(expected_substring)\n\n", color=:green)
        printstyled("OUTPUT:\n$(output)\n\n", color=:red)
    end
    return result
end

function count_lint_errors(source::String, verbose=false; directory::String = "", context::LintContext=LintContext())
    io = IOBuffer()
    run_lint_on_text(source; io, directory, context)
    result = String(take!(io))
    all_lines = split(result, "\n")

    verbose && @info result
    # We remove decorations
    return length(filter(l->startswith(l, "Line "), all_lines))
end


function lint_has_error_test(source::String, verbose=false; directory::String = "", context::LintContext=LintContext())
    return count_lint_errors(source, verbose; directory, context) > 0
end