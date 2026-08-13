# Pin ollama to 0.32.9 until nixpkgs-unstable catches up (required for muse-glimmer).
# nixpkgs-unstable is currently 0.32.7; muse needs GlimmerParser (tools/thinking) from 0.32.8+.
final: prev: let
  inherit (prev.unstable) lib fetchFromGitHub;

  version = "0.32.9";

  # Matches ollama's LLAMA_CPP_VERSION for v0.32.9 (muse-glimmer needs b10353+).
  llamaCppVersion = "b10353";
  llamaCppSrc = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = llamaCppVersion;
    hash = "sha256-MQP91lL8zQLYcnYw5GlkMvH5sXiES+C6L4/1G3Y6TPY=";
  };

  ollamaSrc = fetchFromGitHub {
    owner = "ollama";
    repo = "ollama";
    rev = "v${version}";
    hash = "sha256-6BDUXDF5pXL3stffvtNJOnhC0A1xjPv43ZpsxegXm4w=";
  };

  # Same go deps as nixpkgs 0.32.7 (go.mod unchanged across 0.32.7–0.32.9).
  vendorHash = "sha256-HMwoaFBMbpoy8f0I+O+i7kIa9BslLu3FcVWeaIOkpvs=";

  bumpOllama = pkg:
    pkg.overrideAttrs (old: {
      inherit version;
      src = ollamaSrc;
      inherit vendorHash;
      postPatch = ''
        substituteInPlace version/version.go \
          --replace-fail 0.0.0 '${version}'

        rm cmd/launch/*_test.go
        rm -r app

        cp -r ${llamaCppSrc} $TMPDIR/llama-cpp-src
        chmod -R +w $TMPDIR/llama-cpp-src
        ( cd $TMPDIR/llama-cpp-src && \
          cmake -DPATCH_DIR=$NIX_BUILD_TOP/source/llama/compat \
            -P $NIX_BUILD_TOP/source/llama/compat/apply-patch.cmake )
      '';
    });
in {
  unstable = prev.unstable // {
    ollama-vulkan = bumpOllama prev.unstable.ollama-vulkan;
  };
}
