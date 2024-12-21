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

printf "\nThis script adds a Service account as apigee.readOnlyAdmin to a specified project.\n\n"
check_shell_variables

if [[ -z "$1" ]]; then
  printf "specify a project to add."
  exit 1
fi

if [[ ! -f .appint_sa_name ]]; then
  printf "There is no stored Service Account; cannot continue."
  exit 1
fi

APIGEE_PROJECT="$1"
APPINT_SA="$(<.appint_sa_name)"
FULL_SA_EMAIL="${APPINT_SA}@${APPINT_PROJECT}.iam.gserviceaccount.com"

printf "\ngcloud projects add-iam-policy-binding $APIGEE_PROJECT --condition=None --member=serviceAccount:$FULL_SA_EMAIL --role=roles/apigee.readOnlyAdmin\n\n"

gcloud projects add-iam-policy-binding "$APIGEE_PROJECT" \
  --condition=None --member="serviceAccount:$FULL_SA_EMAIL" \
  --role=roles/apigee.readOnlyAdmin --quiet
