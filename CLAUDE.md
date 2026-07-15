# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See `AGENTS.md` for the shared agent build instructions. See `docs/development.md` for full platform/build prerequisites and `llama/README.md` for the llama.cpp update workflow.

## Build

Full build (configures native code via CMake, then builds Go binary at repo root with native payload under `build/lib/ollama`):

```sh
cmake -B build .
cmake --build build --parallel 8
./ollama serve
```

Quick Go-only iteration against an already-built native payload:

```sh
go build .
go run . serve
```

If CGO data structures have drifted and you see unexpected crashes, force a clean native rebuild with `go clean -cache` before rebuilding.

Select GPU backends (defaults to Metal on macOS arm64, CPU-only elsewhere):

```sh
cmake -B build . -DOLLAMA_LLAMA_BACKENDS="cuda_v13;vulkan"
```

Supported `OLLAMA_LLAMA_BACKENDS` values: `cuda_v12`, `cuda_v13`, `rocm_v7_1`, `rocm_v7_2`, `vulkan`, `cuda_jetpack5`, `cuda_jetpack6`. Narrow to local hardware with `-DCMAKE_CUDA_ARCHITECTURES=native` or `-DCMAKE_HIP_ARCHITECTURES=gfx1100`. Tune GGML with `GGML_*` cache vars (e.g. `-DGGML_CUDA_FA=OFF`).

MLX engine (optional, safetensor models; enabled by default on macOS arm64):

```sh
cmake -B build . -DOLLAMA_MLX_BACKENDS=cuda_v13   # or metal_v3;metal_v4 via "MLX Metal" preset
```

Local MLX/MLX-C source overrides: set `OLLAMA_MLX_SOURCE` and `OLLAMA_MLX_C_SOURCE` before configuring.

Install to a prefix: `cmake --install build --prefix /path/to/install`. Docker: `docker build .` (or `--build-arg FLAVOR=rocm`).

Native library discovery looks in (in order): `../lib/ollama`, `./lib/ollama`, `.`, `build/lib/ollama`, `dist/<platform>/lib/ollama`. Missing libraries silently disable acceleration.

## Test

Unit tests (default `go test` excludes integration):

```sh
go test ./...
```

Run a single test: `go test ./server -run TestName -v` (or `-run TestName/Subtest`).

Integration tests are gated by build tags and require a freshly built `ollama` binary at the repo root (`go build .` first):

```sh
go build .
go test -tags=integration ./...
```

Tag combinations (use `find integration -type f | xargs grep "go:build"` to see the current set):

- `-tags=integration` — basic suite
- `-tags=integration,models` — broad model matrix (long; ~60m+)
- `-tags=integration,perf` — performance tests
- `-tags=integration,library` — public library model tests
- `-tags=integration,imagegen` — image generation
- `-tags=integration,generate` — Jinja/generate paths

Other integration flags:

- `OLLAMA_TEST_EXISTING=1` — run against an existing server (honors `OLLAMA_HOST`, may be remote)
- `OLLAMA_TEST_LOG_SERVER=1` — print the managed server log after each test
- `OLLAMA_TEST_MODEL=<model>` — run the suite against a specific model (use when validating a new architecture)
- On Windows, the managed server always uses `OLLAMA_HOST`; on Unix it picks a random port.

## Lint

`golangci-lint run` (config in `.golangci.yaml`). Formatters `gofmt`+`gofumpt` are enforced.

## Architecture

Ollama is a Go service that wraps llama.cpp (and MLX) as out-of-process inference engines. The Go binary hosts an HTTP server and a CLI; native inference runs in a separate `llama-server` subprocess spawned per loaded model.

### Request flow

`main.go` → `cmd.NewCLI()` (cobra) → for `serve`, `server.Serve()` starts a gin HTTP server on `OLLAMA_HOST` (default `127.0.0.1:11434`). Per-request:

1. `server/routes.go` handles `/api/*` (Ollama native), `openai/openai.go` handles `/v1/*` (OpenAI-compatible), `middleware/` adapts OpenAI/Anthropic-shaped requests to the internal ChatRequest.
2. `server/model_resolver.go` resolves model name → manifest → GGUF file under `OLLAMA_MODELS`.
3. `server/sched.go` (the Scheduler in `llm/`) picks or loads a `LlamaServer` instance for the model; multiple loaded models are managed as runners with VRAM accounting and GPU selection from `discover/`.
4. The chosen `LlamaServer` (`llm/llama_server.go`) talks to the `llama-server` subprocess over a localhost HTTP protocol; streaming SSE is parsed back into Ollama's response shape.

### Package map

- `api/` — Go client + request/response types for the native REST API.
- `cmd/` — cobra CLI: `serve`, `run`, `pull`, `push`, `create`, `show`, `list`, `ps`, `cp`, `rm`, `stop`, `signin`/`login`, `signout`/`logout`, `agent`, `runner`, `gpu-discover`, plus `launch <integration>` (Claude Code, Codex, Copilot, etc. — see `cmd/launch/`).
- `cmd/tui/` — Bubbletea-based interactive selectors and the run/agent TUI.
- `server/` — HTTP handlers, model manifests, blob store, quantization, model recommendation, cloud proxy, prompt assembly.
- `openai/`, `middleware/openai.go`, `middleware/anthropic.go`, `anthropic/` — OpenAI- and Anthropic-compatible facades over the internal API.
- `llm/` — `LlamaServer` interface, subprocess lifecycle, memory accounting, platform-specific library loading (`llm_darwin.go`, `llm_linux.go`, `llm_windows.go`).
- `discover/` — GPU/CPU detection (CUDA, ROCm, Vulkan, Metal) and runner selection; consumed by the scheduler.
- `ml/` — abstract device/SystemInfo types used to negotiate backends with `llama-server`.
- `envconfig/` — all `OLLAMA_*` env vars (see below).
- `model/parsers/`, `model/renderers/` — per-architecture parsing of model-specific reasoning/tool token streams and rendering of chat templates into the model's expected format (e.g. `gemma4`, `qwen3`, `glm47`, `cogito`, `cohere`, `deepseek3`, `nemotron3nano`, `olmo3`, `lfm2`, `laguna`).
- `convert/` — per-architecture safetensors/PyTorch → GGUF conversion (one file per family, e.g. `convert_gemma3.go`, `convert_llama4.go`, `convert_qwen3vl.go`).
- `template/` — Go-template chat templates (`*.gotmpl` + `*.json` pairs) for older models; modern models use `model/renderers/`.
- `thinking/` — `<think>`-style reasoning block parsing/templating.
- `tools/` — function/tool-call template rendering and parsing.
- `harmony/` — harmony-format parser used by gpt-oss.
- `fs/ggml`, `fs/gguf` — readers for the GGML/GGUF file formats.
- `manifest/` — manifest parsing/writing for the model store.
- `x/` — experimental subsystems (`create/` local model building, `imagegen/`, `mlxrunner/`, `quant/`, `safetensors/`, `transfer/`, `models/`, `server/`).
- `app/` — separate macOS/Windows desktop app (built via `go generate ./... && go run ./cmd/app`, see `app/README.md`).
- `scripts/` — per-platform build/packaging scripts (`build_darwin.sh`, `build_linux.sh`, `build_windows.ps1`, `install.sh`, `install.ps1`).

### Native build model

The root `CMakeLists.txt` orchestrates; `cmake/local.cmake` holds backend-specific rules; `llama/server/CMakeLists.txt` FetchContent-pins `llama.cpp` to `LLAMA_CPP_VERSION` and applies patches from `llama/compat/` during configure. `MLX_VERSION` / `MLX_C_VERSION` pin MLX. CPU/GPU/Metal presets live in `llama/server/CMakePresets.json` (e.g. `cpu`, `darwin`, `llama_cuda_v13_linux`, `rocm_v7_2_linux`, `vulkan`). Each GPU backend installs into a per-backend subdir (`lib/ollama/cuda_v13/`, `lib/ollama/rocm_v7_2/`, …) and the scheduler picks one at runtime based on `discover/` output.

### Updating llama.cpp

Pinned by `LLAMA_CPP_VERSION`. To update: bump the version, run `cmake -S llama/server --preset cpu` to fetch+patch the source, then `git diff <old-ref> <new-ref> -- <path>` against the pristine upstream checkout (not the patched `_deps/` tree). Review: build options, GGML symbols used by `discover/native_probe*.go`, llama-server launch args / status payloads / log lines consumed by `llm/llama_server.go` and `server/sched.go`, streaming frame shape, model/conversion surfaces. If `llama/compat/` patches no longer apply cleanly, regenerate against a fresh checkout of the new ref. Build the CPU target (`cmake --build build/llama-server-cpu --target llama-server --parallel 12`), run `go test ./...`, then run the full integration suite on each platform. See `llama/README.md` for the full checklist.

## Environment variables

All defined in `envconfig/config.go` (call `envconfig.AsMap()` at runtime for the full list). Key ones:

| Var | Default | Purpose |
|-----|---------|---------|
| `OLLAMA_HOST` | `127.0.0.1:11434` | Bind scheme+host+port for the server |
| `OLLAMA_MODELS` | `$HOME/.ollama/models` | Model manifest/blob directory |
| `OLLAMA_ORIGINS` | — | Extra allowed CORS origins |
| `OLLAMA_KEEP_ALIVE` | `5m` | How long models stay loaded |
| `OLLAMA_NUM_PARALLEL` | `1` | Parallel requests per model |
| `OLLAMA_MAX_LOADED_MODELS` | `0` (auto) | Max simultaneously loaded models |
| `OLLAMA_MAX_QUEUE` | `512` | Max queued requests |
| `OLLAMA_CONTEXT_LENGTH` | auto (4k/32k/256k by VRAM) | Default context length |
| `OLLAMA_KV_CACHE_TYPE` | `f16` | KV cache quantization |
| `OLLAMA_FLASH_ATTENTION` | `true` | Enable flash attention |
| `OLLAMA_SCHED_SPREAD` | `false` | Spread model across all GPUs |
| `OLLAMA_VULKAN` | `true` | Enable Vulkan backend |
| `OLLAMA_IGPU_ENABLE` | `true` | Enable integrated GPUs |
| `OLLAMA_LLM_LIBRARY` | — | Force a specific backend library (bypasses autodetect) |
| `OLLAMA_NO_CLOUD` | `false` | Disable cloud (remote inference + web search) |
| `OLLAMA_AUTH` | `false` | Require auth |
| `OLLAMA_DEBUG` | `false` | Verbose logging |
| `OLLAMA_DEBUG_LOG_REQUESTS` | `false` | Log inference request bodies + curl replays to tmpdir |
| `OLLAMA_GO_TEMPLATE` | `false` | Use Go templates instead of model-native renderers |
| `OLLAMA_NOHISTORY` / `OLLAMA_NOPRUNE` | `false` | Disable history / prune behavior |
| `OLLAMA_GPU_OVERHEAD` | `0` | Reserve VRAM (bytes) when computing fit |
| `OLLAMA_EXPERIMENT` | — | Comma-separated experiment flags (e.g. `client2`) |
| `OLLAMA_LOAD_TIMEOUT` | — | Stall-detection timeout for model loads |
| `OLLAMA_REMOTES` | — | Remote backends |
| `OLLAMA_EDITOR` | — | Editor for `ollama create` Modelfile editing |
| `OLLAMA_MAX_TRANSFER_STREAMS` | `4` | Parallel pull streams |

## Conventions

- Commit title: `<package>: <short description>` where `<package>` is the most-affected Go package (or directory name if no Go code). Description starts lowercase and completes the sentence "This changes Ollama to…". Examples: `llm/backend/mlx: support the llama architecture`, `CONTRIBUTING: provide clarity on good commit messages`. Avoid `feat:`/`fix:`/`chore:` prefixes.
- Don't break the public REST API or the OpenAI-compatible API. New API fields / env vars add long-term maintenance surface. Open an issue first for non-trivial changes.
- Add new deps sparingly and explain why. Tests should assert behavior, not implementation.
- Class files / source modules: keep under ~200 lines where possible; split large classes into logically complete modules.