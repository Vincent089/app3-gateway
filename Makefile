namespace:
	kubectl apply -f manifests/namespace.yaml

deploy-config:
	kubectl apply -f manifests/auth-config.yaml
	kubectl apply -f manifests/vlan-config.yaml
	kubectl apply -f manifests/kong-session-plugin-cm.yaml
	kubectl apply -f manifests/kong-session-writer-cm.yaml

deploy-infra:
	kubectl apply -f manifests/redis.yaml
	kubectl apply -f manifests/postgres.yaml
	kubectl apply -f manifests/auth-service.yaml
	kubectl apply -f manifests/vlan-service.yaml

install-kong:
	helm install kong kong/kong -n app3 -f helm/kong-values.yaml

deploy:
	kubectl apply -f manifests/kong-plugins.yaml
	kubectl apply -f manifests/ingress.yaml

