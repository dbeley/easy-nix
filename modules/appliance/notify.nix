{ pkgs }:
/*
  Send a notification to every user that has a session bus right now.

  Desktop notification only, never a mail or a log line: the point is that a person
  looking at the screen learns that an update is waiting. Failure is not an error
  (a machine with nobody logged in has nothing to notify).
*/
pkgs.writeShellApplication {
  name = "easy-nix-notify";

  runtimeInputs = [
    pkgs.systemd
    pkgs.gawk
    pkgs.coreutils
    pkgs.util-linux
    pkgs.libnotify
    pkgs.sudo
  ];

  text = ''
    title="''${1:?usage: easy-nix-notify TITLE [BODY]}"
    body="''${2:-}"

    loginctl list-sessions --no-legend | awk '{print $1}' | while read -r session; do
      name=$(loginctl show-session "$session" -p Name --value 2>/dev/null) || continue
      [ -n "$name" ] || continue

      uid=$(id -u "$name" 2>/dev/null) || continue
      bus="/run/user/$uid/bus"
      [ -S "$bus" ] || continue

      sudo -u "$name" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        notify-send --app-name=easy-nix "$title" "$body" || true
    done
  '';
}
