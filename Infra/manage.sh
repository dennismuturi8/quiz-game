#!/bin/bash
# =============================================================================
# manage.sh — Quiz Game Infrastructure & Cluster Manager
# =============================================================================

set -e

TF_DIR="./Terraform"
ANSIBLE_DIR="./Ansible"

APP_NAME="quiz-game"
NAMESPACE="quiz-game"

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}"
  echo "╔══════════════════════════════════════════════════╗"
  echo "║        🎮  Quiz Game Manager                      ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "${BOLD}Usage:${NC} $0 {command}"
  echo ""
  echo -e "${BOLD}Infrastructure:${NC}"
  echo "  up        Provision infra with Terraform, generate inventory, run Ansible"
  echo "  down      Destroy all infrastructure and delete inventory.ini"
  echo "  ansible   Re-run Ansible only (no Terraform changes)"
  echo ""
  echo -e "${BOLD}Cluster:${NC}"
  echo "  status    Show ArgoCD app sync and health status"
  echo "  password  Print ArgoCD and Grafana admin passwords"
  echo "  urls      nslookup ALB and print nip.io app URLs"
  echo "  ssh       Open SSH session to control plane via bastion"
  echo "  proxy     Start SOCKS5 proxy on localhost:9090 via bastion"
  echo ""
  exit 1
}

[[ -z "$1" ]] && usage

# ─── Shared: Extract Terraform Outputs ────────────────────────────────────────
extract_tf_outputs() {
  info "Extracting Terraform outputs..."
  cd "$TF_DIR"
  BASTION=$(terraform output -raw bastion_ip)
  CONTROL_PLANE=$(terraform output -raw control_plane_ip)
  WORKERS=$(terraform output -json worker_ips | jq -r '.[]')
  SSH_USER=$(terraform output -raw ssh_user)
  KEY=$(terraform output -raw ssh_key_path)
  KEY="${KEY/#\~/$HOME}"
  cd ..
  success "Outputs extracted — bastion=$BASTION, control_plane=$CONTROL_PLANE"
}

# ─── Shared: Setup SSH Agent ──────────────────────────────────────────────────
setup_ssh_agent() {
  info "Setting up SSH agent..."
  if ! ssh-add -l &>/dev/null; then
    eval "$(ssh-agent -s)" >/dev/null
  fi
  ssh-add "$KEY"
  success "SSH key added to agent."
}

# ─── Shared: Generate Ansible Inventory ───────────────────────────────────────
generate_inventory() {
  info "Generating inventory.ini from Terraform outputs..."

  PROXY_CMD="ssh -W %h:%p -o StrictHostKeyChecking=no -i $KEY $SSH_USER@$BASTION"

  cat > "$ANSIBLE_DIR/inventory.ini" <<EOF
[bastion]
jumphost ansible_host=$BASTION ansible_user=$SSH_USER ansible_ssh_private_key_file=$KEY

[control_plane]
$CONTROL_PLANE ansible_user=$SSH_USER ansible_ssh_private_key_file=$KEY

[workers]
$(for ip in $WORKERS; do echo "$ip ansible_user=$SSH_USER ansible_ssh_private_key_file=$KEY"; done)

[all:vars]
ansible_python_interpreter=/usr/bin/python3

[control_plane:vars]
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o ForwardAgent=yes -o ProxyCommand="$PROXY_CMD"

[workers:vars]
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o ForwardAgent=yes -o ProxyCommand="$PROXY_CMD"
EOF

  cat > "$ANSIBLE_DIR/ansible.cfg" <<EOF
[defaults]
host_key_checking = False
interpreter_python = /usr/bin/python3

[ssh_connection]
ssh_args = -o ForwardAgent=yes -o StrictHostKeyChecking=no -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
EOF

  success "inventory.ini and ansible.cfg written to $ANSIBLE_DIR/"
}

# ─── Shared: kubectl helper (runs via bastion jump) ───────────────────────────
kube() {
  ssh -o StrictHostKeyChecking=no -A \
    -J "$SSH_USER@$BASTION" "$SSH_USER@$CONTROL_PLANE" \
    "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf $*"
}

# ─── Command: up ──────────────────────────────────────────────────────────────
case "$1" in
  up)
    echo ""
    info "=== Starting Quiz Game Full Deployment ==="
    echo ""

    # 1 — Terraform
    info "[1/4] Running Terraform..."
    cd "$TF_DIR"
    terraform init -input=false
    terraform apply -auto-approve
    cd ..
    success "Terraform complete."

    # 2 — Extract outputs
    info "[2/4] Extracting outputs..."
    extract_tf_outputs

    # 3 — SSH agent + inventory
    info "[3/4] Preparing Ansible..."
    setup_ssh_agent
    generate_inventory

    # 4 — Ansible
    info "[4/4] Waiting 30s for nodes to settle, then running Ansible..."
    sleep 30

    ansible-playbook \
      -i "$ANSIBLE_DIR/inventory.ini" \
      "$ANSIBLE_DIR/plybk.yaml" \
      --ssh-common-args="-o StrictHostKeyChecking=no -o ForwardAgent=yes"

    echo ""
    success "=== Quiz Game Deployment Complete ==="
    echo ""

    # Credentials
    info "Fetching credentials..."
    setup_ssh_agent

    ARGOCD_PASSWORD=$(kube \
      "get secret argocd-initial-admin-secret -n argocd \
       -o jsonpath='{.data.password}' | base64 --decode && echo")

    GRAFANA_PASSWORD=$(kube \
      "get secret prometheus-grafana -n monitoring \
       -o jsonpath='{.data.admin-password}' | base64 --decode && echo" \
      2>/dev/null || echo "not yet available")

    echo ""
    echo -e "${BOLD}─── ArgoCD ────────────────────────────────────${NC}"
    echo "  Username : admin"
    echo -e "  Password : ${GREEN}$ARGOCD_PASSWORD${NC}"
    echo ""
    echo -e "${BOLD}─── Grafana ───────────────────────────────────${NC}"
    echo "  Username : admin"
    echo -e "  Password : ${GREEN}$GRAFANA_PASSWORD${NC}"
    echo ""

    # URLs
    ALB_DNS=$(cd "$TF_DIR" && terraform output -raw alb_dns 2>/dev/null || echo "")
    if [[ -n "$ALB_DNS" ]]; then
      ALB_IP=$(nslookup "$ALB_DNS" 2>/dev/null | awk '/^Address: / { print $2; exit }')
      if [[ -n "$ALB_IP" ]]; then
        echo -e "${BOLD}─── Quiz Game URLs ────────────────────────────${NC}"
        echo -e "  🎮 Quiz App   : ${GREEN}http://quiz.$ALB_IP.nip.io${NC}"
        echo -e "  🏆 Leaderboard: ${GREEN}http://quiz.$ALB_IP.nip.io/leaderboard${NC}"
        echo ""
      fi
    fi
    ;;

# ─── Command: down ────────────────────────────────────────────────────────────
  down)
    echo ""
    warn "=== Destroying All Quiz Game Infrastructure ==="
    read -rp "Are you sure? This cannot be undone. (yes/no): " CONFIRM
    [[ "$CONFIRM" != "yes" ]] && { info "Aborted."; exit 0; }

    cd "$TF_DIR"
    terraform destroy -auto-approve
    cd ..
    rm -f "$ANSIBLE_DIR/inventory.ini"
    rm -f "$ANSIBLE_DIR/ansible.cfg"
    success "inventory.ini & ansible.cfg deleted."
    success "=== Destroy Complete ==="
    ;;

# ─── Command: ansible ─────────────────────────────────────────────────────────
  ansible)
    echo ""
    info "=== Re-running Ansible Only ==="

    if [[ ! -f "$ANSIBLE_DIR/inventory.ini" ]]; then
      warn "inventory.ini not found — regenerating from Terraform outputs..."
      extract_tf_outputs
      setup_ssh_agent
      generate_inventory
    fi

    ansible-playbook \
      -i "$ANSIBLE_DIR/inventory.ini" \
      "$ANSIBLE_DIR/plybk.yaml" \
      --ssh-common-args="-o StrictHostKeyChecking=no -o ForwardAgent=yes"

    success "=== Ansible Complete ==="
    ;;

# ─── Command: status ──────────────────────────────────────────────────────────
  status)
    extract_tf_outputs
    setup_ssh_agent
    info "Fetching ArgoCD status for: $APP_NAME"
    echo ""

    echo -e "${BOLD}─── ArgoCD App ────────────────────────────────${NC}"
    kube "get application $APP_NAME -n argocd \
      -o custom-columns=\
'APP:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status'"

    echo ""
    echo -e "${BOLD}─── Pods ($NAMESPACE) ─────────────────────────${NC}"
    kube "get pods -n $NAMESPACE -o wide"

    echo ""
    echo -e "${BOLD}─── Services ($NAMESPACE) ─────────────────────${NC}"
    kube "get svc -n $NAMESPACE"

    echo ""
    echo -e "${BOLD}─── Ingress ($NAMESPACE) ──────────────────────${NC}"
    kube "get ingress -n $NAMESPACE"

    echo ""
    echo -e "${BOLD}─── HPAs ($NAMESPACE) ─────────────────────────${NC}"
    kube "get hpa -n $NAMESPACE"
    ;;

# ─── Command: password ────────────────────────────────────────────────────────
  password)
    extract_tf_outputs
    setup_ssh_agent
    info "Retrieving passwords..."

    ARGOCD_PASSWORD=$(kube \
      "get secret argocd-initial-admin-secret -n argocd \
       -o jsonpath='{.data.password}' | base64 --decode && echo")

    GRAFANA_PASSWORD=$(kube \
      "get secret prometheus-grafana -n monitoring \
       -o jsonpath='{.data.admin-password}' | base64 --decode && echo" \
      2>/dev/null || echo "not yet available")

    echo ""
    echo -e "${BOLD}─── ArgoCD ────────────────────────────────────${NC}"
    echo "  Username : admin"
    echo -e "  Password : ${GREEN}$ARGOCD_PASSWORD${NC}"
    echo ""
    echo -e "${BOLD}─── Grafana ───────────────────────────────────${NC}"
    echo "  Username : admin"
    echo -e "  Password : ${GREEN}$GRAFANA_PASSWORD${NC}"
    echo ""
    echo -e "${BOLD}─── Port-forwards (run after: ./manage.sh proxy) ─${NC}"
    echo "  ArgoCD        : kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "                  → https://localhost:8080"
    echo ""
    echo "  Grafana       : kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"
    echo "                  → http://localhost:3000"
    echo ""
    echo "  Prometheus    : kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9091:9090"
    echo "                  → http://localhost:9091"
    echo ""
    echo "  Game Service  : kubectl port-forward svc/game-service -n $NAMESPACE 3001:3001"
    echo "                  → http://localhost:3001"
    echo ""
    echo "  Leaderboard   : kubectl port-forward svc/leaderboard-service -n $NAMESPACE 3002:3002"
    echo "                  → http://localhost:3002"
    echo ""
    echo -e "${BOLD}─── Or use SOCKS proxy ────────────────────────${NC}"
    echo "  Run: ./manage.sh proxy"
    echo "  Set browser SOCKS5 → 127.0.0.1:9090"
    echo ""
    ;;

# ─── Command: urls ────────────────────────────────────────────────────────────
  urls)
    extract_tf_outputs
    setup_ssh_agent

    info "Reading ALB DNS from Terraform outputs..."
    cd "$TF_DIR"
    ALB_DNS=$(terraform output -raw alb_dns 2>/dev/null || echo "")
    cd ..

    if [[ -z "$ALB_DNS" ]]; then
      warn "Could not read alb_dns from Terraform outputs. Check your main.tf has an alb_dns output."
      exit 1
    fi

    info "Running nslookup on $ALB_DNS..."
    ALB_IP=$(nslookup "$ALB_DNS" 2>/dev/null | awk '/^Address: / { print $2; exit }')

    if [[ -z "$ALB_IP" ]]; then
      warn "nslookup returned no IP yet — ALB may still be provisioning. Try again shortly."
      exit 1
    fi

    echo ""
    echo -e "${BOLD}─── Quiz Game URLs (via nip.io) ────────────────${NC}"
    echo -e "  🎮 Quiz App    : ${GREEN}http://quiz.$ALB_IP.nip.io${NC}"
    echo -e "  🏆 Leaderboard : ${GREEN}http://quiz.$ALB_IP.nip.io/leaderboard${NC}"
    echo ""
    echo -e "${BOLD}─── Monitoring (use SOCKS proxy or port-forward) ──${NC}"
    echo -e "  📈 Grafana      : ${GREEN}http://prometheus-grafana.monitoring.svc.cluster.local${NC}"
    echo -e "  🔥 Prometheus   : ${GREEN}http://prometheus-kube-prometheus-prometheus.monitoring:9090${NC}"
    echo -e "  🔔 Alertmanager : ${GREEN}http://prometheus-kube-prometheus-alertmanager.monitoring:9093${NC}"
    echo ""
    echo "  ALB DNS : $ALB_DNS"
    echo "  ALB IP  : $ALB_IP"
    echo ""
    ;;

# ─── Command: ssh ─────────────────────────────────────────────────────────────
  ssh)
    extract_tf_outputs
    setup_ssh_agent
    info "Opening SSH session to control plane via bastion..."
    ssh -o StrictHostKeyChecking=no -A \
      -J "$SSH_USER@$BASTION" "$SSH_USER@$CONTROL_PLANE"
    ;;

# ─── Command: proxy ───────────────────────────────────────────────────────────
  proxy)
    extract_tf_outputs
    setup_ssh_agent
    info "Starting SOCKS5 proxy on localhost:9090 — press Ctrl+C to stop."
    info "Set FoxyProxy or browser to SOCKS5 → 127.0.0.1:9090"
    echo ""
    ssh -D 9090 -N -o StrictHostKeyChecking=no -A \
      -J "$SSH_USER@$BASTION" "$SSH_USER@$CONTROL_PLANE"
    ;;

  *)
    usage
    ;;
esac
