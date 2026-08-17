# Knative Serverless Playground

## DISCLAIMER
> THIS REPO IS DONE JUST FOR FUN TO EASE SETUP SERVERLESS ENVIRONMENT.
> I STRONGLY **NOT** RECOMMEND TO USE ANY OF THESE SCRIPTS AND/OR CONFIGURATIONS IN PRODUCTION DUE PERFORMANCE AND SECURITY ISSUES.
> THIS SCRIPTS AND RESULTS OF IT WORK IS ONLY FOR EDUCATIONAL PURPOSES.
> BEFORE RUNNING SCRIPTS, BE SURE YOU UNDERSTAND WHAT YOU ARE DOING.


## Goal of this repository

This repository is a local playground to experiment with Knative, SonataFlow, and Camel-K. 
It provides a platform for developers to test and explore the integration of these technologies in a controlled 
environment.

In two words we want something that smells like AWS-lambda and AWS-step-functions. But based on FOS projects.

### What we will cover

In this repository, we will cover the following topics:

- Installing baseline, which includes:
  - Setting up a local Kubernetes cluster
  - Installing istio + istio ingress gateway
  - Kafka operator and broker
  - Postgresql operator and instance
- Knative setup and configuration (Serving + Eventing)
- SonataFlow operator
- Camel-K operator
- TODO: Testing and experimentation with the integrated environment

### What we will not cover

In this repository, we will not cover the following topics:

- On-cluster builds (Tekton)
- Production deployment and scaling
- Advanced security and performance optimizations
- Integration with other enterprise systems and services
- Production-ready monitoring and logging
- Production-ready CI/CD pipelines

## Baseline

It include:
- Kubernetes cluster (k3d cluster + k3d local registry)
- Cert/trust managers
- istio (mesh is way to connect services in knative)
- LGMT + Opentelemetry Collector (for traces and logs)
- Strimzi (Kafka operator)
- Kafka-UI
- Single instance of kafka broker
- Zalando Postgres operator
- 2-instances postgresql cluster


### k8s with k3d
```shell
k3d cluster create knative \
  --agents 3 \
  --network knative-net \
  -p "8888:80@loadbalancer" \
  -p "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:*" \
  --registry-create k3d-registry.localhost:0.0.0.0:5111 \
  --registry-config registry/registries.yaml \
  --image rancher/k3s:v1.35.5-k3s1
```
Because we can't assign same ports for registry inside and outside the cluster, we need to use 
[./registry/registries.yaml] to make it looks like single external registry (dirty hack).

Taint master node to protect k8s control-plane:
```shell
kubectl taint nodes k3d-knative-server-0 node-role.kubernetes.io/control-plane=:NoSchedule
```

### Cert/Trust managers
Helm repo:
```shell
helm repo add jetstack https://charts.jetstack.io --force-update
```
Install script:
```shell
cert-manager/install.sh knative
```
### Istio + Istio Ingress Gateway
Helm repo:
```shell
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update istio
```
Istio base chart:
```shell
helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace
```
Istiod:
```shell
helm install istiod istio/istiod -n istio-system --wait
```
Istio Ingress Gateway
```shell
helm upgrade --install knative-istio-gateway istio/gateway -n istio-gateway --create-namespace --wait
```

### LGMT + Opentelemetry Collector
Repositories:
```shell
helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```
Prometheus:
```shell
helm upgrade --install -n observability --create-namespace prometheus prometheus-community/prometheus -f ./observability/prometheus.yaml
```
Loki:
```shell
helm upgrade --install -n observability --create-namespace loki grafana-community/loki -f ./observability/loki.yaml
```
Tempo:
```shell
helm upgrade --install -n observability --create-namespace tempo grafana-community/tempo -f ./observability/tempo.yaml
```
Grafana:
```shell
helm upgrade --install -n observability --create-namespace grafana grafana-community/grafana -f ./observability/grafana.yaml
```
Opentelemetry Operator
```shell
helm upgrade --install -n observability --create-namespace opentelemetry-operator opentelemetry/opentelemetry-operator
```
Opentelemetry Collector:
```shell
kubectl -n observability apply -f ./observability/collector.yaml
```
Grafana Istio Gateway (http://grafana.kn.local:8888)
```shell
kubectl -n observability apply -f ./observability/grafana-istio.yaml
```
> just add 127.0.0.1 grafana.kn.local to /etc/hosts
> then http://grafana.kn.local:8888

To get grafana admin password:
```shell
kubectl -n observability get secret grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```


### Strimzi Kafka + Kafka UI + Broker
Strimzi Operator:
```shell
kubectl create namespace kafka
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
```
Kafka UI helm repo:
```shell
helm repo add kafbat-ui https://kafbat.github.io/helm-charts
helm repo update kafbat-ui
```
Kafka UI:
```shell
helm upgrade --install -n kafka --create-namespace kafka-ui kafbat-ui/kafka-ui -f ./kafka/ui-values.yaml
```
Kafka UI ingress (will be accessible on localhost:8888 under kafka.kn.local domain)
```shell
kubectl -n kafka apply -f ./kafka/kafka-ui-istio.yaml
```
> just add 127.0.0.1 kafka.kn.local to /etc/hosts
> then http://kafka.kn.local:8888

Broker (simple single node):
```shell
kubectl -n kafka apply -f kafka/kafka-single-node.yaml
```

### Zalando Postgresql Operator (with UI) + 2 nodes cluster
```shell
# add repo for postgres-operator
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
# install the postgres-operator
helm install -n postgres --create-namespace postgres-operator postgres-operator-charts/postgres-operator
# add repo for postgres-operator-ui
helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
# install the postgres-operator-ui
helm install -n postgres --create-namespace postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui
```
2 instances patroni cluster + pgBouncer:
```shell
kubectl apply -f ./postgres/sonatapostgres.yaml
```

If everything is ok, it seems that we finished the baseline installation.


## Knative
Knative is mature and stable project so we will use operator that public available in the helm repo:
```shell
helm repo add knative-operator https://knative.github.io/operator
helm repo update knative-operator
```
Operator installation:
```shell
helm install knative-operator --create-namespace --namespace knative-operator knative-operator/knative-operator
```
### Knative Serving
Serving control plane with KPA
```shell
kubectl create namespace knative-serving
kubectl label namespace knative-serving istio-injection=enabled
kubectl apply -f knative/serving.yaml
```
### Knative Eventing
Eventing control plane with IM, MT and Kafka channels and brokers support (Kafka - default)
```shell
kubectl create namespace knative-eventing
kubectl label namespace knative-eventing istio-injection=enabled
kubectl apply -f knative/eventing.yaml
```

If everything is ok, we are ready for simple serverless and CloudEvents (CNCF compatible)

...except on-cluster builds (RFU)

### Knative СLI to help
https://knative.dev/docs/client/install-kn/#install-kubernetes-cli

```shell
brew install knative/client/kn
```
So we have AWS lambda like environment just follow quick start guides from http://knative.dev
> Just keep in mind to use k3d-registry.localhost:5111 as docker registry in your knative deployments.


## Sonataflow (ex Kogito)

This is FOS that contributes CNCF Workflows specs and nearest to AWS Step Functions functionality.
This is a part of big project Apache KIE. We will install just Sonataflow (ex Kogito).
> **NOTE:**
> It is still ***INCUBATING*** stage. And subject to change.
> But it could be forked at least. :)

If you have **linux/amd64** you are lucky. Just do this:
```shell
kubectl create -f https://raw.githubusercontent.com/apache/incubator-kie-tools/refs/tags/10.2.0/packages/sonataflow-operator/operator.yaml
```
Or use Operator Hub as described [here](https://sonataflow.org/serverlessworkflow/latest/cloud/operator/install-serverless-operator.html).

> **BUT! If you Mac arm user.** 

Sonataflow doesn't have arm builds :(
So i can propose you 2 ways:
- Hardway - build yourself from sources. From this [repo](https://github.com/apache/incubator-kie-tools/)
- Easyway - use images from my personal [repo](https://hub.docker.com/u/dlukasevich) which are not tested.

In fact, easiest way is to run this manifest with my images signed:
```shell
kubectl create -f ./sonataflow/operator.yaml
```

### Sonatoflow CLI (kn workflow plugin)

There is no brew. 
So manual download from [here](https://kie.apache.org/downloads/download_10_2_0)
Docs actually [here](https://sonataflow.org/serverlessworkflow/latest/testing-and-troubleshooting/kn-plugin-workflow-overview.html).

So you could follow Sonataflow [guides](https://sonataflow.org/serverlessworkflow/latest/getting-started/introduction-sonataflow-development-guide.html)
to do something like AWS Step Functions, but CNCF compliant.

## Camel-K
Last but not least, you could use [Camel-K](https://camel.apache.org/camel-k/latest/index.html) to run your workflows on Kubernetes.
This huge integration framework but it is in migration stage to quarkus native platform an it is not so stable as yo can expect.
It could be integrated with knative and have some advantages over Sonataflow.
Let's install operator.

Helm repo:
```shell
helm repo add camel-k https://apache.github.io/camel-k/charts/
helm repo update camel-k
```
Operator Installation:
```shell
helm upgrade --install \
  -n camel-k-playground \
  --create-namespace \
  camel-k camel-k/camel-k
```
> **Note**: Operator is namespaced by default (and crds too). So you could use camel pipes only in nnamespace where it is installed.

Finally, we will install Integration platform (it is namespaced too) with fresh quarkus version (default is toooooo old :))
```shell
kubectl -n camel-k-playground apply -f ./camel-k/ip.yaml
```
That's it. 
Follow guides from [here](https://camel.apache.org/camel-k/2.10.x/index.html).

# Have fun!
```shell
k3d cluster edit knative --port-add "5435:5435/tcp@loadbalancer"
```
