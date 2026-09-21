{pkgs, ...}: {
  home.packages = with pkgs; [
    microsoft-edge
    lastpass-cli

    # crane/gcrane: registry work (copy, digest, config, layer inspect)
    # without a Docker daemon or a local image pull.
    go-containerregistry
  ];
}
