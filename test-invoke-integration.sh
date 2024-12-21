#!/bin/bash

# Copyright 2023-2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source ./lib/utils.sh

if [[ ! -f .integration_name || ! -f .trigger_id ]]; then
  printf "missing one or more state files.  Must run setup again. (maybe run clean first)"
  exit 1
fi

TOKEN=$(gcloud auth print-access-token)
OUTFILE=$(mktemp /tmp/appint-samples.test-invoke.out.XXXXXX)
INTEGRATION_NAME="$(<.integration_name)"
trigger_id="$(<.trigger_id)"

invoke_one "$trigger_id" "$INTEGRATION_NAME"
