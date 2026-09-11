{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  makeWrapper,
  zip,
  openjdk11,
  jnr-posix,
  glib,
  libxtst,
  alsa-lib,
  libGL,
  bashInteractive,
}:
# The native 3.0.1 microsoft-identity-broker (the current nixpkgs default)
# fails to complete interactive sign-in on this machine: the session
# broker's WebKitGTK-based login window either can't render or can't
# complete the redirect. This pins back to 2.0.1, the last Java/JavaFX-based
# release before Microsoft's rewrite to the native GTK3/WebKitGTK broker.
# It's a from-scratch reconstruction of the pre-rewrite nixpkgs recipe
# (recovered from a locally cached build's derivation), not a patch on top
# of today's package.nix, since today's native-binary build logic
# (autoPatchelfHook, no JDK) can't produce a working Java-based broker.
stdenv.mkDerivation rec {
  pname = "microsoft-identity-broker";
  version = "2.0.1";

  src = fetchurl {
    url = "https://packages.microsoft.com/ubuntu/22.04/prod/pool/main/m/microsoft-identity-broker/microsoft-identity-broker_${version}_amd64.deb";
    hash = "sha256-v/FxtdvRaUHYqvFSkJIZyicIdcyxQ8lPpY5rb9smnqA=";
  };

  nativeBuildInputs = [
    dpkg
    makeWrapper
    openjdk11
    zip
  ];

  buildInputs = [
    glib
    libxtst
    alsa-lib
    libGL
  ];

  buildPhase = ''
    runHook preBuild
    # The bundled jnr-posix is old; nixpkgs' jnr-posix is added to the
    # classpath below instead.
    rm opt/microsoft/identity-broker/lib/jnr-posix-3.1.4.jar
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/microsoft-identity-broker
    cp -a opt/microsoft/identity-broker/lib/* $out/lib/microsoft-identity-broker
    cp -a usr/* $out

    classpath=""
    for jar in $out/lib/microsoft-identity-broker/*.jar; do
      classpath="$classpath:$jar"
    done
    classpath="$classpath:$(echo ${jnr-posix}/share/java/*.jar)"

    mkdir -p $out/bin
    makeWrapper ${openjdk11}/bin/java $out/bin/microsoft-identity-broker \
      --prefix LD_LIBRARY_PATH : "${glib.out}/lib:${libxtst}/lib:${alsa-lib}/lib:${libGL}/lib" \
      --add-flags "-classpath $classpath" \
      --add-flags "-Xmx256m -Xss256k -XX:+UseParallelGC -XX:ParallelGCThreads=1" \
      --add-flags "-verbose" \
      --add-flags "-Djava.net.useSystemProxies=true" \
      --add-flags "com.microsoft.identity.broker.service.IdentityBrokerService"

    makeWrapper ${openjdk11}/bin/java $out/bin/microsoft-identity-device-broker \
      --prefix LD_LIBRARY_PATH : "${glib.out}/lib:${libxtst}/lib:${alsa-lib}/lib:${libGL}/lib" \
      --add-flags "-classpath $classpath" \
      --add-flags "-Xmx256m -Xss256k -XX:+UseParallelGC -XX:ParallelGCThreads=1" \
      --add-flags "-verbose" \
      --add-flags "-Djava.net.useSystemProxies=true" \
      --add-flags "com.microsoft.identity.broker.service.DeviceBrokerService"

    runHook postInstall
  '';

  postInstall = ''
    substituteInPlace \
      $out/lib/systemd/user/microsoft-identity-broker.service \
      $out/lib/systemd/system/microsoft-identity-device-broker.service \
      $out/share/dbus-1/system-services/com.microsoft.identity.devicebroker1.service \
      $out/share/dbus-1/services/com.microsoft.identity.broker1.service \
      --replace \
        ExecStartPre=sh \
        ExecStartPre=${bashInteractive}/bin/sh \
      --replace \
        ExecStartPre=!sh \
        ExecStartPre=!${bashInteractive}/bin/sh \
      --replace \
        /opt/microsoft/identity-broker/bin/microsoft-identity-broker \
        $out/bin/microsoft-identity-broker \
      --replace \
        /opt/microsoft/identity-broker/bin/microsoft-identity-device-broker \
        $out/bin/microsoft-identity-device-broker \
      --replace \
        /usr/lib/jvm/java-11-openjdk-amd64 \
        ${openjdk11}
  '';

  meta = {
    description = "Microsoft Authentication Broker for Linux, pinned to the last Java-based release (2.0.1) to work around native-broker sign-in failures";
    homepage = "https://www.microsoft.com/";
    license = lib.licenses.unfree;
    platforms = ["x86_64-linux"];
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
}
