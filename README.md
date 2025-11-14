# ReLint.jl

ReLint is a static code analyzer for Julia. It searches for patterns in Julia source
code, such patterns aiming to indicate issues and deserve to be reported to the end-user.
ReLint.jl is inspired from [StaticLint.jl](https://github.com/julia-vscode/StaticLint.jl)
while being versatile. In particular, highlights of ReLint include:

- Lint rules can be easily added;
- ReLint.jl is runnable from a GitHub Action workflow;
- ReLint.jl offer a [pre-commit](https://pre-commit.com/) hook, useful to run it at each commit;
- ReLint.jl is lightweight and fast.

## Installing and Running ReLint

Installing and running ReLint.jl is easy. Several options are available:

  - Run in the Julia REPL `import Pkg ; Pkg.add(url="https://github.com/RelationalAI-oss/ReLint.jl")`
  - You can use our pre-commit hook.

## Basic usage

There are several ways to use ReLint.jl. Here are a few usage examples:

```Julia
ReLint.run_lint_on_text("function f() @async 1 + 2 end ");
---------- /var/folders/nz/1c4rst196ws_18tjtfl0yb980000gn/T/jl_1QHeJ2vm1U.jl
Line 1, column 14: Use `@spawn` instead of `@async`. /var/folders/nz/1c4rst196ws_18tjtfl0yb980000gn/T/jl_1QHeJ2vm1U.jl
1 potential threat is found: 1 violation and 0 recommendation
----------
```

Replacing `@async` by `@spawn` make ReLint happy:

```Julia
julia> ReLint.run_lint_on_text("function f() @spawn 1 + 2 end ");
---------- /var/folders/nz/1c4rst196ws_18tjtfl0yb980000gn/T/jl_gbkLM58LEL.jl
No potential threats were found.
----------
```

ReLint can be run on a file:

```Julia
ReLint.run_lint("/Users/alexandrebergel/Documents/RAI/raicode13/src/RAICode.jl")
```

Note that files directly and indirectly included by `RAICode.jl` are also analyzed.

When a directory is provided to `run_lint`, then ReLint will look for Julia files. E.g.,

```Julia
ReLint.run_lint("/Users/alexandrebergel/Documents/RAI/raicode13/src/")
```

The expression above outputs 1928 potential threats.

## Contributing to ReLint.jl

You may want to contribute to ReLint.jl for many reasons. Here are a few of them:

- _A rule needs to be better documented_. It is easy to do so: create a PR to this repository that improves one of the rules defined [HERE]([https://github.com/RelationalAI-oss/ReLint.jl/blob/main/src/linting/extended_checks.jl]). This `extended_checks.jl` file contains all the RAI-specific rules.
- _A new rule has to be defined_. As a system grows and evolves, new rules may have to be defined. The beginning of the file [extended_checks.jl](https://github.com/RelationalAI-oss/ReLint.jl/blob/main/src/linting/extended_checks.jl) and the section below detail this process. You can always ask `@Alexandre Bergel` on Slack for assistance. Create a new PR with the rule.

## Lint rules

Several RAI-specific and generic rules are verified on Julia source code.
A number of Julia keywords are known to be [either incompatible or dangerous when committed into raicode](https://relationalai.atlassian.net/browse/RAI-5839). \
The Lint rules available to be run on Julia source code may be found in this [FILE](https://github.com/RelationalAI-oss/ReLint.jl/blob/main/src/linting/extended_checks.jl).

Adding a new rule is easy. Only the file `src/linting/extended_checks.jl` has to be modified. You need to follow the steps:
1. Create a subtype of `LintRule`, e.g., `struct AsyncRule <: LintRule end`. Lint rules are dynamically looked up by looking at subtypes of `LintRule`.
2. Create an overload of `check` to perform the actual check.

Here is an example of a `check`:

```Julia
check(::AsyncRule, x::EXPR) = generic_check(x, "@async hole_variable", "Use `@spawn` instead of `@async`.")
```

The `generic_check` function takes as a second parameter the expression to be searched. The template string `"@async hole_variable"` means that the expression `x` will be matched against the template. The pseudo variable `hole_variable` matches everything. In case you want to match any arbitrary number of arguments, you can use `hole_variable_star` (look at the test for concrete examples).

If the expression `x` does match the template, then the expression is marked with the error message and used as an output.

In case the expression must be matched in a particular context, e.g., only with a `const` expression, then you can use a `markers`, e.g.,
```
function check(::InitializingWithFunctionRule, x::EXPR, markers::Dict{Symbol,Symbol})
    # Threads.nthreads() must not be used in a const field, but it is allowed elsewhere
    haskey(markers, :const) || return
    generic_check(x, "Threads.nthreads()", "`Threads.nthreads()` should not be used in a constant variable.")
end
```

The different markers currently supported are:

| Marker  | Value  |
|:------------- |:---------------|
| `:const`        | Const variable name  |
| `:function`         | Function definition name          |
| `:macro`         | Macro definition name          |
| `:macrocall`         | Macro call name          |
| `:filename`         | Path and name of the analyzed file          |

If you wish to run a particular rule only in a directory, you could do:

```
function check(::InitializingWithFunctionRule, x::EXPR, markers::Dict{Symbol,Symbol})
    isnothing(match(r".*/myfolder/.*", markers[:filename])) || return
    generic_check(x, "Threads.nthreads()", "`Threads.nthreads()` should not be used in a constant variable.")
end
```

This will run the `"Threads.nthreads()"` described earlier in all folders except in `myfolder`.

## Locally disabling ReLint

ReLint can be locally disabled. For now, only for a given line. E.g.,

```Julia
function f1()
    # The following line will not emit an error
    @async 1 + 2 # lint-disable-line
end

function f2()
    # lint-disable-next-line
    @async 1 + 2
    @async 1 + 2 # This line will emit an error
end
```

A specific rule can be locally disabled using `lint-disable-next-line:` taking as an argument
the message that has to be ignored. Consider this example:

```Julia
function f()
    # lint-disable-next-line: Use `@spawn` instead of `@async`.
    @async 1 + 1
end
```

The instruction `@async 1 + 1` raises the error: Use `@spawn` instead of `@async`.
Providing this error msg to the comment `lint-disable-next-line:` disabled it.

Note that it is not necessary to have the full message. The beginning of it is enough. As
such, the code above is equivalent to:

```Julia
function f()
    # lint-disable-next-line: Use `@spawn` instead
    @async 1 + 1
end
```

## Integration with GitHub Action

In addition to being run locally, as described above, ReLint can be run via GitHub
Action. When a PR is created, ReLint is run on the files modified in this PR and the
result is posted as a comment.
Only one report of ReLint is posted in a PR, and it gets updated at each commit.

## Editor Integration

ReLint provides a minimal lsp integration(see [./lsp.jl]) which should permit you
to integrate it with your editor's lsp client.

To install and precompile packages(which takes some time), navigate to
the repository root and run:
```sh
julia --project -e "using Pkg;Pkg.instantiate()"
```

Then you can start the lsp client via your editor configuration, not the
server may still take about 25 seconds to start working.

```sh
julia --startup-file=no --project=/path/to/ReLint.jl /path/to/ReLint.jl/lsp.jl
```

### Example configuration

Example configurations (from JETLS.jl)

#### Helix editor

```toml
# languages.toml

[[language]]
name = "julia"
language-servers = [ "relint" ]

[language-server.relint]
command = "/home/engon/bin/julia"
args = ["--startup-file=no", "--project=/path/to/ReLint.jl", "/path/to/ReLint.jl/lsp.jl"]
```

#### Neovim

```julia
vim.lsp.config("relint", {
    cmd = {
        "julia",
        "--startup-file=no",
        "--project=/path/to/ReLint.jl",
        "/path/to/ReLint.jl/lsp.jl",
    },
    filetypes = {"julia"},
})
vim.lsp.enable("relint")
```

## Listing all violations

Currently, ReLint limits the output of the report. In total, the number of reported
violations and recommendations does not exceed 60. This limit is set by the variable
`MAX_REPORTED_ERRORS`. You may want to increase it if you wish to have the full report
from ReLint.

## Fork

This repository was originally a fork of https://github.com/julia-vscode/StaticLint.jl but no code from StaticLint can be found. The decision to
fork this project instead of directly contributing to it was not taken lightly. First, the
julia-vscode/StaticLint.jl is not designed to be easily and modularly extended. As such
extending the original StaticLint with specific rules was not an easy or even feasible
task.

## Update process

Here is a helper for two common processes when updating Lint rules:

 - Adding a new non-fatal rule to ReLint:
   - if the rule should only appear in the PR comment, then simply add the rule to ReLint.jl. No need to update the GitHub repo client.
 - Make a rule block a PR using pre-commit:
   - Create a rule subtype of `FatalLintRule`. Merge the PR containing this rule in `main` of ReLint.jl
   - If the rule can be run with other (fatal lint) rules, then you should modify the hook `lint-fatal-checks` in the file `.pre-commit-hooks.yaml`, in ReLint.jl
   - Create a new tag of the corresponding ReLint.jl's commit and update `.pre-commit-config.yaml` with this new tag in the client.
   - _If the rule should be run in a pre-commit job_ (in parallel with other pre-commit jobs), then you need to add a hook in the file `.pre-commit-hooks.yaml` in ReLint.jl. You will then need to call this hook in the file `.pre-commit-config.yaml` in the client

