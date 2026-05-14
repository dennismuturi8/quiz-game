'use strict';
const express = require('express');
const cors    = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const QUESTIONS = [
  { id:1,  question:'What does K8s stand for?',                          options:['Kernel 8 System','Kubernetes','Key 8 Stack','Kube Stack'],                          answer:1, explanation:'K8s is shorthand for Kubernetes — 8 letters between K and s.' },
  { id:2,  question:'Which command deploys a manifest to Kubernetes?',    options:['kubectl run','kubectl deploy','kubectl apply -f','kubectl push'],                   answer:2, explanation:'"kubectl apply -f <file>" applies a manifest to your cluster declaratively.' },
  { id:3,  question:'What is a Kubernetes Pod?',                          options:['A VM instance','A Docker image','The smallest deployable unit','A load balancer'], answer:2, explanation:'A Pod is the smallest deployable unit in Kubernetes, wrapping one or more containers.' },
  { id:4,  question:'Which AWS service is managed Kubernetes?',           options:['ECS','EKS','ECR','EC2'],                                                           answer:1, explanation:'EKS (Elastic Kubernetes Service) is AWS\'s managed Kubernetes service.' },
  { id:5,  question:'What does a Kubernetes Ingress do?',                 options:['Runs containers','Manages storage','Routes external HTTP traffic','Schedules pods'],answer:2, explanation:'Ingress manages external HTTP/HTTPS access routing to services inside a cluster.' },
  { id:6,  question:'What is Terraform primarily used for?',              options:['Monitoring','Infrastructure as Code','Container runtime','CI/CD'],                  answer:1, explanation:'Terraform is an IaC tool for provisioning and managing cloud infrastructure.' },
  { id:7,  question:'What is the purpose of a Kubernetes ConfigMap?',     options:['Store secrets','Store non-sensitive config data','Schedule pods','Route traffic'],  answer:1, explanation:'ConfigMaps store non-sensitive key-value configuration data for pods.' },
  { id:8,  question:'Which command shows all pods in all namespaces?',    options:['kubectl get pods','kubectl list all','kubectl get pods -A','kubectl show pods'],    answer:2, explanation:'"kubectl get pods -A" lists pods across all namespaces.' },
  { id:9,  question:'What does Docker layer caching improve?',            options:['Runtime performance','Build speed','Network throughput','Security'],               answer:1, explanation:'Layer caching reuses unchanged layers, dramatically speeding up image builds.' },
  { id:10, question:'What is a Kubernetes Namespace used for?',           options:['Grouping and isolating cluster resources','DNS resolution','Load balancing','Encryption'], answer:0, explanation:'Namespaces logically isolate resources within a single Kubernetes cluster.' },
  { id:11, question:'Which tool packages Kubernetes applications?',       options:['Docker Compose','Helm','Ansible','Packer'],                                        answer:1, explanation:'Helm is the Kubernetes package manager — it uses charts to define and deploy apps.' },
  { id:12, question:'What does a Liveness Probe do in Kubernetes?',      options:['Checks readiness','Restarts unhealthy containers','Scales pods','Encrypts traffic'],answer:1, explanation:'A Liveness Probe tells Kubernetes when to restart a container that is stuck or crashed.' },
  { id:13, question:'What is the role of etcd in Kubernetes?',            options:['Container runtime','Cluster state store','Load balancer','API Gateway'],           answer:1, explanation:'etcd is the distributed key-value store that holds all Kubernetes cluster state.' },
  { id:14, question:'What does HPA stand for in Kubernetes?',             options:['High Performance App','Horizontal Pod Autoscaler','Host Process Allocator','HTTP Proxy Agent'], answer:1, explanation:'HPA automatically scales pod count based on metrics like CPU usage.' },
  { id:15, question:'Which port does the Kubernetes API server use?',     options:['8080','443','6443','2379'],                                                        answer:2, explanation:'The Kubernetes API server listens on port 6443 by default (HTTPS).' },
];

app.get('/health', (_req, res) => res.json({ status:'ok', service:'game-service', ts: new Date().toISOString() }));

app.get('/questions', (_req, res) =>
  res.json({ questions: QUESTIONS.map(({ id, question, options }) => ({ id, question, options })), total: QUESTIONS.length })
);

app.get('/questions/random', (req, res) => {
  const count = Math.min(parseInt(req.query.count) || 10, QUESTIONS.length);
  const shuffled = [...QUESTIONS].sort(() => Math.random() - 0.5).slice(0, count);
  res.json({ questions: shuffled.map(({ id, question, options }) => ({ id, question, options })), total: count });
});

app.post('/check', (req, res) => {
  const { questionId, answer } = req.body;
  if (questionId == null || answer == null) return res.status(400).json({ error:'questionId and answer are required' });
  const q = QUESTIONS.find(q => q.id === questionId);
  if (!q) return res.status(404).json({ error:'Question not found' });
  res.json({ correct: q.answer === answer, correctAnswer: q.answer, explanation: q.explanation });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`✅ game-service listening on :${PORT}`));
