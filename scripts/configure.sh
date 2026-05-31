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

require_command ansible
require_command ansible-playbook
require_command timeout

[[ -f "$ANSIBLE_DIRECTORY/hosts.ini" ]] || fail "The generated Ansible inventory does not exist. Run ./scripts/provision.sh first."
[[ -f "$RUNTIME_DIRECTORY/known_hosts" ]] || fail "The generated SSH known-hosts file does not exist. Run ./scripts/provision.sh first."

if [[ -f "$DEPLOYMENT_ENV_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$DEPLOYMENT_ENV_PATH"
    printf '\nTarget public IP: %s\n' "${PUBLIC_IP:-unknown}"
    printf 'Target instance ID: %s\n' "${INSTANCE_ID:-unknown}"
fi

export ANSIBLE_CONFIG="$ANSIBLE_DIRECTORY/ansible.cfg"
cd "$ANSIBLE_DIRECTORY"

printf '\n== Wait for automated Ansible connectivity ==\n'
ANSIBLE_REACHABLE=0

for attempt in {1..30}; do
    printf 'Attempt %d of 30: Ansible connection not ready. Waiting for response.\n' "$attempt"

    set +e
    timeout 20s ansible minecraft -m ansible.builtin.ping > "$RUNTIME_DIRECTORY/ansible-ping.txt" 2>&1
    ANSIBLE_PING_RC="$?"
    set -e

    if [[ "$ANSIBLE_PING_RC" -eq 0 ]]; then
        cat "$RUNTIME_DIRECTORY/ansible-ping.txt"
        ANSIBLE_REACHABLE=1
        break
    fi

    cat "$RUNTIME_DIRECTORY/ansible-ping.txt"
    printf 'Waiting 10 seconds.\n'
    sleep 10
done

if [[ "$ANSIBLE_REACHABLE" -ne 1 ]]; then
    fail "Ansible could not connect to the EC2 instance."
fi

printf '\n== Configure the Minecraft server with Ansible ==\n'
ansible-playbook minecraft.yml | tee "$RUNTIME_DIRECTORY/ansible-first-run.txt"

printf '\n== Run the playbook again to prove repeatability ==\n'
ansible-playbook minecraft.yml | tee "$RUNTIME_DIRECTORY/ansible-second-run.txt"

printf '\nConfiguration complete. Run ./scripts/verify.sh from the repository root.\n'
