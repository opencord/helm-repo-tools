#!/usr/bin/env bats
# -----------------------------------------------------------------------
# Copyright 2024 Open Networking Foundation Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# -----------------------------------------------------------------------
# SPDX-FileCopyrightText: 2024 Open Networking Foundation Contributors
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------

bats_require_minimum_version 1.5.0

# This runs before each of the following tests are executed.
setup() {
    source '../../chart_version_check/filter_files.sh'
}

## -----------------------------------------------------------------------
## Intent: Validate the filter_files function
## -----------------------------------------------------------------------
@test 'Validate filter_files()' {

    local -a good=() # control
    good+=('bar.c')
    good+=('tans.c')

    local -a bad=() # garbage
    bad+=('bar.c~')
    bad+=('.#bar.c')
    bad+=('#bar.c#')

    ## Generate a list of files and paths to filter
    local -a src=()
    for dir in '' 'foo/';
    do
        for fyl in "${good[@]}" "${bad[@]}";
        do
            src+=("${dir}${fyl}")
        done
    done

    local -a got=("${src[@]}")

    # Run is quarky, test ($?==0) and set -e
    if false; then
        run ! filter_files got
    else
        filter_files got
        local status=$?
        [ $status -eq 0 ]
    fi

    ## -----------------------------------------
    ## Compare by size, filtered list is smaller
    ## -----------------------------------------
    [ ${#src[@]} -eq 10 ]
    [ ${#got[@]} -eq 4 ]

    ## -----------------------------------------
    ## Also sanity check strings since we are
    ## not (yet) comparing list contents.
    ## -----------------------------------------
    [[ ! "${got[*]}" == *'#'* ]]
    [[ ! "${got[*]}" == *'~'* ]]

    local val

    ## Verify control values were not filtered
    for val in "${good[@]}";
    do
        [[ "${src[*]}" == *"$val"* ]]
        [[ "${got[*]}" == *"$val"* ]]
    done

    ## Verify garbage exists and was filtered
    for val in "${bad[@]}";
    do
        [[ "${src[*]}" == *"$val"* ]]
        [[ ! "${got[*]}" == *"$val"* ]]
    done
}

# [EOF]
