{
  pkgs,
  lib,
  self,
  ...
}: {
  home.username = "johannes";
  home.homeDirectory = "/home/johannes";
  home.stateVersion = "25.11";

  # User packages
  home.packages = with pkgs; [
    # AI & Agent Tooling
    self.packages.${pkgs.stdenv.hostPlatform.system}.antigravity

    # Modern CLI toolkit
    ripgrep
    fd
    fzf
    bat
    btop
    eza
    lazygit
    gh
    jq
    yq
    zoxide
    devenv
    unzip
    zip
    tree
    fastfetch
    wget
    curl
    rsync
    which
    zellij

    # DevOps & Kubernetes tools
    kubectl
    kubernetes-helm
    k9s
    stern
    kubectx

    # GUI Applications & Browsers
    firefox
    google-chrome
    vscode
    proton-vpn

    # Neovim & backing build tools for treesitter / LSP
    neovim
    gcc
    gnumake
    nodejs
    python3
    tree-sitter

    # Desktop / Hyprland utilities
    cliphist
    wl-clipboard
    grim
    slurp
    pavucontrol
    brightnessctl
    libnotify

    # work
    microsoft-edge
    claude-code
    pnpm
    uv
    jdk17
    mkcert
    lastpass-cli
    terraform
    terragrunt
    helmfile
  ];

  # Shell configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ll = "eza -lah --icons";
      ls = "eza --icons";
      rebuild = "sudo nixos-rebuild switch --flake /home/johannes/code/nixos-config#laptop";
      lg = "lazygit";
      k = "kubectl";
    };
    initContent = ''
      export PATH="$HOME/.local/bin:$PATH"
      [ -f "$HOME/.env.local" ] && source "$HOME/.env.local"
    '';
  };

  # CLI helpers
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      filter_mode = "global";
      filter_mode_shell_up_arrow = "directory";
      search_mode = "fuzzy";
    };
  };

  programs.bat.enable = true;

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

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

  # Hyprland config (ergonomic baseline with Vim navigation & Fn keys)
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    # UWSM (enabled via programs.hyprland.withUWSM) owns systemd session
    # integration now; Home Manager's own integration would conflict with it.
    systemd.enable = false;
    settings = {
      "$mod" = "SUPER";
      "$terminal" = "kitty";
      "$menu" = "wofi --show drun";

      exec-once = [
        "waybar"
        "dunst"
        "nm-applet --indicator"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
      ];

      monitor = [
        ",preferred,auto,1"
      ];

      input = {
        kb_layout = "us";
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        layout = "dwindle";
      };

      decoration = {
        rounding = 8;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        force_default_wallpaper = 0;
        background_color = "0x11111b"; # Clean dark slate background
        disable_watchdog_warning = true;
      };

      bind = [
        # Terminal, Menu & Clipboard
        "$mod, RETURN, exec, $terminal"
        "$mod, SPACE, exec, $menu"
        "$mod, V, exec, cliphist list | wofi -d | cliphist decode | wl-copy"

        # Window Actions
        "$mod, Q, killactive,"
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, SPACE, togglefloating,"
        "$mod, M, exit,"

        # Screen Lock & Screenshots
        "$mod, L, exec, hyprlock"
        "$mod SHIFT, S, exec, grim -g \"$(slurp)\" - | wl-copy && notify-send 'Screenshot copied to clipboard'"
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy && notify-send 'Screenshot copied to clipboard'"
        "SHIFT, Print, exec, grim - | wl-copy && notify-send 'Full screenshot copied to clipboard'"

        # Focus Navigation (Vim HJKL + Arrow keys)
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"

        # Window Movement (Swap with neighbor)
        "$mod SHIFT, left, movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up, movewindow, u"
        "$mod SHIFT, down, movewindow, d"
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        # Switch workspaces with mod + [0-9]
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"

        # Move active window to workspace with mod + SHIFT + [0-9]
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
      ];

      binde = [
        # Resize active window with mod + ctrl + arrows
        "$mod CTRL, right, resizeactive, 20 0"
        "$mod CTRL, left, resizeactive, -20 0"
        "$mod CTRL, up, resizeactive, 0 -20"
        "$mod CTRL, down, resizeactive, 0 20"
      ];

      bindel = [
        # Volume controls
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        # Brightness controls
        ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];

      bindl = [
        # Audio Mute toggles
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
      ];

      bindm = [
        # Mouse movements
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };

  # Terminal emulator configuration
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrainsMono Nerd Font";
      font_size = "11.0";
      enable_audio_bell = false;
      background_opacity = "0.95";
    };
  };

  programs.home-manager.enable = true;
}
