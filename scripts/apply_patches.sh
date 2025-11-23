#!/usr/bin/env bash
set -uxo pipefail

# Function to try applying a patch with fallback
try_apply_patch() {
  local PATCH=$1
  local FALLBACK=$2

  echo "Applying $PATCH"
  if git apply --check --ignore-space-change --ignore-whitespace --directory llvm-project patches/$PATCH.patch 2>/dev/null; then
    git apply --quiet --ignore-space-change --ignore-whitespace --directory llvm-project patches/$PATCH.patch
    echo "Successfully applied patch $PATCH"
    return 0
  fi

  # Check if already applied
  if git apply --check --ignore-space-change --ignore-whitespace --directory llvm-project patches/$PATCH.patch -R 2>/dev/null; then
    echo "Patch $PATCH was already applied"
    return 0
  fi

  # Try fallback if provided
  if [ -n "$FALLBACK" ] && [ -f "patches/$FALLBACK.patch" ]; then
    echo "Primary patch $PATCH failed, trying $FALLBACK as fallback"
    if git apply --check --ignore-space-change --ignore-whitespace --directory llvm-project patches/$FALLBACK.patch 2>/dev/null; then
      git apply --quiet --ignore-space-change --ignore-whitespace --directory llvm-project patches/$FALLBACK.patch
      echo "Successfully applied fallback patch $FALLBACK"
      return 0
    fi

    # Check if fallback already applied
    if git apply --check --ignore-space-change --ignore-whitespace --directory llvm-project patches/$FALLBACK.patch -R 2>/dev/null; then
      echo "Fallback patch $FALLBACK was already applied"
      return 0
    fi
  fi

  echo "ERROR: Failed to apply patch $PATCH and no working fallback found"
  return 1
}

# Function to manually apply async runtime changes if patches fail
apply_async_runtime_changes() {
  local CMAKE_FILE="llvm-project/mlir/lib/ExecutionEngine/CMakeLists.txt"

  if [ ! -f "$CMAKE_FILE" ]; then
    echo "Warning: $CMAKE_FILE not found, skipping async runtime changes"
    return 0
  fi

  echo "Attempting to manually apply async runtime symbol export changes"

  # Check if changes are already applied (looking for commented version)
  if grep -q "#.*set_property(TARGET mlir_async_runtime PROPERTY CXX_VISIBILITY_PRESET hidden)" "$CMAKE_FILE" 2>/dev/null; then
    echo "Async runtime changes already applied"
    return 0
  fi

  # Try to comment out the lines using sed
  if grep -q "set_property(TARGET mlir_async_runtime PROPERTY CXX_VISIBILITY_PRESET hidden)" "$CMAKE_FILE" 2>/dev/null; then
    sed -i.bak 's/^  set_property(TARGET mlir_async_runtime PROPERTY CXX_VISIBILITY_PRESET hidden)/#  set_property(TARGET mlir_async_runtime PROPERTY CXX_VISIBILITY_PRESET hidden)/' "$CMAKE_FILE"
    echo "Commented out CXX_VISIBILITY_PRESET line"
  fi

  if grep -q 'target_link_options(mlir_async_runtime PRIVATE "-Wl,-exclude-libs,ALL")' "$CMAKE_FILE" 2>/dev/null; then
    sed -i.bak 's|^    target_link_options(mlir_async_runtime PRIVATE "-Wl,-exclude-libs,ALL")|#    target_link_options(mlir_async_runtime PRIVATE "-Wl,-exclude-libs,ALL")|' "$CMAKE_FILE"
    echo "Commented out target_link_options line"
  fi

  echo "Manual async runtime changes applied successfully"
  return 0
}

# Function to manually apply OpenMP testing changes if patches fail
apply_openmp_testing_changes() {
  local OPENMP_CMAKE="llvm-project/openmp/CMakeLists.txt"
  local OPENMP_TESTING="llvm-project/openmp/cmake/OpenMPTesting.cmake"

  echo "Attempting to manually apply OpenMP testing changes"

  # Comment out construct_check_openmp_target() if needed
  if [ -f "$OPENMP_CMAKE" ]; then
    if grep -q "#.*construct_check_openmp_target()" "$OPENMP_CMAKE" 2>/dev/null; then
      echo "OpenMP CMakeLists changes already applied"
    elif grep -q "construct_check_openmp_target()" "$OPENMP_CMAKE" 2>/dev/null; then
      sed -i.bak 's/^  construct_check_openmp_target()/#  construct_check_openmp_target()/' "$OPENMP_CMAKE"
      echo "Commented out construct_check_openmp_target() line"
    fi
  fi

  # Comment out ENABLE_CHECK_TARGETS if needed
  if [ -f "$OPENMP_TESTING" ]; then
    if grep -q "#set(ENABLE_CHECK_TARGETS TRUE)" "$OPENMP_TESTING" 2>/dev/null; then
      echo "OpenMP Testing changes already applied"
    elif grep -q "set(ENABLE_CHECK_TARGETS TRUE)" "$OPENMP_TESTING" 2>/dev/null; then
      sed -i.bak 's/^set(ENABLE_CHECK_TARGETS TRUE)/#set(ENABLE_CHECK_TARGETS TRUE)/' "$OPENMP_TESTING"
      echo "Commented out ENABLE_CHECK_TARGETS line"
    fi
  fi

  echo "Manual OpenMP testing changes applied successfully"
  return 0
}

if [[ x"${APPLY_PATCHES:-true}" != x"true" ]]; then
  echo "Skipping patches (APPLY_PATCHES=$APPLY_PATCHES)"
  exit 0
fi

# Apply basic patches
BASIC_PATCHES="\
add_td_to_mlirpythoncapi_headers \
mscv \
"

for PATCH in $BASIC_PATCHES; do
  try_apply_patch "$PATCH" "" || exit 1
done

# Apply async runtime and OpenMP patches with fallback logic
if [ x"$MATRIX_OS" == x"windows-2022" ]; then
  # Windows: only export async symbols
  if ! try_apply_patch "export_async_symbols" "export_async_symbols_21"; then
    echo "Patch application failed, trying manual changes"
    apply_async_runtime_changes || exit 1
  fi
else
  # Non-Windows: try full patch with OpenMP changes, fallback to simpler patches
  if ! try_apply_patch "remove_openmp_dep_on_clang_and_export_async_symbols" "export_async_symbols_21"; then
    echo "All patch attempts failed, trying manual application"
    apply_async_runtime_changes || exit 1
    apply_openmp_testing_changes || exit 1
  fi
fi

# Apply conditional patches
if [ x"$CIBW_ARCHS" == x"wasm32" ]; then
  try_apply_patch "wasm_mlir_opt" "" || exit 1
fi

if [ x"$USE_CMAKE_NAMESPACES" == x"true" ]; then
  try_apply_patch "namespaces" "" || exit 1
fi

if [ x"$MATRIX_OS" == x"macos-13" ]; then
  try_apply_patch "mac_vec" "" || exit 1
fi

echo "All patches applied successfully"
