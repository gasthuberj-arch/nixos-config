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

  # dunst's own follow=mouse/keyboard does nothing on Wayland: src/wayland/wl.c
  # returns a NULL output for both and lets the compositor decide, and Hyprland
  # then parks notifications on one fixed monitor no matter where the focus is.
  # Naming the monitor explicitly does work, so this tails Hyprland's focus
  # events and repoints dunst as the focus moves. It matters beyond cosmetics
  # for the SSH key confirm prompt: a prompt on a screen you aren't looking at
  # means touching the sensor without seeing what asked for it.
  dunstFollowFocus = pkgs.writeShellApplication {
    name = "dunst-follow-focus";
    runtimeInputs = with pkgs; [coreutils dunst hyprland jq socat];
    text = ''
      conf="$XDG_RUNTIME_DIR/dunst-monitor.conf"

      point_at() {
        # dunstctl reload loads whatever this file says, and a dunst rule can
        # carry a `script` that dunst then executes, so the file must never
        # hold anything but a monitor name. Connector names are [A-Za-z0-9-];
        # stripping the rest keeps a crafted name (hyprctl can create outputs)
        # from smuggling a newline and a second setting in behind it.
        local mon=''${1//[^A-Za-z0-9-]/}
        [ -n "$mon" ] || return 0

        # This file is the whole config dunst runs with: reload replaces the
        # settings rather than merging, and dunst had no dunstrc before this,
        # so everything else stays at dunst's built-in defaults.
        printf '[global]\n    monitor = "%s"\n' "$mon" > "$conf"
        dunstctl reload "$conf" || true
      }

      # exec-once neither supervises nor restarts, and losing this silently
      # would put the SSH confirm prompt back on an unwatched screen. So no
      # failure is fatal: a reload that loses the startup race with dunst, a
      # compositor socket that disappears, hyprctl failing - all just retry.
      while :; do
        mon=$(hyprctl monitors -j | jq -r 'first(.[] | select(.focused) | .name) // empty') || mon=""
        [ -n "$mon" ] && point_at "$mon" || true

        socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/''${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock" 2>/dev/null |
          while IFS= read -r line; do
            case "$line" in
              focusedmon\>\>*)
                rest=''${line#focusedmon>>}
                point_at "''${rest%%,*}"
                ;;
            esac
          done || true

        sleep 5
      done
    '';
  };

  # `nixos-rebuild switch` restarts services but cannot swap the running
  # kernel, initrd or module tree, so after a kernel bump the machine keeps
  # running the old one until reboot.
  waybarRebootNeeded = pkgs.writeShellApplication {
    name = "waybar-reboot-needed";
    runtimeInputs = with pkgs; [coreutils jq];
    text = ''
      booted=$(readlink /run/booted-system/{initrd,kernel,kernel-modules})
      current=$(readlink /run/current-system/{initrd,kernel,kernel-modules})
      if [ "$booted" = "$current" ]; then
        jq -cn '{text: ""}'
        exit 0
      fi
      # Store paths are /nix/store/<hash>-linux-<ver>/bzImage; keep linux-<ver>.
      kver() { local p; p=$(basename "$(dirname "$(readlink "$1/kernel")")"); echo "''${p#*-}"; }
      jq -cn --arg b "$(kver /run/booted-system)" --arg c "$(kver /run/current-system)" \
        '{text: "⟳ reboot", class: "reboot-needed",
          tooltip: "Kernel, initrd or modules changed since boot\nbooted:  \($b)\ncurrent: \($c)"}'
    '';
  };
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
    alejandra

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
    thunderbird
    keepassxc

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

    # Rust tooling. rustup (NixOS-patched) instead of nixpkgs rustc/cargo so
    # per-repo rust-toolchain.toml pins, extra targets, and components
    # (clippy, rustfmt, rust-analyzer) work. Links via gcc above.
    # One-time after switch: `rustup default stable`.
    rustup

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
    thunar
    thunar-volman
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
      # TERM=xterm-kitty has no terminfo entry on most remotes; kitten ssh adds it. Alias-only.
      ssh = "kitten ssh";
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

      # Flip kitty, GTK apps, agy, k9s and btop between a day and night theme.
      # kitty remote control is per-process, so pushing colors to the socket
      # in $KITTY_LISTEN_ON would only repaint the window theme-toggle was
      # invoked from; walking every socket repaints all open instances.
      # GTK apps and browsers watching the portal setting (most GTK4/libadwaita)
      # and bat follow immediately - agy, k9s and btop read
      # their theme choice once at startup, so they pick it up next launch.
      theme-toggle() {
        # The (N) glob below needs bareglobqual. Non-interactive callers such as
        # Claude Code's `!` shell turn it off, and the glob then aborts the
        # function after the kitty symlink flip, leaving themes out of sync.
        emulate -L zsh
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

        if [ -f "$HOME/.gemini/antigravity-cli/settings.json" ] && command -v jq >/dev/null 2>&1; then
          local agy_conf="$HOME/.gemini/antigravity-cli/settings.json"
          local agy_theme="dark"
          [ "$target" = day ] && agy_theme="light"
          jq --arg t "$agy_theme" '.colorScheme = $t' "$agy_conf" > "$agy_conf.tmp" && mv "$agy_conf.tmp" "$agy_conf"
        fi

        echo "→ theme: $target ($repainted kitty instance(s), GTK apps, browsers, cursor and bat live; agy/k9s/btop apply next launch)"
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

  # dunst shows a notification on one output only; it can't mirror to every
  # screen. "mouse" (identical to "keyboard" on Wayland) puts it on the
  # output last interacted with, instead of pinning it to monitor 0 - which
  # matters for the SSH key confirm prompt, where an unseen popup means
  # touching the sensor without knowing what asked for it.
  # Hyprland config (ergonomic baseline with Vim navigation & Fn keys)
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";
    # UWSM (enabled via programs.hyprland.withUWSM) owns systemd session
    # integration now; Home Manager's own integration would conflict with it.
    systemd.enable = false;
    # Non-null enables Home Manager's own xdg.portal, which repoints
    # NIX_XDG_DESKTOP_PORTAL_DIR at a dir holding only hyprland.portal. That
    # hides the system's portal-gtk, the only Settings backend, so browsers
    # silently stop following theme-toggle. modules/desktop/hyprland.nix owns portals.
    portalPackage = null;
    settings = {
      "$mod" = "SUPER";
      "$terminal" = "kitty";
      "$menu" = "wofi --show drun";

      exec-once = [
        "waybar"
        "dunst"
        (lib.getExe dunstFollowFocus)
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

      # Clicking a kitty notification (e.g. Claude Code) makes kitty send an
      # xdg-activation request; honor it so the click jumps to that window.
      # Scoped to kitty rather than global misc:focus_on_activate so other
      # apps still can't steal focus (and keystrokes) mid-typing.
      windowrule = [
        "match:class ^(kitty)$, focus_on_activate on"
      ];

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

  # Waybar status bar configuration with interactive controls
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        spacing = 4;
        modules-left = [
          "hyprland/workspaces"
        ];
        modules-center = [
          "hyprland/window"
        ];
        modules-right = [
          "privacy"
          "systemd-failed-units"
          "custom/reboot-needed"
          "idle_inhibitor"
          "pulseaudio"
          "network"
          "power-profiles-daemon"
          "cpu"
          "memory"
          "temperature"
          "backlight"
          "battery"
          "clock"
          "tray"
        ];
        "hyprland/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
        };
        "idle_inhibitor" = {
          format = "{icon}";
          format-icons = {
            activated = "";
            deactivated = "";
          };
        };
        "tray" = {
          spacing = 10;
        };
        # Shows only while something captures the screen or a mic, via PipeWire.
        # audio-out (the third type) is left out: playback is not a privacy signal.
        "privacy" = {
          icon-size = 16;
          modules = [
            {type = "screenshare";}
            {type = "audio-in";}
          ];
        };
        # Hidden at zero (hide-on-ok defaults to true); counts system + user units.
        "systemd-failed-units" = {
          format = "✗ {nr_failed} failed";
          on-click = "kitty --hold sh -c 'systemctl --failed; systemctl --user --failed'";
        };
        "custom/reboot-needed" = {
          exec = lib.getExe waybarRebootNeeded;
          return-type = "json";
          interval = 60;
        };
        "clock" = {
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          format-alt = "{:%Y-%m-%d}";
        };
        "cpu" = {
          format = "{usage}% ";
          tooltip = false;
        };
        "memory" = {
          format = "{}% ";
        };
        "temperature" = {
          critical-threshold = 80;
          format = "{temperatureC}°C {icon}";
          format-icons = ["" "" ""];
        };
        "backlight" = {
          format = "{percent}% {icon}";
          format-icons = ["" "" "" "" "" "" "" "" ""];
          on-scroll-up = "brightnessctl set 5%+";
          on-scroll-down = "brightnessctl set 5%-";
          on-click = "sh -c 'curr=$(brightnessctl -m | cut -d, -f4 | tr -d \"%\" ); if [ \"$curr\" -ge 100 ]; then brightnessctl set 20%; else brightnessctl set +25%; fi'";
        };
        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          format-full = "{capacity}% {icon}";
          format-charging = "{capacity}% ";
          format-plugged = "{capacity}% ";
          format-alt = "{time} {icon}";
          format-icons = ["" "" "" "" ""];
        };
        "power-profiles-daemon" = {
          format = "{icon}";
          tooltip-format = "Power profile: {profile}\nDriver: {driver}";
          tooltip = true;
          format-icons = {
            default = "";
            performance = "";
            balanced = "";
            power-saver = "";
          };
        };
        "network" = {
          format-wifi = "{essid} ({signalStrength}%) ";
          format-ethernet = "{ipaddr}/{cidr} ";
          tooltip-format = "{ifname} via {gwaddr} ";
          format-linked = "{ifname} (No IP) ";
          format-disconnected = "Disconnected ⚠";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
        };
        "pulseaudio" = {
          format = "{volume}% {icon} {format_source}";
          format-bluetooth = "{volume}% {icon} {format_source}";
          format-bluetooth-muted = " {icon} {format_source}";
          format-muted = " {format_source}";
          format-source = "{volume}% ";
          format-source-muted = "";
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = ["" "" ""];
          };
          on-click = "pavucontrol";
        };
      };
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
