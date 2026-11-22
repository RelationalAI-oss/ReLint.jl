#!/bin/bash

# This script is used to run ReLint.jl on a GitHub repository.
# It is designed to be run in a GitHub Actions workflow.

# This bash script expects the following arguments:
# 1. The path of the GitHub repository clone to analyze
# 2. The branch name to consider. Could be master, main, for any branch name.
# 3. Prefix to be removed for file name. In the future, we could simply move into the
# raicode folder and use --project=../ReLint.jl.
# 4. A boolean value indicating if the Lint analysis should be performed on the whole
# codebase or simply on the provided files given in files_to_run_lint.txt
#
# The file files_to_run_lint.txt that contains files on which ReLint.jl has to be run
# Output of this script is a file result.txt that contains the generated report of ReLint
# This script is invoked by the run_lint.yml GitHub Action workflow.

GITHUB_REPOSITORY=$1
BRANCH_NAME=$2
FILE_PREFIX_TO_REMOVE=$3
SHOULD_ANALYZE_WHOLE_CODEBASE=$4
OBSERVE_BEARER=$5
# The pre_commit file is used to identify the files in raicode that must be excluded from
# Lint analyze.
PRE_COMMIT_FILE=$6

cd ReLint.jl
julia --proj -e "import Pkg ; Pkg.Registry.update() ; Pkg.instantiate()"
cd ..

# We make sure the file exist. It may not if we are on master.
touch files_to_run_lint.txt

# RUNNING THE CHECK
julia --project=ReLint.jl -e "
  using ReLint
  ReLint.generate_report(
    readlines(\"files_to_run_lint.txt\"),
    \"result.txt\";
    github_repository=\"$GITHUB_REPOSITORY\",
    branch_name=\"$BRANCH_NAME\",
    file_prefix_to_remove=\"$FILE_PREFIX_TO_REMOVE\",
    json_filename=\"json_report.json\",
    analyze_all_file_found_locally=$SHOULD_ANALYZE_WHOLE_CODEBASE,
    pre_commit_file=\"$PRE_COMMIT_FILE\",
    )
"

# Send Json report to Observe
echo "Sending ReLint report to Observe..."
curl --retry 5 --retry-max-time 60 --retry-all-errors \
  https://171608476159.collect.observeinc.com/v1/http \
 -H "Authorization: Bearer $OBSERVE_BEARER" \
 -H "Content-type: application/json" \
 -d @json_report.json

if [ $? -ne 0 ]; then
  echo "Error: curl failed to send the ReLint report to Observe."
  exit 0
fi
echo "ReLint report successfully sent to Observe."


# SHOW THE RESULTS ON GITHUB ACTION. USEFUL FOR DEBUGGING
# echo "HERE ARE THE RESULTS:"
# cat result.txt
# echo "END OF RESULTS"
