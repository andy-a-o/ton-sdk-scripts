#!/bin/sh

set -e

realpath() {
    [ "$1" = "/*" ] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT=$(basename "$0")
PULL_NODE_SE=1
NODE_SE_IMAGE=tonlabs/local-node:latest
NODE_SE_PORT=8888
BINARIES_ARCHIVE_PREFIX=tonclient_dotnet_bridge
BINARIES_SOURCE_PATH=$(realpath ../ton-client-dotnet-bridge)
BINARIES_DOWNLOAD_PATH=$(realpath ../binaries)
BINARIES_SDK_BRANCH=
DOTNET_SOURCE_PATH=$(realpath ../ton-client-dotnet)
PHP_EXT_SOURCE_PATH=$(realpath ../ton-client-php-ext)
PHP_SOURCE_PATH=$(realpath ../ton-client-php)
SDK_SOURCE_PATH=$(realpath ../TON-SDK)
SKIP_PHP_EXT=0
SKIP_TESTS=0
SDK_VERSION_TAG=
SKIP_BINARIES_BUILD=0
SKIP_BINARIES_DOWNLOAD=0
SKIP_BINARIES_COPY=0
REMOVE_EXISTING_CONTAINER=0
IGNORE_BUILD_FAILURES=0
VERBOSE=0
WAIT=1
HELP=$(
  cat <<EOF

${SCRIPT} <command> [<options>]

Common options:

  -v    - Verbose output.
  -i    - Ignore workflow build failures globally.

List of commands with command-specific options:

  binaries  - Build SDK binaries.
    Options:
      -b          - Specify SDK branch to use. By default, TON SDK is built using the tag name
                    matching the given one via the -t argument.
      -d <PATH>   - Path for binaries download directory (default is ${BINARIES_DOWNLOAD_PATH}).
      -D          - Skip download.
      -p <PATH>   - Path to binaries project sources (default is ${BINARIES_SOURCE_PATH}).
      -s <PATH>   - SDK source path (${SDK_SOURCE_PATH} by default).
      -t <TAG>    - SDK version tag.
      -w          - Wait for GitHub workflow build (enabled by default).
      -W          - Don not wait for GitHub workflow build.

  dotnet - Upgrade .NET SDK sources to the specified version.
    Options:
      -B          - Skip binaries copy.
      -d <PATH>   - Path for binaries download directory (default is ${BINARIES_DOWNLOAD_PATH}).
      -p <PATH>   - Source path (defalt is ${DOTNET_SOURCE_PATH}).
      -s <PATH>   - SDK source path (${SDK_SOURCE_PATH} by default).
      -t <TAG>    - SDK version tag.
      -T          - Skip tests.
      -w          - Wait for GitHub workflow build (enabled by default).
      -W          - Don not wait for GitHub workflow build.

  help  - Print this help.

  run   - Run local Node SE.
    Options:
      -l          - Pull latest Node SE image (enabled by default).
      -L          - Do not pull latest Node SE image.
      -p <PORT>   - Container port (${NODE_SE_PORT} by default).
      -r          - Remove existing docker container if already running.

  php - Upgrade PHP SDK sources to the specified version.
    Options:
      -B          - Skip binaries copy.
      -d <PATH>   - Path for binaries download directory (default is ${BINARIES_DOWNLOAD_PATH}).
      -p <PATH>   - Source path (defalt is ${PHP_SOURCE_PATH}).
      -s <PATH>   - SDK source path (${SDK_SOURCE_PATH} by default).
      -t <TAG>    - SDK version tag.
      -T          - Skip tests.
      -w          - Wait for GitHub workflow build (enabled by default).
      -W          - Don not wait for GitHub workflow build.
      -x <PATH>   - Extension source path (defalt is ${PHP_EXT_SOURCE_PATH}).
      -X          - Skip updating PHP extension code.

  update  - All-in-one script for SDK update using default paths.
    Options:
      -t <TAG>    - SDK version tag.

  up    - Alias for run

EXAMPLES

  Run latest Node SE image locally at port ${NODE_SE_PORT}:

  ./${SCRIPT} run -l

  Upgrade to SDK version X.Y.Z:

  ./${SCRIPT} update -t X.Y.Z

  Build new binaries for SDK version X.Y.Z using source code from branch master:

  ./${SCRIPT} binaries -t X.Y.Z -b master

EOF
)

if [ $# -eq 0 ]; then
  echo "Usage: ${HELP}"
  exit 1
fi

COMMAND=$1
shift 1

help() {
  echo "${HELP}"
  exit 0
}

while getopts "b:Bd:DhilLp:rs:t:TvwWx:X" opt; do
case ${opt} in
  b)
    BINARIES_SDK_BRANCH=$OPTARG
    ;;
  B)
    SKIP_BINARIES_COPY=1
    ;;
  d)
    BINARIES_DOWNLOAD_PATH=$OPTARG
    ;;
  D)
    SKIP_BINARIES_DOWNLOAD=1
    ;;
  h)
    help
    ;;
  i)
    IGNORE_BUILD_FAILURES=1
    ;;
  l)
    PULL_NODE_SE=1
    ;;
  L)
    PULL_NODE_SE=0
    ;;
  p)
    if [ "${COMMAND}" = "run" ] || [ "${COMMAND}" = "up" ]; then NODE_SE_PORT=$OPTARG; fi
    if [ "${COMMAND}" = "binaries" ]; then BINARIES_SOURCE_PATH=$OPTARG; fi
    if [ "${COMMAND}" = "dotnet" ]; then DOTNET_SOURCE_PATH=$OPTARG; fi
    if [ "${COMMAND}" = "php" ]; then PHP_SOURCE_PATH=$OPTARG; fi
    ;;
  r)
    REMOVE_EXISTING_CONTAINER=1
    ;;
  s)
    SDK_SOURCE_PATH=$OPTARG
    ;;
  t)
    SDK_VERSION_TAG=$OPTARG
    ;;
  T)
    SKIP_TESTS=1
    ;;
  v)
    VERBOSE=1
    ;;
  w)
    WAIT=1
    ;;
  W)
    WAIT=0
    ;;
  x)
    PHP_EXT_SOURCE_PATH=$OPTARG
    ;;
  X)
    SKIP_PHP_EXT=1
    ;;
  *)
    echo "Invalid Option: -$OPTARG" 1>&2
    echo "Usage: ${HELP}"
    exit 1
    ;;
  esac
done

verbose() {
  if [ "${VERBOSE}" -eq "1" ]; then
    echo "VERBOSE: $1"
  fi
}

wait_for_build_if_needed() {
  BUILD_NAME=$1
  WORKFLOW_NAME=$2
  RUN_COMMAND="gh run list --limit 1"
  if [ ! "${WORKFLOW_NAME}" = "" ]; then
    WORKFLOW_NAME="${WORKFLOW_NAME}"
    RUN_COMMAND="${RUN_COMMAND} -w ${WORKFLOW_NAME}"
  fi
  if [ "${WAIT}" -eq 1 ]; then
    verbose "Waiting for build ${BUILD_NAME} to finish"
    RUN_ID=$($RUN_COMMAND | grep "${BUILD_NAME}" | perl -pe "s/.*${BUILD_NAME}.*?([0-9]+?)\s.*/\$1/g")
    while [ "${RUN_ID}" = "" ]; do
      verbose "Workflow not running. Waiting 10 seconds"
      sleep 10
      RUN_ID=$($RUN_COMMAND | grep "${BUILD_NAME}" | perl -pe "s/.*${BUILD_NAME}.*?([0-9]+?)\s.*/\$1/g")
    done
    if [ "${IGNORE_BUILD_FAILURES}" -eq "0" ]; then
      gh run watch --exit-status "${RUN_ID}"
    else
      gh run watch "${RUN_ID}"
    fi
  else
    verbose "Don't wait for build ${BUILD_NAME}"
  fi
}

run() {
  CONTAINER_NAME=ton-node-se
  NO_DOCKER_IMAGES=$(docker ps -f name=${CONTAINER_NAME} -q | wc -l)
  if [ "${NO_DOCKER_IMAGES}" -eq "1" ]; then
    verbose "Image ${NODE_SE_IMAGE} is already running"
    if [ "${REMOVE_EXISTING_CONTAINER}" -eq "1" ]; then
      verbose "Removing existing container ${CONTAINER_NAME} for image ${NODE_SE_IMAGE}"
      docker rm -f ${CONTAINER_NAME}
    else
      return 0
    fi
  fi
  if [ "${PULL_NODE_SE}" -eq "1" ]; then
    verbose "Pulling image ${NODE_SE_IMAGE}"
    docker pull ${NODE_SE_IMAGE}
  fi
  verbose "Running image ${NODE_SE_IMAGE}"
  docker run --name ${CONTAINER_NAME} -d -p8888:80 -e USER_AGREEMENT=yes ${NODE_SE_IMAGE}
}

check_version_tag() {
  if [ "${SDK_VERSION_TAG}" = "" ]; then
    echo "SDK version tag is required (specify it via -t option)" 1>&2
    echo "Usage: ${HELP}"
    exit 1
  fi
}

check_binaries_downloaded() {
  if [ ! -d "${BINARIES_DOWNLOAD_PATH}/${SDK_VERSION_TAG}" ]; then
    echo "SDK binaries version ${SDK_VERSION_TAG} not downloaded. Run the following command to download them" 1>&2
    echo "./${SCRIPT} binaries -t ${SDK_VERSION_TAG} -d ${BINARIES_DOWNLOAD_PATH}" 1>&2
    exit 1
  fi
}

download_binaries() {

  if [ "${SKIP_BINARIES_DOWNLOAD}" -eq "1" ]; then
    verbose "Skipping binaries download."
    return
  fi

  BUILD_NAME=$1
  RUN_ID=$(gh run list --limit 1 | grep "${BUILD_NAME}" | perl -pe "s/.*${BUILD_NAME}.*?([0-9]+?)\s.*/\$1/g")
  if [ "${RUN_ID}" = "" ]; then
    verbose "Workflow not found. Exiting"
  fi

  ARTIFACTS_DOWNLOAD_PATH="${BINARIES_DOWNLOAD_PATH}/${SDK_VERSION_TAG}"
  if mkdir -p "${ARTIFACTS_DOWNLOAD_PATH}"; then
    verbose "Downloading artifacts for run ${RUN_ID} into ${ARTIFACTS_DOWNLOAD_PATH}"
    # can't ensure everything is already downloaded
    # so ignore download errors.
    gh run download "${RUN_ID}" -D "${ARTIFACTS_DOWNLOAD_PATH}" || true
  else
    echo "Unable to create directory ${ARTIFACTS_DOWNLOAD_PATH}"
    exit 1
  fi

}

build_new_binaries() {
  verbose "Building new binaries"

  CD=$(pwd)
  cd "${BINARIES_SOURCE_PATH}"

  BINARIES_TAG=$SDK_VERSION_TAG
  if [ ! "${BINARIES_SDK_BRANCH}" = "" ]; then
    BINARIES_TAG="${BINARIES_TAG}-${BINARIES_SDK_BRANCH}"
  fi

  EXISTING_TAG=$(git tag -l "${BINARIES_TAG}")
  if [ "${EXISTING_TAG}" = "${BINARIES_TAG}" ]; then
    verbose "Binaries for SDK tag ${BINARIES_TAG} are already built"
  else
    verbose "Create new tag ${BINARIES_TAG}"
    if git tag "${BINARIES_TAG}"; then
      if ! git push origin "${BINARIES_TAG}"; then
        echo "Failed to push tag ${BINARIES_TAG}"
        exit 1
      fi
    else
      verbose "Tag ${BINARIES_TAG} already exists."
    fi
  fi

  wait_for_build_if_needed "${BINARIES_TAG}" "Release"

  download_binaries "${BINARIES_TAG}"

  cd "${CD}"
}

update_binaries() {

  verbose "Updating TON SDK binaries to ${SDK_VERSION_TAG}"
  if ! mkdir -p "${BINARIES_DOWNLOAD_PATH}"; then
    echo "Unable to create directory ${BINARIES_DOWNLOAD_PATH}"
    exit 1
  fi

  if [ "${SKIP_BINARIES_BUILD}" -eq "0" ]; then
    build_new_binaries
  fi
}

extract_binary() {
  BINARY_SUFFIX=$1
  ZIP_PATH=$2
  EXTRACT_PATH=$3
  ZIP_DIR_PATH="${BINARIES_DOWNLOAD_PATH}/${SDK_VERSION_TAG}/${BINARIES_ARCHIVE_PREFIX}_${BINARY_SUFFIX}_${SDK_VERSION_TAG}"
  if [ -d "${ZIP_DIR_PATH}" ]; then
    verbose "Archive is already extracted into ${ZIP_DIR_PATH}"
    verbose "Copying ${ZIP_DIR_PATH}/${ZIP_PATH} to ${EXTRACT_PATH}"
    cp "${ZIP_DIR_PATH}/${ZIP_PATH}" "${EXTRACT_PATH}"
  else
    ZIP_ARCHIVE="${ZIP_DIR_PATH}.zip"
    verbose "Extracting ${ZIP_ARCHIVE}:${ZIP_PATH} to ${EXTRACT_PATH}"
    if ! unzip -p "${ZIP_ARCHIVE}" "${ZIP_PATH}" > "${EXTRACT_PATH}"; then
      echo "Failed to extract ${ZIP_ARCHIVE}:${ZIP_PATH} into ${EXTRACT_PATH}"
      exit 1
    fi
  fi
}

replace_in_files() {
  SEARCH=$1
  REPLACE=$2
  if [ "${SEARCH}" = "${REPLACE}" ]; then
    verbose "Nothing to replace"
  else
    shift 2
    for file in "$@"
    do
      verbose "Replacing ${SEARCH} with ${REPLACE} in ${file}"
      sed -i '' "s|${SEARCH}|${REPLACE}|g" "${file}"
    done
  fi
}

update_dotnet() {
  verbose "Updating TON .NET SDK to ${SDK_VERSION_TAG}"

  CD=$(pwd)

  verbose "Checking out SDK at ${SDK_VERSION_TAG}"
  cd "${SDK_SOURCE_PATH}" && git fetch --tags -f && git checkout "${SDK_VERSION_TAG}"
  cd "${DOTNET_SOURCE_PATH}"

  if [ "${SKIP_BINARIES_COPY}" -eq 0 ]; then
    check_binaries_downloaded
    extract_binary linux_x64 lib/libton_client.so runtimes/linux-x64/native/libton_client.so
    extract_binary macos_x64 lib/libton_client.dylib runtimes/osx-x64/native/libton_client.dylib
    extract_binary windows_x64 bin/ton_client.dll runtimes/win-x64/native/ton_client.dll
    extract_binary windows_x86 bin/ton_client.dll runtimes/win-x86/native/ton_client.dll
  else
    verbose "Skip binaries copy"
  fi

  CURRENT_SDK_VERSION=$(head -n 1 generator/api.index.txt)
  verbose "Found current SDK version: ${CURRENT_SDK_VERSION}"
  if [ ! "${CURRENT_SDK_VERSION}" = "${SDK_VERSION_TAG}" ]; then

    verbose "Copying api.json"
    cp "${SDK_SOURCE_PATH}/tools/api.json" generator/api.json

    verbose "Generating new code from api.json"
    cd generator && npm run generate && cd ..

  else
    verbose "SDK version ${SDK_VERSION_TAG} is already built"
  fi

  verbose "Copying test contracts"
  cp -rf "${SDK_SOURCE_PATH}/ton_client/src/tests/contracts" tests/Resources

  VERSION_FILES=$(grep -rF "${CURRENT_SDK_VERSION}" -l . | grep -v '/bin/' | grep -v '/runtimes/' | grep -v 'csprojAssemblyReference.cache' | grep -v '.git/' | grep -v 'node_modules' | grep -E '\.cs|\.json|\.txt' | tr '\n' ' ')
  verbose "Replacing version in files ${VERSION_FILES}"
  replace_in_files "${CURRENT_SDK_VERSION}" "${SDK_VERSION_TAG}" ${VERSION_FILES}

  if [ "${SKIP_TESTS}" -eq "0" ]; then
    verbose "Running local tests"
    TON_NETWORK_ADDRESS=http://localhost:${NODE_SE_PORT} dotnet test
  else
    verbose "Skip running local tests"
  fi

  verbose "Pushing changes to master branch"
  git add .
  if git commit -a -m "Upgrade to SDK version ${SDK_VERSION_TAG}."; then
    git push origin master
    wait_for_build_if_needed master "Tests"
  else
    verbose "Nothing to commit"
  fi

  verbose "Pushing new version tag ${SDK_VERSION_TAG}"
  if git tag "${SDK_VERSION_TAG}"; then
    git push origin "${SDK_VERSION_TAG}"
    wait_for_build_if_needed "$SDK_VERSION_TAG" "Release"
  fi

  cd "${CD}"
}

check_php_version() {
  verbose "Checking PHP version"
  # TODO: implement!
}

update_php_ext() {
  verbose "Updating PHP extension version"

  CD=$(pwd)
  cd "${PHP_EXT_SOURCE_PATHPHP_EXT_SOURCE_PATH}"

  if [ "${SKIP_BINARIES_COPY}" -eq 0 ]; then
    check_binaries_downloaded
    extract_binary linux_x64 lib/libton_client.so deps/lib/x64/libton_client.so
    extract_binary macos_x64 lib/libton_client.dylib deps/lib/x64/libton_client.dylib
    extract_binary windows_x64 bin/ton_client.dll deps/bin/x64/ton_client.dll
    extract_binary windows_x64 lib/ton_client.lib deps/lib/x64/ton_client.lib
    extract_binary windows_x86 bin/ton_client.dll deps/bin/x86/ton_client.dll
    extract_binary windows_x86 lib/ton_client.lib deps/lib/x86/ton_client.lib
  else
    verbose "Skip binaries copy"
  fi

  CURRENT_SDK_VERSION=$(grep PHP_TON_CLIENT_VERSION "src/php_ton_client.h" | awk '{gsub(/"/, "", $4); print $4}')
  verbose "Found current SDK version: ${CURRENT_SDK_VERSION}"
  if [ ! "${CURRENT_SDK_VERSION}" = "${SDK_VERSION_TAG}" ]; then
    replace_in_files "${CURRENT_SDK_VERSION}" "${SDK_VERSION_TAG}" src/php_ton_client.h INSTALL.md
    verbose "Pushing new version tag"
    git add deps src/php_ton_client.h INSTALL.md
    git commit -m "Upgrade to ${SDK_VERSION_TAG}."
    git push origin master
    git tag "${SDK_VERSION_TAG}"
    git push origin "${SDK_VERSION_TAG}"
    wait_for_build_if_needed "${SDK_VERSION_TAG}" "Release"
  else
    verbose "SDK version ${SDK_VERSION_TAG} is already built"
  fi

  sudo php installer.php -v "${SDK_VERSION_TAG}"
  php installer.php -v "${SDK_VERSION_TAG}" -T

  cd "${CD}"
}

update_php() {

  verbose "Updating TON PHP SDK to ${SDK_VERSION_TAG}"

  check_version_tag
  check_php_version

  if [ "${SKIP_PHP_EXT}" -eq "0" ]; then
    update_php_ext
  fi

  CD=$(pwd)
  cd "${PHP_SOURCE_PATH}"
  EXISTING_TAG=$(git tag -l "${SDK_VERSION_TAG}")
  if [ "${EXISTING_TAG}" = "${SDK_VERSION_TAG}" ]; then
    verbose "PHP SDK version ${SDK_VERSION_TAG} is already built"
    return
  fi

  CURRENT_SDK_VERSION=$(grep 'ext-ton_client' composer.json | awk '{print $2}' | perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')
  verbose "Found current PHP SDK version: ${CURRENT_SDK_VERSION}"
  if [ ! "${CURRENT_SDK_VERSION}" = "${SDK_VERSION_TAG}" ]; then
    verbose "Checking out SDK at ${SDK_VERSION_TAG}"
    cd "${SDK_SOURCE_PATH}" && git fetch --tags -f && git checkout "${SDK_VERSION_TAG}"
    cd "${PHP_SOURCE_PATH}"
    verbose "Copying api.json"
    cp "${SDK_SOURCE_PATH}/tools/api.json" api.json
    verbose "Copying test contracts"
    cp -rf "${SDK_SOURCE_PATH}/ton_client/src/tests/contracts" tests
    VERSION_FILES=$(grep -rF "${CURRENT_SDK_VERSION}" -l . | grep -v '.git/' | tr '\n' ' ')
    verbose "Replacing version in files ${VERSION_FILES}"
    replace_in_files "${CURRENT_SDK_VERSION}" "${SDK_VERSION_TAG}" ${VERSION_FILES}
  else
    verbose "Source version is up to date"
  fi

  verbose "Generating sources"
  composer generate

  verbose "Running composer update"
  composer update

  if [ "${SKIP_TESTS}" -eq "0" ]; then
    verbose "Running local tests"
    TON_NETWORK_ADDRESS=http://localhost:${NODE_SE_PORT} composer test
  else
    verbose "Skip running local tests"
  fi

  verbose "Commit and push sources"
  git add .
  if git commit -a -m "Upgrade to SDK version ${SDK_VERSION_TAG}."; then
    git push origin master
    wait_for_build_if_needed master "Tests"
  fi

  verbose "Create new tag ${SDK_VERSION_TAG}"
  if git tag "${SDK_VERSION_TAG}"; then
    git push origin "${SDK_VERSION_TAG}"
    wait_for_build_if_needed "$SDK_VERSION_TAG" "Release"
  fi

  cd "${CD}"
}

update_all() {
  run
  update_binaries
  update_dotnet
  update_php
}

case ${COMMAND} in
binaries)
  update_binaries
  ;;
dotnet)
  update_dotnet
  ;;
help)
  help
  ;;
run)
  run
  ;;
up)
  run
  ;;
php)
  update_php
  ;;
update)
  update_all
  ;;
*)
  echo "Usage: ${HELP}"
  exit 1
  ;;
esac
