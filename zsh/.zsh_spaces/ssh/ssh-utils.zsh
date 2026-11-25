# SSH Utilities — helpers for key management, tunnels, and host selection

# Add all private keys from ~/.ssh/ to the agent
ssh-add-all() {
    local count=0
    for key in ~/.ssh/id_*; do
        # Skip public keys and non-files
        [[ "$key" == *.pub ]] && continue
        [ ! -f "$key" ] && continue
        ssh-add "$key" 2>/dev/null && ((count++))
    done
    echo "ssh-add-all: added $count key(s)"
}

# Quick SSH tunnel: ssh-tunnel <host> <local_port> [remote_port]
# If remote_port is omitted, it defaults to local_port
ssh-tunnel() {
    if [ $# -lt 2 ]; then
        echo "Usage: ssh-tunnel <host> <local_port> [remote_port]" >&2
        return 1
    fi
    local host="$1" local_port="$2" remote_port="${3:-$2}"
    echo "ssh-tunnel: forwarding localhost:$local_port -> $host:$remote_port (Ctrl-C to stop)"
    ssh -N -L "$local_port:localhost:$remote_port" "$host"
}

# Pick an SSH host from ~/.ssh/config with fzf
ssh-hosts() {
    if [ ! -f ~/.ssh/config ]; then
        echo "ssh-hosts: ~/.ssh/config not found" >&2
        return 1
    fi
    local host
    host=$(awk '/^Host / && !/\*/ {print $2}' ~/.ssh/config | fzf --prompt="SSH host: " --border --height=40%)
    [ -n "$host" ] && ssh "$host"
}

# Send the clipboard image to an SSH host: imgssh [host]
# Images never cross SSH, so a remote Claude can't Ctrl+V them. This copies the
# image to the host's /tmp and puts that remote path on the local clipboard —
# paste the path into the remote session instead.
imgssh() {
    local host="$1"
    [ -z "$host" ] && host=$(awk '/^Host / && !/\*/ {print $2}' ~/.ssh/config | fzf --prompt="imgssh host: " --height=40%)
    [ -z "$host" ] && return 1
    local f="/tmp/clip-$(date +%Y%m%d-%H%M%S).png"
    if [[ "$OSTYPE" == darwin* ]]; then
        osascript -e "set f to open for access POSIX file \"$f\" with write permission" \
                  -e 'write (the clipboard as «class PNGf») to f' -e 'close access f' >/dev/null 2>&1
    elif [ -n "$WAYLAND_DISPLAY" ]; then
        wl-paste --type image/png > "$f" 2>/dev/null
    else
        xclip -selection clipboard -t image/png -o > "$f" 2>/dev/null
    fi
    [ -s "$f" ] || { rm -f "$f"; echo "imgssh: no image on the clipboard" >&2; return 1; }
    scp -q "$f" "$host:$f" || { rm -f "$f"; return 1; }
    rm -f "$f"
    if command -v pbcopy >/dev/null; then printf '%s' "$f" | pbcopy
    elif [ -n "$WAYLAND_DISPLAY" ]; then printf '%s' "$f" | wl-copy
    else printf '%s' "$f" | xclip -selection clipboard; fi
    echo "imgssh: → $host:$f (path copied, paste it into the remote session)"
}
