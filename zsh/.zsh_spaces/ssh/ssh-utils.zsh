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
