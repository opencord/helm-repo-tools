#!/usr/bin/env bash
# -----------------------------------------------------------------------
# Copyright 2017-2024 Open Networking Foundation Contributors
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
# SPDX-FileCopyrightText: 2017-2024 Open Networking Foundation Contributors
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------
# Intent: This function will remove junk files (editor temp files, etc)
#         from a given list of files.
# -----------------------------------------------------------------------
function filter_files()
{
    local -n ref=$1; shift
    [[ ${#ref[@]} -eq 0 ]] && { return; }

    local -a fyls=("${ref[@]}")
    ref=()

    ## ------------------------------------------------------
    ## Iterate by index to avoid whitespace filename problems
    ## ------------------------------------------------------
    local max=$((${#fyls[@]} - 1))
    local idx
    for idx in $(seq 0 $max);
    do
        local val="${fyls[$idx]}"
        local tmp="${val//[[:blank:]]}"
        if [[ ${#tmp} -eq 0 ]]; then
            continue
        fi

        case "$val" in

            # Skip editor temp files
            *'#'*) continue ;;
            *'~') continue  ;;

            # Else gather for processing
            *) ref+=("$val") ;;
        esac
    done

    return
}

# : # ($?==0) for source $script

# [EOF]
