#!/usr/bin/env bash

set -e
set -x

# This is needed for CentOS5/6 Jenkins workers to bootstrap the gcc-4.8 toolchain.
cd "$(dirname $0)"

# This will set up two global variables: NODE_ARCHIVE_FILENAME and SAVE_NODE_BUILD.
init_vars() {
  local NODE_VER=`grep 'set(NODEJS_VERSION' ../external/node/CMakeLists.txt | sed 's/[^0-9.]//g'`
  # Expect node version to be x.y.z format
  if ! [[ "$NODE_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Couldn't parse node version" >&2
    exit 1
  fi

  if [ "$OS" == "" ]; then
    echo "Missing 'OS' Jenkins environment variable" >&2
    exit 1
  fi

  if [ "$ARCH" == "" ]; then
    echo "Missing 'ARCH' Jenkins environment variable" >&2
    exit 1
  fi

  # The filename of a suitable cached build of Node.js. We will either download
  # and use such a file from S3, or, we will build from source and create this
  # file (and expect Jenkins to upload it).
  NODE_ARCHIVE_FILENAME="node_${NODE_VER}_${OS}_${ARCH}.tar.gz"
}

# Attempt to retrieve a cached Node.js build from S3. If one is found, then we
# will unpack it in ../ext. Otherwise, we bail.
setup_cached_nodejs () {
  # This is the URL where we'll expect to find a suitable cached build of Node.js, if one exists
  local NODE_ARCHIVE_URL="https://s3.amazonaws.com/rstudio-shiny-server-os-build/node/${NODE_ARCHIVE_FILENAME}"
  local NODE_ARCHIVE_DEST="/tmp/${NODE_ARCHIVE_FILENAME}"

  if [ -f "${NODE_ARCHIVE_DEST}" ]; then
    # Pre-built Node exists locally already, unpack it
    mkdir -p ../ext
    tar xzf "${NODE_ARCHIVE_DEST}" -C ../ext
  elif wget -S --spider "${NODE_ARCHIVE_URL}"; then
    # Pre-built Node doesn't exist locally, but can be downloaded
    wget -O "${NODE_ARCHIVE_DEST}" "${NODE_ARCHIVE_URL}"
    mkdir -p ../ext
    tar xzf "${NODE_ARCHIVE_DEST}" -C ../ext
  else
    # Node needs to be built
    echo "Expected pre-built Node at this URL: ${NODE_ARCHIVE_URL}"
    exit 1
  fi
}

# Repo checkout directories are re-used by Jenkins workers, and so a
# $PROJECT_DIR/packaging/build/CMakeCache.txt might be hanging around from a
# previous build. This cache file is platform-specific, and the build that
# generated it may have been on a different platform. In order to build reliably
# we must first blow it and any other files not in the repo away.
git reset --hard && git clean -ffdx

init_vars
setup_cached_nodejs

if (which scl && scl -l | grep -q devtoolset-2);
then
	scl enable devtoolset-2 ./make-package.sh "$@"
else
	CC=gcc CXX=g++ ./make-package.sh "$@"
fi
