#!/usr/bin/env bash
set -uxo pipefail

# note that space before slash is important
PATCHES="\
add_td_to_mlirpythoncapi_headers \
mscv \
"

# For Windows, use simplified patch that only exports async symbols
# For other platforms, use full patch that also removes OpenMP dependencies
# If the full patch fails, fall back to the simpler version
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
      # Check if patch is already applied
      git apply --ignore-space-change --ignore-whitespace --verbose --directory llvm-project patches/$PATCH.patch -R --check
      ERROR=$?
      if [ $ERROR != 0 ]; then
        # If this is the remove_openmp patch, try the alternative export_async_symbols_21 patch
        if [ x"$PATCH" == x"remove_openmp_dep_on_clang_and_export_async_symbols" ]; then
          echo "Primary patch failed, trying export_async_symbols_21 as fallback"
          git apply --quiet --ignore-space-change --ignore-whitespace --directory llvm-project patches/export_async_symbols_21.patch
          ERROR=$?
          if [ $ERROR != 0 ]; then
            # Check if the fallback patch is already applied
            git apply --ignore-space-change --ignore-whitespace --verbose --directory llvm-project patches/export_async_symbols_21.patch -R --check
            ERROR=$?
            if [ $ERROR != 0 ]; then
              echo "Both primary and fallback patches failed for $PATCH"
              exit $ERROR
            else
              echo "Fallback patch export_async_symbols_21 was already applied"
            fi
          else
            echo "Successfully applied fallback patch export_async_symbols_21"
          fi
        else
          exit $ERROR
        fi
      else
        echo "Patch $PATCH was already applied"
      fi
    else
      echo "Successfully applied patch $PATCH"
    fi
  done
fi
