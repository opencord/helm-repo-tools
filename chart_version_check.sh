#!/usr/bin/env bash

# Copyright 2018-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# chart_version_check.sh
# checks that changes to a chart include a change to the chart version

set -u

echo "# chart_version_check.sh, using git: $(git --version) #"

# Collect success/failure, and list/types of failures
fail_version=0
failed_charts=""

# when not running under Jenkins, use current dir as workspace
WORKSPACE=${WORKSPACE:-.}

# branch to compare against, defaults to master
COMPARISON_BRANCH="${COMPARISON_BRANCH:-opencord/master}"
echo "# Comparing with branch: $COMPARISON_BRANCH"

# Create list of changed files compared to branch
changed_files=$(git diff --name-only "${COMPARISON_BRANCH}")

# Create list of untracked by git files
untracked_files=$(git ls-files -o --exclude-standard)

# Print lists of files that are changed/untracked
if [ -z "$changed_files" ] && [ -z "$untracked_files" ]
then
  echo "# chart_version_check.sh - No changes, Success! #"
  exit 0
else
  if [ -n "$changed_files" ]
  then
    echo "Changed files compared with $COMPARISON_BRANCH:"
    # Search and replace per SC2001 doesn't recognize ^ (beginning of line)
    # shellcheck disable=SC2001
    echo "${changed_files}" | sed 's/^/  /'
  fi
  if [ -n "$untracked_files" ]
  then
    echo "Untracked files:"
    # shellcheck disable=SC2001
    echo "${untracked_files}" | sed 's/^/  /'
  fi
fi

# combine lists
if [ -n "$changed_files" ]
then
  if [ -n "$untracked_files" ]
  then
    changed_files+=$'\n'
    changed_files+="${untracked_files}"
  fi
else
  changed_files="${untracked_files}"
fi

# For all the charts, fail on changes within a chart without a version change
# loop on result of 'find -name Chart.yaml'
while IFS= read -r -d '' chart
do
  chartdir=$(dirname "${chart#${WORKSPACE}/}")
  chart_changed_files=""
  version_updated=0

  # create a list of files that were changed in the chart
  for file in $changed_files; do
    if [[ $file =~ ^$chartdir/ ]]
    then
      chart_changed_files+=$'\n'
      chart_changed_files+="  ${file}"
    fi
  done

  # See if chart version changed using 'git diff', and is SemVer
  chart_yaml_diff=$(git diff -p "$COMPARISON_BRANCH" -- "${chartdir}/Chart.yaml")

  if [ -n "$chart_yaml_diff" ]
  then
    echo "Changes to Chart.yaml in '$chartdir'"
    old_version_string=$(echo "$chart_yaml_diff" | awk '/^\-version:/ { print $2 }')
    new_version_string=$(echo "$chart_yaml_diff" | awk '/^\+version:/ { print $2 }')

    if [ -n "$new_version_string" ]
    then
      version_updated=1
      echo " Old version string:${old_version_string//-version:/}"
      echo " New version string:${new_version_string//+version:/}"
    fi
  fi

  # if there are any changed files
  if [ -n "$chart_changed_files" ]
  then
    # and version updated, print changed files
    if [ $version_updated -eq 1 ]
    then
      echo " Files changed:${chart_changed_files}"
    else
      # otherwise fail this chart
      echo "Changes to chart but no version update in '$chartdir':${chart_changed_files}"
      fail_version=1
      failed_charts+=$'\n'
      failed_charts+="  $chartdir"
    fi
  fi

done < <(find "${WORKSPACE}" -name Chart.yaml -print0)

if [[ $fail_version != 0 ]]; then
  echo "# chart_version_check.sh Failure! #"
  echo "Charts that need to be fixed:$failed_charts"
  exit 1
fi

echo "# chart_version_check.sh Success! - all charts have updated versions #"

exit 0

