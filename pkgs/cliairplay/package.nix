# cliairplay — Music Assistant's unified AirPlay 1 (RAOP) + AirPlay 2 sender.
#
# This is the only actively maintained Linux sender that speaks *native*
# AirPlay 2: HomeKit pairing, encrypted RTSP, binary-plist SETUP,
# ChaCha20-Poly1305 audio and a PTP grandmaster. PipeWire's own
# module-raop-sink only speaks AirPlay 1, which current HomePod firmware
# (HomePod OS 26) refuses.
#
# Upstream vendors its dependencies as git submodules that carry *prebuilt*
# static archives for every platform. Two of those are needed on Linux
# (libcodecs, libmdns); the rest are either headers-only or unused here. The
# largest submodule by far is libopenssl (~680 MB of prebuilt OpenSSL for
# every target), which is skipped entirely: the build links nixpkgs' own
# OpenSSL instead, via `OPENSSL=` pointing at its headers and `-lcrypto` from
# buildInputs.
{
  lib,
  stdenv,
  fetchFromGitHub,
  openssl,
}:
let
  # Submodule revisions, from `git submodule status` at the airplay-cli tag.
  libraop = fetchFromGitHub {
    owner = "philippe44";
    repo = "libraop";
    rev = "81c2182649da8645ac2a58b78e9f370c79a4165b";
    hash = "sha256-c4HTlnjNKc9MrYaRkdmY/AMXRf/q+e1k5X1Q61mqO60=";
  };

  crosstools = fetchFromGitHub {
    owner = "philippe44";
    repo = "crosstools";
    rev = "41544c653760a205cbf6cebfdeda4a9394cc6455";
    hash = "sha256-jzEqDqvN4bxIiD8OdLZObN8OqIdaSZFZ0k5ggc2Ttjs=";
  };

  dmap-parser = fetchFromGitHub {
    owner = "philippe44";
    repo = "dmap-parser";
    rev = "2f8ee61e2427a177beea919d72dde8931084fe51";
    hash = "sha256-W7Eo41XjjWzPs7tSOas1RH57Fd2TJ1ix5Kv4RiOgu8g=";
  };

  libcodecs = fetchFromGitHub {
    owner = "philippe44";
    repo = "libcodecs";
    rev = "3234c96680fbe9f45047936a14df10edca822e5e";
    hash = "sha256-HPWxOMm61tQMJ7AT7gbq2gRAboUep2IQ7uMYNwgvTIw=";
  };

  libmdns = fetchFromGitHub {
    owner = "philippe44";
    repo = "libmdns";
    rev = "d7f58bf2791c3c25fd729d739a9267ce9db5b696";
    hash = "sha256-2fHCzQJ21TE7iEkBvmHAAchPS6Q2Q71zSRUr0K412js=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "cliairplay";
  version = "0.5.3";

  src = fetchFromGitHub {
    owner = "music-assistant";
    repo = "airplay-cli";
    rev = "v${finalAttrs.version}";
    hash = "sha256-I+Goscz7i1vI8sZ5rrxxBQT6xob9rtyYfDcyEaH1woA=";
  };

  buildInputs = [ openssl ];

  # Stand the submodule tree back up by hand. The build writes a patched copy
  # of libcodecs.a next to the original, so everything must be writable.
  postUnpack = ''
    cp -r --no-preserve=mode,ownership ${libraop}/. source/libraop/
    cp -r --no-preserve=mode,ownership ${crosstools}/. source/libraop/crosstools/
    cp -r --no-preserve=mode,ownership ${dmap-parser}/. source/libraop/dmap-parser/
    cp -r --no-preserve=mode,ownership ${libcodecs}/. source/libraop/libcodecs/
    cp -r --no-preserve=mode,ownership ${libmdns}/. source/libraop/libmdns/
  '';

  makeFlags = [
    "VERSION=${finalAttrs.version}"
    # Upstream expects its own prebuilt OpenSSL here; only the headers are
    # read, and -lcrypto resolves against buildInputs.
    "OPENSSL=${lib.getDev openssl}"
  ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/cliairplay-linux-${stdenv.hostPlatform.linuxArch} \
      $out/bin/cliairplay

    runHook postInstall
  '';

  # `--check` needs no network and no device.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/cliairplay --check

    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line sender for AirPlay 1 (RAOP) and native AirPlay 2 devices";
    homepage = "https://github.com/music-assistant/airplay-cli";
    license = lib.licenses.gpl3Only;
    mainProgram = "cliairplay";
    platforms = [ "x86_64-linux" ];
  };
})
