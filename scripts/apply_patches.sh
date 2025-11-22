#!/usr/bin/env bash
set -uxo pipefail

# note that space before slash is important
PATCHES="\
add_td_to_mlirpythoncapi_headers \
mscv \
"

# For Windows, use simplified patch that only exports async symbols
# For other platforms, use full patch that also removes OpenMP dependencies
if [ x"$MATRIX_OS" == x"windows-2022" ]; then
  PATCHES="$PATCHES export_async_symbols"
else
  PATCHES="$PATCHES remove_openmp_dep_on_clang_and_export_async_symbols"
fi

if [ x"$CIBW_ARCHS" == x"wasm32" ]; then
  PATCHES="$PATCHES wasm_mlir_opt"
fi
if [ x"$USE_CMAKE_NAMESPACES" == x"true" ]; then
  PATCHES="$PATCHES namespaces"
fi

if [ x"$MATRIX_OS" == x"macos-13" ]; then
  PATCHES="$PATCHES mac_vec"
fi

if [[ x"${APPLY_PATCHES:-true}" == x"true" ]]; then
  for PATCH in $PATCHES; do
    echo "applying $PATCH"
    git apply --quiet --ignore-space-change --ignore-whitespace --directory llvm-project patches/$PATCH.patch
    ERROR=$?
    if [ $ERROR != 0 ]; then
      git apply --ignore-space-change --ignore-whitespace --verbose --directory llvm-project patches/$PATCH.patch -R --check
      ERROR=$?
      if [ $ERROR != 0 ]; then
        exit $ERROR
      fi
    fi
  done
fi
