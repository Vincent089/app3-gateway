# App3 Gateway

Gateway for App3 services deployed using Kong OSS + Redis + LUA plugin

# Requirements

### Kubernetes
1. Gateway ``kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml``
2. App3 namespace

### Kong helm chart

``helm repo add kong https://charts.konghq.com``

### Infra

1. Redis
2. App3 auth service

# How to deploy

First apply plugin config map. This saves reload time on Kong installation since it will see those right away

~~~
kubectl apply -f manifests/kong-session-plugin-cm.yaml
kubectl apply -f manifests/kong-session-writer-cm.yaml
~~~

Install Kong chart

``helm install kong kong/kong -n app3 -f helm/kong-values.yaml``

Deploy dependent infra

``kubectl apply -f manifests/redis.yaml``

### TShooting

Modification to config map aren't hot swappable. Any modification made to *-cm.yaml must be rolled out this way

1. apply your modification
2. upgrade chart
3. rollout update

e.g.
~~~
kubectl apply -f manifests/kong-redis-cache-cm.yaml
helm upgrade kong kong/kong -n app3 -f helm/kong-values.yaml
kubectl rollout status deployment/kong-kong -n app3
~~~

# Later consideration

Currently, using Kong OSS which is open-source but does not have official full support for some feature like caching.
I've been able to create work around using LUA, but Enterprise edition could solve this. Evaluation would be needed