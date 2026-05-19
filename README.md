# 🎮 Quiz Game — Complete Project Guide

**Welcome.** This document explains everything about the Quiz Game project — what it is,
how it works, how to deploy it, and how to use it — in plain language that anyone can
follow, whether you have years of technical experience or are just getting started.

If you are completely new to cloud infrastructure, start at the beginning and read
every section. If you are already familiar with Kubernetes and AWS, you can jump
straight to [Section 7 — Deploying the Project](#7-deploying-the-project).

---

## Table of Contents

1. [What Is This Project?](#1-what-is-this-project)
2. [How Everything Fits Together](#2-how-everything-fits-together)
3. [What You Need Before You Start](#3-what-you-need-before-you-start)
4. [The Project Files — What Each One Does](#4-the-project-files--what-each-one-does)
5. [One-Time Configuration](#5-one-time-configuration)
6. [Your Single Command Reference — manage.sh](#6-your-single-command-reference--managesh)
7. [Deploying the Project — `./manage.sh up`](#7-deploying-the-project----managesh-up)
8. [Accessing the Quiz Game](#8-accessing-the-quiz-game)
9. [Accessing Prometheus, Grafana and ArgoCD via the Internet](#9-accessing-prometheus-grafana-and-argocd-via-the-internet)
10. [How the Gateway API Routes Traffic](#10-how-the-gateway-api-routes-traffic)
11. [How Code Changes Deploy Automatically — CI/CD](#11-how-code-changes-deploy-automatically--cicd)
12. [Monitoring Your Application](#12-monitoring-your-application)
13. [Checking What Is Running — `./manage.sh status`](#13-checking-what-is-running----managesh-status)
14. [Scaling the Application](#14-scaling-the-application)
15. [Troubleshooting — When Things Go Wrong](#15-troubleshooting--when-things-go-wrong)
16. [Shutting Everything Down — `./manage.sh down`](#16-shutting-everything-down----managesh-down)
17. [Quick Reference Card](#17-quick-reference-card)

---

## 1. What Is This Project?

### The quiz game itself

The Quiz Game is a web application that tests your knowledge of DevOps — the field of
engineering that focuses on deploying and running software reliably. You visit a website,
enter your name, choose how many questions you want, and answer multiple-choice questions
about topics like Kubernetes, Docker, AWS, and CI/CD pipelines. At the end your score
is saved to a global leaderboard so you can compare yourself with others.

### Why it is also a DevOps project

The quiz game is not just an app — it *is* the DevOps practice. The way it is built and
deployed demonstrates a complete set of real-world engineering skills:

- **The app runs on its own private cloud cluster** hosted on Amazon Web Services (AWS)
- **Three separate programs** (called microservices) work together to make it run
- **Everything is automated** — one command spins up the entire infrastructure from scratch
- **Code changes deploy themselves** — pushing code to GitHub triggers an automatic
  build, security scan, and deployment with no manual steps
- **The system watches itself** — Prometheus and Grafana collect and display real-time
  health and performance data
- **Traffic is managed intelligently** — the Kubernetes Gateway API routes requests to
  exactly the right service

Think of it like a restaurant: the quiz game website is the dining room customers see,
but behind it there is a kitchen (the game service), a reservations book (the leaderboard),
a storage room (Redis), and a sophisticated system managing everything invisibly.

---

## 2. How Everything Fits Together

### The big picture

```
                    You (the player)
                          │
                          │ opens browser, visits quiz URL
                          ▼
                  ┌───────────────┐
                  │  The Internet │
                  └───────┬───────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  AWS Load Balancer    │  ← The front door.
              │  (ALB)               │    Accepts traffic from
              │                      │    the internet on port 80.
              └──────────┬───────────┘
                         │ port 31000
                         ▼
        ┌──────────────────────────────────────┐
        │           AWS Cloud (Private)         │
        │                                      │
        │  ┌────────────────────────────────┐  │
        │  │  Nginx Gateway Fabric          │  │
        │  │  (Traffic Director)            │  │  ← Reads the HTTPRoute rules
        │  │                                │  │    and sends each request to
        │  │  /api/game/*       ──────────► │  │    the right service.
        │  │  /api/leaderboard/* ─────────► │  │
        │  │  /*                ──────────► │  │
        │  └────┬──────────┬──────────┬─────┘  │
        │       │          │          │         │
        │       ▼          ▼          ▼         │
        │  ┌─────────┐ ┌──────────┐ ┌───────┐  │
        │  │ frontend│ │  game    │ │leader │  │
        │  │ service │ │ service  │ │ board │  │
        │  │ (Quiz   │ │ (Q&A     │ │service│  │
        │  │  UI)    │ │  API)    │ │       │  │
        │  └─────────┘ └──────────┘ └───┬───┘  │
        │                               │       │
        │                           ┌───▼───┐   │
        │                           │ Redis │   │
        │                           │(Scores│   │
        │                           │stored)│   │
        │                           └───────┘   │
        │                                       │
        │  ┌──────────┐  ┌────────┐  ┌───────┐  │
        │  │ ArgoCD   │  │Grafana │  │Prometh│  │
        │  │(Deploys  │  │(Charts)│  │eus    │  │
        │  │ the app) │  │        │  │(Stats)│  │
        │  └──────────┘  └────────┘  └───────┘  │
        │                                       │
        └───────────────────────────────────────┘
```

### The three services explained simply

**Frontend Service** — This is the website itself. When you open the quiz URL in your
browser, you are talking to the frontend service. It serves the HTML page, the buttons,
the question text, and the score at the end. Think of it as the shop window.

**Game Service** — This is the brain. When you click an answer, the frontend sends your
choice to the game service, which checks whether you were right and explains why. It
knows all 15 DevOps questions and their answers, but never sends the answers to your
browser — only a correct/incorrect result after you submit. This means you cannot cheat
by reading the page source.

**Leaderboard Service** — This is the scoreboard. When you finish the quiz and submit
your name, the frontend sends your score to the leaderboard service, which saves it.
When you view the leaderboard tab, the frontend asks the leaderboard service for the
current top scores and displays them. Scores are stored permanently in Redis — they
survive even if the server restarts.

**Redis** — Redis is a fast database that stores the leaderboard scores. Think of it as
a notebook that never forgets. It uses a 1-gigabyte persistent volume so the data is
not lost if the system restarts.

### The infrastructure (the "hosting")

**AWS** — Amazon Web Services is the cloud provider. All the servers, networking, and
storage live here.

**Kubernetes** — Kubernetes (K8s) is the system that manages the containers (programs)
running the quiz game. It starts them, restarts them if they crash, balances traffic
between multiple copies, and scales them up or down based on demand. Think of Kubernetes
as the building manager of an office block — it assigns rooms, replaces broken equipment,
and makes sure everything keeps running.

**Terraform** — Terraform is the tool that creates all the AWS infrastructure
(servers, networking, load balancer) from a set of text files. Instead of clicking
through the AWS website, you describe what you want in code and Terraform builds it.
This means the entire infrastructure can be created and destroyed in minutes.

**Ansible** — Once Terraform has created the servers, Ansible logs into them and
installs all the software (Kubernetes, ArgoCD, Prometheus, and so on). Think of
Terraform as the construction company that builds the building, and Ansible as the
interior decorator who sets everything up inside.

---

## 3. What You Need Before You Start

Before running any commands, make sure you have all of the following. Each item
includes an install command.

### On your computer

**Terraform** — creates the AWS infrastructure
```bash
# macOS
brew install terraform

# Ubuntu / Debian
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor \
  -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform
```

**Ansible** — configures the servers after Terraform creates them
```bash
# macOS
brew install ansible

# Ubuntu / Debian
sudo apt-get install -y ansible
```

**jq** — a tool for reading JSON, used by manage.sh
```bash
brew install jq              # macOS
sudo apt-get install -y jq   # Ubuntu / Debian
```

**nslookup** — resolves hostnames to IP addresses, used by manage.sh
```bash
sudo apt-get install -y dnsutils   # Ubuntu / Debian (usually already installed on macOS)
```

**kubectl** — the command-line tool for talking to Kubernetes
```bash
# macOS
brew install kubectl

# Ubuntu / Debian
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**Docker** — used to build and push container images
```bash
# macOS: download Docker Desktop from https://www.docker.com/products/docker-desktop/
# Ubuntu / Debian
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER   # allows running docker without sudo (log out and back in)
```

**Verify everything is installed:**
```bash
terraform --version
ansible --version
kubectl version --client
docker --version
jq --version
nslookup localhost
```
Each command should print a version number, not an error.

### An AWS account

You need an AWS account with permission to create EC2 instances, a VPC, an Application
Load Balancer, and security groups.

**Configure your AWS credentials:**
```bash
aws configure
```
You will be prompted for:
- `AWS Access Key ID` — from your AWS account's IAM user
- `AWS Secret Access Key` — from the same IAM user
- `Default region name` — for example `us-east-1`
- `Default output format` — type `json`

If you do not have AWS credentials, ask your AWS account administrator to create an
IAM user with `AdministratorAccess` and give you the access key.

### An SSH key pair

This is like a digital password that lets your computer SSH into the servers.

```bash
# Generate a new key pair
ssh-keygen -t ed25519 -C "quiz-game-key" -f ~/.ssh/quiz-game-key

# When asked for a passphrase, press Enter twice (no passphrase)
```

This creates two files:
- `~/.ssh/quiz-game-key` — your **private** key. Never share this.
- `~/.ssh/quiz-game-key.pub` — your **public** key. This goes on the servers.

### A GitHub account and Docker Hub account

- **GitHub** — where the code lives. Fork or push this project to your own GitHub account.
- **Docker Hub** — where the container images are stored. Create a free account at
  [hub.docker.com](https://hub.docker.com).

---

## 4. The Project Files — What Each One Does

```
quiz-game/
│
├── manage.sh                    ← Your main control panel. Every action goes through here.
├── .env.example                 ← A template. Copy this to .env and fill in your details.
├── .gitignore                   ← Tells Git which files to ignore (like .env and log files).
│
├── .github/
│   └── workflows/
│       └── ci.yaml              ← The automatic build pipeline. Runs every time you push code.
│
├── argocd/
│   └── app.yaml                 ← Tells ArgoCD which GitHub repo to watch and where to deploy.
│
├── game-service/                ← The quiz question and answer API
│   ├── server.js                ← The application code (Node.js)
│   ├── package.json             ← Lists the code dependencies
│   └── Dockerfile               ← Instructions for packaging the code into a container
│
├── leaderboard-service/         ← The high score API
│   ├── server.js
│   ├── package.json
│   └── Dockerfile
│
├── frontend-service/            ← The quiz game website
│   ├── index.html               ← The complete game interface (one file)
│   ├── nginx.conf               ← Web server configuration
│   └── Dockerfile
│
├── k8s/                         ← Kubernetes deployment instructions (ArgoCD reads these)
│   ├── namespace.yaml           ← Creates the quiz-game namespace (an isolated workspace)
│   ├── secrets.yaml             ← Stores the admin key securely
│   │
│   ├── gateway/                 ← Traffic routing configuration (Gateway API)
│   │   ├── gatewayclass.yaml    ← Declares which gateway controller to use
│   │   ├── gateway.yaml         ← The actual gateway (listens on port 80)
│   │   └── httproute.yaml       ← The routing rules (which path goes to which service)
│   │
│   ├── redis/
│   │   ├── deployment.yaml      ← How to run Redis and which storage to use
│   │   └── service.yaml         ← How other services reach Redis internally
│   │
│   ├── game-service/
│   │   ├── deployment.yaml      ← How to run game-service (2 copies, health checks)
│   │   ├── service.yaml         ← How other services reach it (on port 3001)
│   │   └── hpa.yaml             ← Auto-scaling rules (grows from 2 to 6 copies under load)
│   │
│   ├── leaderboard-service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml         ← Port 3002
│   │   └── hpa.yaml             ← Scales 2 to 4 copies
│   │
│   └── frontend-service/
│       ├── deployment.yaml
│       └── service.yaml         ← Port 80
│
├── Terraform/                   ← AWS infrastructure definitions
│   ├── main.tf                  ← What to build (load balancer, servers, networking)
│   ├── variables.tf             ← The settings that can be changed
│   ├── outputs.tf               ← Information to pass to manage.sh after building
│   └── terraform.tfvars         ← YOUR values for the settings (you create this)
│
└── Ansible/                     ← Server configuration (runs after Terraform)
    ├── plybk.yaml               ← The step-by-step instructions Ansible follows
    ├── inventory.ini            ← Auto-generated: list of servers with their IPs
    ├── ansible.cfg              ← Auto-generated: Ansible connection settings
    └── group_vars/
        └── all.yaml             ← Variables like software versions and passwords
```

---

## 5. One-Time Configuration

You only need to do this once, before the first deployment.

### Step 1 — Copy the environment template

```bash
cp .env.example .env
```

Open `.env` with any text editor and fill in your details:

```bash
DOCKERHUB_USERNAME=your-dockerhub-username   # the name you use to log into Docker Hub
DOCKERHUB_TOKEN=your-dockerhub-token         # create this at hub.docker.com → Account Settings → Security
NAMESPACE=quiz-game
```

> **Important:** Never commit `.env` to Git. It is already listed in `.gitignore` so
> this is handled automatically.

### Step 2 — Create the Terraform variables file

Inside the `Terraform/` folder, create a file called `terraform.tfvars`:

```bash
nano Terraform/terraform.tfvars
```

Paste and edit this content:

```hcl
region            = "us-east-1"                # AWS region to deploy into
key_name          = "quiz-game-key"            # the name for your key pair in AWS
public_key_path   = "~/.ssh/quiz-game-key.pub" # path to your public key
private_key_path  = "~/.ssh/quiz-game-key"     # path to your private key
ssh_user          = "ubuntu"                   # the username for your EC2 instances

# Server sizes — t3.medium is the minimum Kubernetes needs
control_plane_instance_type = "t3.medium"
worker_instance_type        = "t3.medium"
worker_count                = 2

# Network settings (safe defaults — no need to change these)
vpc_cidr             = "10.0.0.0/16"
public_subnets_cidr  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets_cidr = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]
```

### Step 3 — Configure the Ansible variables

Open `Ansible/group_vars/all.yaml` and check these values:

```yaml
# The range of IP addresses MetalLB can assign.
# Choose IPs that are in your private subnet but not used by DHCP.
metallb_ip_pool: "10.0.10.200-10.0.10.220"

# Grafana password — change this to something strong
grafana_admin_password: "YourStrongPasswordHere123!"

# Your GitHub repository URL (ArgoCD will watch this)
git_repo_url: "https://github.com/YOUR_GH_USER/quiz-game.git"
```

### Step 4 — Update the ArgoCD Application file

Open `argocd/app.yaml` and change the `repoURL` to your own GitHub repository:

```yaml
source:
  repoURL: https://github.com/YOUR_GH_USER/quiz-game.git
```

### Step 5 — Update the ArgoCD manifest URL in the playbook

Open `Ansible/plybk.yaml` and find Step 10. Change `YOUR_GH_USER` to your GitHub username:

```yaml
- name: Apply ArgoCD app manifest from GitHub
  shell: |
    {{ kubectl }} apply -f \
      https://raw.githubusercontent.com/YOUR_GH_USER/quiz-game/main/argocd/app.yaml
```

### Step 6 — Add GitHub repository secrets

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions**
→ **New repository secret** and add these five secrets:

| Secret name | What it is | Where to find it |
|---|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username | Your Docker Hub account |
| `DOCKERHUB_TOKEN` | Docker Hub access token | Docker Hub → Account Settings → Security → New Access Token |
| `GH_PAT` | GitHub Personal Access Token | GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → select `repo` and `workflow` scopes |
| `ARGOCD_SERVER` | Your ArgoCD URL (add after first deploy) | Printed by `./manage.sh urls` |
| `ARGOCD_TOKEN` | ArgoCD API token (add after first deploy) | ArgoCD UI → User Info → Generate Token |

> **Note:** `ARGOCD_SERVER` and `ARGOCD_TOKEN` can be added after the first deployment.
> The pipeline will build and push images without them — it will just skip the
> ArgoCD sync step until they are set.

### Step 7 — Make manage.sh executable

```bash
chmod +x manage.sh
```

You only need to do this once.

---

## 6. Your Single Command Reference — manage.sh

`manage.sh` is your control panel for the entire project. You never need to run Terraform,
Ansible, or kubectl commands manually — manage.sh handles all of that for you.

```
Usage: ./manage.sh {command}

┌─────────────────┬──────────────────────────────────────────────────────┐
│ Infrastructure  │                                                      │
│   up            │ Build everything from scratch (Terraform + Ansible)  │
│   down          │ Destroy all servers and infrastructure               │
│   ansible       │ Re-run Ansible only (no server changes)              │
│                 │                                                      │
│ Cluster         │                                                      │
│   status        │ Show what is running in the cluster                  │
│   gateway-status│ Show the traffic routing state                       │
│   password      │ Print login passwords for ArgoCD and Grafana         │
│   urls          │ Print the web addresses for the quiz game            │
│   ssh           │ Open a terminal on the server                        │
│   proxy         │ Create a secure tunnel to access internal tools      │
└─────────────────┴──────────────────────────────────────────────────────┘
```

---

## 7. Deploying the Project — `./manage.sh up`

This single command builds the entire infrastructure, installs all software, and deploys
the quiz game. Expect it to take **20–30 minutes** from start to finish.

```bash
./manage.sh up
```

### What happens — step by step

#### Stage 1 of 4 — Terraform builds the AWS infrastructure (~8–12 min)

```
[INFO]  [1/4] Running Terraform...
```

Terraform reads `Terraform/main.tf` and creates all the AWS components:

- A **VPC** (Virtual Private Cloud) — your own private section of the AWS network,
  isolated from everyone else
- **Public subnets** — parts of the network visible to the internet. Only the bastion
  host and load balancer live here.
- **Private subnets** — parts of the network not visible to the internet. All servers
  live here. This is a security measure — attackers cannot reach them directly.
- **Bastion host** — a small server in the public subnet that acts as a controlled
  gateway. All SSH access to private servers goes through here.
- **Control plane server** — runs the Kubernetes management software
- **Worker servers** — where your quiz game actually runs
- **Application Load Balancer (ALB)** — the internet-facing entry point. Receives
  traffic from browsers and forwards it to the cluster on port 31000.
- **Security groups** — firewall rules that control which traffic is allowed where

When Terraform finishes:
```
[OK]    Terraform complete.
```

#### Stage 2 of 4 — Extract server addresses

```
[INFO]  [2/4] Extracting outputs...
[OK]    Outputs extracted — bastion=1.2.3.4, control_plane=10.0.10.5
```

manage.sh reads the IP addresses of all the servers that Terraform just created. These
are used in the next steps.

#### Stage 3 of 4 — Prepare Ansible

```
[INFO]  [3/4] Preparing Ansible...
[OK]    SSH key added to agent.
[OK]    inventory.ini and ansible.cfg written to Ansible/
```

Two files are created automatically:

- **`Ansible/inventory.ini`** — the list of servers with their addresses and connection
  settings. Ansible reads this to know which servers to configure.
- **`Ansible/ansible.cfg`** — connection options that make Ansible faster and more
  reliable. It enables tunnelling through the bastion host so Ansible can reach the
  private servers.

#### Stage 4 of 4 — Ansible configures everything (~10–15 min)

```
[INFO]  [4/4] Waiting 30s for nodes to settle, then running Ansible...
```

The 30-second wait lets the servers finish their initial startup routine before Ansible
connects. Then Ansible runs the playbook (`Ansible/plybk.yaml`) step by step:

| Step | What Ansible does | Why |
|---|---|---|
| 1 | Labels worker nodes | Lets Kubernetes know which servers run app workloads |
| 2 | Updates package lists | Ensures servers have the latest software index |
| 3 | Waits for Kubernetes | Gives the cluster time to be fully ready |
| 4 | Copies the kubeconfig | Enables running kubectl commands on the server |
| 5 | Installs ArgoCD | The system that watches Git and deploys the app |
| 6 | Installs Gateway API CRDs | Registers the new traffic routing resource types |
| 6 | Installs Nginx Gateway Fabric | The traffic director that reads the routing rules |
| 6 | Sets NodePort to 31000 | Connects the load balancer to the gateway |
| 7 | Installs Helm | A package manager for Kubernetes |
| 8 | Installs Prometheus + Grafana | Monitoring and dashboards |
| 9 | Creates quiz-game namespace | An isolated workspace for the app |
| 10 | Applies ArgoCD app manifest | Registers the quiz game with ArgoCD |
| 11 | Retrieves passwords | Reads ArgoCD and Grafana passwords |
| 12 | Prints summary | Shows you everything you need to access the app |

#### After `up` completes — what you will see

```
========================================================
 ✅  Quiz Game Cluster Setup Complete! (Gateway API)
========================================================

── Traffic Flow ────────────────────────────────────────
  Internet → ALB :80 → NodePort 31000 → nginx-gateway
  /api/game/*        → game-service:3001   (path stripped)
  /api/leaderboard/* → leaderboard-service:3002 (path stripped)
  /*                 → frontend-service:80

── ArgoCD ──────────────────────────────────────────────
  Username : admin
  Password : Kx7mPqR9vN2w

── Grafana ─────────────────────────────────────────────
  Username : admin
  Password : YourStrongPasswordHere123!

── App URL ─────────────────────────────────────────────
  Run     : ./manage.sh urls
  Or add to /etc/hosts: <ALB_IP>  quiz.kbucci.local
  Then open: http://quiz.kbucci.local
========================================================
```

**Save the passwords shown here.** You can always retrieve them again with
`./manage.sh password`, but it is good practice to note them down.

---

## 8. Accessing the Quiz Game

After deployment, you can access the quiz game in three ways. Method A is the quickest.

### Method A — nip.io URL (quickest, works immediately)

[nip.io](https://nip.io) is a free public service that turns any IP address into a
domain name automatically. For example, `quiz.52.14.88.201.nip.io` automatically resolves
to the IP address `52.14.88.201`. No DNS setup is required.

**Step 1 — Get your URL:**
```bash
./manage.sh urls
```

You will see output like:
```
─── Quiz Game URLs (via nip.io) ────────────────
  🎮 Quiz App : http://quiz.52.14.88.201.nip.io

  Gateway IP  : 52.14.88.201
```

**Step 2 — Open the URL in your browser.**

That is all. The quiz game is live.

> **If `./manage.sh urls` says "nslookup returned no IP yet":** The AWS load balancer
> is still starting up. This can take 2–5 minutes after deployment. Wait and run
> `./manage.sh urls` again.

### Method B — Custom domain with /etc/hosts (for using quiz.kbucci.local)

This method lets you use `quiz.kbucci.local` as the address instead of the nip.io URL.
It works by telling your computer to map that name to the load balancer IP address.

**Step 1 — Get the Gateway IP:**
```bash
./manage.sh urls
# Note the "Gateway IP" shown at the bottom of the output
```

**Step 2 — Add a line to your hosts file:**

On macOS or Linux:
```bash
echo "52.14.88.201  quiz.kbucci.local" | sudo tee -a /etc/hosts
# Replace 52.14.88.201 with your actual Gateway IP
```

On Windows: Open Notepad as Administrator, open `C:\Windows\System32\drivers\etc\hosts`,
and add this line at the bottom:
```
52.14.88.201  quiz.kbucci.local
```

**Step 3 — Open your browser and go to:** `http://quiz.kbucci.local`

### Method C — SOCKS proxy (gives access to everything including monitoring)

This method creates a secure tunnel from your computer into the private cluster network.
It is covered in detail in the next section because it is the main way to access
Prometheus, Grafana, and ArgoCD.

### How to play the quiz

Once you have the URL open:

1. **Enter your name** in the text box on the home screen
2. **Choose how many questions** you want (5, 10, or 15)
3. Click **Start Quiz**
4. **Read each question** and click the answer you think is correct
5. The game immediately shows whether you were right and explains the correct answer
6. After the last question, **your score and accuracy percentage** are displayed
7. **Enter your name** (pre-filled) and click **Submit to Leaderboard**
8. Click **Leaderboard** in the navigation to see all-time top scores

---

## 9. Accessing Prometheus, Grafana and ArgoCD via the Internet

Prometheus, Grafana, and ArgoCD are internal tools that run inside the private cluster
network. They are not directly exposed to the internet — this is intentional, as
exposing monitoring dashboards publicly would be a security risk.

There are two ways to access them. The SOCKS proxy (Method A) is recommended because
it is easier and gives you access to everything at once.

---

### Method A — SOCKS5 Proxy (Recommended)

A SOCKS5 proxy is a secure tunnel from your computer to the cluster. Once it is running,
you configure your browser to send all traffic through the tunnel. This makes your browser
behave as if it is sitting inside the cluster network — you can visit internal addresses
as if they were normal websites.

**Step 1 — Start the proxy tunnel**

Open a terminal and run:
```bash
./manage.sh proxy
```

You will see:
```
[INFO]  Starting SOCKS5 proxy on localhost:9090 — press Ctrl+C to stop.
[INFO]  Set FoxyProxy or browser to SOCKS5 → 127.0.0.1:9090
```

**Leave this terminal window open.** The proxy runs until you press `Ctrl+C`.

**Step 2 — Configure your browser**

You need to tell your browser to send traffic through the proxy. The easiest way is
to use the **FoxyProxy** browser extension (available for Firefox and Chrome, free).

**Using FoxyProxy (recommended):**

1. Install FoxyProxy:
   - Firefox: [addons.mozilla.org — search "FoxyProxy Standard"](https://addons.mozilla.org)
   - Chrome: [chrome.google.com/webstore — search "FoxyProxy Standard"](https://chrome.google.com/webstore)

2. Click the FoxyProxy icon in your browser toolbar

3. Click **Options** (or the settings gear)

4. Click **Add Proxy** (or the + button)

5. Fill in:
   - **Title:** Quiz Game Cluster
   - **Proxy Type:** SOCKS5
   - **Proxy IP:** `127.0.0.1`
   - **Port:** `9090`

6. Click **Save**

7. Click the FoxyProxy icon again and select **Use proxy "Quiz Game Cluster" for all URLs**

**Using built-in macOS system proxy (alternative to FoxyProxy):**

1. Open **System Preferences** → **Network**
2. Select your active network connection and click **Advanced**
3. Click the **Proxies** tab
4. Check **SOCKS Proxy**
5. Enter `127.0.0.1` for the host and `9090` for the port
6. Click **OK** then **Apply**

Remember to uncheck this when you are done, or your regular browsing will also go
through the tunnel.

**Using Chrome with a launch flag (quickest, opens a separate Chrome window):**
```bash
google-chrome --proxy-server="socks5://127.0.0.1:9090" \
              --user-data-dir=/tmp/quiz-game-proxy-chrome
```
This opens a separate Chrome window that uses the proxy. Your normal Chrome windows
are unaffected.

**Step 3 — Access the tools in your browser**

With the proxy active and FoxyProxy enabled, open these URLs:

#### Grafana (monitoring dashboards)
```
http://prometheus-grafana.monitoring.svc.cluster.local
```
- **Username:** `admin`
- **Password:** Run `./manage.sh password` to retrieve it

#### Prometheus (raw metrics)
```
http://prometheus-kube-prometheus-prometheus.monitoring:9090
```
No login required.

#### ArgoCD (deployment manager)
```
https://argocd-server.argocd.svc.cluster.local
```
- **Username:** `admin`
- **Password:** Run `./manage.sh password` to retrieve it
- **Accept the certificate warning** — the certificate is self-signed

#### Alertmanager (alert routing)
```
http://prometheus-kube-prometheus-alertmanager.monitoring:9093
```

**Step 4 — When you are done**

Press `Ctrl+C` in the terminal where the proxy is running.
Turn off the FoxyProxy setting in your browser (click the icon → Disable).

---

### Method B — SSH Port-Forward (Direct tunnel, no browser extension needed)

Port-forwarding creates a tunnel from a port on your local computer directly to a
service inside the cluster. You access it at `localhost:<port>` in your browser.
This requires two terminal windows.

**Step 1 — SSH into the control plane**

In terminal window 1:
```bash
./manage.sh ssh
```

You are now logged into the Kubernetes control plane server. Leave this window open.

**Step 2 — Start port-forwards from the control plane**

Still in terminal window 1 (on the control plane), run one or more of these:

```bash
# Grafana on http://localhost:3000
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
  port-forward svc/prometheus-grafana \
  -n monitoring 3000:80 --address=0.0.0.0 &

# Prometheus on http://localhost:9091
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
  port-forward svc/prometheus-kube-prometheus-prometheus \
  -n monitoring 9091:9090 --address=0.0.0.0 &

# ArgoCD on https://localhost:8080
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
  port-forward svc/argocd-server \
  -n argocd 8080:443 --address=0.0.0.0 &
```

The `&` at the end runs each command in the background.

**Step 3 — Create an SSH tunnel from your local machine**

Open terminal window 2 on your local computer (not the server) and run:

```bash
# Replace BASTION_IP with the actual bastion IP from ./manage.sh urls
# Replace CONTROL_PLANE_IP with the control plane IP

# For Grafana
ssh -L 3000:CONTROL_PLANE_IP:3000 -N ubuntu@BASTION_IP &

# For Prometheus
ssh -L 9091:CONTROL_PLANE_IP:9091 -N ubuntu@BASTION_IP &

# For ArgoCD
ssh -L 8080:CONTROL_PLANE_IP:8080 -N ubuntu@BASTION_IP &
```

**Step 4 — Open in your browser**

| Tool | URL |
|---|---|
| Grafana | `http://localhost:3000` |
| Prometheus | `http://localhost:9091` |
| ArgoCD | `https://localhost:8080` (accept the certificate warning) |
| Alertmanager | `http://localhost:9093` |

**Step 5 — Stop the tunnels when done**

```bash
# Kill all background SSH tunnels
pkill -f "ssh -L"
```

---

### Getting passwords for Grafana and ArgoCD

Run this at any time to retrieve the passwords:

```bash
./manage.sh password
```

Output:
```
─── ArgoCD ────────────────────────────────────
  Username : admin
  Password : Kx7mPqR9vN2w

─── Grafana ───────────────────────────────────
  Username : admin
  Password : YourStrongPasswordHere123!

─── Port-forwards ─────────────────────────────
  ArgoCD      : kubectl port-forward svc/argocd-server -n argocd 8080:443
                → https://localhost:8080

  Grafana     : kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
                → http://localhost:3000

  Prometheus  : kubectl port-forward svc/prometheus-kube-prometheus-prometheus
                  -n monitoring 9091:9090
                → http://localhost:9091

  Game API    : kubectl port-forward svc/game-service -n quiz-game 3001:3001
                → http://localhost:3001

  Leaderboard : kubectl port-forward svc/leaderboard-service -n quiz-game 3002:3002
                → http://localhost:3002

  Frontend    : kubectl port-forward svc/frontend-service -n quiz-game 8080:80
                → http://localhost:8080
```

---

## 10. How the Gateway API Routes Traffic

### The simple explanation

Imagine the load balancer is the reception desk of a large office building. Everyone
who visits the building checks in at reception (port 80 on the load balancer). The
receptionist then looks at why you are there and directs you to the right floor.

In this project, the "receptionist" is **Nginx Gateway Fabric** — a piece of software
that reads the routing rules defined in `k8s/gateway/httproute.yaml` and forwards
each request to the correct service.

### What the routing rules say

The `httproute.yaml` file defines three rules in order:

```
If the URL path starts with /api/game/
    → strip "/api/game" from the path
    → send to game-service on port 3001
    → example: /api/game/questions becomes /questions at the game-service

If the URL path starts with /api/leaderboard/
    → strip "/api/leaderboard" from the path
    → send to leaderboard-service on port 3002
    → example: /api/leaderboard/score becomes /score at the leaderboard-service

Everything else (/)
    → send to frontend-service on port 80
    → serves the quiz game web page
```

### Why is path stripping important?

When you click an answer in the quiz game, your browser sends a request to
`/api/game/check`. The Gateway receives this and needs to forward it to the game-service.
But the game-service's code only knows about `/check` — it was written without any
knowledge of the `/api/game` prefix. The Gateway strips the prefix before forwarding,
so the game-service receives `/check` and everything works correctly.

### The three Gateway API files

**`k8s/gateway/gatewayclass.yaml`** — Declares that Nginx Gateway Fabric is the
traffic controller for this cluster. This is a one-time cluster-level setting.

**`k8s/gateway/gateway.yaml`** — Creates the actual gateway with a listener on port 80
for the hostname `quiz.kbucci.local`. Think of this as creating the reception desk.

**`k8s/gateway/httproute.yaml`** — The routing rules. Think of this as the directory
board behind reception that says "Game API — Floor 3, Leaderboard — Floor 4, Website — Ground floor."

### Verifying the Gateway is working

```bash
./manage.sh gateway-status
```

Output:
```
─── GatewayClass ──────────────────────────────
NAME    CONTROLLER                                      ACCEPTED
nginx   gateway.nginx.org/nginx-gateway-controller      True

─── Gateway ───────────────────────────────────
NAME                CLASS   ADDRESS         PROGRAMMED   AGE
quiz-game-gateway   nginx   10.0.10.200     True         2h

─── HTTPRoutes ─────────────────────────────────
NAME              HOSTNAMES             PARENT              AGE
quiz-game-route   [quiz.kbucci.local]   quiz-game-gateway   2h

─── Gateway Service (LoadBalancer IP) ──────────
SERVICE         TYPE        CLUSTER-IP    EXTERNAL-IP    PORT
nginx-gateway   NodePort    10.96.5.1     <none>         80,443
```

Everything is working correctly when:
- `ACCEPTED` shows `True` under GatewayClass
- `PROGRAMMED` shows `True` under Gateway
- The ADDRESS is populated under Gateway

---

## 11. How Code Changes Deploy Automatically — CI/CD

CI/CD stands for Continuous Integration / Continuous Deployment. It means that every
time you push a code change to GitHub, a series of automated steps runs to test,
package, and deploy your change — with no manual action needed.

### The pipeline, step by step

```
You push code to GitHub
        │
        ▼
GitHub detects the push and starts the pipeline (.github/workflows/ci.yaml)
        │
        ▼
STEP 1: Detect which services changed
        Only the services whose files you changed get rebuilt.
        Changing game-service/server.js will NOT rebuild the frontend.
        │
        ▼
STEP 2: Build Docker image (package the code into a container)
        The image is built locally inside GitHub's servers.
        It is NOT pushed to Docker Hub yet.
        │
        ▼
STEP 3: Security scan with Trivy
        Trivy checks the image for known security vulnerabilities.
        ├── Full report printed to the pipeline logs
        ├── Results uploaded to GitHub Security tab (Settings → Security)
        └── If any CRITICAL vulnerability is found → pipeline STOPS
            The image will NOT be pushed. You must fix the issue first.
        │
        ▼
STEP 4: Push image to Docker Hub (only if scan passed)
        Tagged with: sha-a1b2c3d4 (the exact Git commit)
        Also tagged: latest
        │
        ▼
STEP 5: Update the deployment manifest
        The image tag in k8s/game-service/deployment.yaml is changed
        from the old tag to the new sha-a1b2c3d4 tag.
        This change is committed and pushed back to GitHub automatically.
        │
        ▼
STEP 6: ArgoCD detects the manifest change
        ArgoCD checks the GitHub repository every 3 minutes.
        When it sees the new image tag, it applies the change to the cluster.
        │
        ▼
Kubernetes performs a rolling update
        New pods start with the new image.
        Health checks must pass before old pods are removed.
        The quiz game never goes offline during the update.
        │
        ▼
Deployment complete. The new code is live.
```

### Checking the pipeline status

On GitHub: go to your repository → **Actions** tab → click the latest workflow run.

You will see each step with a green tick (passed) or red X (failed). Click any step
to see its detailed output.

### Triggering a deployment manually

Just push any change to GitHub:

```bash
# Make any small change
echo "# Updated $(date)" >> game-service/README.md
git add .
git commit -m "trigger: manual deployment test"
git push
```

Go to the GitHub Actions tab to watch it run.

---

## 12. Monitoring Your Application

Prometheus and Grafana together give you real-time visibility into how the quiz game
is performing — how many requests it is handling, how much CPU and memory each service
uses, whether any pods have crashed, and much more.

### Accessing Grafana

Follow the steps in [Section 9](#9-accessing-prometheus-grafana-and-argocd-via-the-internet)
to open Grafana at `http://prometheus-grafana.monitoring.svc.cluster.local`.

Log in with:
- **Username:** `admin`
- **Password:** from `./manage.sh password`

### Recommended dashboards

Once logged in, go to **Dashboards → Browse** and import these pre-built dashboards
by entering their ID number:

| Dashboard name | ID | What it shows |
|---|---|---|
| Node Exporter Full | `1860` | CPU, memory, disk, and network for each server |
| Kubernetes Pods | `15759` | Resource usage per pod (game-service, frontend, etc.) |
| Kubernetes Cluster | `7249` | Overall cluster health and resource summary |

To import: **Dashboards → Import → Enter ID → Load → Select "Prometheus" as the data source → Import**

### Key things to watch

**Are the pods healthy?**

In Grafana's search bar, enter this query under Explore:
```
kube_pod_container_status_restarts_total{namespace="quiz-game"}
```
This should return 0 or a very small number for all pods. A rising number means a
pod is repeatedly crashing.

**How much CPU is the game using?**
```
sum(rate(container_cpu_usage_seconds_total{namespace="quiz-game"}[5m])) by (pod)
```

**How much memory?**
```
sum(container_memory_working_set_bytes{namespace="quiz-game"}) by (pod)
```

**Is the quiz game receiving traffic?**
```
sum(rate(container_network_receive_bytes_total{namespace="quiz-game"}[5m])) by (pod)
```

### Checking what Prometheus is scraping

Open Prometheus at `http://prometheus-kube-prometheus-prometheus.monitoring:9090`
(via the proxy). Go to **Status → Targets** to see a list of all services being monitored.
They should all show `UP` in green.

---

## 13. Checking What Is Running — `./manage.sh status`

```bash
./manage.sh status
```

This shows a complete snapshot of the cluster without you needing to SSH in.

### Sample output explained

```
─── ArgoCD Apps ───────────────────────────────
APP          SYNC    HEALTH
quiz-game    Synced  Healthy
```

- **SYNC = Synced** — the cluster matches what is in Git. Good.
- **SYNC = OutOfSync** — Git has been updated but the cluster has not caught up yet.
  ArgoCD will fix this automatically within 3 minutes.
- **HEALTH = Healthy** — all pods are running correctly.
- **HEALTH = Degraded** — one or more pods are in trouble. Run `./manage.sh ssh`
  and check the logs.

```
─── Pods (quiz-game) ──────────────────────────
NAME                                  READY  STATUS   RESTARTS  AGE
frontend-service-6d9f-xk2pq           1/1    Running  0         3h
game-service-7c8d-p9qrt               1/1    Running  0         3h
leaderboard-service-5f6g-r2st         1/1    Running  0         3h
redis-7b8c-p3qt                       1/1    Running  0         3h
```

- **READY 1/1** — the pod is running and passing health checks. Good.
- **STATUS Running** — the pod is active.
- **RESTARTS 0** — the pod has not crashed. Any number above 0 warrants investigation.

```
─── Gateway API Resources ─────────────────────
NAME                CLASS   ADDRESS
quiz-game-gateway   nginx   10.0.10.200

NAME              HOSTNAMES            PARENT
quiz-game-route   [quiz.kbucci.local]  quiz-game-gateway
```

The ADDRESS must be populated. If it is empty, the Gateway is not yet ready.

---

## 14. Scaling the Application

### What auto-scaling does automatically

The quiz game is configured with Horizontal Pod Autoscalers (HPAs). Think of these as
automatic staffing systems: when the quiz gets very busy and CPU usage rises above 65%,
Kubernetes automatically starts more copies of the service. When traffic drops, it
removes the extra copies to save resources.

| Service | Minimum copies | Maximum copies |
|---|---|---|
| game-service | 2 | 6 |
| leaderboard-service | 2 | 4 |
| frontend-service | 2 | (fixed at 2) |

### Permanently changing the number of copies (the right way)

Manually running `kubectl scale` would work, but ArgoCD would reverse it within 3 minutes
because it always makes the cluster match what is in Git. The correct way is to edit
the file and push to GitHub:

```bash
# Open the deployment file
nano k8s/game-service/deployment.yaml

# Find this line:
#   replicas: 2
# Change it to:
#   replicas: 4

# Save and push
git add k8s/game-service/deployment.yaml
git commit -m "scale: increase game-service to 4 replicas"
git push

# ArgoCD will apply the change automatically within a few minutes
```

---

## 15. Troubleshooting — When Things Go Wrong

### The quiz URL gives a 502 or 504 error

This means the browser reached the load balancer, but the load balancer could not
reach the quiz game. The Gateway or a service may not be ready.

```bash
# Check the Gateway is working
./manage.sh gateway-status
# ADDRESS must be populated under Gateway
# PROGRAMMED must be True

# Check the pods are running
./manage.sh status
# All pods must show Running with READY 1/1

# Check Gateway controller logs
./manage.sh ssh
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
  logs -n nginx-gateway -l app=nginx-gateway --tail=50
```

### A pod shows `CrashLoopBackOff`

This means a container keeps starting and crashing. Read its logs to find out why:

```bash
./manage.sh ssh

# Replace POD_NAME with the actual name from ./manage.sh status
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
  logs POD_NAME -n quiz-game --previous
```

Common cause for leaderboard-service: it cannot reach Redis. Check Redis is running:
```bash
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -n quiz-game | grep redis
```

### A pod shows `ImagePullBackOff`

The cluster cannot download the Docker image.

```bash
./manage.sh ssh
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf \
  describe pod POD_NAME -n quiz-game
# Read the Events section at the bottom — it will say exactly what went wrong
```

Common causes:
- The image tag in the deployment manifest does not exist in Docker Hub yet
  (CI pipeline may not have run)
- The Docker Hub repository is private — the cluster needs credentials to pull from it

### `./manage.sh urls` says "nslookup returned no IP yet"

The AWS load balancer is still starting. This normally takes 2–5 minutes after
`./manage.sh up` completes.

```bash
sleep 120 && ./manage.sh urls
```

### ArgoCD shows `OutOfSync` for more than 5 minutes

ArgoCD normally syncs automatically. If it is stuck, trigger a sync manually:

```bash
./manage.sh ssh

# Log into ArgoCD CLI (get IP from gateway-status)
argocd login <ARGOCD_IP> --username admin --password <PASSWORD> --insecure

# Force sync
argocd app sync quiz-game --prune
```

Or log into the ArgoCD UI (Section 9) and click the **Sync** button.

### Ansible fails during `./manage.sh up`

If the Ansible step fails partway through, you do not need to start from scratch.
Terraform has already built the servers. Run just Ansible again:

```bash
./manage.sh ansible
```

Ansible is designed to be run multiple times safely — it will skip steps that are
already done and retry the ones that failed.

### Full diagnostic — gather all information

```bash
./manage.sh ssh
# On the control plane:

alias k='sudo kubectl --kubeconfig /etc/kubernetes/admin.conf'

k get nodes -o wide                                           # are all nodes Ready?
k get pods -A                                                 # are all pods Running?
k get events -n quiz-game --sort-by='.lastTimestamp'          # recent events in the quiz namespace
k get gateway,httproute -n quiz-game                          # gateway status
k top nodes                                                   # server resource usage
k top pods -n quiz-game                                       # pod resource usage
k logs -n nginx-gateway -l app=nginx-gateway --tail=50        # gateway logs
```

---

## 16. Shutting Everything Down — `./manage.sh down`

When you are finished and want to stop paying for AWS resources, run:

```bash
./manage.sh down
```

You will be asked to confirm:
```
[WARN]  === Destroying All Quiz Game Infrastructure ===
Are you sure? This cannot be undone. (yes/no):
```

Type `yes` and press Enter. Anything else (including `y`) cancels the operation.

### What gets deleted

- All EC2 instances (bastion, control plane, workers)
- The VPC and all network infrastructure
- The Application Load Balancer
- All security groups
- The key pair registration in AWS
- The auto-generated `Ansible/inventory.ini` and `Ansible/ansible.cfg`

### What is NOT deleted

- Your local files (code, configuration, `.env`)
- Your SSH key files on your computer (`~/.ssh/quiz-game-key` and `.pub`)
- Your Docker Hub images — they remain and can be reused
- Your GitHub repository and all code history
- The Terraform state files in `Terraform/`

### Coming back

You can redeploy at any time by running `./manage.sh up` again. Because the Docker
images still exist in Docker Hub and all the manifests are in Git, ArgoCD will restore
the quiz game to exactly the same state it was in before.

---

## 17. Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────────┐
│                  Quiz Game — Quick Reference                        │
├───────────────────────┬─────────────────────────────────────────────┤
│  DEPLOYMENT           │                                             │
│  ./manage.sh up       │  Build everything from scratch (~25 min)   │
│  ./manage.sh down     │  Destroy all AWS infrastructure             │
│  ./manage.sh ansible  │  Re-run Ansible without rebuilding servers  │
├───────────────────────┼─────────────────────────────────────────────┤
│  MONITORING           │                                             │
│  ./manage.sh status   │  Show pods, services, Gateway, ArgoCD       │
│  ./manage.sh gateway-status │ Show routing rules and Gateway health │
│  ./manage.sh password │  Get ArgoCD + Grafana passwords             │
│  ./manage.sh urls     │  Get the quiz game web address              │
├───────────────────────┼─────────────────────────────────────────────┤
│  ACCESS               │                                             │
│  ./manage.sh ssh      │  Open a terminal on the cluster server      │
│  ./manage.sh proxy    │  Open tunnel to access internal dashboards  │
└───────────────────────┴─────────────────────────────────────────────┘

QUIZ GAME ACCESS
  Quickest  : ./manage.sh urls → open the printed URL
  Custom    : Add <IP> quiz.kbucci.local to /etc/hosts → http://quiz.kbucci.local
  Via proxy : ./manage.sh proxy → configure browser SOCKS5 127.0.0.1:9090

INTERNAL TOOLS (requires ./manage.sh proxy OR SSH tunnel from Section 9)
  ArgoCD    : https://argocd-server.argocd.svc.cluster.local
  Grafana   : http://prometheus-grafana.monitoring.svc.cluster.local
  Prometheus: http://prometheus-kube-prometheus-prometheus.monitoring:9090

GATEWAY API FILES (go in k8s/gateway/ in the repo)
  gatewayclass.yaml  → declares Nginx Gateway Fabric as the controller
  gateway.yaml       → creates the gateway on quiz.kbucci.local port 80
  httproute.yaml     → /api/game/* → game-service
                        /api/leaderboard/* → leaderboard-service
                        /* → frontend-service

SERVICES AND THEIR PORTS
  frontend-service      port 80    quiz game UI
  game-service          port 3001  questions and answer checking API
  leaderboard-service   port 3002  high score storage API
  redis                 port 6379  score database (internal only)
```

---

*Built by KBUCCI Technologies — Nairobi, Kenya 🇰🇪*
*Securing Tomorrow's Infrastructure, Today.*
