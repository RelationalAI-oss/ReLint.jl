@testset "LintContext" begin
    using ReLint: LintContext, VIOLATIONS

    @testset "Basic" begin
        @test isempty(LintContext(Rule[]).rules)

        rules = [VIOLATIONS["@async"], VIOLATIONS["unsafe_ function"]]
        c = LintContext(rules)
        @test length(c.rules) == 2
        @test c.rules == rules

        @test iszero(LintContext(Rule[]).rules)
    end

    @testset "Setting context or not" begin
        source = """
            function f()
                _unsafe_g()
            end

            function _unsafe_g()
                return 42
            end
            """
        @test count_lint_errors(source) == 1
        @test count_lint_errors(source; context=LintContext()) == 1
        @test count_lint_errors(source; context=LintContext(Rule[])) == 0
        @test count_lint_errors(source;
                                context=LintContext([VIOLATIONS["@async"]])) == 0
        @test count_lint_errors(source;
                                context=LintContext([VIOLATIONS["unsafe_ function"]])) == 1
    end

    @testset "File in a dir" begin
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io
                write(io, "function f()\n  @async 1 + 1\nend\n")
                flush(io)

                @test has_values(ReLint.run_lint(dir; io), 1, 1, 0)

                context=LintContext(Rule[])
                @test has_values(ReLint.run_lint(dir; io, context), 1, 0, 0)

            end
        end
    end
end

@testset "Run several times on same file" begin
    mktempdir() do dir
        open(joinpath(dir, "foo.jl"), "w") do io
            write(io, "function f()\n  @async 1 + 1\nend\n")
            flush(io)

            @test has_values(ReLint.run_lint(dir; io), 1, 1, 0)
            @test has_values(ReLint.run_lint(dir; io), 1, 1, 0)
            @test has_values(ReLint.run_lint(dir; io), 1, 1, 0)
            @test has_values(ReLint.run_lint(dir; io), 1, 1, 0)
        end
    end
end

@testset "Linting multiple files" begin
    @testset "No errors" begin
        local result_is_empty = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @spawn 1 + 1\nend\n")
                    write(io2, "function g()\n  @spawn 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    ReLint.run_lint(dir; io=str, formatter=ReLint.MarkdownFormat())
                    result = String(take!(str))
                    result_is_empty = isempty(result)
                end
            end
        end
        @test result_is_empty
    end

    @testset "Two files with errors" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2, "function g()\n  @async 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    ReLint.run_lint(dir; io=str, formatter=ReLint.MarkdownFormat())

                    result = String(take!(str))

                    expected = r"""
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end

    @testset "No splatting warning in tests" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar_test.jl"), "w") do io2
                    write(io1, "function f()\n  foo(x...)\nend\n")
                    write(io2, "\n\nfunction g()\n  foo(x...)\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    ReLint.run_lint(dir; io=str, formatter=ReLint.MarkdownFormat())

                    result = String(take!(str))

                    expected = " - **Line 2, column 3:** Splatting (`...`) should be used with extreme caution."
                    result_matching = startswith(result, expected)
                    result_matching = result_matching && !contains(result, "bar_test.jl")
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with errors" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2,
                          "function g()\n  finalizer(\"hello\") do x nothing\nend\nend")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_output = IOBuffer()
                    stream_workflowcommand = IOBuffer()
                    ReLint.generate_report([file1, file2], output_file; json_output, stream_workflowcommand)

                    # Checking the Workflow command
                    stream_workflowcommand_report = String(take!(stream_workflowcommand))
                    wc_lines = split(stream_workflowcommand_report, "\n")
                    @test length(wc_lines) == 3
                    @test isempty(wc_lines[end])
                    @test contains(wc_lines[1], "foo.jl,line=2,col=3::Use `@spawn` instead of `@async`.")

                    # Checking the JSON
                    json_report = JSON3.read(String(take!(json_output)))
                    @test json_report[:source] == "ReLint"
                    @test json_report[:data][:files_count] == 2

                    @test json_report[:data][:violation_count] == 1
                    @test json_report[:data][:recommandation_count] == 1
                    @test json_report[:data][:fatalviolations_count] == 0

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    # First violations across files, then recommendations across files
                    expected = r"""
                        ## Static analysis report
                        \*\*Output of \[ReLint\.jl\]\(https://github\.com/RelationalAI-oss/ReLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+


                        <details>
                        <summary>For PR Reviewer \(1\)</summary>

                         - \*\*Line 2, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+\

                        </details>

                        🚨\*\*In total, 0 fatal violations, 1 violation and 1 PR reviewer recommendation were found over 2 Julia files\*\*🚨
                        """
                    result_matching = !isnothing(match(expected, result))
                    # DEBUG:
                    !result_matching && @info result
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with errors 02" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function g()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")
                    write(io2, "function f()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_output = IOBuffer()
                    ReLint.generate_report([file1, file2], output_file; json_output, stream_workflowcommand=devnull)

                    json_report = JSON3.read(String(take!(json_output)))
                    @test json_report[:source] == "ReLint"
                    @test json_report[:data][:files_count] == 2

                    @test json_report[:data][:recommandation_count] == 2
                    @test json_report[:data][:violation_count] == 2

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    # First violations across files, then recommendations across files
                    expected = r"""
                        ## Static analysis report
                        \*\*Output of \[ReLint\.jl\]\(https://github\.com/RelationalAI-oss/ReLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+

                        <details>
                        <summary>For PR Reviewer \(2\)</summary>

                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+
                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+

                        </details>

                        🚨\*\*In total, 0 fatal violations, 2 violations and 2 PR reviewer recommendations were found over 2 Julia files\*\*🚨
                        """
                    result_matching = !isnothing(match(expected, result))
                    # DEBUG:
                    !result_matching && @info result
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with errors 02 - JSON report" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function g()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")
                    write(io2, "function f()\n  @async 1 + 1\nend\n  finalizer(\"hello\") do x nothing\nend\n")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_filename = tempname()
                    @test !isfile(json_filename)
                    # json_io = IOBuffer()
                    ReLint.generate_report([file1, file2], output_file; json_filename, stream_workflowcommand=devnull)

                    @test isfile(json_filename)
                    json_content = open(io->read(io, String), json_filename)
                    json_report = JSON3.read(json_content)

                    @test json_report[:source] == "ReLint"
                    @test json_report[:data][:files_count] == 2

                    @test json_report[:data][:recommandation_count] == 2
                    @test json_report[:data][:violation_count] == 2

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    # First violations across files, then recommendations across files
                    expected = r"""
                        ## Static analysis report
                        \*\*Output of \[ReLint\.jl\]\(https://github\.com/RelationalAI-oss/ReLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+
                         - \*\*Line 2, column 3:\*\* Use `@spawn` instead of `@async`\. \H+

                        <details>
                        <summary>For PR Reviewer \(2\)</summary>

                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+
                         - \*\*Line 4, column 3:\*\* `finalizer\(_,_\)` should not be used\. \H+

                        </details>

                        🚨\*\*In total, 0 fatal violations, 2 violations and 2 PR reviewer recommendations were found over 2 Julia files\*\*🚨
                        """
                    result_matching = !isnothing(match(expected, result))
                    # DEBUG:
                    !result_matching && @info result
                end
            end
        end
        @test result_matching
    end

    @testset "No modified julia file" begin
        output_file = tempname()
        json_output = IOBuffer()
        ReLint.generate_report(String[], output_file; json_output, stream_workflowcommand=devnull)

        json_report = JSON3.read(String(take!(json_output)))
        @test json_report[:source] == "ReLint"
        @test json_report[:data][:files_count] == 0

        @test json_report[:data][:recommandation_count] == 0
        @test json_report[:data][:violation_count] == 0


        expected = r"""
            ## Static analysis report
            \*\*Output of \[ReLint\.jl\]\(https://github\.com/RelationalAI-oss/ReLint\.jl\).+\*\*
            Report creation time \(UTC\): \H+
            No Julia files were modified or added in this PR.
            """
        result = open(io->read(io, String), output_file)

        result_matching = !isnothing(match(expected, result))
        @test result_matching
    end

    @testset "No result with no julia file" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.txt")
            open(file1, "w") do io1
                write(io1, "Hello World\n")
                flush(io1)

                output_file = tempname()
                json_output = IOBuffer()
                ReLint.generate_report([file1], output_file; json_output, stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_output)))
                @test json_report[:source] == "ReLint"
                @test json_report[:data][:files_count] == 0
                @test json_report[:data][:recommandation_count] == 0
                @test json_report[:data][:violation_count] == 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end


                expected = r"""
                    ## Static analysis report
                    \*\*Output of \[ReLint\.jl\]\(https://github\.com/RelationalAI-oss/ReLint\.jl\).+\*\*
                    Report creation time \(UTC\): \H+
                    No Julia files were modified or added in this PR.
                    """
                result_matching = !isnothing(match(expected, result))
            end
        end
        @test result_matching
    end

    @testset "Report generation of two files with no errors" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            file2 = joinpath(dir, "bar.jl")
            open(file1, "w") do io1
                open(file2, "w") do io2
                    write(io1, "function f()\n  @spawn 1 + 1\nend\n")
                    write(io2, "function g()\n  @spawn 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    output_file = tempname()
                    json_output = IOBuffer()
                    ReLint.generate_report([file1, file2], output_file; json_output, stream_workflowcommand=devnull)

                    json_report = JSON3.read(String(take!(json_output)))
                    @test json_report[:source] == "ReLint"
                    @test json_report[:data][:files_count] == 2
                    @test json_report[:data][:recommandation_count] == 0
                    @test json_report[:data][:violation_count] == 0

                    local result
                    open(output_file) do oo
                        result = read(oo, String)
                    end

                    expected = r"""
                        ## Static analysis report
                        \*\*Output of \[ReLint\.jl\]\(https://github\.com/RelationalAI-oss/ReLint\.jl\).+\*\*
                        Report creation time \(UTC\): \H+
                        🎉No potential threats were found over 2 Julia files.👍
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end

    @testset "Report generation of 1 file with no errors" begin
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n  @spawn 1 + 1\nend\n")
                flush(io1)

                output_file = tempname()
                json_output = IOBuffer()
                ReLint.generate_report([file1], output_file; json_output, stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_output)))
                @test json_report[:source] == "ReLint"
                @test json_report[:data][:files_count] == 1

                @test json_report[:data][:recommandation_count] == 0
                @test json_report[:data][:violation_count] == 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end

                expected = r"""
                    ## Static analysis report
                    \*\*Output of \[ReLint\.jl\]\(https://github\.com/RelationalAI-oss/ReLint\.jl\).+\*\*
                    Report creation time \(UTC\): \H+
                    🎉No potential threats were found over 1 Julia file.👍
                    """
                result_matching = !isnothing(match(expected, result))
            end
        end
        @test result_matching
    end

    @testset "Report generation of 1 file with 1 error and github info" begin
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n  @async 1 + 1\nend\n")
                flush(io1)

                output_file = tempname()
                json_io = IOBuffer()
                ReLint.generate_report(
                    [file1],
                    output_file;
                    json_output=json_io,
                    github_repository="RelationalAI/raicode",
                    branch_name="axb-foo-bar",
                    file_prefix_to_remove="var/",
                    stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_io)))
                @test json_report[:source] == "ReLint"
                @test json_report[:data][:files_count] == 1

                @test json_report[:data][:violation_count] == 1
                @test json_report[:data][:recommandation_count] == 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end

                # Remove the first folder to address an issue of GitHub Action
                # (See MarkdownFormat for more information)
                corrected_file_name = ReLint.remove_prefix_from_filename(file1, "var/")

                expected = " - **[Line 2, column 3:]" *
                    "(https://github.com/RelationalAI/raicode/blob/axb-foo-bar/$(corrected_file_name)" *
                    "#L2)** Use `@spawn` instead of `@async`."
                if !occursin(expected, result)
                    @info "didn't match" expected result
                end
                @test occursin(expected, result)
            end
        end
    end

    @testset "Report generation of all the folder" begin
        # This is a slow test
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n  @async 1 + 1\nend\n")
                flush(io1)

                output_file = tempname()
                json_io = IOBuffer()
                ReLint.generate_report(
                    [file1], # Ignored because of analyze_all_file_found_locally
                    output_file;
                    json_output=json_io,
                    github_repository="RelationalAI/raicode",
                    branch_name="axb-foo-bar",
                    file_prefix_to_remove="var/",
                    local_files_only=true, # OVERRIDE THE PROVIDED SET OF FILES
                    stream_workflowcommand=devnull
                )

                json_report = JSON3.read(String(take!(json_io)))

                @test json_report[:source] == "ReLint"
                @test json_report[:data][:files_count] >= 2
                @test json_report[:data][:violation_count] >= 0
                @test json_report[:data][:recommandation_count] >= 0
                @test json_report[:data][:fatalviolations_count] >= 0

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end
                last_line = filter(!isempty, split(result, "\n"))[end]
                @test last_line != "No Julia file is modified or added in this PR."
            end
        end
    end

    @testset "Limiting report" begin
        # this tests create a Julia file with 100 violations, the report should mention
        # 100 violations, however only (an arbitrary) 30 are reported.
        local result_matching = false
        mktempdir() do dir
            file1 = joinpath(dir, "foo.jl")
            open(file1, "w") do io1
                write(io1, "function f()\n")
                for _ in 1:100
                    write(io1, "    @async 1 + 1\n")
                end
                write(io1, "end\n")
                flush(io1)

                output_file = tempname()
                json_output = IOBuffer()
                ReLint.generate_report([file1], output_file; json_output, stream_workflowcommand=devnull)

                json_report = JSON3.read(String(take!(json_output)))
                @test json_report[:source] == "ReLint"
                @test json_report[:data][:files_count] == 1
                @test json_report[:data][:recommandation_count] == 0
                @test json_report[:data][:violation_count] == 100

                local result
                open(output_file) do oo
                    result = read(oo, String)
                end
                all_lines = split(result, "\n")
                lines_count = length(all_lines)
                @test lines_count < 70

                @test all_lines[end-3] == "⚠️Only a subset of the reports are shown⚠️"
                @test all_lines[end-2] == """
                                          🚨**In total, 0 fatal violations, 100 \
                                          violations and 0 PR reviewer recommendations \
                                          were found over 1 Julia file**🚨"""
                @test all_lines[end] == ""
            end
        end
    end

    @testset "Diamond between files" begin
        mktempdir() do dir
            open(joinpath(dir, "leaf.jl"), "w") do io
                write(io, "function f()\n  @async 1 + 1\nend\n")
            end

            open(joinpath(dir, "bar.jl"), "w") do io
                write(io, "include(\"leaf.jl\")\n")
            end

            str = IOBuffer()
            result = ReLint.run_lint(dir; io=str, formatter=ReLint.MarkdownFormat())
            @test result.files_count == 2
            @test result.violations_count == 1
            @test result.recommendations_count == 0
        end
    end
end

@testset "Running on a directory" begin
    @testset "Non empty directory" begin
        local r
        r = LintGlobalReport()

        formatters = [ReLint.PlainFormat(), ReLint.MarkdownFormat()]
        for formatter in formatters
            mktempdir() do dir
                open(joinpath(dir, "foo.jl"), "w") do io
                    write(io, "function f()\n  @async 1 + 1\nend\n")
                    flush(io)
                    str = IOBuffer()
                    append!(r, ReLint.run_lint(dir; io=str, formatter))
                end
            end
        end
        @test (r.violations_count + r.recommendations_count) == 2
    end

    @testset "Empty directory" begin
        mktempdir() do dir
            @test ReLint.run_lint(dir) == LintGlobalReport()
        end
    end
end

@testset "File exclusion" begin
    using ReLint: extract_file_exclusions_from_precommit_file, LintFileExclusion

    filename = "precommit-config-fortesting.yaml"
    precommit_full_path = joinpath(dirname(@__FILE__), filename)
    if !isfile(precommit_full_path)
        precommit_full_path = joinpath(dirname(@__FILE__), "test", filename)
    end
    @test isfile(precommit_full_path)

    @testset "Pre-commit file" begin
        # Test the extraction of file exclusions from a pre-commit file.
        expected_reg_exs = [
            "test.jl",
            "src/version.jl",
            "packages/jet_test_utils.jl",
            "src/Test/jcompile-stats.jl",
            "src/Test/integration.jl",
            "build/.*",
            ".github/.*",
            "packages/RAI_Benchmarks/.*",
            "test_cloud/.*",
            "packages/Arroyo/bench/.*",
            "contrib/.*",
            "packages/RAI_Snoop/.*",
            "packages/Salsa/examples/.*",
            "test_spcs/.*",
            "test/.*",
            "bench/.*",
            "scripts/.*",
            "skaffold/.*",
        ]
        exclusions = extract_file_exclusions_from_precommit_file(precommit_full_path)
        reg_exs = map(l->l.regex, exclusions)
        @test all(l->l isa LintFileExclusion, exclusions)
        @test reg_exs == expected_reg_exs
    end

    @testset "Two files with errors" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "test.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2, "function g()\n      @async 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    re = extract_file_exclusions_from_precommit_file(precommit_full_path)
                    context = LintContext(ReLint.ALL_RULES, re)

                    # Run the linter on the directory
                    str = IOBuffer()
                    ReLint.run_lint(
                        dir;
                        io=str,
                        formatter=ReLint.MarkdownFormat(),
                        context,
                    )

                    result = String(take!(str))

                    # Only one of the files is linted
                    expected = r"""
                         - \*\*Line 2, column 7:\*\* Use `@spawn` instead of `@async`\. \H+
                        """

                    result_matching = !isnothing(match(expected, result))
                    result_matching || @info "DEBUG: $(result)"
                end
            end
        end
        @test result_matching
    end

    @testset "Generating report" begin
        local result_matching = false

        mktempdir() do dir
            file1_name = joinpath(dir, "test.jl")
            file2_name = joinpath(dir, "bar.jl")

            open(file1_name, "w") do io1
                open(file2_name, "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2, "function g()\n      @async 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    re = extract_file_exclusions_from_precommit_file(precommit_full_path)
                    context = LintContext(ReLint.ALL_RULES, re)

                    # Run the linter on the directory
                    output_file = tempname()
                    ReLint.generate_report(
                        [file1_name, file2_name],
                        output_file;

                        json_filename=tempname(),
                        stream_workflowcommand=devnull,
                        pre_commit_file=precommit_full_path)

                    result = open(output_file, "r") do io read(io, String) end

                    # Only one of the files is linted
                    expected = r"""
                         - \*\*Line 2, column 7:\*\* Use `@spawn` instead of `@async`\. \H+
                        """

                    result_matching = !isnothing(match(expected, result))
                    result_matching || @info "DEBUG: $(result)"
                end
            end
        end
        @test result_matching
    end
end

@testset "Locally disabling lint" begin
    @testset "lint-disable-next-line" begin
        @test !lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2
            end
            """)
        @test !lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2
            end
            """)

        @test !lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2
            end
            """)

        @test lint_has_error_test("""
            function f()
                # lint-disable-next-line
                @async 1 + 2
                @async 1 + 3
            end
            """)
        @test lint_has_error_test("""
            function f()
                @async 1 + 2
                # lint-disable-next-line
                @async 1 + 3
            end
            """)
        @test lint_has_error_test("""
            function f()
                @async 1 + 2
                # lint-disable-next-line
                @async 1 + 3
            end
            """)
    end

    @testset "Locally disabling rule 01" begin
        source = """
        function f()
            # lint-disable-next-line: Use `@spawn` instead of `@async`.
            @async 1 + 1
        end
        """
        @test !lint_has_error_test(source)
    end

    @testset "Locally disabling rule 02" begin
        source = """
        function f()
            # lint-disable-next-line: Use `@spawn` instead of `@async`.
            @async unsafe_foo(12)
        end
        """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 3, column 12: An `unsafe_` function should be called only from an `unsafe_` function.")
    end

    @testset "Locally disabling rule 03" begin
        source = """
        function f()
            # lint-disable-next-line: An `unsafe_` function
            @async unsafe_foo(42)
        end
        """
        @test lint_has_error_test(source)
        @test lint_test(source,
            "Line 3, column 5: Use `@spawn` instead of `@async`.")
    end

    @testset "Locally disabling rule 04" begin
        source = """
        function f()
            # lint-disable-next-line:Use `@spawn` instead of `@async`.
            @async 1 + 1
        end
        """
        @test !lint_has_error_test(source)
    end

    @testset "Locally disabling rule 05" begin
        source = """
        function f()
            # lint-disable-next-line:  Use `@spawn` instead of `@async`.
            @async 1 + 1
        end
        """
        @test !lint_has_error_test(source)
    end
end

@testset "Recommentation separated from violations" begin
    source = """
    function f()
        @async 1 + 1
    end
    function g()
        @lock Lock() begin
            1 + 1
        end
    end
    """
    io=IOBuffer()
    run_lint_on_text(source; io)

    result = String(take!(io))
    expected = r"""
    ---------- \H+
    Line 2, column 5: Use `@spawn` instead of `@async`\. \H+
    1 potential threat was found: 0 fatal violations, 1 violation and 0 recommendations
    ----------
    """
    @test !isnothing(match(expected, result))
end

@testset "Arithmetic LintGlobalReport" begin
    l1 = LintGlobalReport()
    l2 = LintGlobalReport(1, 2, 3)
    l3 = LintGlobalReport(10, 20, 30)
    l6 = LintGlobalReport(10, 20, 30, 40)
    l4 = LintGlobalReport(10, 20, 30, 40, ["foo.jl"], 100, [])
    l5 = LintGlobalReport(10, 20, 30, 40, ["foo2.jl"], 250)


    @test l1 == l1
    @test l1 == LintGlobalReport()
    # @test (l1 + l2) == l2
    # @test (l3 + l2) == LintGlobalReport(11, 22, 33)
    @test l4 != l5
    @test l3 != l4
    @test l3 != l5

    append!(l4, l5)
    @test l4 == LintGlobalReport(20, 40, 60, 80, ["foo.jl", "foo2.jl"], 350)
end

@testset "PreCommit format" begin
    @testset "No fatal violation" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\nend\n")
                    write(io2, "function g()\n  @async 1 + 1\nend\n")

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    result = ReLint.run_lint(dir; io=str, formatter=ReLint.PreCommitFormat())
                    ReLint.print_summary(ReLint.PreCommitFormat(), str, result)

                    result = String(take!(str))

                    expected = r"""
                        2 potential threats were found: 0 fatal violations, 2 violations and 0 recommendations
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end

    @testset "With fatal violations" begin
        local result_matching = false
        mktempdir() do dir
            open(joinpath(dir, "foo.jl"), "w") do io1
                open(joinpath(dir, "bar.jl"), "w") do io2
                    write(io1, "function f()\n  @async 1 + 1\n  @warn \"blah\"\nend\n")
                    write(io2, """
                        function g()
                            @async 1 + 1
                            @info "blah"
                        end
                        """)

                    flush(io1)
                    flush(io2)

                    str = IOBuffer()
                    result = ReLint.run_lint(dir; io=str, formatter=ReLint.PreCommitFormat())
                    ReLint.print_summary(ReLint.PreCommitFormat(), str, result)

                    result = String(take!(str))

                    expected = r"""
                        Line 3, column 5: Unsafe logging statement\. You must enclose variables and strings with `@safe\(\.\.\.\)`\. \H+/bar.jl
                        Line 3, column 3: Unsafe logging statement\. You must enclose variables and strings with `@safe\(\.\.\.\)`\. \H+/foo.jl
                        4 potential threats were found: 2 fatal violations, 2 violations and 0 recommendations
                        Note that the list above only shows fatal violations
                        """
                    result_matching = !isnothing(match(expected, result))
                end
            end
        end
        @test result_matching
    end
end

@testset "Printing LintReport" begin
    using ReLint: LintRuleReport, LintGlobalReport, print_report, PreCommitFormat, is_fatal

    result = LintGlobalReport()
    lint_report = LintRuleReport(ReLint.FATAL_VIOLATIONS["@generated"], "error")
    io = IOBuffer()
    print_report(PreCommitFormat(), io, lint_report, result)
    @test String(take!(io)) == "Line 0, column 0: error \n"
end

@testset "Formatter" begin
    source = """
           const x = Threads.nthreads()
           function f()
               return x
           end
           """

    @testset "Plain 02" begin
        io = IOBuffer()
        run_lint_on_text(source; io=io)
        result = String(take!(io))

        expected = r"""
            ---------- \H+
            Line 1, column 1: `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            1 potential threat was found: 0 fatal violations, 1 violation and 0 recommendations
            ----------
            """
        @test !isnothing(match(expected, result))
    end

    @testset "Markdown 02" begin
        io = IOBuffer()
        run_lint_on_text(source; io=io, formatter=MarkdownFormat())
        result = String(take!(io))

        expected = r"""
             - \*\*Line 1, column 1:\*\* `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            """
        @test !isnothing(match(expected, result))
    end

    @testset "Markdown 03 - with github information" begin
        formatter = MarkdownFormat("axb-example-with-lint-errors", "RelationalAI/raicode")
        io = IOBuffer()

        run_lint_on_text(
            source;
            io,
            formatter,
            directory="/src/Compiler/")
        result = String(take!(io))

        expected = r"""
             - \*\*\[Line 1, column 1:\]\(https://github\.com/RelationalAI/raicode/blob/axb-example-with-lint-errors/\H+/src/Compiler/tmp_julia_file\.jl#L1\)\*\* `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            """
        @test !isnothing(match(expected, result))
    end

    @testset "Markdown 04 - with github information" begin
        formatter = MarkdownFormat("axb-example-with-lint-errors", "RelationalAI/raicode")
        io = IOBuffer()
        run_lint_on_text(
            source;
            io,
            formatter,
            directory="src/Compiler/")
        result = String(take!(io))
        expected = r"""
             - \*\*\[Line 1, column 1:\]\(https://github\.com/RelationalAI/raicode/blob/axb-example-with-lint-errors/\H+/src/Compiler/tmp_julia_file\.jl#L1\)\*\* `Threads.nthreads\(\)` should not be used in a constant variable\. \H+
            """
        @test !isnothing(match(expected, result))
    end
end
