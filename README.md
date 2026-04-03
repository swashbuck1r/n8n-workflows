# n8n Workflow Runner

Run n8n workflows locally and in CloudBees Unify CI/CD pipelines.

## Quick Start

### 1. Import Existing Workflows (First Time)

```bash
make import-workflows
```

This imports workflows from `n8n-workflows/` into your local database.

### 2. Start the n8n Server (Optional - for editing)

```bash
make start-server
```

Then open http://localhost:5678 to create/edit workflows using the UI.

### 3. Export Workflows After Editing

```bash
make export-workflows
```

This saves workflows from the database to `n8n-workflows/` directory (for git).

### 4. List Workflows

```bash
make list-workflows
```

### 5. Run a Workflow

```bash
make run-ci WORKFLOW_NAME=hello-workflow
```

Or with custom environment variables:

```bash
NAME=Alice make run-ci WORKFLOW_NAME=hello-workflow
```

### 6. Stop the Server

```bash
make stop-server
```

## How It Works

- **Workflow Files**: Version-controlled JSON files in `n8n-workflows/` directory
- **Local Database**: `.n8n/` directory (git-ignored, regenerated from workflow files)
- **Server Mode**: `make start-server` runs n8n UI for editing workflows
- **Export/Import**: Use `export-workflows` and `import-workflows` to sync between database and files
- **CI/CD**: The `run-ci` command automatically imports workflows before execution

## CloudBees Unify Workflow Example

This example shows how to run n8n workflows in CloudBees Unify and capture structured results.

```yaml
apiVersion: automation.cloudbees.io/v1alpha1
kind: workflow
name: run-n8n-workflow

on:
  workflow_dispatch:
    inputs:
      workflow_name:
        description: "Name of the n8n workflow to execute"
        default: "hello-workflow"
      input_name:
        description: "Name parameter to pass to workflow"
        default: "CloudBees"

jobs:
  run-workflow:
    steps:
      - name: Checkout code
        uses: cloudbees-io/checkout@v1

      - name: Execute n8n workflow
        uses: docker://docker.n8n.io/n8nio/n8n:latest
        with:
          entrypoint: node
          args: /workspace/run-workflow.js
        env:
          WORKFLOW_NAME: ${{ inputs.workflow_name }}
          NAME: ${{ inputs.input_name }}
          N8N_BLOCK_ENV_ACCESS_IN_NODE: "false"
          SKIP_IMPORT: "true"

      - name: Display results
        run: |
          echo "=== Execution Summary ==="
          cat $CLOUDBEES_OUTPUTS/summary.json | jq '.'
          echo ""
          echo "=== Result Data ==="
          cat $CLOUDBEES_OUTPUTS/result.json | jq '.data'

      - name: Check execution success
        run: |
          SUCCESS=$(cat $CLOUDBEES_OUTPUTS/summary.json | jq -r '.success')
          if [ "$SUCCESS" != "true" ]; then
            echo "Workflow execution failed"
            exit 1
          fi
```

### Output Files

The workflow execution creates three files in `$CLOUDBEES_OUTPUTS`:

1. **`summary-json`** - High-level execution summary
   ```json
   {
     "workflow": "hello-workflow",
     "workflowId": "Raqzqu66GkRc9z6I",
     "executionId": "123",
     "success": true,
     "startedAt": "2024-01-01T00:00:00.000Z",
     "stoppedAt": "2024-01-01T00:00:01.000Z",
     "resultDataCount": 1
   }
   ```

2. **`result-json`** - Workflow output data
   ```json
   {
     "success": true,
     "workflowId": "Raqzqu66GkRc9z6I",
     "data": [
       {
         "json": {
           "message": "Hello world",
           "name": "John"
         }
       }
     ]
   }
   ```

3. **`execution-json`** - Full execution details (for debugging)

Note: Filenames use hyphens instead of dots for compatibility with CloudBees step outputs.

## Makefile Targets

- `make import-workflows` - Import workflows from `n8n-workflows/` to database
- `make export-workflows` - Export workflows from database to `n8n-workflows/`
- `make start-server` - Start n8n UI server (port 5678)
- `make stop-server` - Stop the server
- `make list-workflows` - List all workflows in the database
- `make run WORKFLOW_NAME=<name>` - Execute a specific workflow (raw output)
- `make run-ci WORKFLOW_NAME=<name>` - Execute workflow with structured CI output (saves to `outputs/`)
- `make clean` - Remove .n8n directory

## Environment Variables

Workflows can access environment variables via `$env.VARIABLE_NAME` in n8n.

### Option 1: .env File (Persistent)

Create a `.env` file for default values:

```env
NAME=John
API_KEY=your-key-here
```

### Option 2: Command Line (Override)

Pass environment variables directly on the command line:

```bash
NAME=Alice make run-ci WORKFLOW_NAME=hello-workflow
```

This overrides any values in the `.env` file.

## Directory Structure

```
.
├── n8n-workflows/     # Workflow JSON files (version controlled)
├── .n8n/              # n8n database (git-ignored, regenerated from n8n-workflows/)
├── run-workflow.js    # CI/CD execution script
├── .env               # Environment variables (git-ignored)
├── .env.example       # Example environment file
├── Makefile           # Build and run commands
└── README.md          # This file
```

## Workflow Development Cycle

1. **Import** - `make import-workflows` - Load workflows from git into local database
2. **Edit** - `make start-server` - Open UI to edit workflows
3. **Export** - `make export-workflows` - Save changes back to git (with clean formatting)
4. **Commit** - `git add n8n-workflows/ && git commit`
5. **CI/CD** - Workflows run automatically in CloudBees from the `n8n-workflows/` directory

### Export Features

The `export-workflows` command automatically:
- Exports all workflows from the database
- Renames files to use workflow names (e.g., `hello-workflow.json`)
- Formats JSON with proper indentation (2 spaces)
- Sorts keys alphabetically for consistent git diffs
- Handles duplicate workflow names by appending the ID
