#!/usr/bin/env julia

using Test
using ReLint

# Test 1: ConstGlobalMissingTypeRule
println("Testing ConstGlobalMissingTypeRule...")
code1 = "global x = 42"
io = IOBuffer()
ReLint.run_lint_on_text(code1; io)
output1 = String(take!(io))
println("Output for 'global x = 42':")
println(output1)
println()

# Test 2: With type annotation
code2 = "global x::Int = 42"
io2 = IOBuffer()
ReLint.run_lint_on_text(code2; io=io2)
output2 = String(take!(io2))
println("Output for 'global x::Int = 42':")
println(output2)
println()

# Test 3: Rule registration
println("Checking rule registration...")
all_rules = ReLint.all_rules()
rule_names = string.(nameof.(all_rules))
println("Found $(length(rule_names)) rules")
println("New rules present:")
for name in ["ConstGlobalMissingTypeRule", "IsNothingPerformanceRule", "MissingAutoHashEqualsRule",
             "NotFullyParameterizedConstructorRule", "ClosureCaptureByValueRule"]
    println("  $name: ", name in rule_names ? "✓" : "✗")
end
