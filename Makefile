SHELL ?= /bin/bash

.DEFAULT_GOAL := test

################################################################################
# Version details                                                              #
################################################################################

GIT_VERSION = $(shell git describe --always --abbrev=7 --dirty)

################################################################################
# Docker images we build and publish                                           #
################################################################################

ifdef DOCKER_REGISTRY
	DOCKER_REGISTRY := $(DOCKER_REGISTRY)/
else
	DOCKER_REGISTRY := brigadecore/
endif

ifdef VERSION
	IMMUTABLE_DOCKER_TAG := $(VERSION)
	MUTABLE_DOCKER_TAG   := latest
else
	IMMUTABLE_DOCKER_TAG := $(GIT_VERSION)
	MUTABLE_DOCKER_TAG   := edge
endif

################################################################################
# Utility targets                                                              #
################################################################################

.PHONY: redeploy
redeploy: test push-all-images
redeploy:
	kubectl delete `kubectl get po -l app=github-app-test-brigade-github-app -o name`
	@echo 'Waiting for pod to start... (20 seconds)'
	sleep 20
	kubectl logs -f `kubectl get po -l app=github-app-test-brigade-github-app -o name | tail -n 1 | sed 's/pod\///'`

HAS_DEP          := $(shell command -v dep;)
HAS_GOLANGCI     := $(shell command -v golangci-lint;)

.PHONY: bootstrap
bootstrap:
ifndef HAS_DEP
	curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
endif
ifndef HAS_GOLANGCI
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s -- -b $(GOPATH)/bin
endif
	dep ensure

################################################################################
# Tests                                                                        #
################################################################################

.PHONY: lint
lint:
	golangci-lint run --config ./golangci.yml

.PHONY: test
test:
	go test ./pkg/...

################################################################################
# Build / Publish                                                              #
################################################################################

BINS := github-gateway check-run
IMAGES = brigade-github-app brigade-github-check-run

# Cross-compile for Docker+Linux
.PHONY: build-all-bins
build-all-bins: $(addsuffix -build-bin,$(BINS))

%-build-bin: bootstrap
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o ./rootfs/$* ./cmd/$*

# To use build-all-images, you need to have Docker installed and configured. You
# should also set DOCKER_REGISTRY to your own personal registry if you are not
# pushing to the official upstream.
.PHONY: build-all-images
build-all-images: build-all-bins
build-all-images: $(addsuffix -build-image,$(IMAGES))

%-build-image:
	docker build -f Dockerfile.$* -t $(DOCKER_REGISTRY)$*:$(IMMUTABLE_DOCKER_TAG) .
	docker tag $(DOCKER_REGISTRY)$*:$(IMMUTABLE_DOCKER_TAG) $(DOCKER_REGISTRY)$*:$(MUTABLE_DOCKER_TAG)

# You must be logged into DOCKER_REGISTRY before you can push.
.PHONY: push-all-images
push-all-images: build-all-images
push-all-images: $(addsuffix -push-image,$(IMAGES))

%-push-image:
	docker push $(DOCKER_REGISTRY)$*:$(IMMUTABLE_DOCKER_TAG)
	docker push $(DOCKER_REGISTRY)$*:$(MUTABLE_DOCKER_TAG)
