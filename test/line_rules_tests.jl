@testset "Line rule tests" begin
    @testset "TodoPrRule tests" begin
        using ReLint: TodoJiraIssueRule, TodoPrRule, SplattingRule
        using ReLint: is_recommendation, is_violation, is_fatal
        @test !is_recommendation(TodoPrRule())
        @test !is_recommendation(TodoJiraIssueRule())
        @test is_violation(TodoJiraIssueRule())
        @test is_fatal(TodoPrRule())
        @test !is_fatal(TodoJiraIssueRule())
        @test is_recommendation(SplattingRule())
    end

    @testset "TodoPrRule tests" begin
        using ReLint: LintContext, TodoPrRule

        context = LintContext([TodoPrRule])
        @test lint_has_error_test("function f()\n # TODO (PR): fix this\n end"; context)
        @test lint_test("function f()\n # TODO (PR): fix this\n end",
                "Line 2, column 1: `TODO (PR)` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue.")

        @test lint_has_error_test("function f()\n # TODO PR: fix this\n end"; context)
        @test lint_test("function f()\n # TODO PR: fix this\n end",
                "Line 2, column 1: `TODO PR` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue.")

        @test !lint_has_error_test("function f()\n # TODO: fix this\n end"; context)
        @test !lint_has_error_test("function f()\n # fix this\n end"; context)

        @test lint_test("function f()\n @info \"zork\" # TODO PR: fix this\n end",
                "Line 2, column 2: Unsafe logging statement. You must enclose variables and strings with `@safe(...)`.")

        @test lint_test("function f()\n @info \"zork\" # TODO PR: fix this\n end",
                "Line 2, column 1: `TODO PR` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue.")

        @test !lint_has_error_test("function f()\n # TODO probably okay\n end"; context)
    end

     @testset "TodoPrRule tests" begin
        using ReLint: LintContext, TodoJiraIssueRule

        context = LintContext([TodoJiraIssueRule])
        @test lint_has_error_test("function f()\n # TODO (PR): fix this\n end"; context)
        @test lint_test("function f()\n # TODO (PR): fix this\n end",
                "Line 2, column 1: `TODO` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue.")

        @test lint_has_error_test("function f()\n # TODO: fix this\n end"; context)
        @test lint_test("function f()\n # TODO: fix this\n end",
                "Line 2, column 1: `TODO` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue.")

        @test !lint_has_error_test("function f()\n # TODO (RAI-12314): fix this\n end"; context)
        @test !lint_has_error_test("function f()\n # fix this\n end"; context)

        @test lint_test("function f()\n @info \"zork\" # TODO: fix this\n end",
                "Line 2, column 2: Unsafe logging statement. You must enclose variables and strings with `@safe(...)`.")

        @test lint_test("function f()\n @info \"zork\" # TODO fix this\n end",
                "Line 2, column 1: `TODO` found, use `TODO (RAI-XXXXX)` instead to refer to a Jira issue.")

        @test !lint_has_error_test("function f()\n # TODO (RAI-121) probably okay\n end")
    end
end