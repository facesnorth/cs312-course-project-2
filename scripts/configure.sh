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

require_command ansible
require_command ansible-playbook
[[ -f "$ANSIBLE_DIRECTORY/hosts.ini" ]] || fail "The generated Ansible inventory does not exist. Run ./scripts/provision.sh first."
[[ -f "$RUNTIME_DIRECTORY/known_hosts" ]] || fail "The generated SSH known-hosts file does not exist. Run ./scripts/provision.sh first."

export ANSIBLE_CONFIG="$ANSIBLE_DIRECTORY/ansible.cfg"
cd "$ANSIBLE_DIRECTORY"

printf '\n== Wait for automated Ansible connectivity ==\n'
ANSIBLE_REACHABLE=0
for attempt in {1..30}; do
    if ansible minecraft -m ansible.builtin.ping > "$RUNTIME_DIRECTORY/ansible-ping.txt" 2>&1; then
        cat "$RUNTIME_DIRECTORY/ansible-ping.txt"
        ANSIBLE_REACHABLE=1
        break
    fi
    printf 'Attempt %d of 30: Ansible connection not ready; waiting 10 seconds.\n' "$attempt"
    sleep 10
done

if [[ "$ANSIBLE_REACHABLE" -ne 1 ]]; then
    cat "$RUNTIME_DIRECTORY/ansible-ping.txt" >&2
    fail "Ansible could not connect to the provisioned EC2 instance."
fi

printf '\n== Configure the Docker-based Minecraft server with Ansible ==\n'
ansible-playbook minecraft.yml | tee "$RUNTIME_DIRECTORY/ansible-first-run.txt"

printf '\n== Run the playbook again to demonstrate idempotency ==\n'
ansible-playbook minecraft.yml | tee "$RUNTIME_DIRECTORY/ansible-second-run.txt"

printf '\nConfiguration complete. Run ./scripts/verify.sh from the repository root.\n'
