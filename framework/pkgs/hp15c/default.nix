{ stdenv, fetchzip, autoPatchelfHook, makeWrapper, lib, unstable }:

stdenv.mkDerivation rec {
  pname = "hp15c";
  version = "4.5.00";

  src = fetchzip {
    url = "https://www.hpcalc.org/other/pc/HP-15C_4.5.00_Linux_x86_64.zip";
    sha256 = "15hxpckif4sab3lwkksqfnsf8agn545g2f5ijm6xrs2b23hdflmv";
    stripRoot = false;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    unstable.tcl
    unstable.tk
  ];

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/hp15c
    mkdir -p $out/share/fonts/truetype

    # Install the binary
    install -Dm755 HP-15C $out/bin/hp15c

    # Install the font
    install -Dm644 HP-15C_Simulator_Font.ttf $out/share/fonts/truetype/

    # Install documentation
    cp -r doc $out/share/hp15c/
    cp "Read Me & Release Notes.html" $out/share/hp15c/

    # Create a wrapper script that sets up the environment
    makeWrapper $out/bin/hp15c $out/bin/hp15c-calculator \
      --set FONTCONFIG_PATH /etc/fonts \
      --set FONTCONFIG_FILE /etc/fonts/fonts.conf \
      --prefix TCLLIBPATH : "${unstable.tcl}/lib" \
      --prefix TCLLIBPATH : "${unstable.tk}/lib" \
      --set TK_LIBRARY "${unstable.tk}/lib/tk8.6" \
      --set TCL_LIBRARY "${unstable.tcl}/lib/tcl8.6" \
      --prefix LD_LIBRARY_PATH : "${unstable.tcl}/lib" \
      --prefix LD_LIBRARY_PATH : "${unstable.tk}/lib"
  '';

  meta = with lib; {
    description = "HP-15C Calculator Simulator";
    homepage = "https://www.hpcalc.org/other/pc/";
    license = licenses.unfree; # You should check the actual license
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}