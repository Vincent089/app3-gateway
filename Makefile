k8-gateway:
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

deploy:
	kubectl apply -f manifests/redis.yaml
	kubectl apply -f manifests/kong-session-plugin-cm.yaml
	kubectl apply -f manifests/kong-session-writer-cm.yaml
	kubectl apply -f manifests/kong-redis-cache-cm.yaml
	helm install kong kong/kong -n app3 -f helm/kong-values.yaml
	kubectl apply -f manifests/gateway.yaml
	kubectl apply -f manifests/kong-plugins.yaml
	kubectl apply -f manifests/http-routes.yaml

down:
	helm uninstall kong -n app3
	kubectl delete -f manifests