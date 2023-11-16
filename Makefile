.ONESHELL:
.PHONY:

all: install

##### Variables ######
COLOR := "\e[1;36m%s\e[0m\n"

TEMPORAL_ROOT := temporal
TCTL_ROOT := tctl

IMAGE_TAG=$(shell git rev-parse --short HEAD)
TEMPORAL_SHA := $(shell sh -c 'git submodule status -- temporal | cut -c2-40')
TCTL_SHA := $(shell sh -c "git submodule status -- tctl | cut -c2-40")

BAKE := IMAGE_TAG=$(IMAGE_TAG) TEMPORAL_SHA=$(TEMPORAL_SHA) TCTL_SHA=$(TCTL_SHA) docker buildx bake

##### Scripts ######
install: install-submodules

update: update-submodules

install-submodules:
	@printf $(COLOR) "Installing temporal and tctl submodules..."
	git submodule update --init $(TEMPORAL_ROOT) $(TCTL_ROOT)

update-submodules:
	@printf $(COLOR) "Updatinging temporal and tctl submodules..."
	git submodule update --force --remote $(TEMPORAL_ROOT) $(TCTL_ROOT)

##### Docker #####

build:
	$(BAKE)

simulate-push:
	@act push -s GITHUB_TOKEN="$(shell gh auth token)" -j build-push-images -P ubuntu-latest-16-cores=catthehacker/ubuntu:act-latest

COMMIT =?
simulate-dispatch:
	@act workflow-dispatch -s GITHUB_TOKEN="$(shell gh auth token)" -j build-push-images -P ubuntu-latest-16-cores=catthehacker/ubuntu:act-latest --input commit=$(COMMIT)

# We hard-code linux/amd64 here as the docker machine for mac doesn't support cross-platform builds (but it does when running verify-ci)
docker-server:
	@printf $(COLOR) "Building docker image temporalio/server:$(IMAGE_TAG)..."
	$(BAKE) server --set "*.platform=linux/amd64"

docker-admin-tools:
	@printf $(COLOR) "Build docker image temporalio/admin-tools:$(IMAGE_TAG)..."
	$(BAKE) admin-tools --set "*.platform=linux/amd64"

docker-auto-setup:
	@printf $(COLOR) "Build docker image temporalio/auto-setup:$(IMAGE_TAG)..."
	$(BAKE) auto-setup --set "*.platform=linux/amd64"

docker-buildx-container:
	docker buildx create --name builder-x --driver docker-container --use

docker-server-x:
	@printf $(COLOR) "Building cross-platform docker image temporalio/server:$(IMAGE_TAG)..."
	$(BAKE) server

docker-admin-tools-x:
	@printf $(COLOR) "Build cross-platform docker image temporalio/admin-tools:$(IMAGE_TAG)..."
	$(BAKE) admin-tools

docker-auto-setup-x:
	@printf $(COLOR) "Build cross-platform docker image temporalio/auto-setup:$(DOCKER_IMAGE_TAG)..."
	$(BAKE) auto-setup
