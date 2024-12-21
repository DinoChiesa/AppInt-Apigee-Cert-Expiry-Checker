#!/bin/bash
# Copyright 2024 Google LLC
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

APPINT_ENDPT=https://integrations.googleapis.com

# Array of environment variable names to check
env_vars_to_check=(
  "APPINT_PROJECT"
  "APIGEE_PROJECTS"
  "REGION"
  "EXAMPLE_NAME"
  "EMAIL_ADDR"
)

maybe_install_integrationcli() {
  if [[ ! -d "$HOME/.apigeecli/bin" ]]; then
    echo "\nInstalling integrationcli"
    curl -L https://raw.githubusercontent.com/GoogleCloudPlatform/application-integration-management-toolkit/main/downloadLatest.sh | sh -
  fi
  export PATH=$PATH:$HOME/.integrationcli/bin
}

CURL() {
  [[ -z "${CURL_OUT}" ]] && CURL_OUT=$(mktemp /tmp/appint-setup-script.curl.out.XXXXXX)
  [[ -f "${CURL_OUT}" ]] && rm ${CURL_OUT}
  #[[ $verbosity -gt 0 ]] && echo "curl $@"
  echo "--------------------" >>"$OUTFILE"
  echo "curl $@" >>"$OUTFILE"
  [[ $verbosity -gt 0 ]] && echo "curl $@"
  CURL_RC=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $TOKEN" -o "${CURL_OUT}" "$@")
  [[ $verbosity -gt 0 ]] && echo "==> ${CURL_RC}"
  echo "==> ${CURL_RC}" >>"$OUTFILE"
  cat "${CURL_OUT}" >>"$OUTFILE"
}

beginswith() { case $2 in "$1"*) true ;; *) false ;; esac }

googleapis_whoami() {
  # for diagnostic purposes only
  CURL -X GET "https://www.googleapis.com/oauth2/v1/userinfo?alt=json"
  if [[ ${CURL_RC} -ne 200 ]]; then
    printf "cannot inquire userinfo"
    cat ${CURL_OUT}
    exit 1
  fi

  printf "\nGoogle access token info:\n"
  cat ${CURL_OUT}
}

check_shell_variables() {
  MISSING_ENV_VARS=()
  for var_name in "${env_vars_to_check[@]}"; do
    if [[ -z "${!var_name}" ]]; then
      MISSING_ENV_VARS+=("$var_name")
    fi
  done

  [[ ${#MISSING_ENV_VARS[@]} -ne 0 ]] && {
    printf -v joined '%s,' "${MISSING_ENV_VARS[@]}"
    printf "You must set these environment variables: %s\n" "${joined%,}"
    exit 1
  }

  printf "Settings in use:\n"
  printf "Settings in use:\n" >>"$OUTFILE"
  for var_name in "${env_vars_to_check[@]}"; do
    printf "  %s=%s\n" "$var_name" "${!var_name}"
    printf "  %s=%s\n" "$var_name" "${!var_name}" >>"$OUTFILE"
  done
}

invoke_one() {
  local url trigger_id integration_name
  if [[ -z "$1" || -z "$2" ]]; then
    printf "invoke_one needs at least two arguments."
    exit 1
  fi

  trigger_id="$1"
  integration_name="$2"
  url="${APPINT_ENDPT}/v1/projects/${APPINT_PROJECT}/locations/${REGION}/integrations/${integration_name}:execute"

  if [[ -z "$3" || "$3" != "just-show-command" ]]; then
    printf "CURL -X POST ${url} -H 'Content-Type: application/json' -H \"Authorization: Bearer \$TOKEN\" -d '{  \"triggerId\": \"$trigger_id\" }'\n"
    CURL -X POST "${url}" -H 'Content-Type: application/json' -d '{  "triggerId": "'$trigger_id'" }'
    cat ${CURL_OUT}
  else
    printf "To invoke yourself:\n"
    printf "CURL -X POST ${url} -H 'Content-Type: application/json' -H \"Authorization: Bearer \$TOKEN\" -d '{  \"triggerId\": \"$trigger_id\" }'\n"
  fi
}
