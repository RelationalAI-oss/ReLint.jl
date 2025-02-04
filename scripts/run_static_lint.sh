#!/bin/bash

# This bash script expects two things:
# - RelationalAI/StaticLint.jl to be cloned
# - The file files_to_run_lint.txt that contains files on which StaticLint.jl has to be run
# Output of this script is a file result.txt that contains the generated report of StaticLint
# This script is invoked by the run_lint.yml GitHub Action workflow.

GITHUB_REPOSITORY=$1
BRANCH_NAME=$2
FILE_PREFIX_TO_REMOVE=$3

cd StaticLint.jl
julia --proj -e "import Pkg ; Pkg.Registry.update() ; Pkg.instantiate()"
cd ..

# RUNNING THE CHECK
julia --project=StaticLint.jl -e "
  using StaticLint
  StaticLint.generate_report(
    readlines(\"files_to_run_lint.txt\"),
    \"result.txt\";
    github_repository=\"$GITHUB_REPOSITORY\",
    branch_name=\"$BRANCH_NAME\",
    file_prefix_to_remove=\"$FILE_PREFIX_TO_REMOVE\",
    )
"

# SHOW THE RESULTS ON GITHUB ACTION. USEFUL FOR DEBUGGING
# echo "HERE ARE THE RESULTS:"
# cat result.txt
# echo "END OF RESULTS"
