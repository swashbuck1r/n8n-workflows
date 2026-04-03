# n8n Workflow Runner for CloudBees

A CloudBees action that executes n8n workflows in your CI/CD pipelines.

> **Note:** This document refers to two types of workflows:
>
> - **n8n workflows** = Workflow automations created in n8n (the workflow engine)
> - **CloudBees workflows** = CI/CD pipeline definitions (YAML files in `.cloudbees/workflows/`)

## What This Provides

- **CloudBees Action** - Execute n8n workflows from your repository in CloudBees workflows (CI/CD pipelines)
- **Structured Outputs** - Access n8n workflow results as JSON in subsequent pipeline steps
- **Parameter Passing** - Send data to n8n workflows via JSON parameters
- **Optional Development Tools** - Makefile commands to develop and test n8n workflows locally (if you clone this repo)

## Using the Action

Add this action to your CloudBees workflow in three steps:

### 1. Add n8n Workflow Files to Your Repository

Export your n8n workflows as JSON files and add them to your repository in an `n8n-workflows/` directory (or any directory you prefer).

**How to export from n8n:**

- Use n8n's built-in export feature (Settings → Export)
- Or use the tools in this repo if you've cloned it (see [Local Development](#local-development-optional) below)

```bash
your-repo/
└── n8n-workflows/
    └── my-workflow.json
```

### 2. Configure Your n8n Workflow

n8n workflows must use a **manual trigger** and should extract environment variables using a **Set node**:

**Example workflow structure:**

```
Manual Trigger → Set Node (extract env vars) → Your Logic → Output Node
```

**Set Node Configuration:**
Extract environment variables as JSON fields:

- `NAME` from `{{ $env.NAME }}`
- `API_KEY` from `{{ $env.API_KEY }}`
- etc.

The **last node's output** becomes the action's result.

### 3. Use the Action in Your CloudBees Workflow

In your CloudBees workflow (CI/CD pipeline definition), add a step that uses this action:

```yaml
- name: Execute n8n workflow
  id: process
  uses: swashbuck1r/n8n-workflows@v1  # Reference this action repo
  with:
    workflows-dir: n8n-workflows         # Directory with your n8n workflows
    workflow-name: "hello-workflow".     # Name of your n8n workflow
    parameters: |
      {
        "NAME": "Alice"
      }

- name: Use the n8n workflow results
  run: |
    echo '${{ steps.process.outputs.result-json }}' | jq '.data'
```

The action will:

1. Import your n8n workflows from your repository's `n8n-workflows/` directory
2. Execute the specified n8n workflow with the provided parameters
3. Return the results as structured JSON outputs

See [ACTION.md](ACTION.md) for complete action documentation.

## Local Development (Optional)

If you clone this repository, you can use the included tools to develop and test n8n workflows locally.

### Start n8n Server

```bash
make start-server
```

Opens n8n UI at http://localhost:5678 to create/edit n8n workflows.

### Export n8n Workflows

```bash
make export-workflows
```

Saves n8n workflows from the database to `n8n-workflows/` directory for version control.

### Test Locally

```bash
make run-ci WORKFLOW_NAME=hello-workflow
```

Or with custom parameters:

```bash
NAME=Alice make run-ci WORKFLOW_NAME=hello-workflow
```

## n8n Workflow Requirements

Your n8n workflows must be configured correctly to work with this action.

### Manual Trigger Required

n8n workflows **must use a manual trigger**, not webhook triggers. This allows the action to execute them programmatically.

### Extracting Environment Variables

Use a **Set node** immediately after the manual trigger to extract environment variables passed via the `parameters` input:

**Set Node Configuration:**

1. Add field: `name` → Value: `{{ $env.NAME }}`
2. Add field: `api_key` → Value: `{{ $env.API_KEY }}`
3. Add additional fields as needed

These fields become available as JSON data for downstream nodes.

### Output Data

The **last node executed** in your workflow determines the action's output. The result is available as:

- `steps.<step-id>.outputs.result-json` - Full result data
- `steps.<step-id>.outputs.summary-json` - Execution summary
- `steps.<step-id>.outputs.execution-json` - Full execution details

## Example n8n Workflow

Here's a complete n8n workflow structure that:

1. Receives a `NAME` parameter
2. Processes it
3. Returns a greeting

**Workflow Structure:**

```
┌─────────────────┐
│ Manual Trigger  │
└────────┬────────┘
         │
┌────────▼────────┐
│  Set (Extract)  │  ← Extract $env.NAME to name field
└────────┬────────┘
         │
┌────────▼────────┐
│  Code (Process) │  ← Process: { message: "Hello", name: $json.name }
└────────┬────────┘
         │
    (Output) ← Last node output becomes action result
```

See `n8n-workflows/hello-workflow.json` for a working example.

## Advanced Usage

### Multiple Parameters

```yaml
parameters: |
  {
    "NAME": "Alice",
    "EMAIL": "alice@example.com",
    "ENVIRONMENT": "production",
    "DEBUG": "true"
  }
```

### Using Secrets

```yaml
parameters: |
  {
    "API_KEY": "${{ secrets.MY_API_KEY }}",
    "DATABASE_URL": "${{ secrets.DB_URL }}"
  }
```

### Conditional Execution

```yaml
- name: Run workflow
  if: ${{ inputs.environment == 'production' }}
  uses: your-org/your-repo@v1
  with:
    workflow-name: deploy-workflow
    parameters: '{"ENV":"${{ inputs.environment }}"}'
```

## CloudBees Integration Details

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
        uses: cloudbees-io/checkout@v2

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

## Troubleshooting

### n8n Workflow Not Found

If the action reports "Workflow not found":

1. Check that your n8n workflow JSON file exists in `n8n-workflows/` in **your repository**
2. Verify the `workflow-name` input matches the n8n workflow's `name` field in the JSON file
3. Check the action logs for the list of available n8n workflows

### Environment Variables Not Working

If `$env.VARIABLE` returns empty in your n8n workflow:

1. Verify the variable is in the `parameters` JSON in your CloudBees workflow step
2. Check the Set node in your n8n workflow is using `{{ $env.VARIABLE }}` syntax
3. Ensure `N8N_BLOCK_ENV_ACCESS_IN_NODE` is not set to `true`

### Output Not Showing

If the action completes but outputs are empty:

1. Ensure your n8n workflow has a manual trigger (not webhook)
2. Check the last node in your n8n workflow produces output
3. Review `execution-json` output for the full n8n workflow execution details

## Makefile Targets (Local Development)

- `make start-server` - Start n8n UI server (port 5678)
- `make stop-server` - Stop the server
- `make export-workflows` - Export workflows from database to `n8n-workflows/`
- `make import-workflows` - Import workflows from `n8n-workflows/` to database
- `make list-workflows` - List all workflows in the database
- `make run-ci WORKFLOW_NAME=<name>` - Execute workflow with structured output
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

## Repository Structure

### This Action Repository

This repository contains the action and optional development tools:

```
.
├── action.yml               # CloudBees action definition
├── run-workflow.js          # n8n workflow execution script
├── ACTION.md                # Action API reference
├── README.md                # This file
│
├── Makefile                 # Optional: local development commands
├── n8n-workflows/           # Optional: example n8n workflows
│   └── hello-workflow.json
│
└── .n8n/                    # Optional: local n8n database (git-ignored)
```

### Your Repository Structure

When using this action, your repository only needs the n8n workflow JSON files:

```
your-repo/
├── .cloudbees/
│   └── workflows/
│       └── pipeline.yaml        # Your CloudBees workflow (references this action)
│
└── n8n-workflows/               # Your n8n workflow JSON files
    ├── deploy.json
    └── process-data.json
```

The action automatically finds `run-workflow.js` and other dependencies from this repo when you reference it.

## Development Workflow (If Using Local Tools)

This workflow applies if you've cloned this repository to develop n8n workflows locally.

### Creating New n8n Workflows

1. **Start n8n Server**

   ```bash
   make start-server
   ```

2. **Create n8n Workflow** in UI at http://localhost:5678
   - Add a **Manual Trigger** node
   - Add a **Set** node to extract env vars (e.g., `name` from `{{ $env.NAME }}`)
   - Add your n8n workflow logic
   - Ensure the last node produces the output you want

3. **Export n8n Workflows**

   ```bash
   make export-workflows
   git add n8n-workflows/
   git commit -m "Add new n8n workflow"
   ```

4. **Test Locally**

   ```bash
   make run-ci WORKFLOW_NAME=your-workflow
   ```

5. **Use in CloudBees**
   ```bash
   git push
   # n8n workflow JSON files are now in your repo
   # Reference them in your CloudBees workflow using this action
   ```

### Export Features

The `export-workflows` command automatically:

- Exports all workflows from the database
- Renames files using workflow names (e.g., `hello-workflow.json`)
- Formats JSON with 2-space indentation
- Sorts keys alphabetically for clean git diffs
- Handles duplicate workflow names by appending the ID
