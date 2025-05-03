{ stdenv, lib, fetchFromGitHub, pkg-config, autoreconfHook, pkgs }:

stdenv.mkDerivation rec {
  pname = "nonpareil";
  version = "unstable-2024-04-25";

  src = fetchFromGitHub {
    owner = "brouhaha";
    repo = "nonpareil";
    rev = "c347bc1ab20170c253512042f7aac0d952f304ea";
    sha256 = "1d130hmsgvlmj8iy8sdd0frx9gzsc68wp84zdax6i8f7dhqdfxzx"; # You'll need to replace this
  };

  nativeBuildInputs = [
    pkg-config
    autoreconfHook
  ];

  buildInputs = [
    pkgs.gtk2
    pkgs.glib
    pkgs.libxml2
    pkgs.SDL
  ];

  configureFlags = [
    "--with-gtk2"
  ];

  meta = with lib; {
    description = "Microcode-level simulation of HP calculators";
    homepage = "https://github.com/brouhaha/nonpareil";
    license = licenses.gpl2;
    platforms = platforms.linux;
    maintainers = [ ];
  };
} 
