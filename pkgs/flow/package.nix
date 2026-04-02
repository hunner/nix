{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  nodejs_20,
  pnpm_10,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "flow";
  version = "unstable-2026-03-28";

  src = fetchFromGitHub {
    owner = "pacexy";
    repo = "flow";
    rev = "36f3cc7c4581f62ff6d72b75641c674020bb1e9f";
    hash = "sha256-Bro3DrYNtBvPKCOJBZMb7EBRrAnsC/3QIdKnLvo6FJA=";
  };

  pnpmDeps = pnpm_10.fetchDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 3;
    pnpm = pnpm_10;
    hash = "sha256-+m5PTXjmSQcH98T3MmrBRds8JBCHiq0qmRP3JjISUAc=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_20
    pnpm_10.configHook
  ];

  env = {
    DOCKER = "1";
    NEXT_TELEMETRY_DISABLED = "1";
  };

  postPatch = ''
    # Upstream currently imports `@flow/reader/locales`, but the tsconfig path
    # aliases only cover `apps/reader/src/*`, which breaks clean production
    # builds from source.
    sed -i '/"@flow\/reader\/\*"/a\      "@flow/reader/locales": ["apps/reader/locales/index.ts"],' tsconfig.json
  '';

  buildPhase = ''
    runHook preBuild

    pnpm --offline --filter reader build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/flow

    cp -R apps/reader/.next/standalone/. $out/share/flow/
    mkdir -p $out/share/flow/apps/reader/.next
    cp -R apps/reader/.next/static $out/share/flow/apps/reader/.next/static
    cp -R apps/reader/public $out/share/flow/apps/reader/public

    makeWrapper ${lib.getExe nodejs_20} $out/bin/flow \
      --add-flags $out/share/flow/apps/reader/server.js

    runHook postInstall
  '';

  meta = {
    description = "Browser-based ePub reader";
    homepage = "https://github.com/pacexy/flow";
    license = lib.licenses.agpl3Only;
    mainProgram = "flow";
    platforms = nodejs_20.meta.platforms;
  };

  dontCheckForBrokenSymlinks = true;
})
