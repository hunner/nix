# The Squire CLI, previously run out of a direnv `go install` in
# ~/work/git/squire-cli/.direnv/go/bin. Building it here puts it in the system
# closure instead, which is also what lets Squire Village find it: the app
# searches /run/current-system/sw/bin, and a bundle opened from the Dock never
# sees a direnv environment.
{
  pkgs,
  squireCliSrc,
  ...
}:
let
  # Reconstruct the Go pseudo-version from the flake input rather than writing
  # one down, so it stays true across `nix flake update squire-cli`. Go's form
  # is v0.0.0-<UTC commit time>-<first 12 of the revision>, which is exactly
  # what lastModifiedDate and rev carry.
  goVersion = "v0.0.0-${squireCliSrc.lastModifiedDate}-${builtins.substring 0 12 squireCliSrc.rev}";

  # go_latest rather than the default go: upstream's go.mod tracks new Go
  # releases closely and already asks for 1.27.1, while pkgs.go is 1.26.7.
  # buildGoModule sets GOTOOLCHAIN=local, so a go.mod that outruns the compiler
  # fails the build outright rather than downloading a toolchain. Following
  # nixpkgs' newest keeps that from needing a manual bump every time upstream
  # moves, which is the point of tracking the default branch.
  squire = pkgs.callPackage ./package.nix {
    buildGoModule = pkgs.buildGoModule.override { go = pkgs.go_latest; };
    src = squireCliSrc;
    inherit goVersion;
    rev = squireCliSrc.rev;
  };
in
{
  environment.systemPackages = [ squire ];
}
