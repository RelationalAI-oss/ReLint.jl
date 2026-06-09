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

The main entry point of `ReLint` is `run_lint`, which runs all
available linting rules on a given file or directory.

```julia
julia> using ReLint

julia> f = tempname() * ".jl";

julia> write(f, """
       @generated function f(x)::Any
           y = unsafe_f(x)
           return y
       end
       """);

julia> ReLint.run_lint(f)
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
Line 1, column 1: `@generated` should be used with extreme caution. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
Line 2, column 9: An `unsafe_` function should be called only from an `unsafe_` function. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
Line 1, column 12: Avoid return type annotations `function foo()::Type`. Return type annotations can hurt performance by forcing type conversions. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
ReLint.LintGlobalReport(1, 1, 1, 1, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl"], 3, ReLint.LintRuleReport[], "master")
```

A specific set of rules can be given through `LintContext`:

```julia
julia> ReLint.run_lint(f; context=ReLint.LintContext([values(ReLint.RECOMMENDATIONS)...]))
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
Line 1, column 12: Avoid return type annotations `function foo()::Type`. Return type annotations can hurt performance by forcing type conversions. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
ReLint.LintGlobalReport(1, 0, 1, 0, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl"], 1, ReLint.LintRuleReport[], "master")
```

ReLint's rules are constructs that come from
[Argus](https://github.com/iuliadmtru/Argus.jl). For more information
on syntax patterns, rules and rule matching see the [Argus
documentation](https://github.com/iuliadmtru/Argus.jl?tab=readme-ov-file#argusjl).

The available set of rules can be extended either by adding rules to
the existing rule groups or by defining new groups:

```julia
julia> using Argus: Rule, @pattern

julia> ReLint.RECOMMENDATIONS["my rule"] = Rule(
           "my rule",
           "This is my recommendation rule -- don't use `::Any`",
           @pattern {_}::Any
       )
my rule:
This is my recommendation rule -- don't use `::Any`

Pattern:
[::-i]
  _:::expr                               :: ~var
  Any                                    :: Identifier

Template:
<no template>

Hooks:
<no hooks>


julia> ReLint.run_lint(f; context=ReLint.LintContext([values(ReLint.RECOMMENDATIONS)...]))
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
Line 1, column 12: Avoid return type annotations `function foo()::Type`. Return type annotations can hurt performance by forcing type conversions. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
Line 1, column 21: This is my recommendation rule -- don't use `::Any` /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
ReLint.LintGlobalReport(1, 0, 2, 0, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl"], 2, ReLint.LintRuleReport[], "master")

julia> MY_GROUP = RuleGroup("my group")
RuleGroup("my group")

julia> MY_GROUP["my rule"] = Rule(
           "my rule",
           "This is my recommendation rule -- don't use `::Any`",
           @pattern {_}::Any
       );

julia> ReLint.run_lint(f; context=ReLint.LintContext([values(MY_GROUP)...]))
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
Line 1, column 21: This is my recommendation rule -- don't use `::Any` /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl
ReLint.LintGlobalReport(1, 0, 1, 0, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_nIHKJ0JiPW.jl"], 1, ReLint.LintRuleReport[], "master")
```

> [!NOTE] 
> Currently, ReLint limits the output of the report to 60 errors. This
> limit can be increased by setting `MAX_REPORTED_ERRORS` to the
> desired amount.

### Defining New Rules

To learn how to define new rules, see the [Argus documentation on
rules](https://github.com/iuliadmtru/Argus.jl?tab=readme-ov-file#rules)

Once you have a rule, a set of rules or a rule group, you can register
them to ReLint:

```julia
help?> ReLint.register_rule!
  register_rule!(rule::Rule)

  Register a rule to ReLint.

help?> ReLint.register_rules!
  register_rules!(rules::Vector{Rule})

  Register a set of rules to ReLint.

help?> ReLint.register_rule_group!
  register_rule_group!(rule_group::RuleGroup)

  Register a rule group to ReLint.

help?> ReLint.register_rule_groups!
  register_rule_groups!(rule_groups::Vector{RuleGroup})

  Register a set of rule groups to ReLint.

julia> ReLint.register_rule_group!(MY_GROUP)

julia> ReLint.run_lint(f)
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_GRSpoXwPWl.jl
Line 1, column 1: `@generated` should be used with extreme caution. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_GRSpoXwPWl.jl
Line 2, column 9: An `unsafe_` function should be called only from an `unsafe_` function. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_GRSpoXwPWl.jl
Line 1, column 12: Avoid return type annotations `function foo()::Type`. Return type annotations can hurt performance by forcing type conversions. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_GRSpoXwPWl.jl
Line 1, column 21: This is my recommendation rule -- don't use `::Any` /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_GRSpoXwPWl.jl
ReLint.LintGlobalReport(1, 1, 1, 1, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_GRSpoXwPWl.jl"], 4, ReLint.LintRuleReport[], "master")
```

### Disabling Rules

Rules can be disabled using `#lint-disable-next-line[:
<rule-name|rule-message>]` comments.

```julia
julia> write(f, """
       # lint-disable-next-line
       @generated function f(x)::Any
           y = unsafe_f(x)
           return y
       end
       """);

julia> ReLint.run_lint(f)
ReLint.LintGlobalReport(1, 0, 0, 0, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl"], 0, ReLint.LintRuleReport[], "master")

julia> write(f, """
       # lint-disable-next-line: my rule
       @generated function f(x)::Any
           y = unsafe_f(x)
           return y
       end
       """);

julia> ReLint.run_lint(f)
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
Line 2, column 1: `@generated` should be used with extreme caution. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
Line 3, column 9: An `unsafe_` function should be called only from an `unsafe_` function. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
Line 2, column 12: Avoid return type annotations `function foo()::Type`. Return type annotations can hurt performance by forcing type conversions. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
ReLint.LintGlobalReport(1, 1, 1, 1, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl"], 3, ReLint.LintRuleReport[], "master")

julia> write(f, """
       # lint-disable-next-line: `@generated` should be used with extreme caution
       @generated function f(x)::Any
           y = unsafe_f(x)
           return y
       end
       """);

julia> ReLint.run_lint(f)
---------- /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
Line 3, column 9: An `unsafe_` function should be called only from an `unsafe_` function. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
Line 2, column 12: Avoid return type annotations `function foo()::Type`. Return type annotations can hurt performance by forcing type conversions. /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
Line 2, column 21: This is my recommendation rule -- don't use `::Any` /var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl
ReLint.LintGlobalReport(1, 1, 1, 0, ["/var/folders/4p/xtm72jnx4654xybjwm1mpd0h0000gn/T/jl_fwJaTGzSJe.jl"], 3, ReLint.LintRuleReport[], "master")
```

The rule disabling mechanism can be changed. See the [Argus
documentation](https://github.com/iuliadmtru/Argus.jl?tab=readme-ov-file#disabling-rules)
for more details.

## Linting Locally

The `scripts/` directory contains a shell script for running ReLint
locally.

```
➜  ./scripts/run_locally.sh -h
./run_locally.sh <file-name|directory-name> [options]

Available options:
-r|--rule          <rule>                           - run a single rule
-rs|--rules        <rule1[(, )? rule]*>             - run a set of rules
-rg|--rule-group   <rule-group-name>                - run a rule group
-rgs|--rule-groups <rule-group1[(, )? rule-group]*> - run a set of rule groups
-h|--help                                           - show this message
```

## Integration With GitHub Actions and Workflows

ReLint can be run via GitHub Actions. When a PR is created, ReLint is
run on the files modified in the PR and the result is posted as a
comment. Only one report is posted per PR, which gets updated at each
commit.

ReLint provides three pre-commit hooks in `.pre-commit-hooks.yaml`.

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

## Contributing

For bug reports and improvement suggestions, feel free to file an
issue.

### Adding New Rules or Modifying Existing Rules

If you wish to improve or extend the default set of rules, you can do
so by modifying the relevant file(s) in the `rules/` directory. Please
read the [relevant ReLint](#defining-new-rules) and
[Argus](https://github.com/iuliadmtru/Argus.jl?tab=readme-ov-file#rules)
documentation before.

### Improving the Interface

All interface-related code can be found in `src/interface.jl`.
