CONTAINER_RUNTIME := $(shell which docker podman 2>/dev/null | head -n1)
IMAGE_NAME := zunit-tester

build-container:
	if ! $(CONTAINER_RUNTIME) image inspect $(IMAGE_NAME) > /dev/null 2>&1; then \
		echo "Building $(IMAGE_NAME)..."; \
		$(CONTAINER_RUNTIME) build -t $(IMAGE_NAME) .; \
	fi

docker-test: build-container
	echo "Running zunit tests in container..." && \
	$(CONTAINER_RUNTIME) run --rm \
		-v "$(shell pwd):/app" \
		-v "$(shell pwd)/.zshrc:/root/.zshrc:ro" \
		$(IMAGE_NAME)

dev: build-container
	$(CONTAINER_RUNTIME) run --rm -ti \
		-v "$(shell pwd):/app" \
		-v "$(shell pwd)/.zshrc:/root/.zshrc:ro" \
		--entrypoint zsh \
		$(IMAGE_NAME)
