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
                    context = LintContext(ReLint.all_extended_rule_types[], re)

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
                    context = LintContext(ReLint.all_extended_rule_types[], re)

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