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
require_command aws
[[ -f "$DEPLOYMENT_ENV_PATH" ]] || fail "Deployment environment data does not exist. Run ./scripts/provision.sh first."
[[ -f "$ANSIBLE_DIRECTORY/hosts.ini" ]] || fail "The Ansible inventory does not exist. Run ./scripts/provision.sh first."

# shellcheck disable=SC1090
source "$DEPLOYMENT_ENV_PATH"
[[ -n "${AWS_REGION:-}" && -n "${INSTANCE_ID:-}" ]] || fail "The deployment environment data is incomplete."
aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1 || fail "AWS Academy CLI credentials are missing or expired."

export ANSIBLE_CONFIG="$ANSIBLE_DIRECTORY/ansible.cfg"
cd "$ANSIBLE_DIRECTORY"

printf '\n== Demonstrate Minecraft container shutdown ==\n'
ansible minecraft --become -m ansible.builtin.command -a "/usr/bin/systemctl stop minecraft-container.service"

printf '\n== Display shutdown log output from stopped container ==\n'
ansible minecraft --become -m ansible.builtin.shell -a "/usr/bin/docker logs --tail 40 minecraft-server 2>&1"

printf '\n== Start service again before testing EC2 reboot ==\n'
ansible minecraft --become -m ansible.builtin.command -a "/usr/bin/systemctl start minecraft-container.service"
ansible minecraft --become -m ansible.builtin.wait_for -a "host=127.0.0.1 port=25565 delay=2 timeout=600"

printf '\n== Reboot EC2 instance through the AWS CLI ==\n'
aws ec2 reboot-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"
sleep 30
aws ec2 wait instance-status-ok --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"

printf '\n== Wait for automated Ansible connectivity after reboot ==\n'
ANSIBLE_REACHABLE=0
for attempt in {1..30}; do
    if ansible minecraft -m ansible.builtin.ping > "$RUNTIME_DIRECTORY/ansible-after-reboot.txt" 2>&1; then
        cat "$RUNTIME_DIRECTORY/ansible-after-reboot.txt"
        ANSIBLE_REACHABLE=1
        break
    fi
    printf 'Attempt %d of 30: instance not ready after reboot. Waiting 10 seconds.\n' "$attempt"
    sleep 10
done

if [[ "$ANSIBLE_REACHABLE" -ne 1 ]]; then
    cat "$RUNTIME_DIRECTORY/ansible-after-reboot.txt" >&2
    fail "Ansible could not connect after EC2 reboot."
fi

cd "$REPOSITORY_ROOT"
./scripts/verify.sh
