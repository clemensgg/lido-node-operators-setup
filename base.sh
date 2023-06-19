#!/usr/bin/env bash

set -e
set -u
set -o pipefail

export ANSIBLE_FORCE_COLOR="True"

# Description:
# Shell script for initiall cofiguration to deploy all needed software
#
# Run as
# curl -L https://raw.githubusercontent.com/path_to_script | bash -s

# ENVs
. /etc/os-release
DATE=$(date +%T_%d-%m-%Y)
LOG_FILE="installation.log"
REPO_USER="clemensgg"
CUSTOM_INVENTORY="variables"

# SSH ENVs
CURRENT_USERNAME=$(whoami)
KNOWN_HOSTS=~/.ssh/known_hosts

# SECRET ENVs
PREGEN_SECRETS="jwtsecret.hex"
SECRETS_FILE="secret_variables"

# Functions
read_sudo_password() {
  echo "Please enter the hosts sudo password:"
  read -s SUDO_PW
}

check_os_version() {
  if [ ${ID} == "ubuntu" ]; then
    case ${VERSION_ID} in
    20.04 | 22.04)
      echo -ne "${DATE} ${PRETTY_NAME} is supported\n"
      echo -ne "\n"
      ;;
    *)
      echo -ne "${PRETTY_NAME} is not supported by this script\n"
      echo -ne "\n"
      exit 2
      ;;
    esac
  fi
}

export_custom_envs() {
  export ETHEREUM_NODES_IP=${ETHEREUM_NODES_IP}
  export ETHEREUM_NODES_SSH_PORT=${ETHEREUM_NODES_SSH_PORT}
  export ETHEREUM_NODES_SSH_KEY=${ETHEREUM_NODES_SSH_KEY}
  export ETHEREUM_NODES_SSH_USER=${ETHEREUM_NODES_SSH_USER}
  export VALIDATORS_EJECTOR_IP=${VALIDATORS_EJECTOR_IP}
  export VALIDATORS_EJECTOR_SSH_PORT=${VALIDATORS_EJECTOR_SSH_PORT}
  export VALIDATORS_EJECTOR_SSH_KEY=${VALIDATORS_EJECTOR_SSH_KEY}
  export VALIDATORS_EJECTOR_SSH_USER=${VALIDATORS_EJECTOR_SSH_USER}
  export MONITORING_SERVER_IP=${MONITORING_SERVER_IP}
  export MONITORING_SERVER_SSH_PORT=${MONITORING_SERVER_SSH_PORT}
  export MONITORING_SERVER_SSH_KEY=${MONITORING_SERVER_SSH_KEY}
  export MONITORING_SERVER_SSH_USER=${MONITORING_SERVER_SSH_USER}
  export VALIDATOR_EJECTOR_STAKING_MODULE_ID=${VALIDATOR_EJECTOR_STAKING_MODULE_ID}
  export VALIDATOR_EJECTOR_OPERATOR_ID=${VALIDATOR_EJECTOR_OPERATOR_ID}
  export VALIDATOR_EJECTOR_MESSAGES_PASSWORD=${VALIDATOR_EJECTOR_MESSAGES_PASSWORD}
  export TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
  export TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
  export SUDO_PW
}

export_pregen_secrets() {
  export JWT_TOKEN=${JWT_TOKEN}
}

export_secrets() {
  export ALERTS_BOX_GRAFANA_USER=${ALERTS_BOX_GRAFANA_USER}
  export ALERTS_BOX_GRAFANA_PASSWORD=${ALERTS_BOX_GRAFANA_PASSWORD}
  export LIDO_KEYS_API_DB_PASSWORD=${LIDO_KEYS_API_DB_PASSWORD}
}

add_host_keys_to_known_host() {
  echo "${ETHEREUM_NODES_IP} ${VALIDATORS_EJECTOR_IP} ${MONITORING_SERVER_IP}"
  ssh-keyscan -p ${ETHEREUM_NODES_SSH_PORT} -H ${ETHEREUM_NODES_IP} >>${KNOWN_HOSTS}
  ssh-keyscan -p ${VALIDATORS_EJECTOR_SSH_PORT} -H ${VALIDATORS_EJECTOR_IP} >>${KNOWN_HOSTS}
  ssh-keyscan -p ${MONITORING_SERVER_SSH_PORT} -H ${MONITORING_SERVER_IP} >>${KNOWN_HOSTS}
  sort ${KNOWN_HOSTS} | uniq >${KNOWN_HOSTS}.uniq
  mv ${KNOWN_HOSTS}{.uniq,}
}

check_custom_inventory_existence() {
  if [ -f ${CUSTOM_INVENTORY} ]; then
    echo -ne "${DATE} File -> ${CUSTOM_INVENTORY} <- exists\n"
    source ${CUSTOM_INVENTORY}
    echo "Exporting env vars"
    export_custom_envs
    echo "Adding host keys to known_hosts"
    add_host_keys_to_known_host
  else
    echo -ne "${DATE} You have to provide -> ${CUSTOM_INVENTORY} <- file\n"
    echo -ne "\n"
    exit 2
  fi
  echo -ne "\n"
}

check_gen_secret_variables() {
  if [ -f ${SECRETS_FILE} ]; then
    echo -ne "${DATE} File -> ${SECRETS_FILE} <- exists\n"
    source ${SECRETS_FILE}
    if [ -z $ALERTS_BOX_GRAFANA_USER ]; then
      echo "no defined ALERTS_BOX_GRAFANA_USER variable"
      exit 2
    fi
    if [ -z $ALERTS_BOX_GRAFANA_PASSWORD ]; then
      echo "no defined ALERTS_BOX_GRAFANA_PASSWORD variable"
      exit 2
    fi
    if [ -z $LIDO_KEYS_API_DB_PASSWORD ]; then
      echo "no defined LIDO_KEYS_API_DB_PASSWORD variable"
      exit 2
    fi
    echo "ALERTS_BOX_GRAFANA_USER, ALERTS_BOX_GRAFANA_PASSWORD, LIDO_KEYS_API_DB_PASSWORD exist and have value"
    echo -ne "\n"
  else
    echo -ne "${DATE} Generating new secrets in $SECRETS_FILE"
    echo "ALERTS_BOX_GRAFANA_USER=operator-$(openssl rand -base64 5 | tr -d "=+/" | cut -c1-4)" >${SECRETS_FILE}
    echo "ALERTS_BOX_GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-29)" >>${SECRETS_FILE}
    echo "LIDO_KEYS_API_DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-29)" >>${SECRETS_FILE}
  fi
  source ${SECRETS_FILE}
  export_secrets
}

check_pregen_secrets() {
  if [ -s ${PREGEN_SECRETS} ]; then
    echo -ne "${DATE} File -> ${PREGEN_SECRETS} <- exists\n"
    echo -ne "\n"
    source ${PREGEN_SECRETS}
    export_pregen_secrets
  else
    echo -ne "${DATE} Generating secrets\n"
    echo -ne "\n"
    echo "JWT_TOKEN=$(openssl rand -hex 32 | tr -d "\n")" >${PREGEN_SECRETS}
    source ${PREGEN_SECRETS}
    export_pregen_secrets
  fi
}

install_ansible() {
  echo "${DATE} Checking if Ansible is already installed"
  if hash ansible 2>/dev/null; then
    echo -ne "${DATE} Ansible is already installed\n"
    echo -ne "\n"
  else
    echo -ne "${DATE} Adding Ansible PPA\n"
    sudo apt-add-repository ppa:ansible/ansible -y
    echo -ne "${DATE} Installing Ansible\n"
    sudo apt-get update
    sudo apt-get install software-properties-common ansible -y
  fi
}

install_git() {
  echo -ne "${DATE} Checking if Git is already installed\n"
  if hash git 2>/dev/null; then
    echo -ne "${DATE} Git is already installed\n"
    echo -ne "\n"
  else
    echo -ne "${DATE} Installing Git\n"
    sudo apt-get install git -y
  fi
}

install_openssl() {
  echo -ne "${DATE} Checking if openssl is already installed\n"
  if hash openssl 2>/dev/null; then
    echo -ne "${DATE} openssl is already installed\n"
    echo -ne "\n"
  else
    echo -ne "${DATE} Installing openssl\n"
    sudo apt-get install openssl -y
  fi
}

add_ssh_keys() {
  ssh-add ${ETHEREUM_NODES_SSH_KEY}
  ssh-add ${VALIDATORS_EJECTOR_SSH_KEY}
  ssh-add ${MONITORING_SERVER_SSH_KEY}
}

ansible_initial_run() {
  pip uninstall ansible-base
  pip install ansible-core
  ansible-galaxy collection install community.docker
  set +e
  if [ -f ansible/inventories/${ENVIRONMENT}.yml ]; then
    ansible all -i ansible/inventories/${ENVIRONMENT}.yml -m ping
  else
    echo "No inventory file for ${ENVIRONMENT} environment"
    exit 2
  fi
  if [ $? -eq 0 ]; then
    echo -ne "${DATE} SSH connection by Ansible is succesful\n"
    echo -ne "\n"
  else
    echo -ne "${DATE} SSH connection by Ansible isn't successful\n"
    exit 1
  fi
  set -e
}

ansible_run() {
  echo -ne "${DATE} Running Ansible with tag ${1}\n"
  export ANSIBLE_ROLES_PATH=ansible/roles/
  if [ -f ansible/inventories/${ENVIRONMENT}.yml ]; then
    ansible-playbook -i ansible/inventories/${ENVIRONMENT}.yml \
    ansible/playbooks/site.yml \
    -t ${1}
  else
    echo "No inventory file for ${ENVIRONMENT} environment"
    exit 2
  fi
}

main() {
  read_sudo_password
  echo -ne "${DATE} Starting installation script\n"
  check_os_version
  check_gen_secret_variables
  check_custom_inventory_existence
  install_ansible
  install_git
  install_openssl
  check_pregen_secrets
  add_ssh_keys
  ansible_initial_run
  ansible_run common
  ansible_run alerts-box
  ansible_run services
  ansible_run nodes
  echo -ne "${DATE} Installation script ended\n"
}

main | tee -a ${LOG_FILE}
