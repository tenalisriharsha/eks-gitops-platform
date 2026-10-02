.PHONY: validate validate-gitops validate-all fmt

validate:
	./scripts/validate.sh

validate-gitops:
	./scripts/validate-gitops.sh

validate-all: validate validate-gitops

fmt:
	terraform fmt -recursive terraform
