# ReLint.jl

Lightweight linter for Julia programs. It provides a set of linting
rules grouped by severity, GitHub Action integration and some
pre-commit hooks.

## Overview

ReLint is a fast and lightweight linter for Julia built on top of
[Argus.jl](https://github.com/iuliadmtru/Argus.jl). It provides a set
of pre-defined linting rules grouped in three categories:
recommendations, violations and fatal violations.

```julia
julia> using ReLint

julia> keys(ReLint.RECOMMENDATIONS)
KeySet for a Dict{String, Argus.Rule} with 16 entries. Keys:
  "string concatenation"
  "@cfunction"
  "@inbounds"
  "finalizer"
  "mutating ENV"
  "@threads"
  "isnothing"
  "sleep"
  "unlock"
  "yield"
  "@sync"
  "interpolation in `@warnv_safe_to_log`"
  "closure capture by reference"
  "return type annotation"
  "splatting"
  "ccall"

julia> keys(ReLint.VIOLATIONS)
KeySet for a Dict{String, Argus.Rule} with 27 entries. Keys:
  "RelPath"
  "@async"
  "equal"
  "unreachable branch"
  "RelPath relpath_from_signature"
  "RelPath drop_first"
  "uv"
  "unsafe_ function"
  "untyped array comprehension"
  "array with no specific type"
  "no import RAICode"
  "not fully parametrised constructor"
  "in"
  "no import"
  "non-const untyped global"
  "Task"
  "error"
  "haskey"
  "static threads"
  "RelPath split_path"
  "TODO"
  "string interpolation"
  "initializing with `nthreads`"
  "initializing with `is_local_deployment`"
  "bare using"
  "ErrorException"
  "remove_page"

julia> keys(ReLint.FATAL_VIOLATIONS)
KeySet for a Dict{String, Argus.Rule} with 7 entries. Keys:
  "unsafe-logging"
  "noinline with non-literal/identifier args"
  "show"
  "TODO PR"
  "return in anonymous function"
  "@generated"
  "unsafe-assert"
```

The rules can be run on a file or directory using `run_lint`:

```julia
julia> f = tempname() * ".jl";

julia> write(f, """
       function f(x)::Int
           y = unsafe_f(x)
           return y
       end
       """);

julia> ReLint.run_lint(f)
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_HGJU58HAr2.jl
Line 2, column 9: An `unsafe_` function should be called only from an `unsafe_` function. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_HGJU58HAr2.jl
Line 1, column 1: Avoid return type annotations `function foo()::Type`. Return type annotations can hurt performance by forcing type conversions. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_HGJU58HAr2.jl
ReLint.LintGlobalReport(1, 1, 1, 0, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_HGJU58HAr2.jl"], 2, ReLint.LintRuleReport[], "master")
```

The `scripts/` directory contains a shell script that can be used to
run the rules locally:

```julia
➜  touch temp.jl
➜  echo "@generated function f(x)::Int
    y = unsafe_f(x)
    return y
end" >> temp.jl
➜  ./scripts/run_locally.sh temp.jl
FULLNAME SCRIPT                 = ./scripts/run_locally.sh
RELINTPATH PATH                 = ./scripts/..
FILES_TO_RUN                    = temp.jl
About to run ReLint...
Attempt 1 of 5 to run ReLint...
[ Info: Running lint on 1 files
┌ Info: Running rules:
│   rule_names =
│    50-element Vector{String}:
│     "string concatenation"
│     "@cfunction"
│     "@inbounds"
│     "finalizer"
│     "mutating ENV"
│     "@threads"
│     "isnothing"
│     "sleep"
│     "unlock"
│     "yield"
│     ⋮
│     "ErrorException"
│     "remove_page"
│     "unsafe-logging"
│     "noinline with non-literal/identifier args"
│     "show"
│     "TODO PR"
│     "return in anonymous function"
│     "@generated"
└     "unsafe-assert"
Line 1, column 1: `@generated` should be used with extreme caution. temp.jl
3 potential threats were found: 1 fatal violation, 1 violation and 1 recommendation
Note that the list above only shows fatal violations
┌ Error: Fatal error discovered
└ @ Main none:32
ReLint found fatal violations
➜  ./scripts/run_locally.sh temp.jl --rule 'VIOLATIONS["unsafe_ function"]'
FULLNAME SCRIPT                 = ./scripts/run_locally.sh
RULE                            = ReLint.VIOLATIONS["unsafe_ function"]
RELINTPATH PATH                 = ./scripts/..
FILES_TO_RUN                    = temp.jl
About to run ReLint...
Attempt 1 of 5 to run ReLint...
[ Info: Running lint on 1 files
┌ Info: Running rules:
│   rule_names =
│    1-element Vector{String}:
└     "unsafe_ function"
1 potential threat was found: 0 fatal violations, 1 violation and 0 recommendations
Note that the list above only shows fatal violations
ReLint found non-fatal violations
➜  ./scripts/run_locally.sh temp.jl --rule-group RECOMMENDATIONS
FULLNAME SCRIPT                 = ./scripts/run_locally.sh
RULE_GROUP_NAME                 = ReLint.RECOMMENDATIONS,
RELINTPATH PATH                 = ./scripts/..
FILES_TO_RUN                    = temp.jl
About to run ReLint...
Attempt 1 of 5 to run ReLint...
[ Info: Running lint on 1 files
┌ Info: Running rules:
│   rule_names =
│    16-element Vector{String}:
│     "string concatenation"
│     "@cfunction"
│     "@inbounds"
│     "finalizer"
│     "mutating ENV"
│     "@threads"
│     "isnothing"
│     "sleep"
│     "unlock"
│     "yield"
│     "@sync"
│     "interpolation in `@warnv_safe_to_log`"
│     "closure capture by reference"
│     "return type annotation"
│     "splatting"
└     "ccall"
1 potential threat was found: 0 fatal violations, 0 violations and 1 recommendation
Note that the list above only shows fatal violations
ReLint found non-fatal violations
```

Three pre-commit hooks are provided in `.pre-commit-hooks.yaml`. You
can modify or extend them by writing your own hooks file.
  
## Getting Started

### Installation

ReLint is not yet registered in the Julia package system. It can be installed with `Pkg`:

```julia
using Pkg
Pkg.add("https://github.com/RelationalAI-oss/ReLint.jl")
```

### Basic Usage

TODO: README updated until here...

There are several ways to use ReLint.jl. Here are a few usage examples:

```Julia
ReLint.run_lint_on_text("function f() @async 1 + 2 end ");
---------- /var/folders/nz/1c4rst196ws_18tjtfl0yb980000gn/T/jl_1QHeJ2vm1U.jl
Line 1, column 14: Use `@spawn` instead of `@async`. /var/folders/nz/1c4rst196ws_18tjtfl0yb980000gn/T/jl_1QHeJ2vm1U.jl
1 potential threat is found: 1 violation and 0 recommendation

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
```fish
julia --project -e "using Pkg;Pkg.instantiate()"
```

Then you can start the lsp client via your editor configuration, not the
server may still take about 25 seconds to start working.

```fish
julia --startup-file=no --project=/path/to/ReLint.jl /path/to/ReLint.jl/lsp.jl
```

To reduce startup time and use with editors, you may also compile lsp.jl with
`JuliaC.jl` by running one of these commands at the repository root
and use the output instead.

```fish
# Using juliac app
juliac --project=. --output-exe lsp --bundle build lsp.jl
# OR with the module module
julia --project -e 'using Pkg;Pkg.add("JuliaC");using JuliaC; JuliaC.main(ARGS)' -- \
    --output-exe lsp --bundle build lsp.jl
```

This should create a relocatable `build` folder at the repository root,
with the executable being at `build/bin/lsp`.

### Editor configuration

#### Helix 

```toml
# languages.toml

[[language]]
name = "julia"
language-servers = [ "relint" ]

[language-server.relint]
command = "/path/to/Relint.jl/build/bin/lsp"
```

#### Neovim

```julia
vim.lsp.config("relint", {
    cmd = {"/path/to/Relint.jl/build/bin/lsp",},
    filetypes = {"julia"},
})
vim.lsp.enable("relint")
```

#### emacs 30 .emacs configuration (julia-mode + eglot)

emacs 30 includes eglot which provides basic lsp server functionality.

The following configuration should work with both
[julia-repl](https://github.com/tpapp/julia-repl) and
[julia-snail](https://github.com/gcv/julia-snail) since they both rely on
julia-mode:

```emacs
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(julia-mode . ("/path/to/ReLint.jl/build/bin/lsp"))))

(add-hook 'julia-mode-hook 'eglot-ensure)
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
