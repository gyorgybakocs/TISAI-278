BASE_NAMES = POSTGRES REDIS
DOCKERHUB_BASE_NAMES = PGBOUNCER
SERVICES = POSTGRES PGBOUNCER REDIS
DEPLOYS = POSTGRES PGBOUNCER REDIS
PORTFORWARD = POSTGRES PGBOUNCER REDIS
PODS = postgres pgbouncer redis

# ---------------------------------------------------------------------------------
# ---------------------------- get base imaged from aws ---------------------------
# ---------------------------------------------------------------------------------
aws-login: apply-config
	@echo "======================= CONFIGURING AWS CLI =========================="
	@AWS_ACCESS_KEY_ID=$$(kubectl get secret global-secret -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode); \
	AWS_SECRET_ACCESS_KEY=$$(kubectl get secret global-secret -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode); \
	AWS_DEFAULT_REGION=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_DEFAULT_REGION}'); \
	aws configure set aws_access_key_id "$${AWS_ACCESS_KEY_ID}"; \
	aws configure set aws_secret_access_key "$${AWS_SECRET_ACCESS_KEY}"; \
	aws configure set region "$${AWS_DEFAULT_REGION}";
	@echo "======================= LOGGING IN TO AWS ECR =========================="
	@AWS_ECR_REGISTRY_URL=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_ECR_REGISTRY_URL}'); \
	aws ecr get-login-password --region $$(kubectl get configmap global-config -o jsonpath='{.data.AWS_DEFAULT_REGION}') | \
	docker login --username AWS --password-stdin "$${AWS_ECR_REGISTRY_URL}"

base-build:
	@echo "----------------- Starting port-forward to local registry -------------------"
	@kubectl port-forward svc/registry 5000:5000 &
	@echo "Waiting for port-forward..." && sleep 5

	@echo "----------------- Pulling, Tagging, and Pushing Base Images -------------------"
	@AWS_ECR_REGISTRY_URL=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_ECR_REGISTRY_URL}'); \
	IMG_PREFIX=$$(kubectl get configmap global-config -o jsonpath='{.data.IMG_PREFIX}'); \
	ENV_TAG=$$(kubectl get configmap global-config -o jsonpath='{.data.ENV_TAG}'); \
	BITBUCKET_BRANCH=$$(kubectl get configmap global-config -o jsonpath='{.data.BITBUCKET_BRANCH}'); \
	for base_name in $(BASE_NAMES); do \
    		config_map=$$(echo $$base_name | tr 'A-Z' 'a-z')-config; \
    		\
    		IMAGE_NAME=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_IMAGE}"); \
    		VERSION=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_VERSION}"); \
    		LOCAL_TAG=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_BUILT_IMAGE}"); \
    		\
    		ECR_IMAGE_PATH="$${AWS_ECR_REGISTRY_URL}/$${IMG_PREFIX}-$${IMAGE_NAME}:$${ENV_TAG}-$${BITBUCKET_BRANCH}-$${VERSION}"; \
    		LOCAL_IMAGE_PATH="localhost:5000/$${LOCAL_TAG}"; \
    		\
    		echo "--- Processing service: $$base_name ---"; \
    		echo "Pulling from: $${ECR_IMAGE_PATH}"; \
    		docker pull "$${ECR_IMAGE_PATH}"; \
    		echo "Tagging as: $${LOCAL_IMAGE_PATH}"; \
    		docker tag "$${ECR_IMAGE_PATH}" "$${LOCAL_IMAGE_PATH}"; \
    		docker push "$${LOCAL_IMAGE_PATH}"; \
    		echo "--- Done ---"; \
    	done

	@echo "----------------- Pulling, Tagging, and Pushing Docker Hub Base Images -------------------"
	@for base_name in $(DOCKERHUB_BASE_NAMES); do \
			config_map=$$(echo $$base_name | tr 'A-Z' 'a-z')-config; \
			\
			DOCKERHUB_IMAGE_PATH=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_IMAGE}"); \
			LOCAL_TAG=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_BUILT_IMAGE}"); \
			LOCAL_IMAGE_PATH="localhost:5000/$${LOCAL_TAG}"; \
			\
			echo "--- Processing Docker Hub service: $$base_name ---"; \
			echo "Pulling from: $${DOCKERHUB_IMAGE_PATH}"; \
			docker pull "$${DOCKERHUB_IMAGE_PATH}"; \
			echo "Tagging as: $${LOCAL_IMAGE_PATH}"; \
			docker tag "$${DOCKERHUB_IMAGE_PATH}" "$${LOCAL_IMAGE_PATH}"; \
			docker push "$${LOCAL_IMAGE_PATH}"; \
			echo "--- Done ---"; \
		done

	@echo "----------------- Verifying images in local registry -------------------"
	@curl -s http://localhost:5000/v2/_catalog
	@echo "----------------- Killing port-forward process -------------------"
	@pkill -f "kubectl port-forward.*5000" || true

# ---------------------------------------------------------------------------------
# ------------------------------ Minikube Management ------------------------------
# ---------------------------------------------------------------------------------
mk-up: mk-config
	@echo "----------------- Starting Minikube -------------------"
	minikube start --insecure-registry="192.168.0.0/16" --force

mk-stop:
	@echo "----------------- Stopping Minikube -------------------"
	-minikube stop

mk-delete:
	@echo "----------------- Deleting Minikube cluster -------------------"
	-minikube delete

mk-restart: mk-stop mk-up
	@echo "----------------- Restarting Minikube -------------------"

mk-setup:
	@echo "----------------- Mounting working directory into Minikube -------------------"
	docker cp . minikube:/workspace

# ---------------------------------------------------------------------------------
# -------------------------------- build Minikube ---------------------------------
# ---------------------------------------------------------------------------------

mk-build: mk-stop mk-delete mk-up mk-setup pre-build apply-config apply-instances-config aws-login base-build

pre-build:
	@echo "----------------- Auto-configuring resource limits -------------------"
	@CPU_CORES=$$(nproc); \
	TOTAL_MEM_GB=$$(free -g | awk '/^Mem:/ {print $$2}'); \
	\
	export LIMIT_CPU=$$(($$CPU_CORES - 2)); \
	export LIMIT_MEM=$$(($$TOTAL_MEM_GB - 4))Gi; \
	\
	export REQUEST_CPU=1; \
	export REQUEST_MEM=4Gi; \
	\
	echo "Detected $$CPU_CORES CPU cores and $$TOTAL_MEM_GB GB RAM."; \
	echo "Setting default container limits to: $$LIMIT_CPU cores and $$LIMIT_MEM memory."; \
	echo "Setting default container requests to: $$REQUEST_CPU core and $$REQUEST_MEM memory."; \
	\
	envsubst < kubernetes/limits.yaml.tpl > kubernetes/limits.yaml;
	@echo "kubernetes/limits.yaml generated successfully."

# ---------------------------------------------------------------------------------
# --------------------------------- apply configs ---------------------------------
# ---------------------------------------------------------------------------------
mk-config:
	@echo "----------------- Dynamically Configuring Minikube VM based on HOST resources -------------------"
	@CPU_CORES=$$(nproc); \
	TOTAL_MEM_MB=$$(free -m | awk '/^Mem:/ {print $$2}'); \
	\
	MINIKUBE_CPUS=$$(( $$CPU_CORES > 4 ? $$CPU_CORES - 2 : $$CPU_CORES )); \
	MINIKUBE_MEM_MB=$$(( $$TOTAL_MEM_MB > 8192 ? $$TOTAL_MEM_MB - 4096 : $$TOTAL_MEM_MB )); \
	\
	echo "Host has $$CPU_CORES CPUs and $$TOTAL_MEM_MB MB RAM."; \
	echo "--> Configuring Minikube with $$MINIKUBE_CPUS CPUs and $$MINIKUBE_MEM_MB MB RAM."; \
	\
	minikube config unset insecure-registry || true; \
	minikube config set insecure-registry "registry.default.svc.cluster.local:5000"; \
	minikube config set insecure-registry "localhost:5000"; \
	minikube config set memory "$${MINIKUBE_MEM_MB}"; \
	minikube config set cpus "$${MINIKUBE_CPUS}";

apply-config:
	@echo "----------------- Applying Kubernetes Registry -------------------"
	kubectl apply -f kubernetes/registry.yaml
	kubectl rollout status deployment registry -n default --timeout=180s
	@echo "----------------- Ensuring registry is ready -------------------"
	@echo "Waiting for registry pod to be ready..."
	@kubectl wait --for=condition=ready pod -l app=registry -n default --timeout=90s
	@echo "Registry pod is ready!"
	@sleep 2
	@echo "----------------- Applying Kubernetes Namespace Limits -------------------"
	kubectl apply -f kubernetes/limits.yaml
	@echo "----------------- Applying Global Configs & Secrets -------------------"
	kubectl apply -f kubernetes/global-config.yaml
	kubectl apply -f kubernetes/global-secret.yaml

apply-instances-config:
	@echo "----------------- Applying Postgres Persistent Volume Claim -------------------"
	kubectl apply -f kubernetes/postgres/postgres-pvc.yaml
	@echo "----------------- Applying Postgres ConfigMaps and Secrets -------------------"
	kubectl apply -f kubernetes/postgres/postgres-init-cm.yaml
	kubectl apply -f kubernetes/postgres/postgres-config.yaml
	kubectl apply -f kubernetes/postgres/postgres-secret.yaml
	@echo "----------------- Applying PgBouncer ConfigMaps -------------------"
	kubectl apply -f kubernetes/pgbouncer/pgbouncer-config.yaml
	@echo "----------------- Applying Redis Persistent Volume Claim -------------------"
	kubectl apply -f kubernetes/redis/redis-pvc.yaml
	@echo "----------------- Applying Redis ConfigMaps and Secrets -------------------"
	kubectl apply -f kubernetes/redis/redis-config.yaml
	kubectl apply -f kubernetes/redis/redis-secret.yaml

# ---------------------------------------------------------------------------------
# ----------------------------------- BUILD k8s -----------------------------------
# ---------------------------------------------------------------------------------

build-k8s: mk-setup build-k8s-postgres build-k8s-pgbouncer build-k8s-redis

build-k8s-postgres:
	@echo "----------------- Building Postgres for Kubernetes -------------------"
	@kubectl delete job postgres-build --ignore-not-found=true
	@kubectl apply -f kubernetes/postgres/postgres-build-job.yaml
	@echo "Waiting for Postgres build job to complete..."
	@kubectl wait --for=condition=complete job/postgres-build --timeout=90s || \
		(echo "!!! Postgres build failed, showing logs: !!!" && kubectl logs job/postgres-build --follow && exit 1)
	@echo "Postgres build completed successfully."

build-k8s-pgbouncer:
	@echo "----------------- Building PgBouncer for Kubernetes -------------------"
	@kubectl delete job pgbouncer-build --ignore-not-found=true
	@kubectl apply -f kubernetes/pgbouncer/pgbouncer-build-job.yaml
	@echo "Waiting for PgBouncer build job to complete..."
	@kubectl wait --for=condition=complete job/pgbouncer-build --timeout=90s || \
		(echo "!!! PgBouncer build failed, showing logs: !!!" && kubectl logs job/pgbouncer-build --follow && exit 1)
	@echo "PgBouncer build completed successfully."

build-k8s-redis:
	@echo "----------------- Building Redis for Kubernetes -------------------"
	@kubectl delete job redis-build --ignore-not-found=true
	@kubectl apply -f kubernetes/redis/redis-build-job.yaml
	@echo "Waiting for Redis build job to complete..."
	@kubectl wait --for=condition=complete job/redis-build --timeout=90s || \
		(echo "!!! Redis build failed, showing logs: !!!" && kubectl logs job/redis-build --follow && exit 1)
	@echo "Redis build completed successfully."

# ---------------------------------------------------------------------------------
# ----------------------------------- MANAGE k8s ----------------------------------
# ---------------------------------------------------------------------------------
up-k8s: down-k8s delete-pods create-services deploy-k8s port-forward-services
	@echo "----------------- System is up. Listing running Kubernetes pods -------------------"
	kubectl get pods

delete-pods:
	@for pod in $(PODS); do \
		echo "----------------- Deleting $$pod_app pods... -------------------"; \
		kubectl delete pods -l app=$$pod --ignore-not-found=true; \
	done
	@-kubectl delete pods -l job-name=langflow-benchmark --force --grace-period=0

create-services:
	@for service in $(SERVICES); do \
		echo "----------------- Creating $$service Service -------------------"; \
		service_lower=$$(echo $$service | tr 'A-Z' 'a-z'); \
		config_map=$${service_lower}-config; \
        \
        SERVICE=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${service}_SERVICE}"); \
        PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${service}_PORT}"); \
        export SERVICE PORT; \
        envsubst < kubernetes/$${service_lower}/$${service_lower}-service.yaml | kubectl apply -f -; \
	done

deploy-k8s:
	@for deploy in $(DEPLOYS); do \
		echo "----------------- Deploying $$deploy to Kubernetes -------------------"; \
		deploy_lower=$$(echo $$deploy | tr 'A-Z' 'a-z'); \
		config_map="$${deploy_lower}-config"; \
		\
		REGISTRY_HOST=$$(minikube ip); \
		BUILT_IMAGE=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${deploy}_BUILT_IMAGE}"); \
		PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${deploy}_PORT}"); \
		export REGISTRY_HOST BUILT_IMAGE PORT; \
		\
		envsubst < kubernetes/$$deploy_lower/$$deploy_lower-deployment.yaml | kubectl apply -f -; \
		\
		echo "----------------- Waiting for $$deploy_lower pod to be ready -------------------"; \
		kubectl wait --for=condition=ready pod -l app=$$deploy_lower --timeout=180s; \
		\
		echo "----------------- Testing $$deploy_lower Service -------------------"; \
		SERVICE_NAME=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${deploy}_SERVICE}"); \
		kubectl get service $$SERVICE_NAME; \
	done

down-k8s:
	@echo "----------------- Deleting Deployed Services Commander from Kubernetes -------------------"
	@for deploy in $(DEPLOYS); do \
		deploy_lower=$$(echo $$deploy | tr 'A-Z' 'a-z'); \
		kubectl delete -f kubernetes/$$deploy_lower/$$deploy_lower-deployment.yaml --ignore-not-found=true; \
	done
	@-kubectl delete job langflow-benchmark postgres-build langflow-build
    @PODS=""

ps-k8s:
	@echo "----------------- Listing running Kubernetes pods -------------------"
	@kubectl get pods
	@echo "----------------- Listing Kubernetes services -------------------"
	@kubectl get services

# ---------------------------------------------------------------------------------
# --------------------------------- port forwarding -------------------------------
# ---------------------------------------------------------------------------------
port-forward-services:
	@for portforward in $(PORTFORWARD); do \
		echo "----------------- Forwarding $$portforward to localhost (in background)... -------------------"; \
		portforward_lower=$$(echo $$portforward | tr 'A-Z' 'a-z'); \
		config_map=$${portforward_lower}-config; \
        \
        PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${portforward}_PORT}"); \
        REDIRECT_PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${portforward}_REDIRECT_PORT}"); \
        export PORT REDIRECT_PORT; \
        nohup kubectl port-forward "$$(kubectl get pods -l app=$${portforward_lower} -o jsonpath='{.items[0].metadata.name}')" "$${REDIRECT_PORT}:$${PORT}" > /dev/null 2>&1 & \
        echo "Waiting for port-forward..." && sleep 5 && \
        echo "----------------- $$portforward should be accessible at localhost:$${REDIRECT_PORT} -------------------"; \
	done

# ---------------------------------------------------------------------------------
# ------------------------------------ helpers ------------------------------------
# ---------------------------------------------------------------------------------
monitor-db:
	@bash kubernetes/monitoring/db.sh

monitor-pgbouncer:
	@bash kubernetes/monitoring/bouncer.sh