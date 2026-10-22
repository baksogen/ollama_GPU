# Known MoltenVK release versions and their SHA256 checksums.
# Used when OLLAMA_FETCH_MOLTENVK=ON and the default MoltenVK URL is used.
# Format: version sha256 (pairs)
#
# To add a new version, download the MoltenVK-macos.tar from the KhronosGroup
# release page and compute the SHA256:
#   shasum -a 256 MoltenVK-macos.tar
set(OLLAMA_MOLTENVK_RELEASE_SHA256_MAP
    1.4.1    5ea0c259df7ded9a275444820f09cced54d6e5a7c7a31d262de62a5cdb7e15cf
    # 1.4.2 fixes AMD maxSubgroupSize (64 -> 32): Metal simdgroup ops on AMD
    # produce wrong results when the shader assumes 64-wide subgroups, which
    # corrupted llama.cpp Vulkan output (FA scalar + gated delta net paths).
    # See KhronosGroup/MoltenVK#2755 and ggml-org/llama.cpp#20029.
    1.4.2    f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e
)