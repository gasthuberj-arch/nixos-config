{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.homelab.services.gpu-power;
in {
  options.homelab.services.gpu-power = {
    enable = mkEnableOption "GPU power management and task termination utilities";

    user = mkOption {
      type = types.str;
      default = "johannes";
      description = "The primary user running graphical sessions and services";
    };

    autoSpindownOnBoot = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to spin down GPU to low-power profile automatically on boot";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      psmisc # fuser, killall
      lsof
      amdgpu_top

      # 1. kill-gpu-tasks: Terminates emulators, games, Wine/Proton, and rogue GPU users
      (writeShellScriptBin "kill-gpu-tasks" ''
        set -euo pipefail

        if [ "$EUID" -ne 0 ]; then
          exec sudo "$0" "$@"
        fi

        INCLUDE_SUNSHINE=false
        DRY_RUN=false

        for arg in "$@"; do
          case "$arg" in
            --include-sunshine|-s)
              INCLUDE_SUNSHINE=true
              ;;
            --dry-run|-n)
              DRY_RUN=true
              ;;
            --help|-h)
              echo "Usage: kill-gpu-tasks [options]"
              echo ""
              echo "Terminates emulators, gaming processes, Wine/Proton, and unwhitelisted GPU users."
              echo ""
              echo "Options:"
              echo "  --include-sunshine, -s   Also stop the Sunshine game streaming service"
              echo "  --dry-run, -n            Show processes that would be killed without killing them"
              echo "  --help, -h               Show this help message"
              exit 0
              ;;
            *)
              echo "Unknown option: $arg" >&2
              exit 1
              ;;
          esac
        done

        echo "Searching for active GPU tasks and gaming processes..."

        # Known gaming and emulator process patterns
        KNOWN_TARGETS=(
          retroarch dolphin-emu pcsx2 pcsx2-qt rpcs3 duckstation cemu
          Ryujinx ryubing ppsspp ppsspp-qt pegasus-frontend pegasus-fe
          steam steamwebhelper gamescope heroic legendary gogdl wine
          wine64 wineserver wine-preloader wine64-preloader Proton
          mangohud gamemoded
        )

        SYSTEM_WHITELIST="^(systemd.*|systemd-logind|gnome-shell|mutter.*|Xwayland|ibus.*|dbus.*|colord|gdm.*|btop|amdgpu_top|bash|sudo|sh|lsof|fuser|kill-gpu-tasks|spindown-gpu|spinup-gpu|check-gpu-power|grep|sed|awk|find|cat|cut|sort)$"

        TARGET_PIDS=()

        # 1. Match known targets
        for pattern in "''${KNOWN_TARGETS[@]}"; do
          matched=$(pgrep -f "$pattern" 2>/dev/null || true)
          if [ -n "$matched" ]; then
            for pid in $matched; do
              [ "$pid" -ne "$$" ] && TARGET_PIDS+=("$pid")
            done
          fi
        done

        # 2. Inspect active GPU file descriptors using fuser
        dri_pids=""
        if command -v fuser &>/dev/null; then
          dri_pids=$(fuser /dev/dri/* /dev/kfd 2>/dev/null || true)
        fi

        if [ -n "$dri_pids" ]; then
          for pid in $dri_pids; do
            [ -d "/proc/$pid" ] || continue
            [ "$pid" -eq "$$" ] && continue
            exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
            base=$(basename "$exe" 2>/dev/null | sed -e 's/^\.//' -e 's/-wrapped$//' || true)

            if [[ "$base" == "sunshine" ]]; then
              if [ "$INCLUDE_SUNSHINE" = true ]; then
                TARGET_PIDS+=("$pid")
              fi
            elif ! [[ "$base" =~ $SYSTEM_WHITELIST ]]; then
              TARGET_PIDS+=("$pid")
            fi
          done
        fi

        # Deduplicate
        UNIQUE_PIDS=($(printf "%s\n" "''${TARGET_PIDS[@]:-}" 2>/dev/null | sort -nu))

        if [ ''${#UNIQUE_PIDS[@]} -eq 0 ]; then
          echo "No active gaming or rogue GPU tasks detected."
        else
          echo "Found ''${#UNIQUE_PIDS[@]} process(es) to terminate:"
          for pid in "''${UNIQUE_PIDS[@]}"; do
            [ -d "/proc/$pid" ] || continue
            comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "unknown")
            user=$(ps -o user= -p "$pid" 2>/dev/null || echo "unknown")
            cmd=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 80 || echo "")
            printf "  • PID %-7s %-10s %-15s %s\n" "$pid" "$user" "$comm" "$cmd"
          done

          if [ "$DRY_RUN" = true ]; then
            echo "[DRY RUN] Processes were not terminated."
            exit 0
          fi

          echo ""
          echo "Sending SIGTERM (graceful shutdown)..."
          for pid in "''${UNIQUE_PIDS[@]}"; do
            kill -TERM "$pid" 2>/dev/null || true
          done

          sleep 2

          REMAINING=()
          for pid in "''${UNIQUE_PIDS[@]}"; do
            if [ -d "/proc/$pid" ]; then
              REMAINING+=("$pid")
            fi
          done

          if [ ''${#REMAINING[@]} -gt 0 ]; then
            echo "Sending SIGKILL to remaining ''${#REMAINING[@]} stubborn process(es)..."
            for pid in "''${REMAINING[@]}"; do
              kill -KILL "$pid" 2>/dev/null || true
            done
            sleep 1
          fi
          echo "Process termination completed successfully."
        fi

        if [ "$INCLUDE_SUNSHINE" = true ]; then
          echo "Stopping Sunshine service..."
          systemctl --user -M ${cfg.user}@ stop sunshine.service 2>/dev/null || true
        fi
      '')

      # 2. spindown-gpu: Drops GPU to low-power profile and terminates tasks
      (writeShellScriptBin "spindown-gpu" ''
        set -euo pipefail

        if [ "$EUID" -ne 0 ]; then
          exec sudo "$0" "$@"
        fi

        SKIP_KILL=false
        INCLUDE_SUNSHINE=false

        for arg in "$@"; do
          case "$arg" in
            --no-kill)
              SKIP_KILL=true
              ;;
            --include-sunshine|-s)
              INCLUDE_SUNSHINE=true
              ;;
            --help|-h)
              echo "Usage: spindown-gpu [options]"
              echo ""
              echo "Terminates GPU workloads and configures the GPU into minimum power-saving mode."
              echo ""
              echo "Options:"
              echo "  --no-kill                Do not terminate GPU tasks before spindown"
              echo "  --include-sunshine, -s   Also stop the Sunshine game streaming service"
              echo "  --help, -h               Show this help message"
              exit 0
              ;;
            *)
              echo "Unknown option: $arg" >&2
              exit 1
              ;;
          esac
        done

        echo ">>> Executing homelab GPU spindown..."
        echo ""

        # Step 1: Kill GPU tasks
        if [ "$SKIP_KILL" = false ]; then
          kill_args=()
          [ "$INCLUDE_SUNSHINE" = true ] && kill_args+=("--include-sunshine")
          kill-gpu-tasks "''${kill_args[@]}"
          echo ""
        fi

        # Step 2: Configure AMD GPU power saving
        found_gpu=0
        for dev in /sys/class/drm/card[0-9]/device; do
          [ -f "$dev/vendor" ] || continue
          if [ "$(cat "$dev/vendor")" = "0x1002" ]; then
            card_name=$(basename "$(dirname "$dev")")
            echo "Spinning down $card_name to lowest power state..."

            # Force lowest DPM performance level (minimum core & memory clocks)
            if [ -f "$dev/power_dpm_force_performance_level" ]; then
              echo "low" > "$dev/power_dpm_force_performance_level"
              echo "  • DPM Performance Level: set to 'low'"
            fi

            # Set power saving profile mode (mode 2)
            if [ -f "$dev/pp_power_profile_mode" ]; then
              echo "2" > "$dev/pp_power_profile_mode" 2>/dev/null || true
              echo "  • Power Profile Mode:    set to 'POWER_SAVING'"
            fi

            # Enable PCIe runtime PM
            pci_power="$dev/power/control"
            if [ -f "$pci_power" ]; then
              echo "auto" > "$pci_power"
              echo "  • PCIe Runtime PM:       set to 'auto'"
            fi

            found_gpu=1
          fi
        done

        if [ "$found_gpu" -eq 0 ]; then
          echo "Warning: No AMD GPU sysfs device found."
        fi

        # Step 3: Screen lock / screensaver activation to minimize display power
        echo ""
        echo "Locking desktop display session and engaging DPMS sleep..."
        loginctl lock-sessions 2>/dev/null || true
        user_uid=$(id -u "${cfg.user}" 2>/dev/null || echo "1000")
        if [ -S "/run/user/$user_uid/bus" ]; then
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_uid/bus" \
            gdbus call --session \
              --dest org.gnome.ScreenSaver \
              --object-path /org/gnome/ScreenSaver \
              --method org.gnome.ScreenSaver.SetActive true 2>/dev/null || true
        fi

        echo ""
        echo "GPU spindown complete!"
        echo ""
        check-gpu-power
      '')

      # 3. spinup-gpu: Restores GPU to dynamic scaling and wakes display
      (writeShellScriptBin "spinup-gpu" ''
        set -euo pipefail

        if [ "$EUID" -ne 0 ]; then
          exec sudo "$0" "$@"
        fi

        echo ">>> Spinning up homelab GPU to dynamic performance mode..."
        echo ""

        found_gpu=0
        for dev in /sys/class/drm/card[0-9]/device; do
          [ -f "$dev/vendor" ] || continue
          if [ "$(cat "$dev/vendor")" = "0x1002" ]; then
            card_name=$(basename "$(dirname "$dev")")
            echo "Spinning up $card_name..."

            # Restore dynamic DPM scaling
            if [ -f "$dev/power_dpm_force_performance_level" ]; then
              echo "auto" > "$dev/power_dpm_force_performance_level"
              echo "  • DPM Performance Level: restored to 'auto'"
            fi

            # Restore default power profile mode
            if [ -f "$dev/pp_power_profile_mode" ]; then
              echo "0" > "$dev/pp_power_profile_mode" 2>/dev/null || true
              echo "  • Power Profile Mode:    restored to 'BOOTUP_DEFAULT'"
            fi

            found_gpu=1
          fi
        done

        if [ "$found_gpu" -eq 0 ]; then
          echo "Warning: No AMD GPU sysfs device found."
        fi

        # Step 2: Wake screen & session
        echo ""
        echo "Waking desktop display session..."
        user_uid=$(id -u "${cfg.user}" 2>/dev/null || echo "1000")
        if [ -S "/run/user/$user_uid/bus" ]; then
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_uid/bus" \
            gdbus call --session \
              --dest org.gnome.ScreenSaver \
              --object-path /org/gnome/ScreenSaver \
              --method org.gnome.ScreenSaver.SetActive false 2>/dev/null || true
        fi
        loginctl unlock-sessions 2>/dev/null || true

        # Step 3: Ensure Sunshine service is active
        echo "Ensuring Sunshine service is active..."
        systemctl --user -M ${cfg.user}@ start sunshine.service 2>/dev/null || true

        echo ""
        echo "GPU spinup complete!"
        echo ""
        check-gpu-power
      '')

      # 4. check-gpu-power: Displays current power, temperatures, and GPU users
      (writeShellScriptBin "check-gpu-power" ''
        set -euo pipefail

        if [ "$EUID" -ne 0 ]; then
          exec sudo "$0" "$@"
        fi

        BOLD='\033[1m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        CYAN='\033[0;36m'
        NC='\033[0m'

        found=0
        for dev in /sys/class/drm/card[0-9]/device; do
          [ -f "$dev/vendor" ] || continue
          [ "$(cat "$dev/vendor")" = "0x1002" ] || continue

          found=1
          card_name=$(basename "$(dirname "$dev")")
          pci_id=$(basename "$(readlink -f "$dev")")

          echo -e "''${BOLD}======================================================''${NC}"
          echo -e "''${BOLD}              GPU POWER & HARDWARE STATUS             ''${NC}"
          echo -e "''${BOLD}======================================================''${NC}"
          echo -e "Device:         ''${CYAN}$card_name ($pci_id)''${NC}"

          # DPM Performance level
          if [ -f "$dev/power_dpm_force_performance_level" ]; then
            dpm=$(cat "$dev/power_dpm_force_performance_level")
            if [ "$dpm" = "low" ]; then
              echo -e "DPM Level:      ''${GREEN}low (Power-Saving / Spun Down)''${NC}"
            else
              echo -e "DPM Level:      ''${YELLOW}$dpm (Dynamic Performance / Spun Up)''${NC}"
            fi
          fi

          # Power Profile Mode
          if [ -f "$dev/pp_power_profile_mode" ]; then
            active_profile=$(grep "\*" "$dev/pp_power_profile_mode" | awk '{print $2}' | tr -d '*' | tr -d ':')
            echo -e "Power Profile:  $active_profile"
          fi

          # Power & Sensors
          for hwmon in "$dev"/hwmon/hwmon*; do
            [ -d "$hwmon" ] || continue
            if [ -f "$hwmon/power1_average" ]; then
              pw=$(cat "$hwmon/power1_average")
              pw_w=$(awk "BEGIN {printf \"%.2f\", $pw / 1000000}")
              echo -e "Power Draw:     ''${BOLD}''${pw_w} W''${NC}"
            fi
            if [ -f "$hwmon/temp1_input" ]; then
              t1=$(cat "$hwmon/temp1_input")
              echo -e "Temp (Edge):    $(( t1 / 1000 ))°C"
            fi
            if [ -f "$hwmon/temp2_input" ]; then
              t2=$(cat "$hwmon/temp2_input")
              echo -e "Temp (Junction):$(( t2 / 1000 ))°C"
            fi
            if [ -f "$hwmon/fan1_input" ]; then
              fan=$(cat "$hwmon/fan1_input")
              echo -e "Fan Speed:      $fan RPM"
            fi
          done

          # Clock Frequencies
          if [ -f "$dev/pp_dpm_sclk" ]; then
            cur_sclk=$(grep "\*" "$dev/pp_dpm_sclk" | head -n 1 | awk '{print $2}')
            echo -e "Core Clock:     $cur_sclk"
          fi
          if [ -f "$dev/pp_dpm_mclk" ]; then
            cur_mclk=$(grep "\*" "$dev/pp_dpm_mclk" | head -n 1 | awk '{print $2}')
            echo -e "Memory Clock:   $cur_mclk"
          fi

          echo -e "''${BOLD}------------------------------------------------------''${NC}"
          echo -e "''${BOLD}Active GPU File Descriptors (/dev/dri, /dev/kfd):''${NC}"

          dri_pids=""
          if command -v fuser &>/dev/null; then
            dri_pids=$(fuser /dev/dri/* /dev/kfd 2>/dev/null || true)
          fi

          proc_found=0
          if [ -n "$dri_pids" ]; then
            unique_pids=$(printf "%s\n" $dri_pids | sort -nu)
            for pid in $unique_pids; do
              [ -d "/proc/$pid" ] || continue
              exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
              base=$(basename "$exe" 2>/dev/null | sed -e 's/^\.//' -e 's/-wrapped$//' || true)
              user=$(ps -o user= -p "$pid" 2>/dev/null || echo "unknown")
              printf "  • PID %-7s %-10s %-20s\n" "$pid" "$user" "$base"
              proc_found=1
            done
          fi

          if [ "$proc_found" -eq 0 ]; then
            echo "  (No active GPU users)"
          fi
          echo -e "''${BOLD}======================================================''${NC}"
        done

        if [ "$found" -eq 0 ]; then
          echo "No AMD GPU device found."
        fi
      '')
    ];

    # Optional auto-spindown on boot
    systemd.services.gpu-spindown-boot = mkIf cfg.autoSpindownOnBoot {
      description = "Spin down GPU to low-power profile on boot";
      after = ["graphical.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeShellScript "gpu-spindown-boot" ''
          for dev in /sys/class/drm/card[0-9]/device; do
            [ -f "$dev/vendor" ] || continue
            if [ "$(cat "$dev/vendor")" = "0x1002" ]; then
              if [ -f "$dev/power_dpm_force_performance_level" ]; then
                echo "low" > "$dev/power_dpm_force_performance_level"
              fi
              if [ -f "$dev/pp_power_profile_mode" ]; then
                echo "2" > "$dev/pp_power_profile_mode" 2>/dev/null || true
              fi
            fi
          done
        ''}";
      };
    };
  };
}
