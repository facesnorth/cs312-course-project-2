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

validate_ipv4() {
    local address="$1"
    local first second third fourth

    IFS='.' read -r first second third fourth <<< "$address"
    [[ -n "${first:-}" && -n "${second:-}" && -n "${third:-}" && -n "${fourth:-}" ]] || return 1
    [[ "$first" =~ ^[0-9]+$ && "$second" =~ ^[0-9]+$ && "$third" =~ ^[0-9]+$ && "$fourth" =~ ^[0-9]+$ ]] || return 1
    (( first >= 0 && first <= 255 )) || return 1
    (( second >= 0 && second <= 255 )) || return 1
    (( third >= 0 && third <= 255 )) || return 1
    (( fourth >= 0 && fourth <= 255 )) || return 1
}

SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIRECTORY/.." && pwd)"
TERRAFORM_DIRECTORY="$REPOSITORY_ROOT/terraform"
ANSIBLE_DIRECTORY="$REPOSITORY_ROOT/ansible"
RUNTIME_DIRECTORY="$REPOSITORY_ROOT/.runtime"
TERRAFORM_VARIABLES_PATH="$RUNTIME_DIRECTORY/terraform.tfvars"
DEPLOYMENT_ENV_PATH="$RUNTIME_DIRECTORY/deployment.env"
KNOWN_HOSTS_PATH="$RUNTIME_DIRECTORY/known_hosts"
SSH_PRIVATE_KEY_PATH="$HOME/.ssh/cs312_course_project_2_ec2"
SSH_PUBLIC_KEY_PATH="${SSH_PRIVATE_KEY_PATH}.pub"
AWS_REGION="us-east-1"
AWS_AVAILABILITY_ZONE="us-east-1c"

for command_name in aws curl ssh-keygen ssh-keyscan terraform; do
    require_command "$command_name"
done

mkdir -p "$RUNTIME_DIRECTORY" "$HOME/.ssh"
chmod 700 "$RUNTIME_DIRECTORY" "$HOME/.ssh"

aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1 || fail "AWS Academy CLI credentials are missing or expired."
aws ec2 describe-availability-zones --region "$AWS_REGION" --zone-names "$AWS_AVAILABILITY_ZONE" >/dev/null 2>&1 || fail "The AWS CLI cannot access availability zone $AWS_AVAILABILITY_ZONE."

if [[ ! -f "$SSH_PRIVATE_KEY_PATH" && ! -f "$SSH_PUBLIC_KEY_PATH" ]]; then
    ssh-keygen -q -t rsa -b 4096 -N "" -C "cs312-course-project-2-ansible" -f "$SSH_PRIVATE_KEY_PATH"
elif [[ ! -f "$SSH_PRIVATE_KEY_PATH" || ! -f "$SSH_PUBLIC_KEY_PATH" ]]; then
    fail "Only one file in the project EC2 SSH key pair exists. Correct the key pair before provisioning."
fi

chmod 600 "$SSH_PRIVATE_KEY_PATH"
chmod 644 "$SSH_PUBLIC_KEY_PATH"

ADMIN_PUBLIC_IP="$(curl --ipv4 -fsS https://checkip.amazonaws.com | tr -d '[:space:]')" || fail "Unable to retrieve the control node public IPv4 address."
validate_ipv4 "$ADMIN_PUBLIC_IP" || fail "The retrieved control node address is not a valid IPv4 address."

cat > "$TERRAFORM_VARIABLES_PATH" <<EOFVARS
admin_cidr          = "$ADMIN_PUBLIC_IP/32"
ssh_public_key_path = "$SSH_PUBLIC_KEY_PATH"
EOFVARS
chmod 600 "$TERRAFORM_VARIABLES_PATH"

printf '\n== Validate AWS identity and fixed deployment location ==\n'
aws sts get-caller-identity --region "$AWS_REGION"
printf 'AWS Region: %s\n' "$AWS_REGION"
printf 'Availability Zone: %s\n' "$AWS_AVAILABILITY_ZONE"
printf 'Ansible management CIDR: %s/32\n' "$ADMIN_PUBLIC_IP"

printf '\n== Initialize and apply Terraform infrastructure ==\n'
terraform -chdir="$TERRAFORM_DIRECTORY" init
terraform -chdir="$TERRAFORM_DIRECTORY" fmt -check -recursive
terraform -chdir="$TERRAFORM_DIRECTORY" validate
terraform -chdir="$TERRAFORM_DIRECTORY" apply -auto-approve -var-file="$TERRAFORM_VARIABLES_PATH"

INSTANCE_ID="$(terraform -chdir="$TERRAFORM_DIRECTORY" output -raw instance_id)"
PUBLIC_IP="$(terraform -chdir="$TERRAFORM_DIRECTORY" output -raw instance_public_ip)"
validate_ipv4 "$PUBLIC_IP" || fail "Terraform did not return a valid public IPv4 address for the server."

printf 'AWS_REGION=%q\n' "$AWS_REGION" > "$DEPLOYMENT_ENV_PATH"
printf 'AWS_AVAILABILITY_ZONE=%q\n' "$AWS_AVAILABILITY_ZONE" >> "$DEPLOYMENT_ENV_PATH"
printf 'INSTANCE_ID=%q\n' "$INSTANCE_ID" >> "$DEPLOYMENT_ENV_PATH"
printf 'PUBLIC_IP=%q\n' "$PUBLIC_IP" >> "$DEPLOYMENT_ENV_PATH"
printf 'SSH_PRIVATE_KEY_PATH=%q\n' "$SSH_PRIVATE_KEY_PATH" >> "$DEPLOYMENT_ENV_PATH"
chmod 600 "$DEPLOYMENT_ENV_PATH"

cat > "$ANSIBLE_DIRECTORY/hosts.ini" <<EOFINVENTORY
[minecraft]
minecraft-server ansible_host=$PUBLIC_IP ansible_user=ubuntu ansible_ssh_private_key_file=$SSH_PRIVATE_KEY_PATH
EOFINVENTORY
chmod 600 "$ANSIBLE_DIRECTORY/hosts.ini"

printf '\n== Record the provisioned host key for automated Ansible management ==\n'
: > "$KNOWN_HOSTS_PATH"
HOST_KEY_RECORDED=0
for attempt in {1..30}; do
    if ssh-keyscan -T 5 -H "$PUBLIC_IP" > "$KNOWN_HOSTS_PATH" 2>/dev/null && [[ -s "$KNOWN_HOSTS_PATH" ]]; then
        HOST_KEY_RECORDED=1
        printf 'Recorded SSH host key for %s.\n' "$PUBLIC_IP"
        break
    fi
    printf 'Attempt %d of 30: SSH host key not available; waiting 10 seconds.\n' "$attempt"
    sleep 10
done

[[ "$HOST_KEY_RECORDED" -eq 1 ]] || fail "Unable to record the provisioned instance SSH host key."
chmod 600 "$KNOWN_HOSTS_PATH"

printf '\nInfrastructure provisioning complete.\n'
terraform -chdir="$TERRAFORM_DIRECTORY" output
printf '\nRun ./scripts/configure.sh to configure and start the Minecraft container.\n'
