# Setup some useful vars
PKG = github.com/apprenda/kismatic
HOST_GOOS = $(shell go env GOOS)
HOST_GOARCH = $(shell go env GOARCH)
BUILD_OUTPUT = out-$(GOOS)

# Set the build version
ifeq ($(origin VERSION), undefined)
	VERSION := $(shell git describe --tags --always --dirty)
endif
# Set the build branch
ifeq ($(origin BRANCH), undefined)
	BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif
# build date
ifeq ($(origin BUILD_DATE), undefined)
	BUILD_DATE := $(shell date -u)
endif
# If no target is defined, assume the host is the target.
ifeq ($(origin GOOS), undefined)
	GOOS := $(HOST_GOOS)
endif
# Lots of these target goarches probably won't work,
# since we depend on vendored packages also being built for the correct arch
ifeq ($(origin GOARCH), undefined)
	GOARCH := $(HOST_GOARCH)
endif


# Versions of external dependencies
GLIDE_VERSION = v0.13.1
ANSIBLE_VERSION = 2.3.0.0
TERRAFORM_VERSION = 0.11.3
SWAGGER_VERSION = 0.13.0
SWAGGER-UI_VERSION = 3.10.0
KUBERANG_VERSION = v1.2.2
GO_VERSION = 1.9.4
KUBECTL_VERSION = v1.9.2
HELM_VERSION = v2.7.2

install: build copy-kismatic copy-inspector copy-playbooks copy-terraform

dist: shallow-clean vendor glide-install
	@echo "Running dist inside contianer"
	@docker run                                \
	    --rm                                   \
	    -e GOOS="$(GOOS)"                      \
	    -e HOST_GOOS="linux"                   \
	    -e VERSION="$(VERSION)"                \
	    -e BUILD_DATE="$(BUILD_DATE)"          \
	    -u root:root                 		   \
	    -v "$(shell pwd)":"/go/src/$(PKG)"     \
	    -w "/go/src/$(PKG)"                    \
	    circleci/golang:$(GO_VERSION)          \
	    make dist-common

test:
	@docker run                             \
	    --rm                                \
	    -e HOST_GOOS="linux"               \
	    -u root:root              \
	    -v "$(shell pwd)":/go/src/$(PKG)    \
	    -v /tmp:/tmp                        \
	    -w /go/src/$(PKG)                   \
	    circleci/golang:$(GO_VERSION)       \
	    make test-host

test-host:
	go test ./cmd/... ./pkg/... $(TEST_OPTS)

clean: shallow-clean
	rm -rf bin
	rm -rf out-*
	rm -rf vendor
	rm -rf vendor-ansible
	rm -rf vendor-terraform
	rm -rf vendor-kuberang
	rm -rf vendor-helm
	rm -rf vendor-kubectl
	rm -rf vendor-swagger-ui
	tools/glide-$(HOST_GOOS)-$(HOST_GOARCH) cc
	rm -rf tools
	rm kismatic-*.tar.gz

# YOU SHOULDN'T NEED TO USE ANYTHING BENEATH THIS LINE
# UNLESS YOU REALLY KNOW WHAT YOU'RE DOING
# ---------------------------------------------------------------------
all:
	@$(MAKE) GOOS=darwin make dist
	@$(MAKE) GOOS=linux make dist
	@$(MAKE) make dist-docker


all-host:

shallow-clean:
	rm -rf $(BUILD_OUTPUT)

build: 
	@echo Building kismatic in container
	@docker run                                \
	    --rm                                   \
	    -e GOOS="$(GOOS)" 		      		   \
	    -e HOST_GOOS="linux"                   \
	    -e VERSION="$(VERSION)"                \
	    -e BUILD_DATE="$(BUILD_DATE)"          \
	    -u root:root                 		   \
	    -v "$(shell pwd)":"/go/src/$(PKG)"     \
	    -w /go/src/$(PKG)                      \
	    circleci/golang:$(GO_VERSION)          \
	    make build-host

build-host: bin/$(GOOS)/kismatic

.PHONY: bin/$(GOOS)/kismatic
bin/$(GOOS)/kismatic:
	go build -o $@                                                              \
	    -ldflags "-X main.version=$(VERSION) -X 'main.buildDate=$(BUILD_DATE)'" \
	    ./cmd/kismatic

build-inspector:
	@echo Building inspector in container
	@docker run                                \
	    --rm                                   \
	    -e GOOS="$(GOOS)"               \
	    -e HOST_GOOS="linux"                   \
	    -e VERSION="$(VERSION)"                \
	    -e BUILD_DATE="$(BUILD_DATE)"          \
	    -u root:root                		   \
	    -v "$(shell pwd)":"/go/src/$(PKG)"     \
	    -w /go/src/$(PKG)                      \
	    circleci/golang:$(GO_VERSION)          \
	    make build-inspector-host

build-inspector-host:
	@$(MAKE) GOOS=linux bin/inspector/linux/$(GOARCH)/kismatic-inspector

.PHONY: bin/inspector/$(GOOS)/$(GOARCH)/kismatic-inspector
bin/inspector/$(GOOS)/$(GOARCH)/kismatic-inspector:
	go build -o $@                                                               \
	    -ldflags "-X main.version=$(VERSION) -X 'main.buildDate=$(BUILD_DATE)'"  \
	    ./cmd/kismatic-inspector

integration-test: dist just-integration-test

glide-install:
	tools/glide-$(HOST_GOOS)-$(HOST_GOARCH) install

.PHONY: vendor
vendor: vendor-tools vendor-ansible/out vendor-terraform/out vendor-swagger-ui/out vendor-kuberang/$(KUBERANG_VERSION) vendor-kubectl/out/kubectl-$(KUBECTL_VERSION)-$(GOOS)-$(GOARCH) vendor-helm/out/helm-$(HELM_VERSION)-$(GOOS)-$(GOARCH)

.PHONY: vendor-tools
vendor-tools: tools/glide-$(HOST_GOOS)-$(HOST_GOARCH) tools/swagger-$(HOST_GOOS)-$(HOST_GOARCH)
	
tools/glide-$(HOST_GOOS)-$(HOST_GOARCH):
	mkdir -p tools
	curl -L https://github.com/Masterminds/glide/releases/download/$(GLIDE_VERSION)/glide-$(GLIDE_VERSION)-$(HOST_GOOS)-$(HOST_GOARCH).tar.gz | tar -xz -C tools
	mv tools/$(HOST_GOOS)-$(HOST_GOARCH)/glide tools/glide-$(HOST_GOOS)-$(HOST_GOARCH)
	rm -r tools/$(HOST_GOOS)-$(HOST_GOARCH)

tools/swagger-$(HOST_GOOS)-$(HOST_GOARCH):
	curl -L https://github.com/go-swagger/go-swagger/releases/download/$(SWAGGER_VERSION)/swagger_$(HOST_GOOS)_$(HOST_GOARCH) -o tools/swagger-$(HOST_GOOS)-$(HOST_GOARCH)
	chmod +x tools/swagger-$(HOST_GOOS)-$(HOST_GOARCH)

vendor-ansible/out:
	mkdir -p vendor-ansible/out
	curl -L https://github.com/apprenda/vendor-ansible/releases/download/v$(ANSIBLE_VERSION)/ansible.tar.gz -o vendor-ansible/out/ansible.tar.gz
	tar -zxf vendor-ansible/out/ansible.tar.gz -C vendor-ansible/out
	rm vendor-ansible/out/ansible.tar.gz

vendor-swagger-ui/out:
	mkdir -p vendor-swagger-ui/out
	curl -L https://github.com/swagger-api/swagger-ui/archive/v$(SWAGGER-UI_VERSION).tar.gz | tar -xz -C vendor-swagger-ui/out
	sed -i "" 's@http://petstore.swagger.io/v2/swagger.json@/spec/v1/swagger.json@g' vendor-swagger-ui/out/swagger-ui-$(SWAGGER-UI_VERSION)/dist/index.html

vendor-terraform/out:
	mkdir -p vendor-terraform/out/$(GOOS)
	curl -L https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_$(GOOS)_$(GOARCH).zip -o vendor-terraform/out/$(GOOS)/tmp.zip
	unzip vendor-terraform/out/$(GOOS)/tmp.zip -d vendor-terraform/out/$(GOOS)/
	rm vendor-terraform/out/$(GOOS)/tmp.zip

vendor-kuberang/$(KUBERANG_VERSION):
	mkdir -p vendor-kuberang/$(KUBERANG_VERSION)
	curl -L https://github.com/apprenda/kuberang/releases/download/$(KUBERANG_VERSION)/kuberang-linux-$(GOARCH) -o vendor-kuberang/$(KUBERANG_VERSION)/kuberang-linux-$(GOARCH)

vendor-kubectl/out/kubectl-$(KUBECTL_VERSION)-$(GOOS)-$(GOARCH):
	mkdir -p vendor-kubectl/out/
	curl -L https://storage.googleapis.com/kubernetes-release/release/$(KUBECTL_VERSION)/bin/$(GOOS)/$(GOARCH)/kubectl -o vendor-kubectl/out/kubectl-$(KUBECTL_VERSION)-$(GOOS)-$(GOARCH)
	chmod +x vendor-kubectl/out/kubectl-$(KUBECTL_VERSION)-$(GOOS)-$(GOARCH)

vendor-helm/out/helm-$(HELM_VERSION)-$(GOOS)-$(GOARCH):
	mkdir -p vendor-helm/out/
	curl -L https://storage.googleapis.com/kubernetes-helm/helm-$(HELM_VERSION)-$(GOOS)-$(GOARCH).tar.gz | tar zx -C vendor-helm
	cp vendor-helm/$(GOOS)-$(GOARCH)/helm vendor-helm/out/helm-$(HELM_VERSION)-$(GOOS)-$(GOARCH)
	rm -rf vendor-helm/$(GOOS)-$(GOARCH)
	chmod +x vendor-helm/out/helm-$(HELM_VERSION)-$(GOOS)-$(GOARCH)

copy-kismatic:
	mkdir -p $(BUILD_OUTPUT)
	cp bin/$(GOOS)/kismatic $(BUILD_OUTPUT)

copy-inspector:
	mkdir -p $(BUILD_OUTPUT)/ansible/playbooks/inspector
	cp -r bin/inspector/* $(BUILD_OUTPUT)/ansible/playbooks/inspector

copy-playbooks:
	rm -rf $(BUILD_OUTPUT)/ansible/playbooks
	cp -r ansible $(BUILD_OUTPUT)/ansible/playbooks

copy-terraform:
	cp vendor-terraform/out/$(GOOS)/terraform $(BUILD_OUTPUT)/terraform
	cp -r providers $(BUILD_OUTPUT)/providers

copy-vendors: # omit kismatic, inspector, playbooks, terraform since we provide configs for those.
	mkdir -p $(BUILD_OUTPUT)/ansible
	cp -r vendor-ansible/out/ansible/* $(BUILD_OUTPUT)/ansible
	mkdir -p $(BUILD_OUTPUT)/swagger-ui/spec
	cp -r vendor-swagger-ui/out/swagger-ui-$(SWAGGER-UI_VERSION)/dist $(BUILD_OUTPUT)/swagger-ui
	cp docs/swagger.json $(BUILD_OUTPUT)/swagger-ui/spec
	cp vendor-kubectl/out/kubectl-$(KUBECTL_VERSION)-$(GOOS)-$(GOARCH) $(BUILD_OUTPUT)/kubectl
	cp vendor-helm/out/helm-$(HELM_VERSION)-$(GOOS)-$(GOARCH) $(BUILD_OUTPUT)/helm
	mkdir -p $(BUILD_OUTPUT)/ansible/playbooks/kuberang/linux/$(GOARCH)/
	cp vendor-kuberang/$(KUBERANG_VERSION)/kuberang-linux-$(GOARCH) $(BUILD_OUTPUT)/ansible/playbooks/kuberang/linux/$(GOARCH)/kuberang

tarball/$(GOOS): 
	rm -f kismatic-$(GOOS).tar.gz
	tar -czf kismatic-$(GOOS).tar.gz -C $(BUILD_OUTPUT) .

dist-common: build-host build-inspector-host copy-kismatic copy-inspector copy-playbooks copy-terraform copy-vendors

dist-host: shallow-clean vendor glide-install dist-common

dist-docker: vendor glide-install
	@$(MAKE) GOOS=linux BUILD_OUTPUT=out-docker dist-common
	docker build . --no-cache --tag apprenda/kismatic:dev-$(BRANCH)
	docker push apprenda/kismatic:dev-$(BRANCH)

get-ginkgo:
	go get github.com/onsi/ginkgo/ginkgo
	cd integration-tests && ../tools/glide-$(GLIDE_GOOS)-$(HOST_GOARCH) install

just-integration-test: integration-tests/vendor
	ginkgo --skip "\[slow\]" -p $(GINKGO_OPTS) -v integration-tests

slow-integration-test: integration-tests/vendor
	ginkgo --focus "\[slow\]" -p $(GINKGO_OPTS) -v integration-tests

serial-integration-test: integration-tests/vendor
	ginkgo -v integration-tests

focus-integration-test: integration-tests/vendor
	ginkgo --focus $(FOCUS) $(GINKGO_OPTS) -v integration-tests

docs/update-plan-file-reference.md:
	@$(MAKE) docs/generate-plan-file-reference.md > docs/plan-file-reference.md

docs/generate-plan-file-reference.md:
	@go run cmd/gen-kismatic-ref-docs/*.go -o markdown pkg/install/plan_types.go Plan

docs/generate-swagger.json:
	GOROOT=$(shell go env GOROOT) tools/swagger_$(HOST_GOOS) generate spec -b ./pkg/server 

docs/update-swagger.json: 
	GOROOT=$(shell go env GOROOT) tools/swagger_$(HOST_GOOS) generate spec -b ./pkg/server > docs/swagger.json

CIRCLE_ENDPOINT=
ifndef CIRCLE_CI_BRANCH
	CIRCLE_ENDPOINT=https://circleci.com/api/v1.1/project/github/apprenda/kismatic
else
	CIRCLE_ENDPOINT=https://circleci.com/api/v1.1/project/github/apprenda/kismatic/tree/$(CIRCLE_CI_BRANCH)
endif

trigger-ci-slow-tests:
	@echo Triggering build with slow tests
	curl -u $(CIRCLE_CI_TOKEN): -X POST --header "Content-Type: application/json"     \
		-d '{"build_parameters": {"RUN_SLOW_TESTS": "true"}}'                         \
		$(CIRCLE_ENDPOINT)
trigger-ci-focused-tests:
	@echo Triggering focused test
	curl -u $(CIRCLE_CI_TOKEN): -X POST --header "Content-Type: application/json"     \
		-d "{\"build_parameters\": {\"FOCUS\": \"$(FOCUS)\"}}"                         \
		$(CIRCLE_ENDPOINT)
