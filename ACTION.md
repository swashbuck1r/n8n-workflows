# n8n Workflow Runner Action

A reusable CloudBees action for executing n8n workflows with JSON parameter support.

## Usage

```yaml
- name: Run n8n workflow
  uses: ./ # or path to this action
  with:
    workflow-name: my-workflow
    parameters: '{"NAME":"Alice","API_KEY":"secret123"}'
    workflows-dir: n8n-workflows
```

## Inputs

### `workflow-name` (required)
Name of the n8n workflow to execute. Must match a workflow name in your workflows directory.

**Example:** `hello-workflow`

### `parameters` (optional)
JSON string containing environment variables to pass to the workflow. These will be available in n8n nodes via `$env.VARIABLE_NAME`.

**Default:** `'{}'`

**Example:**
```yaml
parameters: '{"NAME":"Bob","EMAIL":"bob@example.com","DEBUG":"true"}'
```

In your n8n workflow, access these as:
- `$env.NAME` → "Bob"
- `$env.EMAIL` → "bob@example.com"
- `$env.DEBUG` → "true"

### `workflows-dir` (optional)
Directory containing n8n workflow JSON files, relative to the workspace root.

**Default:** `n8n-workflows`

## Outputs

### `result-json`
The workflow execution result data containing the output from the final node.

**Example:**
```json
{
  "success": true,
  "data": [
    {
      "json": {
        "message": "Hello world",
        "name": "Alice"
      }
    }
  ]
}
```

### `summary-json`
High-level execution summary with metadata.

**Example:**
```json
{
  "workflow": "hello-workflow",
  "success": true,
  "startedAt": "2026-04-03T02:00:00.000Z",
  "stoppedAt": "2026-04-03T02:00:01.000Z",
  "resultDataCount": 1
}
```

### `execution-json`
Full workflow execution details including all node outputs (useful for debugging).

## Complete Example

```yaml
apiVersion: automation.cloudbees.io/v1alpha1
kind: workflow
name: process-data

on:
  workflow_dispatch:
    inputs:
      customer_name:
        type: string
      customer_email:
        type: string

jobs:
  process:
    steps:
      - name: Checkout code
        uses: cloudbees-io/checkout@v1

      - name: Run data processing workflow
        id: process
        uses: ./
        with:
          workflow-name: process-customer-data
          parameters: |
            {
              "CUSTOMER_NAME": "${{ inputs.customer_name }}",
              "CUSTOMER_EMAIL": "${{ inputs.customer_email }}",
              "ENVIRONMENT": "production"
            }

      - name: Check result
        run: |
          echo "Processing complete!"
          echo '${{ steps.process.outputs.result-json }}' | jq '.data'
```

## Requirements

- `run-workflow.js` must exist in the workspace root
- `n8n-workflows/` directory must contain workflow JSON files
- Workflows should use manual triggers (not webhook triggers)

## Environment Variables in n8n

The parameters JSON is converted to environment variables that can be accessed in n8n nodes:

**Code Node Example:**
```javascript
const name = $env.NAME;
const apiKey = $env.API_KEY;

return {
  json: {
    greeting: `Hello ${name}!`,
    hasApiKey: !!apiKey
  }
};
```

**Set Node Example:**
Use expressions like `{{ $env.NAME }}` to access environment variables.

## Debugging

If the workflow fails, check the `execution-json` output:

```yaml
- name: Debug on failure
  if: failure()
  run: |
    echo "Full execution details:"
    echo '${{ steps.process.outputs.execution-json }}' | jq '.'
```

## Notes

- Workflow files are named using the workflow name (e.g., `hello-workflow.json`)
- Output files use hyphenated names for CloudBees compatibility (`result-json`, not `result.json`)
- The action automatically imports workflows before execution
- Sensitive parameters should be stored in CloudBees secrets
