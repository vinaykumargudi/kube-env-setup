#!/bin/bash


curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh



mkdir nginx
cd nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace

wget https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml

cd ..

mkdir sample-app
cd sample-app

echo 'apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: web-server
        image: gcr.io/google-samples/hello-app:1.0
        ports:
        - containerPort: 8080
        env:
        - name: "PORT"
          value: "8080"
        - name: "MESSAGE"
          value: "Hello from pod: $(hostname)"
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
spec:
  selector:
    app: sample-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: NodePort' > sample-app.yaml


kubectl apply -f sample-app.yaml

cd ..

mkdir chaos-mesh
cd chaos-mesh

helm repo add chaos-mesh https://charts.chaos-mesh.org

helm install chaos-mesh chaos-mesh/chaos-mesh -n=chaos-mesh --version 2.6.3 --create-namespace

wget https://github.com/chaos-mesh/chaos-mesh/blob/master/helm/chaos-mesh/values.yaml

echo 'kind: ServiceAccount
apiVersion: v1
metadata:
  namespace: default
  name: account-cluster-manager-surne

---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: role-cluster-manager-surne
rules:
- apiGroups: [""]
  resources: ["pods", "namespaces"]
  verbs: ["get", "watch", "list"]
- apiGroups: ["chaos-mesh.org"]
  resources: [ "*" ]
  verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: bind-cluster-manager-surne
subjects:
- kind: ServiceAccount
  name: account-cluster-manager-surne
  namespace: default
roleRef:
  kind: ClusterRole
  name: role-cluster-manager-surne
  apiGroup: rbac.authorization.k8s.io' > rbac.yaml

kubectl apply -f rbac.yaml

kubectl create token account-cluster-manager-surne

kubectl describe secrets account-cluster-manager-surne

cd ..

mkdir k6
cd k6 

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install k6-operator grafana/k6-operator

wget https://github.com/grafana/k6-operator/blob/main/charts/k6-operator/values.yaml

cd ..

mkdir prom
cd prom 

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus-stack prometheus-community/kube-prometheus-stack

wget https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml

kubectl patch ds prometheus-stack-prometheus-node-exporter --type "json" -p '[{"op": "remove", "path" : "/spec/template/spec/containers/0/volumeMounts/2/mountPropagation"}]'

kubectl patch svc prometheus-stack-grafana -p '{"spec": {"type": "NodePort"}}'
cd ..

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.metrics.serviceMonitor.additionalLabels.release="prometheus-stack"

kubectl patch svc prometheus-stack-grafana --type='json' -p '[{"op": "replace", "path": "/spec/type", "value": "NodePort"}]'



kubectl patch svc prometheus-stack-kube-prom-prometheus --type='json' -p '[{"op": "replace", "path": "/spec/type", "value": "NodePort"}]'


 kubectl patch svc ingress-nginx-controller  -n ingress-nginx --type='json' -p '[{"op": "replace", "path": "/spec/type", "value": "NodePort"}]'

 kubectl patch svc ingress-nginx-controller-metrics  -n ingress-nginx --type='json' -p '[{"op": "replace", "path": "/spec/type", "value": "NodePort"}]'

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-app-service
            port:
              number: 80
EOF

kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ingress-nginx-controller-metrics
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: controller
      app.kubernetes.io/instance: ingress-nginx
      app.kubernetes.io/name: ingress-nginx
  endpoints:
  - port: metrics
    interval: 15s
EOF
