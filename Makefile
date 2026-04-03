.PHONY: start-server stop-server run run-ci list-workflows export-workflows import-workflows clean

# Variables
CONTAINER_NAME=n8n-server
N8N_PORT=5678
N8N_DATA_DIR=$(PWD)/.n8n
WORKFLOWS_DIR=$(PWD)/n8n-workflows
WORKFLOW_NAME?=hello-workflow
ENV_FILE=$(PWD)/.env
OUTPUT_DIR?=$(PWD)/outputs

# Start n8n server with UI for editing workflows
# Workflows are saved directly to .n8n directory in this repo
start-server:
	@echo "Starting n8n server..."
	@mkdir -p $(N8N_DATA_DIR)
	@if [ -f $(ENV_FILE) ]; then \
		echo "Loading environment from .env file..."; \
		docker run -d \
			--name $(CONTAINER_NAME) \
			-p $(N8N_PORT):5678 \
			-v $(N8N_DATA_DIR):/home/node/.n8n \
			--env-file $(ENV_FILE) \
			-e N8N_BASIC_AUTH_ACTIVE=false \
			-e N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
			docker.n8n.io/n8nio/n8n:latest; \
	else \
		echo "No .env file found, starting without environment variables..."; \
		docker run -d \
			--name $(CONTAINER_NAME) \
			-p $(N8N_PORT):5678 \
			-v $(N8N_DATA_DIR):/home/node/.n8n \
			-e N8N_BASIC_AUTH_ACTIVE=false \
			-e N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
			docker.n8n.io/n8nio/n8n:latest; \
	fi
	@echo ""
	@echo "✓ n8n server is starting!"
	@echo "   URL: http://localhost:$(N8N_PORT)"
	@echo "   Data: $(N8N_DATA_DIR)"
	@echo ""
	@echo "After creating/editing workflows, run 'make export-workflows' to save them to git"

# Stop the n8n server
stop-server:
	@echo "Stopping n8n server..."
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true
	@docker rm $(CONTAINER_NAME) 2>/dev/null || true
	@echo "✓ Server stopped"

# List all workflows in the database
list-workflows:
	@echo "Workflows in $(N8N_DATA_DIR):"
	@docker run --rm \
		-v $(N8N_DATA_DIR):/home/node/.n8n \
		docker.n8n.io/n8nio/n8n:latest \
		list:workflow 2>/dev/null || echo "No workflows found or database not initialized"

# Export all workflows from database to files (for version control)
export-workflows:
	@echo "Exporting workflows from $(N8N_DATA_DIR) to $(WORKFLOWS_DIR)..."
	@mkdir -p $(WORKFLOWS_DIR)
	@echo "Clearing old exports..."
	@rm -f $(WORKFLOWS_DIR)/*.json
	@docker run --rm \
		-v $(N8N_DATA_DIR):/home/node/.n8n \
		-v $(WORKFLOWS_DIR):/workflows \
		docker.n8n.io/n8nio/n8n:latest \
		export:workflow --output=/workflows --all --separate 2>&1 | grep -v "^n8n Task Broker" | grep -v "^Failed to start Python" | grep -v "^Registered runner" || true
	@echo "Renaming and formatting files..."
	@for file in $(WORKFLOWS_DIR)/*.json; do \
		if [ -f "$$file" ]; then \
			BASENAME=$$(basename "$$file" .json); \
			NAME=$$(cat "$$file" | jq -r '.name // empty' | sed 's/[^a-zA-Z0-9_-]/_/g'); \
			if [ -n "$$NAME" ] && [ "$$NAME" != "null" ]; then \
				NEWFILE="$(WORKFLOWS_DIR)/$$NAME.json"; \
				if [ "$$file" != "$$NEWFILE" ]; then \
					if [ -f "$$NEWFILE" ]; then \
						echo "  Warning: Duplicate workflow name '$$NAME', keeping both:"; \
						echo "    - $$(basename "$$NEWFILE")"; \
						NEWFILE="$(WORKFLOWS_DIR)/$${NAME}_$${BASENAME}.json"; \
						echo "    - $$(basename "$$NEWFILE")"; \
					fi; \
					mv "$$file" "$$NEWFILE"; \
				fi; \
				cat "$$NEWFILE" | jq --indent 2 --sort-keys '.' > "$$NEWFILE.tmp" && mv "$$NEWFILE.tmp" "$$NEWFILE"; \
				echo "  ✓ $$(basename "$$NEWFILE")"; \
			fi; \
		fi; \
	done
	@echo "✓ Workflows exported to $(WORKFLOWS_DIR)/"
	@ls -lh $(WORKFLOWS_DIR)/

# Import all workflows from files to database
import-workflows:
	@echo "Importing workflows from $(WORKFLOWS_DIR) to $(N8N_DATA_DIR)..."
	@mkdir -p $(N8N_DATA_DIR)
	@if [ ! -d $(WORKFLOWS_DIR) ] || [ -z "$$(ls -A $(WORKFLOWS_DIR)/*.json 2>/dev/null)" ]; then \
		echo "Error: No workflow JSON files found in $(WORKFLOWS_DIR)"; \
		echo "Run 'make export-workflows' first or add workflow JSON files to $(WORKFLOWS_DIR)/"; \
		exit 1; \
	fi
	@docker run --rm \
		-v $(N8N_DATA_DIR):/home/node/.n8n \
		-v $(WORKFLOWS_DIR):/workflows \
		docker.n8n.io/n8nio/n8n:latest \
		import:workflow --input=/workflows --separate 2>&1 | grep -v "^n8n Task Broker" | grep -v "^Failed to start Python" | grep -v "^Registered runner" || true
	@echo "✓ Workflows imported from $(WORKFLOWS_DIR)/"

# Execute a specific workflow (uses the same database as the server)
run:
	@echo "Executing workflow: $(WORKFLOW_NAME)"
	@echo "Using database: $(N8N_DATA_DIR)"
	@echo ""
	@if [ ! -d $(N8N_DATA_DIR) ]; then \
		echo "Error: No .n8n directory found at $(N8N_DATA_DIR)"; \
		echo "Run 'make start-server' first to create workflows"; \
		exit 1; \
	fi
	@echo "Finding workflow ID for: $(WORKFLOW_NAME)..."
	@WORKFLOW_ID=$$(docker run --rm \
		-v $(N8N_DATA_DIR):/home/node/.n8n \
		docker.n8n.io/n8nio/n8n:latest \
		list:workflow 2>/dev/null | grep "$(WORKFLOW_NAME)" | awk '{print $$1}' | cut -d'|' -f1 | head -1); \
	if [ -z "$$WORKFLOW_ID" ]; then \
		echo "Error: Workflow '$(WORKFLOW_NAME)' not found"; \
		echo ""; \
		echo "Available workflows:"; \
		docker run --rm -v $(N8N_DATA_DIR):/home/node/.n8n docker.n8n.io/n8nio/n8n:latest list:workflow 2>/dev/null || true; \
		exit 1; \
	fi; \
	echo "Executing workflow ID: $$WORKFLOW_ID"; \
	echo ""; \
	if [ -f $(ENV_FILE) ]; then \
		docker run --rm \
			-v $(N8N_DATA_DIR):/home/node/.n8n \
			--env-file $(ENV_FILE) \
			-e N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
			docker.n8n.io/n8nio/n8n:latest \
			execute --id=$$WORKFLOW_ID; \
	else \
		docker run --rm \
			-v $(N8N_DATA_DIR):/home/node/.n8n \
			-e N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
			docker.n8n.io/n8nio/n8n:latest \
			execute --id=$$WORKFLOW_ID; \
	fi

# Execute workflow and save structured results (ideal for CI/CD)
run-ci:
	@echo "Executing workflow with CI output: $(WORKFLOW_NAME)"
	@if [ -n "$$NAME" ]; then echo "Using NAME=$$NAME from environment"; fi
	@mkdir -p $(OUTPUT_DIR)
	@ENV_ARGS=""; \
	if [ -f $(ENV_FILE) ]; then ENV_ARGS="--env-file $(ENV_FILE)"; fi; \
	if [ -n "$$NAME" ]; then ENV_ARGS="$$ENV_ARGS -e NAME=$$NAME"; fi; \
	docker run --rm \
		-v $(N8N_DATA_DIR):/home/node/.n8n \
		-v $(WORKFLOWS_DIR):/workflows \
		-v $(PWD)/run-workflow.js:/run-workflow.js \
		-v $(OUTPUT_DIR):/tmp/outputs \
		$$ENV_ARGS \
		-e N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
		-e WORKFLOW_NAME=$(WORKFLOW_NAME) \
		-e OUTPUT_DIR=/tmp/outputs \
		-e WORKFLOWS_DIR=/workflows \
		--entrypoint="" \
		docker.n8n.io/n8nio/n8n:latest \
		/usr/local/bin/node /run-workflow.js
	@echo ""
	@echo "Results saved to $(OUTPUT_DIR)/"
	@ls -lh $(OUTPUT_DIR)/
	@echo ""
	@echo "Quick view:"
	@if [ -f $(OUTPUT_DIR)/result-json ]; then \
		echo "Result:"; \
		cat $(OUTPUT_DIR)/result-json | jq '.data[0].json' 2>/dev/null || cat $(OUTPUT_DIR)/result-json; \
	fi

# Clean n8n data directory
clean:
	@echo "Cleaning n8n data directory..."
	@rm -rf $(N8N_DATA_DIR)
	@echo "✓ Cleanup complete"
