{
  buildGoModule,
  src,
  rev,
  goVersion,
}:

buildGoModule {
  pname = "squire";
  # Upstream publishes no tags, so this is the Go pseudo-version derived from
  # the locked revision.
  version = goVersion;

  inherit src;

  # The repo builds several binaries; only the CLI is wanted here.
  subPackages = [ "cmd/squire" ];

  vendorHash = "sha256-oOXULqHqsGtMLy3MLDpeJWPO57Gi0lPv4r9Po72ZO1s=";

  # Upstream's Makefile stamps these. `go install` gets a version string for
  # free from the module cache, but buildGoModule compiles a plain source tree
  # with no VCS metadata, and without the stamp `squire version` reports
  # "Client: dev" where the hand-installed binary reports the pseudo-version.
  ldflags = [
    "-X main.Version=${goVersion}"
    "-X main.Commit=${rev}"
  ];

  # Upstream is private but depends on nothing private itself, so the module
  # graph resolves from the public proxy like any other Go program.

  meta = {
    description = "Squire CLI for ephemeral development environments";
    homepage = "https://github.com/ductone/squire";
    mainProgram = "squire";
  };
}
