import JSON3
using Dates: now, UTC

global MAX_REPORTED_ERRORS = 60 # 1_000_000

# Lint report
# ===========

# Individual rule report
# ----------------------

"""
    LintRuleReport

Report of the result of linting one file with one rule.
"""
mutable struct LintRuleReport
    rule::Rule
    msg::String
    template::String
    file::String
    line::Int64
    column::Int64
    is_disabled::Bool
    offset::Int64
end
LintRuleReport(rule::Rule, msg::String) = LintRuleReport(rule, msg, "", "", 0, 0, false, 0)

"""
    Argus_result_to_LintRuleReport(rule::Rule, match_result::BindingSet)

Convert a rule match result to a `LintRuleReport`.
"""
Argus_result_to_LintRuleReport(rule::Rule, match_result::BindingSet) =
    LintRuleReport(rule,
                   rule.description,
                   "",
                   JuliaSyntax.filename(match_result),
                   JuliaSyntax.source_location(match_result)[1],
                   JuliaSyntax.source_location(match_result)[2],
                   false,
                   0)

is_recommendation(r::Rule) = haskey(RECOMMENDATIONS, r.name)
is_violation(r::Rule) = haskey(VIOLATIONS, r.name)
is_fatal(r::Rule) = haskey(FATAL_VIOLATIONS, r.name)

is_recommendation(r::LintRuleReport) = is_recommendation(r.rule)
is_violation(r::LintRuleReport) = is_violation(r.rule)
is_fatal(r::LintRuleReport) = is_fatal(r.rule)

# Global report
# -------------

"""
    LintGlobalReport

Report of the result of linting multiple files and directories with a set of rules.
"""
mutable struct LintGlobalReport
    files_count::Integer
    violations_count::Integer
    recommendations_count::Integer
    fatal_violations_count::Integer
    linted_files::Vector{String}
    printout_count::Integer
    lintrule_reports::Vector{LintRuleReport}
    branch::String  # The branch on which we got the result

    LintGlobalReport(args...) = new(args...)
end

LintGlobalReport() = LintGlobalReport(0, 0, 0)
LintGlobalReport(a, b, c) = LintGlobalReport(a, b, c, 0)
LintGlobalReport(a, b, c, d) = LintGlobalReport(a, b, c, d, String[])
LintGlobalReport(a, b, c, d, e) = LintGlobalReport(a, b, c, d, e, 0)
LintGlobalReport(a, b, c, d, e, f) = LintGlobalReport(a, b, c, d, e, f, LintRuleReport[])
LintGlobalReport(a, b, c, d, e, f, g) = LintGlobalReport(a, b, c, d, e, f, LintRuleReport[], "master")

# Base overwrites

function Base.append!(l1::LintGlobalReport, l2::LintGlobalReport)
    l1.files_count += l2.files_count
    l1.violations_count += l2.violations_count
    l1.recommendations_count += l2.recommendations_count
    l1.fatal_violations_count += l2.fatal_violations_count
    Base.append!(l1.linted_files, l2.linted_files)
    Base.append!(l1.lintrule_reports, l2.lintrule_reports)

    return l1.printout_count += l2.printout_count
end

function Base.:(==)(l1::LintGlobalReport, l2::LintGlobalReport)
    return l1.files_count == l2.files_count &&
        l1.violations_count == l2.violations_count &&
        l1.recommendations_count == l2.recommendations_count &&
        l1.fatal_violations_count == l2.fatal_violations_count &&
        l1.linted_files == l2.linted_files &&
        l1.printout_count == l2.printout_count &&
        l1.lintrule_reports == l2.lintrule_reports
end

# Precommit config
# ================

"""
    LintFileExclusion

Wrapper for a regex matching the names of the files that should be excluded when linting
during pre-commit.
"""
struct LintFileExclusion
    regex::String
end

should_be_excluded(lfe::LintFileExclusion, filename::String) =
    !isnothing(match(Regex(lfe.regex), filename))
should_be_excluded(lfes::Vector{LintFileExclusion}, filename::String) =
    any(lfe -> should_be_excluded(lfe, filename), lfes)

"""
    extract_file_exclusions_from_precommit_file(pre_commit_file::String)

For a given pre-commit file configuration, extract the regex rules used to exclude files
from the linting process.
"""
function extract_file_exclusions_from_precommit_file(pre_commit_file::String)
    # 3 states:
    #   - outside the ReLint repo entry (initial state);
    #   - inside the exclusion entry;
    #   - inside the ReLint repo entry and we are in the exclude section.
    state = :outside_repo_entry

    file_exclusions = []
    open(pre_commit_file, "r") do io
        for line in eachline(io)
            if state == :outside_repo_entry
                # We are outside the ReLint repo entry.
                if contains(line, "lint-fatal-checks")
                    # We are inside the ReLint repo entry.
                    state = :inside_repo_entry
                    continue
                end
            elseif state == :inside_repo_entry
                if contains(line, "(?x)^(")
                    # We are inside the ReLint repo entry.
                    state = :inside_exclusion_entry
                    continue
                end
            elseif state == :inside_exclusion_entry
                # We are leaving the exclusion portion.
                if contains(line, ")")
                    state = :outside_repo_entry
                    continue
                end
                regex_rule = strip(line, ['{', '}', '\n', ' ', '|'])
                !isempty(regex_rule) &&
                    push!(file_exclusions, LintFileExclusion(regex_rule))
            end
        end
    end
    return file_exclusions
end

# Formatting
# ==========

"""
    AbstractFormatter

Supertype for all lint report formatters.
"""
abstract type AbstractFormatter end

"""
    PlainFormat <: AbstractFormatter

Default lint report formatter.
"""
struct PlainFormat <: AbstractFormatter end

# MarkdownFormat can optionally contains github information. This is useful when a
# report is generated which contains Markdown links.
# file_prefix_to_remove corresponds to a prefix files will be removed when generating the
# report. This is useful because GitHub Action clones a repository in a folder of the same
# name. In our case, GHA will create /home/runner/work/raicode/raicode so we need to remove
# one "raicode" from the fullname.
"""
    MarkdownFormat <: AbstractFormatter

Markdown lint report formatter which contains GitHub information such as branch and
repository. It is useful when the generated report contains Markdown links.
"""
struct MarkdownFormat <: AbstractFormatter
    github_branch_name::String
    github_repository_name::String
    file_prefix_to_remove::String
    stream_workflowcommand::IO

    MarkdownFormat() = new("", "", "", devnull)
    MarkdownFormat(
        branch::String,
        repo::String,
        prefix::String,
        stream_workflowcommand::IO
    ) = new(branch, repo, prefix, stream_workflowcommand)
    MarkdownFormat(branch::String, repo::String) = new(branch, repo, "", devnull)
end

"""
    PreCommitFormat <: AbstractFormatter

Pre-commit lint report formatter. Only shows fatal violations and a summary.
"""
struct PreCommitFormat <: AbstractFormatter end

# Linting
# =======

"""
    LintContext

The lint context containing the set of rules to run and the set of `LintFileExclusion`s,
if any.
"""
struct LintContext
    rules::Vector{Rule}
    file_exclusions::Vector{LintFileExclusion}

    LintContext(rules::Vector{Rule}) = new(rules, [])
    LintContext(rule::Rule) = new([rule], [])
    LintContext() = new(ALL_RULES, [])
    LintContext(a, b) = new(a, b)
end

"""
    lint_file(rootpath[, context::LintContext])

Lint the file found at `rootpath`. If a lint context is not specified, use all rules
defined in ReLint.
"""
lint_file(rootpath, context::LintContext=LintContext()) =
    lint_text(read(rootpath, String); context, filename = rootpath)

"""
    lint_text(text::String; filename="<string>", context::LintContext=LintContext())

Runs lint checks on `text`. Lints will be reported as comming from `filename`.
"""
function lint_text(text::String; filename="<string>", context::LintContext=LintContext())
    ast = JuliaSyntax.parseall(SyntaxNode, text; filename=filename, ignore_warnings=true)
    ast = Argus._normalise!(ast)

    lint_rule_reports = []
    match_results = rules_match(context.rules, ast; disabler=relint_disabler)
    # Remove refactorings.
    #
    # TODO: Include refactorings as suggestions.
    for (rule_name, match_result) in match_results
        successful_match_results = map(m -> m[1], match_result.matches)
        rule =
            context.rules[findfirst(r -> r.name == rule_name, context.rules)]
        for m in successful_match_results
            push!(lint_rule_reports, Argus_result_to_LintRuleReport(rule, m))
        end
    end

    return lint_rule_reports
end

"""
    run_lint_on_dir(rootpath::String;
                    result::LintGlobalReport=LintGlobalReport(),
                    io::Union{IO, Nothing}=stdout,
                    io_violations::Union{IO, Nothing}=nothing,
                    io_recommendations::Union{IO, Nothing}=nothing,
                    formatter::AbstractFormatter=PlainFormat(),
                    context::LintContext=LintContext())

Lint the directory found at `rootpath`.
"""
function run_lint_on_dir(rootpath::String;
                         result::LintGlobalReport = LintGlobalReport(),
                         io::Union{IO, Nothing} = stdout,
                         io_violations::Union{IO, Nothing} = nothing,
                         io_recommendations::Union{IO, Nothing} = nothing,
                         formatter::AbstractFormatter = PlainFormat(),
                         context::LintContext = LintContext())
    # Exit if we are in .git
    !isnothing(match(r".*/\.git.*", rootpath)) && return result

    for (root, dirs, files) in walkdir(rootpath)
        for file in files
            filename = joinpath(root, file)
            endswith(filename, ".jl") &&
                run_lint(filename;
                         result,
                         io,
                         io_violations,
                         io_recommendations,
                         formatter,
                         context)
        end

        for dir in dirs
            p = joinpath(root, dir)
            !isnothing(match(r".*/\.git.*", p)) && continue
            run_lint_on_dir(p;
                            result,
                            io,
                            io_violations,
                            io_recommendations,
                            formatter,
                            context)
        end
    end
    return result
end

"""
    run_lint(rootpath::String;
             io::IO=stdout,
             io_violations::Union{IO,Nothing},
             io_recommendations::Union{IO,Nothing})

Lint the file found at `rootpath`. Return a LintGlobalReport.

# Examples

```
import ReLint
ReLint.run_lint("foo/bar/myfile.jl")
```
"""
function run_lint(rootpath::String;
                  result::LintGlobalReport=LintGlobalReport(),
                  io::Union{IO, Nothing}=stdout,
                  io_violations::Union{IO, Nothing}=nothing,
                  io_recommendations::Union{IO, Nothing}=nothing,
                  io_others::Union{IO, Nothing}=nothing,
                  formatter::AbstractFormatter=PlainFormat(),
                  context::LintContext=LintContext())
    # Return if `rootpath` is already linted.
    rootpath in result.linted_files && return result
    # Lint as directory if `rootpath` is a directory.
    isdir(rootpath) && return run_lint_on_dir(rootpath;
                                              result,
                                              io,
                                              io_violations,
                                              io_recommendations,
                                              formatter,
                                              context)
    # Don't lint non-Julia files.
    endswith(rootpath, ".jl") || return result
    # Exclude files as specified by the pre-commit configuration.
    should_be_excluded(context.file_exclusions, rootpath) && return result

    # Here, `rootpath` is surely an unlinted Julia file.
    #
    # Lint the file and print the report.
    lint_reports = lint_file(rootpath, context)
    isempty(lint_reports) || print_header(formatter, io, rootpath)
    # Extract reports according to rule type.
    violation_reports = filter(is_violation, lint_reports)
    recommandation_reports = filter(is_recommendation, lint_reports)
    fatal_violation_reports = filter(is_fatal, lint_reports)
    other_reports = filter(r -> !is_recommendation(r) && !is_violation(r) && !is_fatal(r),
                           lint_reports)
    count_violations = length(violation_reports)
    count_recommendations = length(recommandation_reports)
    count_fatal_violations = length(fatal_violation_reports)
    count_others = length(other_reports)
    # Print reports to their specific `IO`s.
    io_fatal_violations = isnothing(io_violations) ? io : io_violations
    for r in fatal_violation_reports
        print_report(formatter, io_fatal_violations, r, result)
    end
    io_violations = isnothing(io_violations) ? io : io_violations
    for r in violation_reports
        print_report(formatter, io_violations, r, result)
    end
    io_recommendations = isnothing(io_recommendations) ? io : io_recommendations
    for r in recommandation_reports
        print_report(formatter, io_recommendations, r, result)
    end
    io_others = isnothing(io_others) ? io : io_others
    for r in other_reports
        print_report(formatter, io_others, r, result)
    end
    # Collect all reports and return the result.
    append!(result, LintGlobalReport(1,
                                     count_violations,
                                     count_recommendations,
                                     count_fatal_violations,
                                     [rootpath],
                                     0,
                                     lint_reports))
    return result
end

# TODO: Remove/replace this.
"""
file_name corresponds to a file name that is used to create the temporary file. This is
useful to test some rules that depends on the filename.

`directory` can be "src/Compiler". In that case, the file to be created is "tmp_julia_file.jl"
"""
function run_lint_on_text(
        source::String;
        result::LintGlobalReport = LintGlobalReport(),
        io::Union{IO, Nothing} = stdout,
        formatter::AbstractFormatter = PlainFormat(),
        directory::String = "",
        context::LintContext = LintContext()
    )
    io_violations = IOBuffer()
    io_recommendations = IOBuffer()
    local tmp_file_name, tmp_dir
    local correct_directory = ""
    if isempty(directory)
        tmp_file_name = tempname() * ".jl"
    else
        correct_directory = first(directory) == '/' ? directory[2:end] : directory
        tmp_dir = joinpath(tempdir(), correct_directory)
        mkpath(tmp_dir)
        tmp_file_name = joinpath(tmp_dir, "tmp_julia_file.jl")
    end

    open(tmp_file_name, "w") do file
        write(file, source)
        flush(file)
        run_lint(tmp_file_name; result, io, io_violations, io_recommendations, formatter, context)
    end

    print(io, String(take!(io_violations)))
    print(io, String(take!(io_recommendations)))

    print_summary(
        formatter,
        io,
        result
    )
    print_footer(formatter, io)

    # If a directory has been provided, then it needs to be deleted, after manually deleting the file
    return if !isempty(correct_directory)
        rm(tmp_file_name)
        rm(tmp_dir)
    end
end

"""
    generate_report(filenames::Vector{String},
                    output_filename::String;
                    json_output::IO=stdout,
                    json_filename::Union{Nothing, String}=nothing,
                    github_repository::String="",
                    branch_name::String="",
                    file_prefix_to_remove::String="",
                    local_files_only::Bool=false,
                    stream_workflowcommand::IO=stdout,
                    rules::Vector{Rule}=ALL_RULES,
                    pre_commit_file::String="")

Generate a Markdown report based on the linting all given files. The report is intenteded
to be posted as a comment on a GitHub PR.

The report could also be generated in JSON format (useful for DataDog).

# Arguments

  - `filenames`: the list of files to be analysed. Only Julia files are linted;
                 if `local_files_only` is `true`, `filenames` is ignored;
  - `output_filename`: the file where the Markdown report will be printed;
                       if the file already exist, no analysis is run;
  - `json_output`: the output stream where the JSON report should be printed; may be
                   overridden by `json_filename`;
  - `json_filename`: the file where the JSON report will be printed;
  - `github_repository`: the name of the repository where the analysis is run;
  - `branch_name`: the name of the branch where the analysis is run;
  - `file_prefix_to_remove`: prefix to remove for all analysed files; this is
                             because GHAction creates a folder of the same name before
                             cloning it; this argument can be removed in the future;
  - `local_files_only`: when set to `true` replace `filenames` with the list of files found
                        at `.` (`pwd`); used by the github action workflow to run ReLint
                        on master;
  - `rules`: the set of lint rules to be run;
  - `pre_commit_file`: the path to the pre-commit configuration file.
"""
function generate_report(filenames::Vector{String},
                         output_filename::String;
                         json_output::IO=stdout,
                         json_filename::Union{Nothing, String}=nothing,
                         github_repository::String="",
                         branch_name::String="",
                         file_prefix_to_remove::String="",
                         local_files_only::Bool=false,
                         stream_workflowcommand::IO=stdout,
                         rules::Vector{Rule}=ALL_RULES,
                         pre_commit_file::String="")
    if isfile(output_filename)
        @error "File $(output_filename) exist already."
        return nothing
    end

    if !isnothing(json_filename)
        if isfile(json_filename)
            @error "File $(json_filename) exist already, cannot create JSON file."
            return nothing
        end
        json_output = open(json_filename, "w")
    end

    local errors_count = 0
    local julia_filenames = local_files_only ?
        [pwd()] :
        filter(n -> endswith(n, ".jl"), filenames)

    # Initialise the report.
    lint_report = LintGlobalReport()
    lint_report.branch = branch_name
    # Run the rules and print the report in `output_filename`.
    open(output_filename, "w") do output_io
        # Print report header.
        println(output_io, "## Static analysis report")
        println(output_io, "**Output of [ReLint.jl]\
            (https://github.com/RelationalAI-oss/ReLint.jl). \
            🫵[Want to contribute?]\
            (https://github.com/RelationalAI-oss/ReLint.jl?tab=readme-ov-file#contributing-to-relintjl)🫵\
            **\n\
            Report creation time (UTC): ($(now(UTC)))")
        # Initialise Markdown formatter.
        formatter = MarkdownFormat(
            branch_name,
            github_repository,
            file_prefix_to_remove,
            stream_workflowcommand,
        )
        # Set up report buffers for each rule category.
        io_violations = IOBuffer()
        io_recommendations = IOBuffer()
        # Set up the lint context.
        context = isempty(pre_commit_file) ?
            LintContext(rules) :
            LintContext(rules,
                        extract_file_exclusions_from_precommit_file(pre_commit_file))
        # Lint all files.
        for filename in julia_filenames
            run_lint(filename;
                     result=lint_report,
                     io=output_io,
                     io_violations,
                     io_recommendations,
                     formatter,
                     context)
        end
        # Print violation reports.
        print(output_io, String(take!(io_violations)))
        # Print recommendation reports.
        recommendations = String(take!(io_recommendations))
        if !isempty(recommendations)
            println(output_io, "\n")
            println(
                output_io, """
                <details>
                <summary>For PR Reviewer ($(lint_report.recommendations_count))</summary>

                $(recommendations)
                </details>
                """
            )
        end
        # Print a warning if not all reports are shown.
        violation_and_recommendation_reports_count =
            lint_report.violations_count + lint_report.recommendations_count
        if violation_and_recommendation_reports_count > lint_report.printout_count
            println(output_io,
                    "⚠️Only a subset of the reports are shown⚠️")
        end
        # Print summary.
        if isempty(lint_report.linted_files)
            println(output_io, "No Julia files were modified or added in this PR.")
        else
            errors_count =
                violation_and_recommendation_reports_count +
                lint_report.fatal_violations_count
            ending = length(julia_filenames) == 1 ? "" : "s"
            if iszero(errors_count)
                print(output_io, string("🎉No potential threats were found over ",
                                        length(julia_filenames),
                                        " Julia file",
                                        ending,
                                        ".👍\n"))
            else
                ending_recommendations = lint_report.recommendations_count == 1 ? "" : "s"
                ending_violations = lint_report.violations_count == 1 ? "" : "s"
                ending_fatal_violations =
                    lint_report.fatal_violations_count == 1 ? "" : "s"
                was_or_were = errors_count == 1 ? "was" : "were"
                ending_files = lint_report.files_count == 1 ? "" : "s"
                println(output_io, string("🚨**In total, ",
                                          lint_report.fatal_violations_count,
                                          " fatal violation",
                                          ending_fatal_violations,
                                          ", ",
                                          lint_report.violations_count,
                                          " violation",
                                          ending_violations,
                                          " and ",
                                          lint_report.recommendations_count,
                                          " PR reviewer recommendation",
                                          ending_recommendations,
                                          " ",
                                          was_or_were,
                                          " found over ",
                                          lint_report.files_count,
                                          " Julia file",
                                          ending_files,
                                          "**🚨"))
            end
        end
        println(output_io, string(length(rules), " rules were used to build this report."))
    end

    # Print DataDog report.
    report_as_string = open(output_filename) do io
        read(io, String)
    end
    print_datadog_report(
        json_output,
        report_as_string,
        lint_report.files_count,
        lint_report.violations_count,
        lint_report.recommendations_count,
        lint_report.fatal_violations_count,
        lint_report.branch,
        length(rules),
    )

    # If `json_filename` is provided, we are writing the result in `json_output` and need
    # to close the stream.
    isnothing(json_filename) || close(json_output)

    return nothing
end

# Registering rules
# -----------------

"""
    register_rule!(rule::Rule)

Register a rule to ReLint.
"""
function register_rule!(rule::Rule)
    push!(ALL_RULES, rule)
    return  nothing
end

"""
    register_rules!(rules::Vector{Rule})

Register a set of rules to ReLint.
"""
function register_rules!(rules::Vector{Rule})
    append!(ALL_RULES, rules)
    return nothing
end

"""
    register_rule_group!(rule_group::RuleGroup)

Register a rule group to ReLint.
"""
function register_rule_group!(rule_group::RuleGroup)
    append!(ALL_RULES, collect(values(rule_group)))
    return nothing
end

"""
    register_rule_groups!(rule_groups::Vector{RuleGroup})

Register a set of rule groups to ReLint.
"""
function register_rule_groups!(rule_groups::Vector{RuleGroup})
    [register_rule_group!(rg) for rg in rule_groups]
    return nothing
end

# Printing
# --------

# Plain format

print_header(::PlainFormat, io::IO, rootpath::String) =
    printstyled(io, "-"^10 * " $(rootpath)\n", color = :blue)

print_footer(::PlainFormat, io::IO) =
    printstyled(io, "-"^10 * "\n\n", color = :blue)

function print_report(::PlainFormat,
                      io::IO,
                      lint_report::LintRuleReport,
                      result::LintGlobalReport)
    should_print_report(result) || return
    printstyled(io,
                "Line $(lint_report.line), column $(lint_report.column):",
                color = :green)
    print(io, " ")
    print(io, lint_report.msg)
    print(io, " ")
    println(io, lint_report.file)
    result.printout_count += 1

    return nothing
end

function print_summary(::PlainFormat,
                       io::IO,
                       result::LintGlobalReport)
    nb_rulereports =
        result.recommendations_count +
        result.violations_count +
        result.fatal_violations_count
    if iszero(nb_rulereports)
        printstyled(io, "No potential threats were found.\n", color = :green)
    else
        was_or_were = nb_rulereports == 1 ? " was" : "s were"
        ending_violations = result.violations_count == 1 ? "" : "s"
        ending_fata_violations = result.fatal_violations_count == 1 ? "" : "s"
        ending_recommendations = result.recommendations_count == 1 ? "" : "s"
        printstyled(io,
                    string(nb_rulereports, " potential threat$(was_or_were) found: "),
                    color = :red)
        printstyled(io,
                    string(result.fatal_violations_count,
                           " fatal violation",
                           ending_fata_violations,
                           ", ",
                           result.violations_count,
                           " violation",
                           ending_violations,
                           " and ",
                           result.recommendations_count,
                           " recommendation",
                           ending_recommendations,
                           "\n"),
                    color = :red)
    end

    return nothing
end

# Markdown format

print_header(::MarkdownFormat, io::IO, rootpath::String) = nothing

print_footer(::MarkdownFormat, io::IO) = nothing

# Remove the leading '/', if any. Remove the prefix mentioned in `generate_report`.
function remove_prefix_from_filename(file_name::String, file_prefix_to_remove::String)
    corrected_file_name = first(file_name) == '/' ? file_name[2:end] : file_name
    if startswith(corrected_file_name, file_prefix_to_remove)
        corrected_file_name = corrected_file_name[(length(file_prefix_to_remove) + 1):end]
    end
    return corrected_file_name
end
remove_prefix_from_filename(file_name::String, format::MarkdownFormat) =
    remove_prefix_from_filename(file_name, format.file_prefix_to_remove)

function print_report(format::MarkdownFormat,
                      io::IO,
                      lint_report::LintRuleReport,
                      result::LintGlobalReport)
    should_print_report(result) || return nothing

    corrected_file_name = remove_prefix_from_filename(lint_report.file, format)
    coordinates = "Line $(lint_report.line), column $(lint_report.column):"
    if !isempty(format.github_branch_name) && !isempty(format.github_repository_name)
        coordinates = string("[",
                             coordinates,
                             "](https://github.com/",
                             format.github_repository_name,
                             "/blob/",
                             format.github_branch_name,
                             "/",
                             corrected_file_name,
                             "#L",
                             lint_report.line,
                             ")")
    end
    print(io, " - **$(coordinates)** $(lint_report.msg) $(lint_report.file)\n")
    # Produce workflow command to see results in the PR file changed tab:
    # https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#example-setting-an-error-message
    println(format.stream_workflowcommand,
            string("::error file=",
                   corrected_file_name,
                   ",line=",
                   lint_report.line,
                   ",col=",
                   lint_report.column,
                   "::",
                   lint_report.msg))
    result.printout_count += 1

    return nothing
end

print_summary(::MarkdownFormat, io::IO, result::LintGlobalReport) = nothing

# Pre-commit format

print_header(::PreCommitFormat, io::IO, rootpath::String) = nothing

print_footer(::PreCommitFormat, io::IO) = nothing

function print_summary(::PreCommitFormat, io::IO, result::LintGlobalReport)
    print_summary(PlainFormat(), io, result)
    return printstyled(io,
                       "Note that the list above only shows fatal violations\n",
                       color = :red)
end

function print_report(::PreCommitFormat,
                      io::IO,
                      lint_report::LintRuleReport,
                      result::LintGlobalReport)
    should_print_report(result) || return nothing
    # Only print fatal violations.
    is_fatal(lint_report) || return nothing
    printstyled(io,
                "Line $(lint_report.line), column $(lint_report.column):",
                color = :green)
    print(io, " ")
    print(io, lint_report.msg)
    print(io, " ")
    println(io, lint_report.file)
    result.printout_count += 1

    return nothing
end

# DataDog

function print_datadog_report(json_output::IO,
                              report_as_string::String,
                              files_count::Integer,
                              violation_count::Integer,
                              recommandation_count::Integer,
                              fatalviolations_count::Integer,
                              branch::String,
                              rules_count::Integer)
    event = Dict(
        :source => "ReLint",
        :specversion => "1.1",
        :type => "result",
        :time => string(now(UTC)),
        :data => Dict(
            :report_as_string => report_as_string,
            :files_count => files_count,
            :violation_count => violation_count,
            :recommandation_count => recommandation_count,
            :fatalviolations_count => fatalviolations_count,
            :branch => branch,
            :rules_count => rules_count,
        )
    )

    return println(json_output, JSON3.write(event))
end

# Utils

should_print_report(result) = result.printout_count <= MAX_REPORTED_ERRORS
