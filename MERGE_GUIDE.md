# Merge Guide — MoltenVK Intel Mac GPU Support

This file is a runbook for merging upstream Ollama updates into the
`feature/moltenvk-intel-amd` branch while preserving the GPU support
patches. When the user asks to "follow MERGE_GUIDE.md", "merge
upstream", or "update from Ollama", execute the workflow below.

## Branch and remote layout

| Remote | URL | Role |
|--------|-----|------|
| `ModGPU` / `OllamaOrigin` | `https://github.com/ollama/ollama.git` | upstream Ollama (fetch updates from here) |
| `origin` | `https://github.com/baksogen/ollama_GPU.git` | user's fork (push here) |
| `x86-GPU` | `https://github.com/jamfor999/ollama.git` | reference fork the MoltenVK port was based on |

Working branch: `feature/moltenvk-intel-amd`
Upstream branch: `ModGPU/main` (or `OllamaOrigin/main`)

## GPU support patches to preserve

These are the files that carry the MoltenVK/Vulkan + Intel Mac
patches. They must survive the merge — if upstream touches the same
regions, resolve in favor of keeping the GPU logic and re-applying
upstream's non-conflicting changes on top.

### New files (no conflict expected unless upstream adds a same-named file)
- `cmake/OllamaMoltenVK.cmake` — MoltenVK download with SHA256 verification
- `cmake/OllamaMoltenVKVersion.cmake` — pins MoltenVK version (currently 1.4.1)
- `scripts/build_darwin_vulkan.sh` — full build + packaging script for the Vulkan/MoltenVK variant

### Modified files (likely conflict zones)
- `CMakeLists.txt` — adds `OLLAMA_FETCH_MOLTENVK` option and `cmake/` to module path
- `CMakePresets.json` — adds a Vulkan/MoltenVK preset
- `cmake/local.cmake` — calls `ollama_configure_moltenvk()` and threads `VULKAN_SDK` / `Vulkan_INCLUDE_DIR` / `Vulkan_LIBRARY` into the nested llama-server build via `CONFIGURE_ENV`
- `llama/server/CMakeLists.txt` — adds `CONFIGURE_ENV` argument to `ollama_add_llama_server_build`, passes Vulkan env to the ExternalProject subprocess
- `discover/llama_server.go` — **per-library device index** instead of a global counter (the key runtime fix; without it, skipping BLAS pseudo-devices drifts the index and Vulkan0 gets `GGML_VK_VISIBLE_DEVICES=1`, which the backend rejects, falling back to CPU)
- `x/mlxrunner/mlx/dynamic.go` — skips MLX dynamic load on `darwin/amd64` and sets `initError` so `CheckInit()` reports MLX unavailable (MLX Metal requires Apple Silicon)
- `README.md` — documents the experimental MoltenVK build
- `.gitignore` — ignores `.claude/` and `app/assetsOrig/`
- `app/assets/{app,tray,tray_upgrade}.ico` + `app/assets/setup.bmp` — updated icons for the modified build

## Merge workflow

### 1. Pre-flight checks
```sh
git status                          # must be clean
git branch --show-current           # must be feature/moltenvk-intel-amd
git fetch ModGPU                    # or: git fetch OllamaOrigin
```
If the working tree is dirty, stash or commit before proceeding.

### 2. Create a merge branch (safety net)
```sh
git checkout -b merge/upstream-$(date +%Y%m%d)
```
This keeps `feature/moltenvk-intel-amd` untouched until the merge is verified.

### 3. Merge upstream main
```sh
git merge ModGPU/main --no-edit
```
Prefer a merge commit over a rebase — the branch has 13+ commits and
rebase would rewrite history, requiring a force-push to `origin`.

### 4. Resolve conflicts

Use the per-file guidance below. After resolving each file:
```sh
git add <file>
git status   # confirm no remaining conflicts for that file
```

#### `discover/llama_server.go` — highest priority
The critical change is in `parseLlamaServerDevicesWithNative`: the
device loop uses `libraryIndex := map[string]int{}` (per-library
counter) instead of a single `deviceIndex` integer. The per-library
counter must NOT increment when a 0 MiB pseudo-device (BLAS) is
skipped, and must increment per-library only when a real device is
appended or a CUDA device is skipped due to arch mismatch.

If upstream refactors this function, re-apply the pattern:
- Replace any global `deviceIndex` with `libraryIndex[library]`
- `idx := libraryIndex[library]` is read after the 0 MiB skip block
- All map lookups (`ccByIndex`, `gfxByIndex`, `integratedByIndex`,
  `nativeByIndex`) use `idx`, not a global counter
- `deviceIndex++` at loop end becomes `libraryIndex[library] = idx + 1`

#### `x/mlxrunner/mlx/dynamic.go`
The `init()` function has an early return on `darwin/amd64` that sets
`initError = fmt.Errorf("MLX requires Apple Silicon (not available on Intel Mac)")`.
This must stay so `CheckInit()` returns an error and the mlxrunner
(plus tests) skip cleanly instead of crashing on NULL function pointers.

If upstream changes `init()`, keep the guard immediately after the
`switch runtime.GOOS` block and before `findMLXLibrary`.

#### `cmake/local.cmake` + `llama/server/CMakeLists.txt`
These carry the `ollama_configure_moltenvk()` call and the
`CONFIGURE_ENV` argument on `ollama_add_llama_server_build`. The
env threading is necessary because ExternalProject subprocesses
don't reliably inherit env vars set during the parent configure step.

If upstream renames `ollama_add_llama_server_build` or restructures
the function, port the `CONFIGURE_ENV` parameter and the
`VULKAN_SDK` / `Vulkan_INCLUDE_DIR` / `Vulkan_LIBRARY` forwarding
to the new signature.

#### `CMakeLists.txt` (root)
Keep the `OLLAMA_FETCH_MOLTENVK` option declaration and
`list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)` line.

#### `CMakePresets.json`
Keep the Vulkan/MoltenVK preset. If upstream restructures presets,
add the Vulkan preset back as a new entry.

#### `README.md`
Keep the "Experimental MoltenVK build" section. If upstream
restructures the README, re-add the section in an appropriate place.

#### `.gitignore`
Keep `.claude/` and `app/assetsOrig/` entries.

#### `app/assets/*` (binary)
These are the user's custom icons. If upstream changes the same
icons, keep the user's versions (they are the point of the fork's
branding). Use `git checkout --ours -- app/assets/` during the
merge if needed.

### 5. Verify the merge compiles
```sh
go build ./discover/ ./x/mlxrunner/...
go test ./discover/ ./x/mlxrunner/...
go build .
```
If any package fails to build, the conflict resolution missed
something — re-examine the affected files.

### 6. Fast-forward the feature branch
Once the merge branch builds and tests pass:
```sh
git checkout feature/moltenvk-intel-amd
git merge --ff-only merge/upstream-$(date +%Y%m%d)
git branch -d merge/upstream-$(date +%Y%m%d)
```

### 7. Push
```sh
git push origin feature/moltenvk-intel-amd
```
Do NOT push to `ModGPU` or `OllamaOrigin` — those are upstream.

## Post-merge build (full app bundle)

```sh
./scripts/build_darwin_vulkan.sh
```
This builds both arches (arm64 + amd64), merges the amd64 Vulkan
payload, creates the universal binary, and packages `Ollama.app`
into `dist/`. The script handles:
- MoltenVK fetch + SHA256 verification (pinned to 1.4.1)
- Vulkan backend build via `OLLAMA_LLAMA_BACKENDS=vulkan`
- MLX disabled (`OLLAMA_MLX_BACKENDS=` empty)
- Stale MLX library filtering in `_merge_darwin_payload`
- Universal binary creation via `lipo`
- Optional code signing if `APPLE_IDENTITY` is set

For quick Go-only iteration against an already-built native payload:
```sh
go build .
./ollama serve
```

## Verification checklist

After the merge and build, verify:

1. **Device discovery** — `llama-server --list-devices --offline` shows
   `Vulkan0: AMD Radeon ...` with nonzero MiB.
2. **No MLX errors** — `~/.ollama/logs/server.log` should NOT contain
   `CHECK failed: mlx_array_new_data_managed_`.
3. **No invalid Vulkan index** — the log should NOT contain
   `ggml_vulkan: Invalid device index`.
4. **GPU inference** — load a GGUF model and check `inference compute`
   log line shows `library=Vulkan` (not CPU). The `filter_id` should
   match the per-library Vulkan index (0 for a single GPU).
5. **App bundle** — `dist/Ollama.app/Contents/Resources/` contains
   `libMoltenVK.dylib` and `libggml-vulkan.so` but NOT `libmlx.dylib`
   or `libmlxc.dylib`.

## Quick reference: the 13 GPU commits

```
4908338f cmake: add experimental MoltenVK support for Intel Mac AMD GPUs
349255e8 scripts: add build_darwin_vulkan.sh for Intel Mac AMD GPU builds via MoltenVK
ea54ea1f README: document experimental MoltenVK build for Intel Mac AMD GPUs
9366f37a gitignore: ignore ggml-vulkan ExternalProject prefix directories
41c2e21f scripts: pin MoltenVK version in build_darwin_vulkan.sh
06965e99 llama/server: set CMAKE_CROSSCOMPILING for single-arch macOS builds
5a8d4eb1 scripts: handle vulkan subdir in build_darwin_vulkan payload merge
0c26fc08 discover: key device index per-library instead of globally
4918a88e mlx: skip dynamic library load on Intel Mac
fd51266c scripts: exclude stale MLX libraries from Vulkan build payload
fe7c9d23 app: update icons for the MoltenVK Intel Mac variant
2ede7167 CLAUDE.md: expand build, test, lint, and architecture guidance
292ecf2a gitignore: ignore .claude/ and app/assetsOrig/
```

If a merge goes wrong and you need to identify which GPU patch
touched a specific line: `git log --oneline 4908338f~1..HEAD -- <file>`.