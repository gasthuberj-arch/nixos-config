{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:
# To check for updates:
#   curl -s "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json"
# To get the SRI hash:
#   nix hash convert --to sri --hash-algo sha256 $(nix-prefetch-url <url>)
stdenv.mkDerivation rec {
  pname = "antigravity";
  version = "1.4.0";
  buildId = "5281842794987520";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${buildId}/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha256-/ZaWdYPB7tlHM8A5Y4+lm3HdvYI8devI3Q5ndGNWWq0=";
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
