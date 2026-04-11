{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "lean-ctx";
  version = "2.21.6";

  src = fetchFromGitHub {
    owner = "yvgude";
    repo = "lean-ctx";
    rev = "40b840c548a40d03fe91d5aa412fc7c92da4b9e0";
    hash = "sha256-3/YAmN4iO7cngj2DbXm9vAutxiz483qf7a81odxQOl8=";
  };

  sourceRoot = "${finalAttrs.src.name}/rust";

  cargoLock = {
    lockFile = "${finalAttrs.src}/rust/Cargo.lock";
  };

  # Upstream's test suite exercises shell/sandbox behavior and is not stable
  # under Nix builds, but the release binary itself builds fine.
  doCheck = false;

  meta = {
    description = "Context Intelligence Engine with CCP";
    homepage = "https://github.com/yvgude/lean-ctx";
    license = lib.licenses.mit;
    mainProgram = "lean-ctx";
    platforms = lib.platforms.linux;
  };
})
