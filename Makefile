.PHONY: validate fmt

validate:
	./scripts/validate.sh

fmt:
	terraform fmt -recursive terraform
