k8-gateway:
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

deploy-config:
	kubectl apply -f test-infra/auth-config.yaml
	kubectl apply -f test-infra/vlan-config.yaml
	kubectl apply -f manifests/kong-session-plugin-cm.yaml
	kubectl apply -f manifests/kong-session-writer-cm.yaml
	kubectl apply -f manifests/kong-redis-cache-cm.yaml

deploy-infra:
	kubectl apply -f manifests/redis.yaml
	kubectl apply -f test-infra

deploy: deploy-infra deploy-config
	helm install kong kong/kong -n app3 -f helm/kong-values.yaml
	kubectl apply -f manifests/gateway.yaml
	kubectl apply -f manifests/kong-plugins.yaml
	kubectl apply -f manifests/http-routes.yaml

down:
	helm uninstall kong -n app3
	kubectl delete -f manifests
	kubectl delete -f test-infra