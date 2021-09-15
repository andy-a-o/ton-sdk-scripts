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
BINARIES_SOURCE_PATH=$(realpath ../ton-sdk-dotnet-bridge)
BINARIES_DOWNLOAD_PATH=$(realpath ../binaries)
DOTNET_SOURCE_PATH=$(realpath ../ton-client-dotnet)
PHP_EXT_SOURCE_PATH=$(realpath ../ton-client-php-ext)
PHP_SOURCE_PATH=$(realpath ../ton-client-php)
SDK_SOURCE_PATH=$(realpath ../TON-SDK)
SKIP_PHP_EXT=0
SKIP_TESTS=0
SDK_VERSION_TAG=
SKIP_BINARIES_COPY=0
VERBOSE=0
WAIT=1
HELP=$(
  cat <<EOF

${SCRIPT} <command> [<options>]

Common options:

  -v    - Verbose output.

List of commands with command-specific options:

  binaries  - Build SDK binaries.
    Options:
      -d <PATH>   - Path for binaries download directory (default is ${BINARIES_DOWNLOAD_PATH}).
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

EOF
)

if [ $# -eq 0 ]; then
  echo "Usage: ${HELP}"
  exit 1
fi

COMMAND=$1
shift 1

while getopts "Bd:hlLp:s:t:TvwWx:X" opt; do
case ${opt} in
  B)
    SKIP_BINARIES_COPY=1
    ;;
  d)
    BINARIES_DOWNLOAD_PATH=$OPTARG
    ;;
  h)
    echo "${HELP}"
    exit 0
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

run() {
  if [ "${PULL_NODE_SE}" -eq "1" ]; then
    verbose "Pulling image ${PULL_NODE_SE}"
    docker pull ${NODE_SE_IMAGE}
  fi
  verbose "Running image ${PULL_NODE_SE}"
  docker run --name ton-node-se -d -p8888:80 -e USER_AGREEMENT=yes ${NODE_SE_IMAGE}
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
    echo "./${SCRIPT} binaries -d ${BINARIES_DOWNLOAD_PATH}" 1>&2
    exit 1
  fi
}

update_binaries() {
  verbose "Updating TON SDK binaries to ${SDK_VERSION_TAG}"
  mkdir -p "${BINARIES_DOWNLOAD_PATH}"
  # TODO: implement!
}

extract_binary() {
  BINARY_SUFFIX=$1
  ZIP_PATH=$2
  EXTRACT_PATH=$3
  ZIP_ARCHIVE="${BINARIES_DOWNLOAD_PATH}/${SDK_VERSION_TAG}/${BINARIES_ARCHIVE_PREFIX}_${BINARY_SUFFIX}_${SDK_VERSION_TAG}.zip"
  verbose "Extracting ${ZIP_ARCHIVE}:${ZIP_PATH} to ${EXTRACT_PATH}"
  unzip -p "${ZIP_ARCHIVE}" "${ZIP_PATH}" > "${EXTRACT_PATH}"
}

update_dotnet() {
  verbose "Updating TON .NET SDK to ${SDK_VERSION_TAG}"
  # TODO: implement!
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

check_php_version() {
  verbose "Checking PHP version"
  # TODO: implement!
}

wait_for_build_if_needed() {
  BUILD_NAME=$1
  if [ "${WAIT}" -eq 1 ]; then
    verbose "Waiting for build ${BUILD_NAME} to finish"
    RUN_ID=$(gh run list --limit 1 | grep "${BUILD_NAME}" | perl -pe "s/.*${BUILD_NAME}.*?([0-9]+?)\s.*/\$1/g")
    while [ "${RUN_ID}" = "" ]; do
      verbose "Workflow not running. Waiting 10 seconds"
      sleep 10
      RUN_ID=$(gh run list --limit 1 | grep "${BUILD_NAME}" | perl -pe "s/.*${BUILD_NAME}.*?([0-9]+?)\s.*/\$1/g")
    done
    gh run watch --exit-status "${RUN_ID}"
  else
    verbose "Don't wait for build ${BUILD_NAME}"
  fi
}

update_php_ext() {
  verbose "Updating PHP extension version"

  CD=$(pwd)
  cd "${PHP_EXT_SOURCE_PATH}"

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
    wait_for_build_if_needed "$SDK_VERSION_TAG"
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
    cd "${SDK_SOURCE_PATH}" && git checkout "${SDK_VERSION_TAG}"
    cd "${PHP_SOURCE_PATH}"
    verbose "Copying api.json"
    cp "${SDK_SOURCE_PATH}/tools/api.json" api.json
    verbose "Copying test contracts"
    cp -rf "${SDK_SOURCE_PATH}/ton_client/src/tests/contracts" tests
    VERSION_FILES=$(grep -r "${CURRENT_SDK_VERSION}" -l . | grep -v '.git/' | tr '\n' ' ')
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
  if git commit -a -m "Upgrade to SDK version ${SDK_VERSION_TAG}."; then
    git push origin master
    wait_for_build_if_needed master
  fi

  verbose "Create new tag ${SDK_VERSION_TAG}"
  if git tag "${SDK_VERSION_TAG}"; then
    git push origin "${SDK_VERSION_TAG}"
    wait_for_build_if_needed "$SDK_VERSION_TAG"
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
