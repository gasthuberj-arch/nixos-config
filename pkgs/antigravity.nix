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
  version = "1.5.7";
  buildId = "6190022064472064";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${buildId}/linux-x64/cli_linux_x64.tar.gz";
    hash = "sha256-1hUKjSqeKaPRcbIyXW9mtucFlij0eZogwGm47Y94/bs=";
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
