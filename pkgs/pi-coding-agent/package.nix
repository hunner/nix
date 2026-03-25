{
  lib,
  buildNpmPackage,
  nodejs,
}:
buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  version = "0.62.0";

  src = ./.;
  npmDepsHash = "sha256-zflUWPUrg49y9AUlgdXNasXTj5VUHYx09/GFB4Q5nZ4=";

  inherit nodejs;
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/node_modules/pi-coding-agent-package

    cp -R node_modules package.json package-lock.json $out/lib/node_modules/pi-coding-agent-package/
    ln -s $out/lib/node_modules/pi-coding-agent-package/node_modules/.bin/pi $out/bin/pi

    runHook postInstall
  '';

  meta = {
    description = "Coding agent CLI from the PI ecosystem";
    homepage = "https://www.npmjs.com/package/@mariozechner/pi-coding-agent";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = lib.platforms.unix;
  };
})
