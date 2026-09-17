{lib, ...}: {
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/work.nix
  ];

  home.username = "johannes";
  home.homeDirectory = "/home/johannes";
  home.stateVersion = "25.11";

  programs.zsh.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /home/johannes/code/nixos-config#work-laptop";

  programs.git = {
    enable = true;
    signing = {
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "Johannes Gasthuber";
        email = "johannes.gasthuber@manex.ai";
      };
      gpg = {
        format = "ssh";
        ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      };
    };
  };

  home.activation.createGitAllowedSigners = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
      echo "$(git config --global user.email) $(cat "$HOME/.ssh/id_ed25519.pub")" > "$HOME/.ssh/allowed_signers"
    fi
  '';
}
