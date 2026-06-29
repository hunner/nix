# Pin ollama to 0.30.11 until nixpkgs-unstable catches up (required for ornith).
final: prev: let
  inherit (prev.unstable) lib fetchFromGitHub;

  llamaCppSrc = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "51eae8cfcac4fb403bcf91d1fb524fec0974f510";
    hash = "sha256-AxMidqvx93b80GqDTgR34RCMdjr/UXDdeztxiXf6sEM=";
  };

  ollamaSrc = fetchFromGitHub {
    owner = "ollama";
    repo = "ollama";
    rev = "d26a58557d83aa8892bdfa79b3550f5ee969cd1c";
    hash = "sha256-RQfRnzk5beJqkrK69f3BxK6QdkoEVTkbgEf1DkB6p1U=";
  };

  bumpOllama = pkg:
    pkg.overrideAttrs (old: {
      version = "0.30.11";
      src = ollamaSrc;
      vendorHash = "sha256-lZdGzGb9xRjTm1Rm7/wHjqM490gLznLEndmb4mNbCX0=";
      postPatch = ''
        substituteInPlace version/version.go \
          --replace-fail 0.0.0 '0.30.11'

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