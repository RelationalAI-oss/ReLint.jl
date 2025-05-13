using Dates
using JSON3

global MAX_REPORTED_ERRORS = 60 # 1_000_000

# Each individual rule violation report
mutable struct LintRuleReport
    rule::LintRule
    msg::String
    template::String
    file::String
    line::Int64
    column::Int64
    is_disabled::Bool   # Happens with a comments in the code

    offset::Int64
end
LintRuleReport(rule::LintRule, msg::String) = LintRuleReport(rule, msg, "", "", 0, 0, false, 0)

# File exclusion
struct LintFileExclusion
    regex::String
end
function should_be_excluded(lfe::LintFileExclusion, filename::String)
    # isdefined(Main, :Infiltrator) && Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    return !isnothing(match(Regex(lfe.regex), filename))
end
function should_be_excluded(lfes::Vector{LintFileExclusion}, filename::String)
    return any(lfe -> should_be_excluded(lfe, filename), lfes)
end

# For a given pre-commit file configuration, the function extract the regex rules
# that are used to exclude files from the linting process.
function extract_file_exclusions_from_precommit_file(pre_commit_file::String)
    # 3 states:
    #   - outside the ReLint repo entry (initial state)
    #   - inside the exclusion entry
    #   - inside the ReLint repo entry and we are in the exclude section
    state = :outside_repo_entry

    file_exclusions = []
    open(pre_commit_file, "r") do io
        for line in eachline(io)
            if state == :outside_repo_entry
                # We are outside the ReLint repo entry
                if contains(line, "lint-fatal-checks")
                    # We are inside the ReLint repo entry
                    # @info :inside_repo_entry
                    state = :inside_repo_entry
                    continue
                end
            elseif state == :inside_repo_entry
                # @info :inside_repo_entry

                if contains(line, "(?x)^(")
                    # We are inside the ReLint repo entry
                    state = :inside_exclusion_entry
                    continue
                end
            elseif state == :inside_exclusion_entry
                # @info :inside_exclusion_entry

                # We are leaving the exclusion portion
                if contains(line, ")")
                    state = :outside_repo_entry
                    continue
                end
                regex_rule = strip(line, ['{', '}', '\n', ' ', '|'])
                !isempty(regex_rule) && push!(file_exclusions, LintFileExclusion(regex_rule))
            end
        end
    end
    return file_exclusions
end


# Global result of executing Lint on files and folders
mutable struct LintResult
    files_count::Integer
    violations_count::Integer
    recommendations_count::Integer
    fatalviolations_count::Integer
    linted_files::Vector{String}
    printout_count::Integer
    lintrule_reports::Vector{LintRuleReport}
    branch::String  # The branch on which we got the result

    LintResult(args...) = new(args...)
end

LintResult() = LintResult(0, 0, 0)
LintResult(a, b, c) = LintResult(a, b, c, 0)
LintResult(a, b, c, d) = LintResult(a, b, c, d, String[])
LintResult(a, b, c, d, e) = LintResult(a, b, c, d, e, 0)
LintResult(a, b, c, d, e, f) = LintResult(a, b, c, d, e, f, LintRuleReport[])
LintResult(a, b, c, d, e, f, g) = LintResult(a, b, c, d, e, f, LintRuleReport[], "master")


function Base.append!(l1::LintResult, l2::LintResult)
    l1.files_count += l2.files_count
    l1.violations_count += l2.violations_count
    l1.recommendations_count += l2.recommendations_count
    l1.fatalviolations_count += l2.fatalviolations_count
    Base.append!(l1.linted_files, l2.linted_files)
    Base.append!(l1.lintrule_reports, l2.lintrule_reports)

    l1.printout_count += l2.printout_count
end

function Base.:(==)(l1::LintResult, l2::LintResult)
    return l1.files_count == l2.files_count &&
           l1.violations_count == l2.violations_count &&
           l1.recommendations_count == l2.recommendations_count &&
           l1.fatalviolations_count == l2.fatalviolations_count &&
           l1.linted_files == l2.linted_files &&
           l1.printout_count == l2.printout_count &&
           l1.lintrule_reports == l2.lintrule_reports
end

function is_already_linted(l::LintResult, filename)
    return filename in l.linted_files
end

function has_values(l::LintResult, a, b, c)
    return  l.files_count == a &&
            l.violations_count == b &&
            l.recommendations_count == c
end


"""
    lint_file(rootpath, context)


"""
function lint_file(rootpath, context::LintContext)
    file_content_string = open(io->read(io, String), rootpath, "r")
    ast = CSTParser.parse(file_content_string, true)

    markers::Dict{Symbol,String} = Dict(:filename => rootpath)
    check_all(ast, markers, context)

    lint_rule_reports = []

    for (offset, x) in collect_lint_report(ast)
        if haserror(x)
            # The next line should be deleted
            lint_rule_report = x.meta.error
            lint_rule_report.offset = offset

            line_number, column, annotation_line = convert_offset_to_line_from_filename(lint_rule_report.offset + 1, lint_rule_report.file)
            lint_rule_report.line = line_number
            lint_rule_report.column = column

            # If the annotation is to disable lint,
            if annotation_line == "lint-disable-line"
                # then we disable it.
            elseif !isnothing(annotation_line) && startswith("lint-disable-line: $(lint_rule_report.msg)", annotation_line)
                # then we disable it.
            else
                # Else we record it.
                push!(lint_rule_reports, lint_rule_report)
            end
        end
    end
    return lint_rule_reports
end

# Return (index_line, index_column, annotation) for a given offset in a source
function convert_offset_to_line_from_filename(offset::Union{Int64, Int32}, filename::String)
    all_lines = open(io->readlines(io), filename)
    return convert_offset_to_line_from_lines(offset, all_lines)
end

function convert_offset_to_line(offset::Integer, source::String)
    return convert_offset_to_line_from_lines(offset, split(source, "\n"))
end

# Return the lint next-line annotation, if there is one, at the end of `line`.
# Return
#   * `nothing`      if there is no `lint-disable-next-line` annotation.
#   * ""::SubString  if the end of the line is "lint-disable-next-line".
#   * s::SubString   if the end of the line is "lint-disable_next_line: $s"
function annotation_for_next_line(line::AbstractString)
    if endswith(line, "lint-disable-next-line")
        return ""
    end
    # An annotation must be in a comment and not contain any `#` or `"` characters.
    m = match(r"# lint-disable-next-line: *([^\"#]+)$", line)
    return isnothing(m) ? nothing : m[1]
end

function annotation_for_this_line(line::AbstractString)
    if endswith(line, "lint-disable-line")
        return ""
    end
    # An annotation must be in a comment and not contain any `#` or `"` characters.
    m = match(r"#\h*lint-disable-line: *([^\"#]+)$", line)
    return isnothing(m) ? nothing : m[1]
end

# Return a triple: (line::Int, column::Int, annotation::Option(String))
#
# `annotation` could be either `nothing`, "lint-disable-line", or
# `"lint-disable-line: $ERROR_MSG_TO_IGNORE"`
#
# Note: `offset` is measured in codepoints.  The returned `column` is a character
# offset, not a codepoint offset.
function convert_offset_to_line_from_lines(offset::Integer, all_lines)
    offset < 0 && throw(BoundsError("source", offset))

    current_codepoint = 1
    # In these annotations, "" means "lint-disable-line", a nonempty string `s` means
    # "lint_disable_line: $s", and nothing means there's no applicable annotation.
    prev_annotation::Union{Nothing,SubString} = nothing
    this_annotation::Union{Nothing,SubString} = nothing
    for (line_number, line) in enumerate(all_lines)
        this_annotation = annotation_for_this_line(line)
        # current_codepoint + sizeof(line) is possibly pointing at the newline that isn't
        # actually stored in `line`.
        if offset in current_codepoint:(current_codepoint + sizeof(line))
            index_in_line = offset - current_codepoint + 1 # possibly off the end by 1.
            if !isnothing(this_annotation)
                annotation = this_annotation
            elseif !isnothing(prev_annotation)
                annotation = prev_annotation
            else
                annotation = nothing
            end
            if !isnothing(annotation)
                if annotation == ""
                    annotation = "lint-disable-line"
                else
                    annotation = "lint-disable-line: " * annotation
                end
            end
            if index_in_line == sizeof(line) + 1
                return line_number, length(line)+1, annotation
            else
                return line_number, length(line, 1, index_in_line), annotation
            end
        end
        prev_annotation = annotation_for_next_line(line)
        current_codepoint += sizeof(line) + 1 # 1 is for the newline
    end
    throw(BoundsError("source", offset))
end

abstract type AbstractFormatter end
struct PlainFormat <: AbstractFormatter end

# MarkdownFormat can optionally contains github information. This is useful when a
# report is generated which contains Markdown links.
# file_prefix_to_remove corresponds to a prefix files will be removed when generating the
# report. This is useful because GitHub Action clones a repository in a folder of the same
# name. In our case, GHA will create /home/runner/work/raicode/raicode so we need to remove
# one "raicode" from the fullname.
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
        stream_workflowcommand::IO) = new(branch, repo, prefix, stream_workflowcommand)
    MarkdownFormat(branch::String, repo::String) = new(branch, repo, "", devnull)
end

# Only show the fatal violations and a summary
struct PreCommitFormat <: AbstractFormatter end

function print_header(::PreCommitFormat, io::IO, rootpath::String)
    # printstyled(io, "-" ^ 10 * " $(rootpath)\n", color=:blue)
    # printstyled(io, "**List of Fatal violations, please address them to commit these files**\n", color=:red)
end

print_footer(::PreCommitFormat, io::IO) = nothing
function print_summary(::PreCommitFormat, io::IO, result::LintResult)
    print_summary(PlainFormat(), io, result)
    printstyled(io, "Note that the list above only show fatal violations\n", color=:red)
end

function print_report(::PreCommitFormat, io::IO, lint_report::LintRuleReport, result::LintResult)
    should_print_report(result) || return
    # Do not print anything if it is not a fatal violation
    lint_report.rule isa FatalLintRule || return
    printstyled(io, "Line $(lint_report.line), column $(lint_report.column):", color=:green)
    print(io, " ")
    print(io, lint_report.msg)
    print(io, " ")
    println(io, lint_report.file)
    result.printout_count += 1
end

should_print_report(result) = result.printout_count <= MAX_REPORTED_ERRORS

function _run_lint_on_dir(
    rootpath::String;
    result::LintResult=LintResult(),
    io::Union{IO,Nothing}=stdout,
    io_violations::Union{IO,Nothing}=nothing,
    io_recommendations::Union{IO,Nothing}=nothing,
    formatter::AbstractFormatter=PlainFormat(),
    context::LintContext=LintContext()
)
    # Exit if we are in .git
    !isnothing(match(r".*/\.git.*", rootpath)) && return result

    for (root, dirs, files) in walkdir(rootpath)
        for file in files
            filename = joinpath(root, file)
            if endswith(filename, ".jl")
                run_lint(filename; result, io, io_violations, io_recommendations, formatter, context)
            end
        end

        for dir in dirs
            p = joinpath(root, dir)
            !isnothing(match(r".*/\.git.*", p)) && continue
            _run_lint_on_dir(p; result, io, io_violations, io_recommendations, formatter, context)
        end
    end
    return result
end

function print_header(::PlainFormat, io::IO, rootpath::String)
    printstyled(io, "-" ^ 10 * " $(rootpath)\n", color=:blue)
end

function print_report(::PlainFormat, io::IO, lint_report::LintRuleReport, result::LintResult)
    should_print_report(result) || return
    printstyled(io, "Line $(lint_report.line), column $(lint_report.column):", color=:green)
    print(io, " ")
    print(io, lint_report.msg)
    print(io, " ")
    println(io, lint_report.file)
    result.printout_count += 1

end

function print_summary(
    ::PlainFormat,
    io::IO,
    result::LintResult
)
    nb_rulereports = result.violations_count + result.recommendations_count + result.fatalviolations_count
    if iszero(nb_rulereports)
        printstyled(io, "No potential threats were found.\n", color=:green)
    else
        plural = nb_rulereports > 1 ? "s are" : " is"
        plural_vio = result.violations_count > 1 ? "s" : ""
        plural_fatal = result.fatalviolations_count > 1 ? "s" : ""
        plural_rec = result.recommendations_count > 1 ? "s" : ""
        printstyled(io, "$(nb_rulereports) potential threat$(plural) found: ", color=:red)
        printstyled(io, "$(result.fatalviolations_count) fatal violation$(plural_fatal), $(result.violations_count) violation$(plural_vio) and $(result.recommendations_count) recommendation$(plural_rec)\n", color=:red)
    end
end

function print_footer(::PlainFormat, io::IO)
    printstyled(io, "-" ^ 10 * "\n\n", color=:blue)
end

print_header(::MarkdownFormat, io::IO, rootpath::String) = nothing
print_footer(::MarkdownFormat, io::IO) = nothing

# Remove a leading '/' if the file starts with one. This is necessary to build the URL
# Remove the prefix mentioned in the Markdown from the file_name
function remove_prefix_from_filename(file_name::String, file_prefix_to_remove::String)
    corrected_file_name = first(file_name) == '/' ? file_name[2:end] : file_name
    if startswith(corrected_file_name, file_prefix_to_remove)
        corrected_file_name = corrected_file_name[length(file_prefix_to_remove)+1:end]
    end
    return corrected_file_name
end

function remove_prefix_from_filename(file_name::String, format::MarkdownFormat)
    return remove_prefix_from_filename(file_name, format.file_prefix_to_remove)
end

function print_report(format::MarkdownFormat, io::IO, lint_report::LintRuleReport, result::LintResult)
    should_print_report(result) || return

    corrected_file_name = remove_prefix_from_filename(lint_report.file, format)

    coordinates = "Line $(lint_report.line), column $(lint_report.column):"
    if !isempty(format.github_branch_name) && !isempty(format.github_repository_name)
        extended_coordinates = "[$(coordinates)](https://github.com/$(format.github_repository_name)/blob/$(format.github_branch_name)/$(corrected_file_name)#L$(lint_report.line))"
        print(io, " - **$(extended_coordinates)** $(lint_report.msg) $(lint_report.file)\n")
    else
        print(io, " - **$(coordinates)** $(lint_report.msg) $(lint_report.file)\n")
    end

    # Produce workflow command to see results in the PR file changed tab:
    # https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#example-setting-an-error-message
    println(format.stream_workflowcommand, "::error file=$(corrected_file_name),line=$(lint_report.line),col=$(lint_report.column)::$(lint_report.msg)")
    result.printout_count += 1
end

print_summary(
    ::MarkdownFormat,
    io::IO,
    result::LintResult
) = nothing


"""
    run_lint(rootpath::String; io::IO=stdout, io_violations::Union{IO,Nothing}, io_recommendations::Union{IO,Nothing})

Run lint rules on a file `rootpath`, which must be an existing non-folder file. Return a
LintResult.

Example of use:
    import ReLint
    ReLint.run_lint("foo/bar/myfile.jl")
"""
function run_lint(
    rootpath::String;
    result::LintResult=LintResult(),
    io::Union{IO,Nothing}=stdout,
    io_violations::Union{IO,Nothing}=nothing,
    io_recommendations::Union{IO,Nothing}=nothing,
    formatter::AbstractFormatter=PlainFormat(),
    context::LintContext=LintContext()
)
    # If already linted, then we merely exit
    rootpath in result.linted_files && return result

    # If we are running Lint on a directory
    isdir(rootpath) && return _run_lint_on_dir(rootpath; result, io, io_violations, io_recommendations, formatter, context)

    # Check if we have to be run on a Julia file. Simply exit if not.
    # This simplify the amount of work in GitHub Action
    endswith(rootpath, ".jl") || return result

    # We should ignore this file?
    should_be_excluded(convert(Vector{LintFileExclusion}, context.regex_exclusions), rootpath) && return result

    # We are running Lint on a Julia file
    lint_reports = ReLint.lint_file(rootpath, context)
    isempty(lint_reports) || print_header(formatter, io, rootpath)

    is_recommendation(r::LintRuleReport) = r.rule isa RecommendationLintRule
    is_violation(r::LintRuleReport) = r.rule isa ViolationLintRule
    is_fatal(r::LintRuleReport) = r.rule isa FatalLintRule

    violation_reports = filter(is_violation, lint_reports)
    recommandation_reports = filter(is_recommendation, lint_reports)
    fatalviolation_reports = filter(is_fatal, lint_reports)

    count_violations = length(violation_reports)
    count_recommendations = length(recommandation_reports)
    count_fatalviolations = length(fatalviolation_reports)

    # Fatal reports are printed in io_violations, but first
    io_tmp = isnothing(io_violations) ? io : io_violations
    for r in fatalviolation_reports
        print_report(formatter, io_tmp, r, result)
    end

    io_tmp = isnothing(io_violations) ? io : io_violations
    for r in violation_reports
        print_report(formatter, io_tmp, r, result)
    end

    io_tmp = isnothing(io_recommendations) ? io : io_recommendations
    for r in recommandation_reports
        print_report(formatter, io_tmp, r, result)
    end

    # We run Lint on a single file.
    append!(result, LintResult(1, count_violations, count_recommendations, count_fatalviolations, [rootpath], 0, lint_reports))
    return result
end

"""
file_name corresponds to a file name that is used to create the temporary file. This is
useful to test some rules that depends on the filename.

`directory` can be "src/Compiler". In that case, the file to be created is "tmp_julia_file.jl"
"""
function run_lint_on_text(
    source::String;
    result::LintResult=LintResult(),
    io::Union{IO,Nothing}=stdout,
    formatter::AbstractFormatter=PlainFormat(),
    directory::String = "",   # temporary directory to be created. If empty, let Julia decide
    context::LintContext=LintContext()
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
        result)
    print_footer(formatter, io)

    # If a directory has been provided, then it needs to be deleted, after manually deleting the file
    if !isempty(correct_directory)
        rm(tmp_file_name)
        rm(tmp_dir)
    end
end

function print_datadog_report(
    json_output::IO,
    report_as_string::String,
    files_count::Integer,
    violation_count::Integer,
    recommandation_count::Integer,
    fatalviolations_count::Integer,
    branch::String,
)
    event = Dict(
        :source => "ReLint",
        :specversion => "1.0",
        :type => "result",
        :time => string(now(UTC)), #Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SSZ"), # RFC3339 format
        :data => Dict(
                    :report_as_string=>report_as_string,
                    :files_count => files_count,
                    :violation_count => violation_count,
                    :recommandation_count => recommandation_count,
                    :fatalviolations_count => fatalviolations_count,
                    :branch => branch,
                    )
    )
    println(json_output, JSON3.write(event))
end

"""
    generate_report(filenames::Vector{String}, output_filename::String;...)

Main entry point of ReLint.jl. The function `generate_report` takes as argument a list
of files on which lint has to process. A report is generated containing the result of the
Lint analysis.

The procuded markdown report is intenteded to be posted as a comment on a GitHub PR.
Furthermore, a JSON report file is produced to feed DataDog.

Here are the arguments:

    - `filenames` is the list of all the file that have to be analyzed. From this lint
only Julia files are considered. Filenames provided to that list that do not end with `.jl`
will be simply ignored. Note that this variable is not considered if
`analyze_all_file_found_locally` is set to true.
    - `output_filename` is the file to be created that will contains the Markdown report.
If the file already exist, then the no analysis is run.
    - `json_output` is an output stream to which the JSON report has to be printed. Note
that the value provided to this variable may be overriden by `json_filename`. In the future,
the variable `json_output` can be removed.
    - `json_filename` file is a filename used to create the JSON report for DataDog
    - `github_repository` is the name of the repository, e.g., `raicode`
    - `branch_name` is a GitHub branch name, useful for the reporting
    - `file_prefix_to_remove` prefix to remove for all the file to be analyzed. This is
because GHAction creates a folder of the same name before cloning it. However, this
option can be removed in the future with a simple `cd` in that folder.
    - `analyze_all_file_found_locally`, when set to `true` the `filenames` argument  is not
used and instead all the file found locally, from `.` will be analyzed. This is used by
the github action workflow to run Lint on master.

When provided, `github_repository` and `branch_name` are used to have clickable links in
the Markdown report.
"""
function generate_report(
    filenames::Vector{String},
    output_filename::String
    ;
    json_output::IO=stdout,
    json_filename::Union{Nothing,String}=nothing,  # Override `json_output` when not nothing
    github_repository::String="",
    branch_name::String="",
    file_prefix_to_remove::String="",
    analyze_all_file_found_locally::Bool=false,
    stream_workflowcommand::IO=stdout,
    rules_to_run::Vector{DataType}=all_extended_rule_types[],
    pre_commit_file::String="",
)
    if isfile(output_filename)
        @error "File $(output_filename) exist already."
        return
    end

    if !isnothing(json_filename)
        if isfile(json_filename)
            @error "File $(json_filename) exist already, cannot create json file."
            return
        end
        json_output = open(json_filename, "w")
    end

    local errors_count = 0
    local julia_filenames = filter(n->endswith(n, ".jl"), filenames)

    # Result of the whole analysis
    lint_result = LintResult()
    lint_result.branch = branch_name

    # If analyze_all_file_found_locally is set to true, we discard all the provided files
    # and analyze everything accessible from "."
    if analyze_all_file_found_locally
        julia_filenames = [pwd()]
    end

    open(output_filename, "w") do output_io
        println(output_io, "## Static code analyzer report")
        println(output_io, "**Output of the [ReLint.jl code analyzer]\
            (https://github.com/RelationalAI-oss/ReLint.jl). \
            🫵[Want to contribute?](https://github.com/RelationalAI-oss/ReLint.jl/blob/main/README.md#contributing-to-staticlintjl)🫵 \
            [RelationalAI Style Guide for Julia](https://github.com/RelationalAI/RAIStyle)**\n\
            Report creation time (UTC): ($(now(UTC)))")


        formatter=MarkdownFormat(
            branch_name,
            github_repository,
            file_prefix_to_remove,
            stream_workflowcommand,
            )

        io_violations = IOBuffer()
        io_recommendations = IOBuffer()

        context = nothing
        if !isempty(pre_commit_file)
            context = LintContext(
                rules_to_run,
                extract_file_exclusions_from_precommit_file(pre_commit_file))
        else
            context = LintContext(rules_to_run)
        end

        # RUN LINT!!!
        for filename in julia_filenames
            ReLint.run_lint(
                filename;
                result = lint_result,
                io = output_io,
                io_violations = io_violations,
                io_recommendations = io_recommendations,
                formatter,
                context
            )
        end
        print(output_io, String(take!(io_violations)))

        recommendations = String(take!(io_recommendations))
        if !isempty(recommendations)
            println(output_io, "\n")
            println(output_io, """
                                <details>
                                <summary>For PR Reviewer ($(lint_result.recommendations_count))</summary>

                                $(recommendations)
                                </details>
                                """)
        end

        has_julia_file = !isempty(lint_result.linted_files)

        if lint_result.violations_count + lint_result.recommendations_count > lint_result.printout_count
            println(output_io, "⚠️Only a subset of the violations and recommandations are here reported⚠️")
        end

        ending = length(julia_filenames) > 1 ? "s" : ""
        if !has_julia_file
            println(output_io, "No Julia file is modified or added in this PR.")
        else
            errors_count = lint_result.violations_count + lint_result.recommendations_count
            if iszero(errors_count)
                print(output_io, "🎉No potential threats are found over $(length(julia_filenames)) Julia file$(ending).👍\n\n")
            else
                s_vio = lint_result.violations_count > 1 ? "s" : ""
                s_rec = lint_result.recommendations_count > 1 ? "s" : ""
                is_or_are = errors_count == 1 ? "is" : "are"
                s_fil = lint_result.files_count > 1 ? "s" : ""
                println(output_io, "🚨**In total, $(lint_result.violations_count) rule violation$(s_vio) and $(lint_result.recommendations_count) PR reviewer recommendation$(s_rec) $(is_or_are) found over $(lint_result.files_count) Julia file$(s_fil)**🚨")
            end
        end
    end

    report_as_string = open(output_filename) do io read(io, String) end
    print_datadog_report(
        json_output,
        report_as_string,
        lint_result.files_count,
        lint_result.violations_count,
        lint_result.recommendations_count,
        lint_result.fatalviolations_count,
        lint_result.branch,)

    # If a json_filename was provided, we are writing the result in json_output.
    # In that case, we need to close the stream at the end.
    if !isnothing(json_filename)
        close(json_output)
    end
end
