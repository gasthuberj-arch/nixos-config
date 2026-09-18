{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  self,
  ...
}: let
  # kitty listens on one socket per process. theme-toggle globs these to
  # repaint every running instance, so the path lives here rather than being
  # written out twice and drifting apart.
  kittySocketPrefix = "/tmp/kitty-socket-";

  # Pointer cursor, day/night. Named here so the Nix side (home.pointerCursor)
  # and the runtime side (hyprctl setcursor in theme-toggle) cannot disagree
  # about the theme name or size.
  cursorSize = 24;
  cursorThemeNight = "catppuccin-mocha-dark-cursors";
  cursorThemeDay = "catppuccin-latte-light-cursors";
in {
  # Plain `virsh`/`virt-manager` default to the unprivileged per-user
  # "session" libvirt instance, which can't touch host networking (no
  # bridges, no default NAT network). Pin the system instance instead.
  home.sessionVariables.LIBVIRT_DEFAULT_URI = "qemu:///system";

  # User packages
  home.packages = with pkgs; [
    # AI & Agent Tooling
    self.packages.${pkgs.stdenv.hostPlatform.system}.antigravity
    pkgs-unstable.claude-code

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
    jj

    # DevOps & Kubernetes tools
    kubernetes-helm
    k9s
    stern
    kubectx
    kubectl
    terraform
    terragrunt
    helmfile
    k3d
    kustomize
    awscli2

    # GUI Applications & Browsers
    google-chrome
    vscode
    proton-vpn

    # Spaced repetition, with AnkiConnect baked in (declaratively, via
    # anki.withAddons) so external tools/scripts can add cards over its
    # localhost:8765 HTTP API without a manual AnkiWeb addon install.
    (anki.withAddons [ankiAddons.anki-connect])

    # Neovim & backing build tools for treesitter / LSP
    neovim
    gcc
    gnumake
    nodejs
    python3
    tree-sitter

    # Elixir / BEAM tooling
    elixir
    elixir-ls
    inotify-tools # Phoenix live-reload file watching on Linux
    postgresql # psql client for local Phoenix/Ecto database work

    # Desktop / Hyprland utilities
    cliphist
    wl-clipboard
    grim
    slurp
    pavucontrol
    brightnessctl
    libnotify

    # File managers: Thunar (GUI, drag-drop/right-click copy-paste) + Yazi
    # (TUI, kitty-graphics-protocol previews)
    xfce.thunar
    xfce.thunar-volman
    tumbler
    yazi

    # General dev tooling
    pnpm
    uv
    jdk17
    mkcert
    openssl

    # home.pointerCursor installs the Mocha (night) cursor as the seeded
    # default; the Latte one is referenced only at runtime by theme-toggle,
    # so without this it would never land on XCURSOR_PATH to switch to.
    catppuccin-cursors.latteLight
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
      lg = "lazygit";
      k = "kubectl";
    };
    initContent = ''
      export PATH="$HOME/.local/bin:$PATH"
      [ -f "$HOME/.env.local" ] && source "$HOME/.env.local"

      # Kill ambient AWS SSO session + kubectl context before/after high-trust agent work.
      # Neither service has a single "log out of everything" - each credential path
      # (aws cli, kubectl auth) is independent, so both need clearing explicitly.
      lockdown() {
        echo "→ aws sso logout"
        aws sso logout
        echo "→ clearing kubectl context (was: $(kubectl config current-context 2>/dev/null))"
        kubectl config unset current-context
        echo "✓ no ambient AWS/kube credentials"
      }

      # Launch Claude Code with zero MCP servers loaded and OS-level sandboxing
      # (bubblewrap on Linux) for autonomous/agentic runs. allowUnsandboxedCommands
      # is off on purpose: a command that fails inside the sandbox should fail, not
      # silently retry with full access - that would defeat the point of lockdown.
      claude-locked() {
        lockdown
        local sandbox_settings='{
          "sandbox": {
            "enabled": true,
            "allowUnsandboxedCommands": false,
            "filesystem": {
              "denyRead": ["~/.ssh", "~/.aws", "~/.kube", "~/.env.local"]
            }
          }
        }'
        claude --strict-mcp-config --settings "$sandbox_settings" "$@"
      }

      # Flip kitty, GTK apps, k9s and btop between a day and night theme.
      # kitty remote control is per-process, so pushing colors to the socket
      # in $KITTY_LISTEN_ON would only repaint the window theme-toggle was
      # invoked from; walking every socket repaints all open instances.
      # GTK apps watching the portal setting (most GTK4/libadwaita) and bat
      # follow immediately - k9s and btop read their theme choice once at
      # startup, so they pick it up next launch.
      theme-toggle() {
        local kitty_dir="$HOME/.config/kitty"
        local current="$kitty_dir/current-theme.conf"
        local target="night"
        if [ -L "$current" ] && [[ "$(readlink "$current")" == *night.conf ]]; then
          target="day"
        fi

        local cursor_theme="${cursorThemeNight}"
        [ "$target" = day ] && cursor_theme="${cursorThemeDay}"

        ln -sf "$kitty_dir/themes/$target.conf" "$current"

        # (N) is zsh's null_glob qualifier: with no kitty running, the pattern
        # has to expand to nothing rather than raise "no matches found", which
        # would abort the function before the GTK/k9s/btop/bat updates below.
        # Sockets outlive kitty processes that died without cleaning up, so a
        # dead one just fails its connect and is skipped.
        local sock repainted=0
        for sock in ${kittySocketPrefix}*(N); do
          if kitty @ --to "unix:$sock" set-colors --all --configured \
            "$kitty_dir/themes/$target.conf" >/dev/null 2>&1; then
            repainted=$((repainted + 1))
          fi
        done

        # Hyprland owns the pointer for the entire session, so one call covers
        # every window. There is no per-process socket to walk as with kitty.
        if command -v hyprctl >/dev/null 2>&1; then
          hyprctl setcursor "$cursor_theme" ${toString cursorSize} >/dev/null 2>&1
        fi

        # GTK apps ignore the compositor cursor and read this key instead.
        if command -v gsettings >/dev/null 2>&1; then
          gsettings set org.gnome.desktop.interface color-scheme \
            "$([ "$target" = night ] && echo prefer-dark || echo prefer-light)"
          gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme"
        fi

        if [ -f "$HOME/.config/k9s/config.yaml" ] && command -v yq >/dev/null 2>&1; then
          yq -y -i ".k9s.ui.skin = \"$target\"" "$HOME/.config/k9s/config.yaml"
        fi

        if [ -f "$HOME/.config/btop/btop.conf" ]; then
          local btop_theme="flexoki-dark"
          [ "$target" = day ] && btop_theme="flexoki-light"
          sed -i "s/^color_theme = .*/color_theme = \"$btop_theme\"/" "$HOME/.config/btop/btop.conf"
        fi

        if command -v bat >/dev/null 2>&1; then
          mkdir -p "$HOME/.config/bat"
          local bat_theme="Catppuccin Mocha"
          [ "$target" = day ] && bat_theme="Catppuccin Latte"
          printf -- '--theme="%s"\n' "$bat_theme" >"$HOME/.config/bat/config"
        fi

        echo "→ theme: $target ($repainted kitty instance(s), GTK apps, cursor and bat live; k9s/btop apply next launch)"
      }
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

  programs.mise = {
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

  # Office web apps (PowerPoint/Word Online) intercept Ctrl+V via the
  # async Clipboard API, which Firefox blocks by default for JS-triggered
  # paste. Without these prefs, copy-paste into PowerPoint Online silently
  # does nothing on Firefox even though the Wayland clipboard itself works.
  programs.firefox = {
    enable = true;
    # Firefox's own default profile dir on Linux ($XDG_CONFIG_HOME) and the
    # existing real profile (2hefm63c.default) it must be pointed at — get
    # either wrong and Home Manager creates a fresh, empty default profile
    # instead of managing the one with actual history/logins/sessions.
    configPath = "${config.xdg.configHome}/mozilla/firefox";
    profiles.johannes = {
      path = "2hefm63c.default";
      isDefault = true;
      settings = {
        "dom.events.asyncClipboard.clipboardItem" = true;
        "dom.events.testing.asyncClipboard.enabled" = true;
      };
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

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

        # File Managers
        "$mod, E, exec, thunar"
        "$mod, Y, exec, $terminal -e yazi"

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
      # Remote control, scoped to this user via a per-pid socket, lets
      # `theme-toggle` push new colors into already-open windows/tabs instead
      # of requiring a restart. One socket per process is also what lets it
      # reach every running kitty, not just the one it was invoked from.
      #
      # socket-only, not yes: kitty's remote control protocol is a DCS escape
      # sequence, so `yes` also accepts commands written to the TTY itself.
      # That turns any untrusted bytes reaching the terminal (a hostile log
      # line, curl output, an SSH session to a compromised host) into local
      # command execution via `kitty @ launch` and scrollback disclosure via
      # `kitty @ get-text`. theme-toggle only ever talks to the socket below,
      # which is already restricted to this uid by its 0755 mode, since
      # connect(2) needs the write bit. Nothing here uses the TTY route.
      allow_remote_control = "socket-only";
      listen_on = "unix:${kittySocketPrefix}{kitty_pid}";
    };
    # current-theme.conf is a symlink toggled between themes/day.conf and
    # themes/night.conf by the theme-toggle shell function below; it's seeded
    # once (see home.activation.seedTerminalTheme) and left alone afterwards
    # so a rebuild doesn't undo the last choice.
    extraConfig = "include current-theme.conf";
  };

  home.file.".config/kitty/themes/night.conf".text = ''
    # Catppuccin Mocha
    foreground            #CDD6F4
    background            #1E1E2E
    selection_foreground  #1E1E2E
    selection_background  #F5E0DC
    cursor                #F5E0DC
    cursor_text_color     #1E1E2E
    url_color             #F5E0DC
    active_border_color   #B4BEFE
    inactive_border_color #6C7086
    active_tab_foreground   #11111B
    active_tab_background   #CBA6F7
    inactive_tab_foreground #CDD6F4
    inactive_tab_background #181825
    tab_bar_background      #11111B

    color0  #45475A
    color8  #585B70
    color1  #F38BA8
    color9  #F38BA8
    color2  #A6E3A1
    color10 #A6E3A1
    color3  #F9E2AF
    color11 #F9E2AF
    color4  #89B4FA
    color12 #89B4FA
    color5  #F5C2E7
    color13 #F5C2E7
    color6  #94E2D5
    color14 #94E2D5
    color7  #BAC2DE
    color15 #A6ADC8
  '';

  home.file.".config/kitty/themes/day.conf".text = ''
    # Catppuccin Latte
    foreground            #4C4F69
    background            #EFF1F5
    selection_foreground  #EFF1F5
    selection_background  #DC8A78
    cursor                #DC8A78
    cursor_text_color     #EFF1F5
    url_color             #DC8A78
    active_border_color   #7287FD
    inactive_border_color #9CA0B0
    active_tab_foreground   #E6E9EF
    active_tab_background   #8839EF
    inactive_tab_foreground #4C4F69
    inactive_tab_background #BCC0CC
    tab_bar_background      #ACB0BE

    color0  #5C5F77
    color8  #6C6F85
    color1  #D20F39
    color9  #D20F39
    color2  #40A02B
    color10 #40A02B
    color3  #DF8E1D
    color11 #DF8E1D
    color4  #1E66F5
    color12 #1E66F5
    color5  #EA76CB
    color13 #EA76CB
    color6  #179299
    color14 #179299
    color7  #ACB0BE
    color15 #BCC0CC
  '';

  # Default to the night theme the first time this config is applied; leave
  # it alone on later activations so theme-toggle's choice survives rebuilds.
  home.activation.seedTerminalTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -e "$HOME/.config/kitty/current-theme.conf" ]; then
      ln -sf "$HOME/.config/kitty/themes/night.conf" "$HOME/.config/kitty/current-theme.conf"
    fi
    if [ ! -e "$HOME/.config/bat/config" ]; then
      mkdir -p "$HOME/.config/bat"
      printf -- '--theme="Catppuccin Mocha"\n' >"$HOME/.config/bat/config"
    fi
  '';

  # Seeds the night cursor and wires up GTK, X11 and ~/.icons/default, which
  # is what most toolkits actually read. theme-toggle overrides it at runtime;
  # this is the value a fresh session starts from.
  home.pointerCursor = {
    package = pkgs.catppuccin-cursors.mochaDark;
    name = cursorThemeNight;
    size = cursorSize;
    gtk.enable = true;
    x11.enable = true;
  };

  # k9s/btop day/night skins for theme-toggle, taken straight from what each
  # package already ships rather than hand-rolled theme files. Neither app
  # re-reads its config while running, so these only take effect on that
  # app's next launch after theme-toggle runs - and only once the app has
  # run at least once before (to have created its own config.yaml/btop.conf
  # for theme-toggle to edit).
  home.file.".config/k9s/skins/night.yaml".source = "${pkgs.k9s}/share/k9s/skins/gruvbox-dark.yaml";
  home.file.".config/k9s/skins/day.yaml".source = "${pkgs.k9s}/share/k9s/skins/gruvbox-light.yaml";
  home.file.".config/btop/themes/flexoki-dark.theme".source = "${pkgs.btop}/share/btop/themes/flexoki-dark.theme";
  home.file.".config/btop/themes/flexoki-light.theme".source = "${pkgs.btop}/share/btop/themes/flexoki-light.theme";

  programs.home-manager.enable = true;
}
