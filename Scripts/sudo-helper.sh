# Shared privilege escalation for the install scripts.
#
# sudo needs a terminal to read a password, and these scripts are often run where
# there is none (an editor's run panel, an agent shell). When that happens we hand
# sudo an askpass helper that asks with the system dialog instead of failing.

_askpass_file=""

_cleanup_askpass() {
    [[ -n "$_askpass_file" && -f "$_askpass_file" ]] && rm -f "$_askpass_file"
}
trap _cleanup_askpass EXIT

_make_askpass() {
    _askpass_file="$(mktemp -t glassfan-askpass)"
    cat > "$_askpass_file" <<'ASKPASS'
#!/bin/bash
osascript \
    -e 'display dialog "GlassFan needs administrator rights to control the fans." with title "GlassFan" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"' \
    -e 'text returned of result' 2>/dev/null
ASKPASS
    chmod 700 "$_askpass_file"
    export SUDO_ASKPASS="$_askpass_file"
}

# Runs a command as root, asking for the password whichever way is possible here.
run_root() {
    if sudo -n true 2>/dev/null; then
        sudo "$@"
    elif [[ -t 0 ]]; then
        sudo "$@"
    else
        [[ -z "$_askpass_file" ]] && _make_askpass
        sudo -A "$@"
    fi
}
