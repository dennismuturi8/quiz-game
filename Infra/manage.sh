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
  echo "  status         Show ArgoCD apps, pods, services, monitoring and gateway status"
  echo "  gateway-status Show HTTPRoutes, Gateway conditions, data-plane NodePort and logs"
  echo "  password       Print ArgoCD and Grafana admin passwords with access URLs"
  echo "  urls           Resolve ALB DNS and print all app + monitoring URLs"
  echo "  ssh            Open SSH session to control plane via bastion"
  echo "  proxy          Start SOCKS5 proxy on localhost:9090 via bastion"
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
        echo -e "  🎮 Quiz App    : ${GREEN}http://quiz.$ALB_IP.nip.io${NC}"
        echo -e "  🏆 Leaderboard : ${GREEN}http://quiz.$ALB_IP.nip.io/leaderboard${NC}"
        echo ""
        echo -e "${BOLD}─── Monitoring URLs (via Gateway) ─────────────${NC}"
        echo -e "  📈 Grafana      : ${GREEN}http://$ALB_IP/grafana${NC}"
        echo -e "  🔥 Prometheus   : ${GREEN}http://$ALB_IP/prometheus${NC}"
        echo -e "  🔔 Alertmanager : ${GREEN}http://$ALB_IP/alertmanager${NC}"
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
    info "Fetching cluster status..."
    echo ""

    echo -e "${BOLD}─── ArgoCD Apps (all) ─────────────────────────${NC}"
    kube "get applications -n argocd \
      -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" \
      2>/dev/null || warn "No ArgoCD applications found — run: ./manage.sh ansible"

    echo ""
    echo -e "${BOLD}─── Pods ($NAMESPACE) ─────────────────────────${NC}"
    kube "get pods -n $NAMESPACE -o wide" \
      2>/dev/null || warn "No pods found in $NAMESPACE"

    echo ""
    echo -e "${BOLD}─── Services ($NAMESPACE) ─────────────────────${NC}"
    kube "get svc -n $NAMESPACE" \
      2>/dev/null || warn "No services found in $NAMESPACE"

    echo ""
    echo -e "${BOLD}─── HPAs ($NAMESPACE) ─────────────────────────${NC}"
    kube "get hpa -n $NAMESPACE" \
      2>/dev/null || warn "No HPAs found in $NAMESPACE"

    echo ""
    echo -e "${BOLD}─── Monitoring Pods ───────────────────────────${NC}"
    kube "get pods -n monitoring -o wide --no-headers" \
      2>/dev/null | awk '{printf "%-50s %-12s %s\n", $1, $3, $7}' \
      || warn "No monitoring pods found"

    echo ""
    echo -e "${BOLD}─── Gateway Data-Plane Service ────────────────${NC}"
    kube "get svc quiz-game-gateway-nginx -n nginx-gateway \
      -o custom-columns=SVC:.metadata.name,TYPE:.spec.type,NODEPORT:.spec.ports[*].nodePort,METALLB-IP:.status.loadBalancer.ingress[0].ip" \
      2>/dev/null || warn "quiz-game-gateway-nginx not found — gateway not yet provisioned"
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
    echo -e "${BOLD}─── Monitoring URLs (via ALB — run: ./manage.sh urls) ─${NC}"
    echo "  📈 Grafana      : http://<ALB-IP>/grafana"
    echo "  🔥 Prometheus   : http://<ALB-IP>/prometheus"
    echo "  🔔 Alertmanager : http://<ALB-IP>/alertmanager"
    echo "  (Run './manage.sh urls' to resolve the actual ALB IP)"
    echo ""
    echo -e "${BOLD}─── Port-forwards (fallback / local access) ───${NC}"
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
    echo -e "${BOLD}─── Quiz Game URLs ─────────────────────────────${NC}"
    echo -e "  🎮 Quiz App    : ${GREEN}http://quiz.$ALB_IP.nip.io${NC}"
    echo -e "  🏆 Leaderboard : ${GREEN}http://quiz.$ALB_IP.nip.io/leaderboard${NC}"
    echo ""
    echo -e "${BOLD}─── Monitoring URLs (via ALB → Gateway) ────────${NC}"
    echo -e "  📈 Grafana      : ${GREEN}http://$ALB_IP/grafana${NC}"
    echo -e "  🔥 Prometheus   : ${GREEN}http://$ALB_IP/prometheus${NC}"
    echo -e "  🔔 Alertmanager : ${GREEN}http://$ALB_IP/alertmanager${NC}"
    echo ""
    echo -e "${BOLD}─── nip.io aliases ─────────────────────────────${NC}"
    echo -e "  📈 Grafana      : ${GREEN}http://quiz.$ALB_IP.nip.io/grafana${NC}"
    echo -e "  🔥 Prometheus   : ${GREEN}http://quiz.$ALB_IP.nip.io/prometheus${NC}"
    echo -e "  🔔 Alertmanager : ${GREEN}http://quiz.$ALB_IP.nip.io/alertmanager${NC}"
    echo ""
    echo "  ALB DNS : $ALB_DNS"
    echo "  ALB IP  : $ALB_IP"
    echo ""
    ;;

# ─── Command: gateway-status ──────────────────────────────────────────────────
  gateway-status)
    extract_tf_outputs
    setup_ssh_agent
    info "Fetching Gateway API status..."
    echo ""

    echo -e "${BOLD}─── GatewayClasses ────────────────────────────${NC}"
    kube "get gatewayclass"

    echo ""
    echo -e "${BOLD}─── Gateways (all namespaces) ─────────────────${NC}"
    kube "get gateway -A"

    echo ""
    echo -e "${BOLD}─── HTTPRoutes (all namespaces) ───────────────${NC}"
    kube "get httproute -A"

    echo ""
    echo -e "${BOLD}─── monitoring-routes conditions ──────────────${NC}"
    kube "get httproute monitoring-routes -n nginx-gateway -o json 2>/dev/null | python3 -c \"
import sys,json
r=json.load(sys.stdin)
parents=r.get('status',{}).get('parents',[])
[print(c['type']+': '+c['status']+' — '+c.get('message','')) for p in parents for c in p.get('conditions',[])] if parents else print('NO_PARENTS — gateway not yet attached')
\"" 2>/dev/null || warn "monitoring-routes HTTPRoute not found"

    echo ""
    echo -e "${BOLD}─── ReferenceGrant (monitoring ns) ────────────${NC}"
    kube "get referencegrant -n monitoring"       2>/dev/null || warn "No ReferenceGrant found in monitoring namespace"

    echo ""
    echo -e "${BOLD}─── Data-plane service NodePort ───────────────${NC}"
    kube "get svc quiz-game-gateway-nginx -n nginx-gateway       -o custom-columns=SVC:.metadata.name,TYPE:.spec.type,NODEPORT:.spec.ports[*].nodePort,LB-IP:.status.loadBalancer.ingress[0].ip"       2>/dev/null || warn "quiz-game-gateway-nginx not found — Gateway not yet provisioned"

    echo ""
    echo -e "${BOLD}─── nginx-gateway logs (last 30 lines) ────────${NC}"
    kube "logs deployment/nginx-gateway -n nginx-gateway --tail=30"
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