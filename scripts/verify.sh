#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || fail "Required command is not installed: $command_name"
}

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIRECTORY/.." && pwd)"
ANSIBLE_DIRECTORY="$REPOSITORY_ROOT/ansible"
RUNTIME_DIRECTORY="$REPOSITORY_ROOT/.runtime"
DEPLOYMENT_ENV_PATH="$RUNTIME_DIRECTORY/deployment.env"
NMAP_RESULTS_PATH="$RUNTIME_DIRECTORY/nmap-verification.txt"

require_command ansible
require_command nmap
[[ -f "$DEPLOYMENT_ENV_PATH" ]] || fail "Deployment environment data does not exist. Run ./scripts/provision.sh first."
[[ -f "$ANSIBLE_DIRECTORY/hosts.ini" ]] || fail "The generated Ansible inventory does not exist. Run ./scripts/provision.sh first."

# shellcheck disable=SC1090
source "$DEPLOYMENT_ENV_PATH"
[[ -n "${PUBLIC_IP:-}" ]] || fail "The deployment environment does not contain the server public IP address."

export ANSIBLE_CONFIG="$ANSIBLE_DIRECTORY/ansible.cfg"
cd "$ANSIBLE_DIRECTORY"

printf '\n== Verify automatic service startup and current service status ==\n'
ansible minecraft --become -m ansible.builtin.command -a "/usr/bin/systemctl is-enabled minecraft-container.service"
ansible minecraft --become -m ansible.builtin.command -a "/usr/bin/systemctl is-active minecraft-container.service"

printf '\n== Verify the running Docker container and image ==\n'
ansible minecraft --become -m ansible.builtin.command -a "/usr/bin/docker ps --filter name=minecraft-server"

printf '\n== Verify Minecraft port and query configuration in persistent server data ==\n'
ansible minecraft --become -m ansible.builtin.shell -a "grep -E '^(server-port|enable-query|query.port)=' /opt/minecraft/data/server.properties | sort"

printf '\n== Verify that systemd stops the container through docker stop ==\n'
ansible minecraft --become -m ansible.builtin.shell -a "systemctl cat minecraft-container.service | grep -E '^(ExecStart|ExecStop)='"

printf '\n== Run required public nmap verification ==\n'
printf 'nmap -sV -Pn -p T:25565 %s\n' "$PUBLIC_IP"
cd "$REPOSITORY_ROOT"
nmap -sV -Pn -p T:25565 "$PUBLIC_IP" | tee "$NMAP_RESULTS_PATH"

grep -Eq '^25565/tcp[[:space:]]+open' "$NMAP_RESULTS_PATH" || fail "nmap did not report TCP port 25565 as open."
printf '\nVerification complete.\n'
