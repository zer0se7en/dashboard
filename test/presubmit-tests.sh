#!/usr/bin/env bash

# Copyright 2018-2023 The Tekton Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script runs the presubmit tests; it is started by prow for each PR.
# For convenience, it can also be executed manually.
# Running the script without parameters, or with the --all-tests
# flag, causes all tests to be executed, in the right order.
# Use the flags --build-tests, --unit-tests and --integration-tests
# to run a specific set of tests.

# Markdown linting failures don't show up properly in Gubernator resulting
# in a net-negative contributor experience.
export DISABLE_MD_LINTING=1
# GitHub is currently rejecting requests from the link checker with 403 due
# to missing header. Disable until the tooling is updated to account for this.
export DISABLE_MD_LINK_CHECK=1

# FIXME(vdemeester) we need to come with something better (like baking common scripts in our image, when we got one)
go mod vendor || exit 1

source $(dirname $0)/../vendor/github.com/tektoncd/plumbing/scripts/presubmit-tests.sh

# To customize the default build flow, you can define methods
# - build
#   - pre_build_tests : runs before the build function
#   - build_tests : replace the default build function
#                   which does go build, and validate some autogenerated code if the scripts are there
#   - post_build_tests : runs after the build function
# - unit-test
#   - pre_unit_tests : runs before the unit-test function
#   - unit_tests : replace the default unit-test function
#                   which does go test with race detector enabled
#   - post_unit_tests : runs after the unit-test function
# - integration-test
#   - pre_integration_tests : runs before the integration-test function
#   - integration_tests : replace the default integration-test function
#                   which runs `test/e2e-*test.sh` scripts
#   - post_integration_tests : runs after the integration-test function
#

function post_build_tests() {
  header "Testing if golint has been done"
  golangci-lint --color=never run

  if [[ $? != 0 ]]; then
      results_banner "Go Lint" 1
      exit 1
  fi

  results_banner "Go Lint" 0
}

function get_node() {
  echo "Installing Node.js"
  apt-get update
  apt-get install -y curl
  curl -O https://nodejs.org/dist/v18.13.0/node-v18.13.0-linux-x64.tar.xz
  tar xf node-v18.13.0-linux-x64.tar.xz
  export PATH=$PATH:$(pwd)/node-v18.13.0-linux-x64/bin
  echo ">> Node.js version"
  node --version
  echo ">> npm version"
  npm --version
}

function node_npm_install() {
  local failed=0
  echo "Configuring npm"
  mkdir ~/.npm-global
  npm config set prefix '~/.npm-global'
  export PATH=$PATH:$HOME/.npm-global/bin
  echo "Installing package dependencies"
  npm ci || failed=1 # similar to `npm install` but ensures all versions from lock file
  return ${failed}
}

function node_test() {
  local failed=0
  echo "Running node tests from $(pwd)"
  node_npm_install || failed=1
  echo "Linting"
  npm run lint || failed=1
  echo "Checking message bundles"
  npm run i18n:extract || failed=1
  git status
  git diff-index --patch --exit-code --no-color HEAD ./src/nls/ || failed=1
  echo "Running unit tests"
  npm run test:ci || failed=1
  echo ""
  return ${failed}
}

function pre_unit_tests() {
  node_test
}

function pre_integration_tests() {
  local failed=0
  if [ "${USE_NIGHTLY_RELEASE}" == "true" ]; then
    echo "Using nightly release, skipping npm install and frontend build"
  else
    node_npm_install || failed=1
    echo "Running frontend build"
    npm run build || failed=1
  fi
  return ${failed}
}

function extra_initialization() {
  echo "Script is running as $(whoami) on $(hostname)"
  get_node
}

function unit_tests() {
  go test -v -race ./...
  return $?
}

main $@
