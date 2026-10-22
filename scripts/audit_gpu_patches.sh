#!/bin/sh

# Audit that all MoltenVK/Vulkan GPU patches are intact after an upstream
# merge. Run this after resolving merge conflicts and BEFORE committing
# the merge (MERGE_GUIDE.md, step "Audit the patches").
#
# Usage:
#   scripts/audit_gpu_patches.sh [upstream-ref]
#
# The upstream ref defaults to ModGPU/main, then OllamaOrigin/main, and
# can be forced with an argument or the UPSTREAM_REF env var.
#
# Checks, in order:
#   1. New GPU files exist in the working tree.
#   2. Files we modify still diverge from the upstream merge base (the
#      patch is present) AND from upstream itself (the merge did not
#      silently resolve our side back to upstream's version).
#   3. Grep invariants: the exact code lines each patch exists to
#      provide are still in the tree.
#
# Exit status: number of failed checks.

set -u

PASS=0
FAIL=0

ok()   { printf '  OK  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "error: not inside a git repository" >&2
    exit 1
}
cd "$REPO"

# --- resolve upstream ref -------------------------------------------------
UPSTREAM="${1:-${UPSTREAM_REF:-}}"
if [ -z "$UPSTREAM" ]; then
    for cand in ModGPU/main OllamaOrigin/main; do
        if git rev-parse --verify --quiet "$cand" >/dev/null; then
            UPSTREAM=$cand
            break
        fi
    done
fi
if [ -z "$UPSTREAM" ] || ! git rev-parse --verify --quiet "$UPSTREAM" >/dev/null; then
    echo "error: upstream ref not found (tried: '$UPSTREAM'). Run 'git fetch ModGPU' first" \
        "or pass a ref: scripts/audit_gpu_patches.sh OllamaOrigin/main" >&2
    exit 1
fi

BASE=$(git merge-base HEAD "$UPSTREAM")
echo "Auditing GPU patches: HEAD=$(git rev-parse --short HEAD) upstream=$UPSTREAM base=$(git rev-parse --short $BASE)"
echo

echo "== New files =="
for f in \
    cmake/OllamaMoltenVK.cmake \
    cmake/OllamaMoltenVKVersion.cmake \
    scripts/build_darwin_vulkan.sh \
    scripts/audit_gpu_patches.sh \
    MERGE_GUIDE.md
do
    if [ -f "$f" ]; then ok "$f exists"; else bad "$f MISSING"; fi
done

echo
echo "== Modified files still carry our divergence =="
# Each must differ from the merge base (patch introduced by us) and from
# upstream (merge did not resolve our side back to upstream's content).
for f in \
    CMakeLists.txt \
    CMakePresets.json \
    cmake/local.cmake \
    llama/server/CMakeLists.txt \
    discover/llama_server.go \
    mlx/dynamic.go \
    README.md \
    .gitignore \
    CLAUDE.md \
    app/assets/app.ico \
    app/assets/setup.bmp \
    app/assets/tray.ico \
    app/assets/tray_upgrade.ico \
    app/darwin/Ollama.app/Contents/Resources/icon.icns
do
    if ! [ -e "$f" ]; then
        bad "$f missing from working tree"
    elif git diff --quiet "$BASE" HEAD -- "$f"; then
        bad "$f: no divergence from merge-base (patch lost before/at merge)"
    elif git diff --quiet "$UPSTREAM" HEAD -- "$f"; then
        bad "$f: identical to upstream (conflict resolved in upstream's favor — patch dropped)"
    else
        ok "$f differs from base and upstream"
    fi
done

echo
echo "== Code invariants =="
# grep_invariant <file> <extended-regex> <description>
grep_inv() {
    if grep -Eq "$2" "$1" 2>/dev/null; then
        ok "$3"
    else
        bad "$3 (pattern '$2' not found in $1)"
    fi
}

grep_inv discover/llama_server.go   'libraryIndex := map\[string\]int\{\}'  "discover: per-library device index present"
grep_inv discover/llama_server.go   'libraryIndex\[library\] = idx \+ 1'    "discover: per-library index increment present"
grep_inv mlx/dynamic.go             'MLX requires Apple Silicon'            "mlx: Intel Mac guard present"
grep_inv CMakeLists.txt             'OLLAMA_FETCH_MOLTENVK'                 "root CMakeLists: MoltenVK option present"
grep_inv CMakeLists.txt             'CMAKE_MODULE_PATH.*cmake'              "root CMakeLists: cmake/ module path present"
grep_inv CMakePresets.json          'OLLAMA_FETCH_MOLTENVK'                 "CMakePresets: MoltenVK preset present"
grep_inv cmake/local.cmake          'ollama_configure_moltenvk'             "local.cmake: MoltenVK configure call present"
grep_inv cmake/local.cmake          'CONFIGURE_ENV'                         "local.cmake: CONFIGURE_ENV threading present"
grep_inv cmake/local.cmake          'OLLAMA_MOLTENVK_SDK_DIR'               "local.cmake: MoltenVK SDK forwarding present"
grep_inv llama/server/CMakeLists.txt  'CMAKE_CROSSCOMPILING'                "llama/server: CMAKE_CROSSCOMPILING fix present"
grep_inv llama/server/CMakeLists.txt  'VULKAN_SDK'                          "llama/server: VULKAN_SDK probing present"
grep_inv cmake/OllamaMoltenVKVersion.cmake  '1\.4\.2'                       "MoltenVK version map has the 1.4.2 entry"
grep_inv scripts/build_darwin_vulkan.sh     'OLLAMA_MOLTENVK_VERSION=1\.4\.2' "build script pins MoltenVK 1.4.2 (1.4.1 = garbage on AMD)"
grep_inv scripts/build_darwin_vulkan.sh     'OllamaGPU\.app'                "build script packages dist/OllamaGPU.app"
grep_inv README.md                  'MoltenVK'                              "README: MoltenVK section present"
grep_inv .gitignore                 '^\.claude/$'                           ".gitignore: .claude/ entry present"
grep_inv .gitignore                 'app/assetsOrig'                        ".gitignore: app/assetsOrig/ entry present"

echo
printf 'Audit complete: %d passed, %d FAILED\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "Do NOT commit the merge until every FAIL above is resolved (see MERGE_GUIDE.md)."
fi
exit "$FAIL"
