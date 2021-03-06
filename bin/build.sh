#!/bin/bash
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
options=`cat ${root_dir}/bin/config_options.sh`
depends_dir=$($root_dir/bin/variables.sh depends_dir)
host=$(${root_dir}/bin/variables.sh host)
btc_dir="${root_dir}/libbitcoind"
patch_sha=$($root_dir/bin/variables.sh patch_sha)
export CPPFLAGS="-I${depends_dir}/${host}/include/boost -I${depends_dir}/${host}/include -L${depends_dir}/${host}/lib"
echo "Using BTC directory: ${btc_dir}"

cd "${root_dir}" || exit -1


build_dependencies () {
  if [ -d "${btc_dir}" ]; then
    pushd "${depends_dir}" || exit -1
    echo "using host for dependencies: ${host}"
    if [ "${test}" = true ]; then
      make HOST=${host} NO_QT=1 NO_UPNP=1
    else
      make HOST=${host} NO_QT=1 NO_WALLET=1 NO_UPNP=1
    fi
    if test $? -eq 0; then
      popd || exit -1
    else
      echo "Safecoin's dependency building failed, please check the previous output for details."
      exit -1
    fi
  fi
}

get_patch_file () {
  if test -e "${root_dir/PATCH_VERSION}"; then
    tag=`cat "${root_dir}/PATCH_VERSION" | xargs` || exit -1
  else
    echo "no tag file found, please create it in the root of the project as so: 'echo \"safecoin-0.10\" > PATCH_VERSION'"
    exit 1
  fi
}

compare_patch () {
  cd "${btc_dir}" || exit -1
  get_patch_file
  echo "running the diff command from HEAD to ${tag}"
  last_commit=$(git rev-parse HEAD)
  diff=$(git show ${last_commit})
  stripped_diff=$( echo -n "${diff}" | tail -n $( expr `echo -n "${diff}" | wc -l` - 5 ) )
  matching_patch=`echo -n "${stripped_diff}" | diff -w "${root_dir}/etc/safecoin.patch" -`
}

cache_files () {
  cache_file="${root_dir}"/cache/cache.tar
  pushd "${btc_dir}" || exit -1
  find . -type f \( -name "*.h" -or -name "*.hpp" -or -name \
"*.ipp" -or -name "*.a" \) | tar -cf "${cache_file}" -T -
  if test $? -ne 0; then
    echo "We were trying to copy over your cached artifacts, but there was an issue."
    exit -1
  fi
  tar xf "${cache_file}" -C "${root_dir}"/cache
  if test $? -ne 0; then
    echo "We were trying to untar your cache, but there was an issue."
    exit -1
  fi
  rm -fr "${cache_file}" >/dev/null 2>&1
  popd || exit -1
}

debug=
if [ "${BITCORENODE_ENV}" == "debug" ]; then
  options=`cat ${root_dir}/bin/config_options_debug.sh` || exit -1
fi

test=false
if [ "${BITCORENODE_ENV}" == "test" ]; then
  test=true
  options=`cat ${root_dir}/bin/config_options_test.sh` || exit -1
fi

if hash shasum 2>/dev/null; then
  shasum_cmd="shasum -a 256"
else
  shasum_cmd="sha256sum"
fi

patch_file_sha=$(${shasum_cmd} "${root_dir}/etc/safecoin.patch" | awk '{print $1}')
last_patch_file_sha=
if [ -e "${patch_sha}" ]; then
  echo "Patch file sha exists, let's see if the patch has changed since last build..."
  last_patch_file_sha=$(cat "${patch_sha}")
fi
shared_file_built=false
if [ "${last_patch_file_sha}" == "${patch_file_sha}" ]; then
  echo "Patch file contents matches the sha from the patch file itself, so no reason to rebuild the bindings unless there are no prebuilt bindings."
  shared_file_built=true
fi

if [ "${shared_file_built}" = false ]; then
  echo "Looks like the patch to safecoin changed since last build -or- this is the first build, so rebuilding libbitcoind itself..."
  mac_response=$($root_dir/bin/variables.sh mac_dependencies)
  if [ "${mac_response}" != "" ]; then
    echo "${mac_response}"
    exit -1
  fi
  only_make=false
  if [ -d "${btc_dir}" ]; then
    echo "running compare patch..."
    compare_patch
    repatch=false
    if [[ "${matching_patch}" =~ [^\s\\] ]]; then
      echo "Warning! libbitcoind is not patched with:\
        ${root_dir}/etc/safecoin.patch."
      echo -n "Would you like to remove the current patch, checkout the tag: ${tag} and \
apply the current patch from "${root_dir}"/etc/safecoin.patch? (y/N): "
      if [ "${BITCORENODE_ASSUME_YES}" = true ]; then
        input=y
        echo ""
      else
        read input
      fi
      if [[ "${input}" =~ ^y|^Y ]]; then
        repatch=true
        echo "Removing directory: \"${btc_dir}\" and starting over!"
        rm -fr "${btc_dir}" >/dev/null 2>&1
      fi
    fi
    if [ "${repatch}" = false ]; then
      echo "Running make inside libbitcoind (assuming you've previously patched and configured libbitcoind)..."
      cd "${btc_dir}" || exit -1
      only_make=true
    fi
  fi

  if [ "${only_make}" = false ]; then
    echo "Cloning, patching, and building libbitcoind..."
    get_patch_file
    echo "attempting to checkout tag: ${tag} of bitcoin from github..."
    cd "${root_dir}" || exit -1
    #versions of git prior to 2.x will not clone correctly with --branch
    git clone ssh://whitelotus@jira.safe.cash:7999/sc/cool-cash.git libbitcoind
    cd "${btc_dir}" || exit -1
    git fetch --tags
    git checkout -b safecoin-0.10
    git pull origin safecoin-0.10
    echo '../patch-safecoin.sh' "${btc_dir}"
    ../bin/patch-safecoin "${btc_dir}"
    exit;
    if ! test -d .git; then
      echo 'Please point this script to an upstream safecoin git repo.'
      exit -1
    fi

  fi
  build_dependencies
  echo './autogen.sh'
  ./autogen.sh || exit -1

  boost_libdir="--with-boost-libdir=${depends_dir}/${host}/lib"

  full_options="${options} ${boost_libdir}"
  echo "running the configure script with the following options:\n :::[\"${full_options}\"]:::"
  ${full_options}

  echo 'make V=1'
  make V=1 || exit -1

  echo "Creating the sha marker for the patching in libbitcoind..."
  echo "Writing patch sha file to: \"${patch_sha}\""
  echo -n `${shasum_cmd} "${root_dir}"/etc/safecoin.patch | awk '{print $1}'` > "${patch_sha}"
  cache_files
  echo 'Build finished successfully.'
else
  echo 'Using existing static library.'
fi

# Building the Bindings

set -e

cd "${root_dir}"

debug=--debug=false
if test x"$1" = x'debug'; then
  debug=--debug
fi

node-gyp ${debug} rebuild
