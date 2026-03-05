PROJECT_ID   := tesserix
STATE_BUCKET := tesserix-tf-state
REGION       := asia-south1

# Bootstrap: create state bucket (run once, manually)
bootstrap:
	gcloud storage buckets create gs://$(STATE_BUCKET) \
		--project=$(PROJECT_ID) \
		--location=$(REGION) \
		--uniform-bucket-level-access \
		--public-access-prevention
	gcloud storage buckets update gs://$(STATE_BUCKET) --versioning

# Stack operations
define STACK_COMMANDS
init-$(1):
	cd $(1) && terraform init \
		-backend-config="bucket=$(STATE_BUCKET)" \
		-backend-config="prefix=$(1)"

plan-$(1):
	cd $(1) && terraform plan \
		-var-file=../terraform.tfvars

apply-$(1):
	cd $(1) && terraform plan \
		-var-file=../terraform.tfvars \
		-out=tfplan && \
	terraform apply tfplan

destroy-$(1):
	cd $(1) && terraform destroy \
		-var-file=../terraform.tfvars
endef

$(eval $(call STACK_COMMANDS,01-foundation))
$(eval $(call STACK_COMMANDS,02-core))
$(eval $(call STACK_COMMANDS,03-iam))
$(eval $(call STACK_COMMANDS,04-services))

# Deploy all stacks in order
all: apply-01-foundation apply-02-core apply-03-iam apply-04-services

# Init all stacks
init-all: init-01-foundation init-02-core init-03-iam init-04-services

.PHONY: bootstrap all init-all
