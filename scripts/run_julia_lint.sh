#!/bin/bash

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
# Run lint on a set of files, provided as arguments.
# Result are printed in the stdout, if a fatal violation is found, then exit with 1
# A rule can be specified using --rule NAME_OF_A_RULE
# If no rule is provided, then run all the rules.

# EXAMPLE1:

# pwd
# /Users/alexandrebergel/Documents/RAI/ReLint.jl

# ./scripts/run_lint_locally.sh /Users/alexandrebergel/Documents/RAI/raicode21/src/*.jl
# FULLNAME SCRIPT ./scripts/run_lint_locally.sh
# RELINT PATH= ./scripts/..
# CURRENT PATH= /Users/alexandrebergel/Documents/RAI/ReLint.jl
# FILES_TO_RUN= /var/folders/nz/1c4rst196ws_18tjtfl0yb980000gn/T/tmp.SloaMkSs16
# About to run ReLint.jl...
# [ Info: Running lint on 2 files
# Line 47, column 9: Unsafe logging statement. You must enclose variables and strings with `@safe(...)`. /Users/alexandrebergel/Documents/RAI/raicode21/src/version.jl
# 6 potential threats are found: 1 fatal violation, 5 violations and 0 recommendation
# Note that the list above only show fatal violations
# ┌ Error: Fatal error discovered
# └ @ Main none:25

# EXAMPLE2:
# ./scripts/run_julia_lint.sh /Users/alexandrebergel/Documents/RAI/raicode4/ --rule LogStatementsMustBeSafe

# EXAMPLE3:
# ./scripts/run_julia_lint.sh /Users/alexandrebergel/Documents/RAI/raicode4/

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

# PARSE ARGUMENTS
RULE=""
FILES_TO_RUN_FROM_COMMAND_LINE=""
while [[ $# -gt 0 ]]; do
  # echo "DEBUG: " $1
  case $1 in
    -r|--rule)
      RULE="$2"
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

# If no rule was set, when we have the empty rule
# Else, we set it for Julia
if [[ ! -z "$RULE" ]] ; then
  RULE="[\"$RULE\"]"
fi

# Initializing some variables
RELINTPATH=$(dirname $0)/..

# Running StaticLint
echo "FULLNAME SCRIPT                 =" $0
# echo "FILES_TO_RUN_FROM_COMMAND_LINE  = " $FILES_TO_RUN_FROM_COMMAND_LINE
echo "RULE                            = $RULE"
echo "RELINTPATH PATH                 =" $RELINTPATH
echo "FILES_TO_RUN                    =" $FILES_TO_RUN

echo "About to run ReLint.jl..."
julia --project=$RELINTPATH -e "
  import Pkg
  Pkg.instantiate()

  using ReLint: ReLint, LintContext
  result = ReLint.LintResult()
  all_files_tmp=split(open(io->read(io, String), \"$FILES_TO_RUN\", \"r\"))
  # convert substring into string
  all_files=map(string, all_files_tmp)
  # filter to existing Julia files only
  all_files=filter(f->isfile(f) || isdir(f), all_files)
  all_files=filter(f->endswith(f, \".jl\") || isdir(f), all_files)

  @info \"Running lint on \$(length(all_files)) files\"

  formatter = ReLint.PreCommitFormat()
  # context = LintContext([\"LogStatementsMustBeSafe\"])
  context = LintContext($RULE)
  @info \"context\" context

  # Run lint on all files
  for f in all_files
    ReLint.run_lint(f; result, formatter, context)
  end

  # Return an error if there is an unsafe log
  if result.fatalviolations_count > 0
    ReLint.print_summary(formatter, stdout, result)
    @error \"Fatal error discovered\"
    exit(1)
  end
  exit(0)
"
