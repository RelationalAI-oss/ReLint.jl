#!/bin/bash

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# Run lint on a set of files, provided as arguments.
# Result are printed in the stdout, if a fatal violation is found, then exit with 1
# A rule can be specified using --rule RULE
# If no rule is provided, then run all the rules.

# Run all rules:

# pwd
# .../ReLint.jl

# ./scripts/run_locally.sh dummy.jl
# FULLNAME SCRIPT ./scripts/run_locally.sh
# RELINT PATH= ./scripts/..
# CURRENT PATH= .../ReLint.jl
# FILES_TO_RUN= /var/folders/nz/1c4rst196ws_18tjtfl0yb980000gn/T/tmp.SloaMkSs16
# About to run ReLint...
# [ Info: Running lint on 2 files
# Line 47, column 9: Unsafe logging statement. You must enclose variables and strings with
# `@safe(...)`. dummy.jl
# 6 potential threats are found: 1 fatal violation, 5 violations and 0 recommendation
# Note that the list above only show fatal violations
# ┌ Error: Fatal error discovered
# └ @ Main none:25

# Run specific rule:
# ./scripts/run_locally.sh dummy/ --rule 'VIOLATIONS["@async"]'
# ./scripts/run_locally.sh dummy/ -r 'VIOLATIONS["@async"]'

# Run multiple rules:
# ./scripts/run_locally.sh dummy/ --rules 'VIOLATIONS["@async"][,] FATAL_VIOLATIONS["unsafe-logging"]'
# ./scripts/run_locally.sh dummy/ -rs 'VIOLATIONS["@async"][,] FATAL_VIOLATIONS["unsafe-logging"]'

# Run rule group:
# ./scripts/run_locally.sh dummy/ --rule-group FATAL_VIOLATIONS
# ./scripts/run_locally.sh dummy/ -rg FATAL_VIOLATIONS

# Run multiple rule groups:
# ./scripts/run_locally.sh dummy/ --rule-groups 'VIOLATIONS[,] FATAL_VIOLATIONS'
# ./scripts/run_locally.sh dummy/ -rgs 'VIOLATIONS[,] FATAL_VIOLATIONS'

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

# PARSE ARGUMENTS
RULE=""
RULES="Rule[]"
RULE_GROUP_NAME=""
RULE_GROUP_NAMES=""
FILES_TO_RUN_FROM_COMMAND_LINE=""
while [[ $# -gt 0 ]]; do
  # echo "DEBUG: " $1
  case $1 in
    -r|--rule)
      RULE="ReLint.$2"
      shift # past argument
      shift # past value
      ;;
    -rs|--rules)
      RULES="["
      for rule in $2
      do
        rule=${rule%,} # remove trailing comma
        RULES+="ReLint.$rule, "
      done
      RULES=${RULES%, } # remove trailing comma and space
      RULES+="]"
      shift # past argument
      shift # past value
      ;;
    -rg|--rule-group)
      RULE_GROUP_NAME+="ReLint.$2, "
      shift # past argument
      shift # past value
      ;;
    -rgs|--rule-groups)
      RULE_GROUP_NAMES="["
      for rule_group in $2
      do
        rule_group=${rule_group%,} # remove trailing comma
        RULE_GROUP_NAMES+="ReLint.$rule_group, "
      done
      RULE_GROUP_NAMES=${RULE_GROUP_NAMES%, } # remove trailing comma and space
      RULE_GROUP_NAMES+="]"
      shift # past argument
      shift # past value
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      FILES_TO_RUN_FROM_COMMAND_LINE+="$1 " # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

# temporary file containing all the files on which lint has to run.
FILES_TO_RUN=$(mktemp)

# If no argument is provided, then we simply use the files staged
if [[ -z "$FILES_TO_RUN_FROM_COMMAND_LINE" ]] ; then
    echo 'No argument provided, running on staged files'
    FILES_LOCALLY_ADDED=`git status --porcelain | awk 'match($1, "A"){print $2}'`
    FILES_LOCALLY_MODIFIED=`git status --porcelain | awk 'match($1, "M"){print $2}'`
    echo ${FILES_LOCALLY_ADDED} > $FILES_TO_RUN
    echo ${FILES_LOCALLY_MODIFIED} >> $FILES_TO_RUN
else
    # If some files are provided, then we use these
    echo $FILES_TO_RUN_FROM_COMMAND_LINE >> $FILES_TO_RUN
    # echo "RUNNING LINT ON: "
    # cat "$FILES_TO_RUN"
    # echo "---"
fi

# Create the `RULES` array either from the given rule group(s) or from the given rules.
if [[ ! -z "$RULE_GROUP_NAMES" ]] ; then
  if [[ -z "$RULES" ]] ; then
    RULES="append!([collect(values(rg)) for rg in $RULE_GROUP_NAMES]...)";
  else
    RULES="append!($RULES, append!([collect(values(rg)) for rg in $RULE_GROUP_NAMES]...))";
  fi
elif [[ ! -z "$RULE_GROUP_NAME" ]] ; then
  if [[ -z "$RULES" ]] ; then
    RULES="collect(values($RULE_GROUP_NAME))";
  else
    RULES="append!($RULES, collect(values($RULE_GROUP_NAME)))";
  fi
fi

# Initializing some variables
RELINTPATH=$(dirname $0)/..

# Running StaticLint
echo "FULLNAME SCRIPT                 =" $0
# echo "FILES_TO_RUN_FROM_COMMAND_LINE  = " $FILES_TO_RUN_FROM_COMMAND_LINE
if [[ ! -z "$RULE" ]] ; then
  echo "RULE                            = $RULE"
fi
if [[ ! -z "$RULE_GROUP_NAMES" ]] ; then
  echo "RULE_GROUP_NAMES                = $RULE_GROUP_NAMES"
elif [[ ! -z "$RULE_GROUP_NAME" ]] ; then
  echo "RULE_GROUP_NAME                 = $RULE_GROUP_NAME";
elif [[ "$RULES" != "Rule[]" ]] ; then
  echo "RULES                           = $RULES"
fi
echo "RELINTPATH PATH                 =" $RELINTPATH
echo "FILES_TO_RUN                    =" $(cat $FILES_TO_RUN)

echo "About to run ReLint..."
MAX_RETRIES=5
RETRY_DELAY=5
ATTEMPT=0

# This shell script may be run several times in parallel. Pre-commit does so
# However, installation of Julia dependencies cannot be run in parallel.
# So we have a retry mechanism.
while [[ $ATTEMPT -lt $MAX_RETRIES ]]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "Attempt $ATTEMPT of $MAX_RETRIES to run ReLint..."

  julia --startup-file=no --history-file=no --project=$RELINTPATH -e "
    import Pkg
    try
      Pkg.instantiate()
    catch e
      @error \"Cannot install dependencies. Retrying...\"
      exit(2)
    end

    using ReLint: ReLint, LintContext
    using Argus: Rule
    result = ReLint.LintGlobalReport()
    all_files_tmp=split(open(io->read(io, String), \"$FILES_TO_RUN\", \"r\"))
    all_files=map(string, all_files_tmp)
    all_files=filter(f->isfile(f) || isdir(f), all_files)
    all_files=filter(f->endswith(f, \".jl\") || isdir(f), all_files)

    @info \"Running lint on \$(length(all_files)) files\"

    formatter = ReLint.PreCommitFormat()
    rules = $RULES
    context = isempty(rules) ? LintContext($RULE) : LintContext(rules)
    rule_names = [r.name for r in context.rules]
    @info \"Running rules:\" rule_names

    for f in all_files
      ReLint.run_lint(f; result, formatter, context)
    end

    if result.fatal_violations_count > 0
      ReLint.print_summary(formatter, stdout, result)
      @error \"Fatal error discovered\"
      exit(1)
    else
      ReLint.print_summary(formatter, stdout, result)
      exit(2)
    end
    exit(0)
  "

  # Capture the exit status of the Julia command
  EXIT_STATUS=$?

  if [[ $EXIT_STATUS -eq 0 ]]; then
    echo "ReLint completed successfully."
    exit 0
  elif [[ $EXIT_STATUS -eq 1 ]]; then
    echo "ReLint found fatal violations"
    exit 1
  elif [[ $EXIT_STATUS -eq 2 ]]; then
    echo "ReLint found non-fatal violations"
    exit 0
  else
    echo "ReLint failed with exit code $EXIT_STATUS. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
  fi
done

if [[ $ATTEMPT -eq $MAX_RETRIES ]]; then
  echo "ReLint failed after $MAX_RETRIES attempts."
  exit $EXIT_STATUS
fi
