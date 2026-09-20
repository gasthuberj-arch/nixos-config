{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:
stdenv.mkDerivation rec {
  pname = "antigravity";
  version = "1.2.7";
  buildId = "6731160148115456";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${buildId}/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha256-5BDdVtjCE+8SZD0/9eqqtXoX4Fu/culBUyLyOHn8Shg=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -m755 -D antigravity $out/bin/antigravity
    ln -s $out/bin/antigravity $out/bin/agy
    runHook postInstall
  '';

  meta = with lib; {
    description = "Google Antigravity CLI";
    homepage = "https://antigravity.google";
    platforms = ["x86_64-linux"];
    mainProgram = "agy";
  };
}
