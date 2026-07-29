#!/bin/bash -eu
#
# Build script for ClusterFuzzLite / Fenrir.
# Builds all fuzz targets using CFL environment variables.
#
# Environment (provided by CFL):
#   SRC    - source root directory (working directory)
#   OUT    - output directory for fuzz targets
#   CC, CXX, CFLAGS, CXXFLAGS
#   LIB_FUZZING_ENGINE
#
# This build is hermetic: all third-party dependencies are vendored
# in third_party/ and built from source. No network access is required.

# ---- Locate project root ----
PROJECT_DIR="${SRC:-$(pwd)}"
if [[ ! -f "${PROJECT_DIR}/CMakeLists.txt" ]]; then
    echo "Error: CMakeLists.txt not found in ${PROJECT_DIR}" >&2
    exit 1
fi

BUILD_DIR="${PROJECT_DIR}/build_fuzz"

# ---- Configure ----
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

FUZZER_FLAG="${LIB_FUZZING_ENGINE:--fsanitize=fuzzer}"

cmake "${PROJECT_DIR}" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER="${CC:-clang}" \
    -DCMAKE_CXX_COMPILER="${CXX:-clang++}" \
    -DCMAKE_C_FLAGS="${CFLAGS:--g -O1}" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS:--g -O1}" \
    -DFUZZER_ENGINE_FLAG="${FUZZER_FLAG}" \
    -DNEBULA_BUILD_TESTS=OFF \
    -DNEBULA_BUILD_FUZZ=ON

# ---- Build ----
make -j"$(nproc)"

# ---- Install fuzz targets ----
FUZZ_TARGETS=(
    archive_parser_fuzzer
    compression_fuzzer
    index_fuzzer
    journal_fuzzer
    metadata_fuzzer
)

for target in "${FUZZ_TARGETS[@]}"; do
    binary="${BUILD_DIR}/fuzz/${target}"
    if [[ -x "${binary}" ]]; then
        cp "${binary}" "${OUT}/"
        echo "  Installed ${target}"
    else
        echo "  Warning: ${target} binary not found at ${binary}" >&2
    fi
done

# ---- Package seed corpora (per-harness) ----
# Fenrir auto-discovers fuzz/corpus/ at the repo root,
# but we also emit zip archives per OSS-Fuzz convention.
SEED_BASE="${PROJECT_DIR}/fuzz/corpus"
for target in "${FUZZ_TARGETS[@]}"; do
    target_seeds="${SEED_BASE}/${target}"
    if [[ -d "${target_seeds}" ]]; then
        # Copy raw seeds for CFL auto-packaging
        mkdir -p "${OUT}/seeds/${target}"
        cp -r "${target_seeds}/"* "${OUT}/seeds/${target}/" 2>/dev/null || true

        # Create zip for OSS-Fuzz compatibility (if zip is available)
        if command -v zip &>/dev/null; then
            zip_path="${OUT}/${target}_seed_corpus.zip"
            (cd "${target_seeds}" && zip -q "${zip_path}" ./*) 2>/dev/null || true
        fi
    fi
done

echo "Build complete. Output in ${OUT}:"
ls -la "${OUT}/" 2>/dev/null || true
