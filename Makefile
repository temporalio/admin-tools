.ONESHELL:
.PHONY:

all: install

##### Variables ######
COLOR := "\e[1;36m%s\e[0m\n"

TEMPORAL_ROOT := temporal
TCTL_ROOT := tctl
CLI_ROOT := cli
DOCKERIZE_ROOT := dockerize
IMAGE_TAG ?= sha-$(shell git rev-parse --short HEAD)
TEMPORAL_SHA := $(shell sh -c 'git submodule status -- temporal | cut -c2-40')
TCTL_SHA := $(shell sh -c "git submodule status -- tctl | cut -c2-40")

DOCKER ?= docker buildx
BAKE := IMAGE_TAG=$(IMAGE_TAG) TEMPORAL_SHA=$(TEMPORAL_SHA) TCTL_SHA=$(TCTL_SHA) $(DOCKER) bake

##### Scripts ######
install: install-submodules

update: update-submodules

install-submodules:
	@printf $(COLOR) "Installing submodules..."
	git submodule update --init

update-submodules:
	@printf $(COLOR) "Updatinging temporal and tctl submodules..."
	git submodule update --force --remote $(TEMPORAL_ROOT) $(TCTL_ROOT)

##### Docker #####
build/%:
	mkdir -p $(@)

# If you're new to Make, this is a pattern rule: https://www.gnu.org/software/make/manual/html_node/Pattern-Rules.html#Pattern-Rules
# $* expands to the stem that matches the %, so when the target is amd64-bins $* expands to amd64
%-bins: build/%
	@printf $(COLOR) "Compiling for $*..."
	(cd $(DOCKERIZE_ROOT) && GOOS=linux GOARCH=$* go build -o $(shell git rev-parse --show-toplevel)/build/$*/dockerize .)
	GOOS=linux GOARCH=$* make -C $(TEMPORAL_ROOT) bins
	cp $(TEMPORAL_ROOT)/{temporal-server,temporal-cassandra-tool,temporal-sql-tool,tdbg} build/$*/
	GOOS=linux GOARCH=$* make -C cli build
	cp ./cli/temporal build/$*/
	GOOS=linux GOARCH=$* make -C $(TCTL_ROOT) build
	cp ./$(TCTL_ROOT)/tctl build/$*/
	cp ./$(TCTL_ROOT)/tctl-authorization-plugin build/$*/

bins: install-submodules amd64-bins arm64-bins
.NOTPARALLEL: bins

build: bins
	$(BAKE)

simulate-push:
	@act push -s GITHUB_TOKEN="$(shell gh auth token)" -j build-push-images -P ubuntu-latest-16-cores=catthehacker/ubuntu:act-latest

COMMIT =?
simulate-dispatch:
	@act workflow_dispatch -s GITHUB_TOKEN="$(shell gh auth token)" -j build-push-images -P ubuntu-latest-16-cores=catthehacker/ubuntu:act-latest --input commit=$(COMMIT)

# We hard-code linux/amd64 here as the docker machine for mac doesn't support cross-platform builds (but it does when running verify-ci)
docker-server: amd64-bins
	@printf $(COLOR) "Building docker image temporalio/server:$(IMAGE_TAG)..."
	$(BAKE) server --set "*.platform=linux/amd64"

docker-admin-tools: amd64-bins
	@printf $(COLOR) "Build docker image temporalio/admin-tools:$(IMAGE_TAG)..."
	$(BAKE) admin-tools --set "*.platform=linux/amd64"

docker-auto-setup: amd64-bins
	@printf $(COLOR) "Build docker image temporalio/auto-setup:$(IMAGE_TAG)..."
	$(BAKE) auto-setup --set "*.platform=linux/amd64"

docker-buildx-container:
	docker buildx create --name builder-x --driver docker-container --use

docker-server-x: bins
	@printf $(COLOR) "Building cross-platform docker image temporalio/server:$(IMAGE_TAG)..."
	$(BAKE) server

docker-admin-tools-x: bins
	@printf $(COLOR) "Build cross-platform docker image temporalio/admin-tools:$(IMAGE_TAG)..."
	$(BAKE) admin-tools

docker-auto-setup-x: bins
	@printf $(COLOR) "Build cross-platform docker image temporalio/auto-setup:$(DOCKER_IMAGE_TAG)..."
	$(BAKE) auto-setup

test:
	IMAGE_TAG=$(IMAGE_TAG) ./test.sh
