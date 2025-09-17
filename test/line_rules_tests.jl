@testset "Line rule tests" begin
    using ReLint: LintContext, TodoPrRule

    context = LintContext([TodoPrRule])
    @test lint_has_error_test("function f()\n # TODO (PR): fix this\n end"; context)
    @test lint_test("function f()\n # TODO (PR): fix this\n end",
            "Line 2, column 1: `TODO (PR)` found, use `TODO` instead.")

    @test lint_has_error_test("function f()\n # TODO PR: fix this\n end"; context)
    @test lint_test("function f()\n # TODO PR: fix this\n end",
            "Line 2, column 1: `TODO PR` found, use `TODO` instead.")

    @test !lint_has_error_test("function f()\n # TODO: fix this\n end"; context)
    @test !lint_has_error_test("function f()\n # fix this\n end"; context)

    @test lint_test("function f()\n @info \"zork\" # TODO PR: fix this\n end",
            "Line 2, column 2: Unsafe logging statement. You must enclose variables and strings with `@safe(...)`.")

    @test lint_test("function f()\n @info \"zork\" # TODO PR: fix this\n end",
            "Line 2, column 1: `TODO PR` found, use `TODO` instead.")

end