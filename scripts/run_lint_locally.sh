#!/bin/bash

# temporary file containing all the files on which lint has to run.
FILES_TO_RUN=$(mktemp)

# If no argument is provided, then we simply use the files staged
if [[ $# -eq 0 ]] ; then
    echo 'No argument provided, running on staged files'
    FILES_LOCALLY_ADDED=`git status --porcelain | awk 'match($1, "A"){print $2}'`
    FILES_LOCALLY_MODIFIED=`git status --porcelain | awk 'match($1, "M"){print $2}'`
    echo ${FILES_LOCALLY_ADDED} > $FILES_TO_RUN
    echo ${FILES_LOCALLY_MODIFIED} >> $FILES_TO_RUN
else
    # If some files are provided, then we use these
    echo $@ >> $FILES_TO_RUN
    # echo "RUNNING LINT ON: "
    # cat "$FILES_TO_RUN"
    # echo "---"
fi

# Running StaticLint
echo "FULLNAME SCRIPT" $0
STATICLINTPATH=$(dirname $0)/..
echo "STATICLINT PATH=" $STATICLINTPATH
RAICODE_PATH=$PWD
echo "CURRENT PATH=" $RAICODE_PATH
echo "FILES_TO_RUN=" $FILES_TO_RUN

echo "About to run StaticLint.jl..."
julia --project=$STATICLINTPATH -e "
  import Pkg
  Pkg.instantiate()

  using StaticLint
  result = StaticLint.LintResult()
  all_files_tmp=split(open(io->read(io, String), \"$FILES_TO_RUN\", \"r\"))
  # convert substring into string
  all_files=map(string, all_files_tmp)
  # filter to existing Julia files only
  all_files=filter(isfile, all_files)
  all_files=filter(f->endswith(f, \".jl\"), all_files)

  @info \"Running lint on \$(length(all_files)) files\"

  formatter = StaticLint.PreCommitFormat()
  # Run lint on all files
  for f in all_files
    StaticLint.run_lint(f; result, formatter)
  end

  # Return an error if there is an unsafe log
  if result.fatalviolations_count > 0
    StaticLint.print_summary(formatter, stdout, result)
    @error \"Fatal error discovered\"
    exit(1)
  end
  exit(0)
"
