# Squire Village, taken from the package the project's own flake exposes rather
# than packaged again here, so the bundle is the one upstream builds and tests.
#
# That derivation needs nix running unsandboxed, because upstream's
# scripts/build.sh calls codesign, iconutil, and ditto. slice has
# `sandbox = false`.
{
  pkgs,
  squireVillage,
  ...
}:
let
  squire-village = squireVillage.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # Puts `village` on PATH and the bundle in /run/current-system/sw/Applications,
  # which nix-darwin surfaces as "Nix Apps" in /Applications, so Spotlight and
  # the Dock find it.
  #
  # The app locates the Squire CLI at /run/current-system/sw/bin/squire, which
  # the squire-cli module puts there. That path matters rather than PATH because
  # a bundle opened from the Dock inherits launchd's environment, not a shell's.
  environment.systemPackages = [ squire-village ];
}
