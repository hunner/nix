{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
}:

stdenvNoCC.mkDerivation rec {
  pname = "xai-grok";
  version = "0.2.38";

  src = fetchurl {
    url = "https://registry.npmjs.org/@xai-official/grok-linux-x64/-/grok-linux-x64-${version}.tgz";
    hash = "sha256-E023XTq3PwPH2zBuOh4jFoUh08o6p4IPfX0x7KFUleE=";
  };

  nativeBuildInputs = [ nodejs ];

  unpackPhase = ''
    tar -xzf $src
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    node -e "const fs=require('fs'),z=require('zlib'); const b=z.brotliDecompressSync(fs.readFileSync('package/bin/grok.br')); fs.writeFileSync('$out/bin/grok', b, {mode:0o755});"

    runHook postInstall
  '';

  meta = {
    description = "Official xAI Grok Build CLI";
    homepage = "https://x.ai/cli";
    license = lib.licenses.unfree;
    mainProgram = "grok";
    platforms = [ "x86_64-linux" ];
  };
}
