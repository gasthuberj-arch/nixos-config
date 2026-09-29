{lib, ...}: let
  # Push/auth key for GitHub: passphrase on disk, held by ssh-agent under a
  # confirm constraint, so every use needs a fingerprint touch (see
  # ssh-push-gate.nix). Separate from the signing key so commits and
  # rebases don't need a touch per commit.
  githubKey = "~/.ssh/id_ed25519_github";
  signingKey = "~/.ssh/id_ed25519_signing";
  email = "johannes.gasthuber@manex.ai";
  # "~/.ssh/..." as the shell sees it: "$HOME" + this.
  signingKeyHome = lib.removePrefix "~" signingKey;
in {
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/work.nix
  ];

  home.username = "johannes";
  home.homeDirectory = "/home/johannes";
  home.stateVersion = "25.11";

  programs.zsh.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /home/johannes/config/nixos-config#work-laptop";

  # Run by hand, not at login: loads the signing key without a confirm
  # constraint and the GitHub key with one. Without it both keys still load
  # lazily (AddKeysToAgent on first push, ssh-keygen on first commit), each
  # asking for its passphrase separately at the worst moment.
  programs.zsh.initContent = ''
    unlock-keys() {
      ssh-add ${signingKey} && ssh-add -c ${githubKey}
    }
  '';

  # This hands ~/.ssh/config to Home Manager: the generated file is only the
  # block below, and any hand-written entry is moved aside to config.backup
  # on the first switch. New host entries belong here from now on.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."github.com" = {
      IdentityFile = githubKey;
      IdentitiesOnly = "yes";
      # Pinned so a stale SSH_AUTH_SOCK from the old gcr agent can't route
      # around the confirm constraint.
      IdentityAgent = "\${XDG_RUNTIME_DIR}/ssh-agent";
      AddKeysToAgent = "confirm";
    };
  };

  programs.git = {
    enable = true;
    signing = {
      key = "${signingKey}.pub";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "Johannes Gasthuber";
        inherit email;
      };
      gpg = {
        format = "ssh";
        ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      };
      # Fetch over HTTPS (gh token, no touch), push over SSH (touch). Covers
      # remotes in either form; the self-mapping pushInsteadOf stops the
      # insteadOf rule from turning SSH pushes into HTTPS ones.
      url."https://github.com/".insteadOf = "git@github.com:";
      url."git@github.com:".pushInsteadOf = ["git@github.com:" "https://github.com/"];
      credential."https://github.com".helper = "!gh auth git-credential";
    };
  };

  # git isn't on the activation PATH, so the email comes from Nix rather than
  # `git config` (which silently wrote a principal-less line). The key path is
  # derived from signingKey too: hardcoding it here would let allowed_signers
  # keep pointing at the old key after a rename, which doesn't fail loudly -
  # commits still sign, they just verify as an unknown signer.
  home.activation.createGitAllowedSigners = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f "$HOME${signingKeyHome}.pub" ]; then
      echo "${email} $(cat "$HOME${signingKeyHome}.pub")" > "$HOME/.ssh/allowed_signers"
    fi
  '';
}
