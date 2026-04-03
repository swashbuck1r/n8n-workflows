# n8n Workflow Action Reference

Complete API reference for the n8n workflow runner action.

## Basic Usage

```yaml
- uses: your-org/your-repo@v1
  with:
    workflow-name: my-workflow
    parameters: '{"NAME":"value"}'
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow-name` | Yes | - | Name of the n8n workflow to execute (must match workflow's `name` field) |
| `parameters` | No | `'{}'` | JSON string of environment variables to pass to the workflow |
| `workflows-dir` | No | `n8n-workflows` | Directory containing workflow JSON files (relative to workspace root) |

### Parameters Format

The `parameters` input must be a valid JSON string. Each key becomes an environment variable in n8n:

```yaml
parameters: '{"KEY":"value","ANOTHER":"value2"}'
```

Access in n8n nodes using:
- `{{ $env.KEY }}` in expressions
- `$env.KEY` in Code nodes

## Outputs

| Output | Description |
|--------|-------------|
| `result-json` | Workflow output data from the last executed node |
| `summary-json` | Execution summary with metadata |
| `execution-json` | Full execution details (for debugging) |

### Output Formats

**result-json:**
```json
{
  "success": true,
  "startedAt": "2026-04-03T00:00:00.000Z",
  "stoppedAt": "2026-04-03T00:00:01.000Z",
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

**summary-json:**
```json
{
  "workflow": "my-workflow",
  "success": true,
  "startedAt": "2026-04-03T00:00:00.000Z",
  "stoppedAt": "2026-04-03T00:00:01.000Z",
  "resultDataCount": 1
}
```

## Complete Example

```yaml
jobs:
  process:
    steps:
      - uses: cloudbees-io/checkout@v2

      - name: Run workflow
        id: run
        uses: your-org/your-repo@v1
        with:
          workflow-name: process-data
          parameters: |
            {
              "INPUT_FILE": "data.csv",
              "OUTPUT_FORMAT": "json",
              "API_KEY": "${{ secrets.API_KEY }}"
            }

      - name: Check success
        run: |
          if [ "$(echo '${{ steps.run.outputs.summary-json }}' | jq -r '.success')" != "true" ]; then
            echo "Workflow failed"
            exit 1
          fi

      - name: Use results
        run: |
          echo '${{ steps.run.outputs.result-json }}' | jq '.data[0].json'
```

## Accessing Parameters in n8n

### Set Node

Use immediately after Manual Trigger to extract env vars:

**Field Assignments:**
- Name: `input_file` → Value: `{{ $env.INPUT_FILE }}`
- Name: `output_format` → Value: `{{ $env.OUTPUT_FORMAT }}`

### Code Node

```javascript
const inputFile = $env.INPUT_FILE;
const apiKey = $env.API_KEY;

return {
  json: {
    message: `Processing ${inputFile}`,
    hasApiKey: !!apiKey
  }
};
```

### HTTP Request Node

Use expressions in URL, headers, or body:
- URL: `https://api.example.com/{{ $env.RESOURCE }}`
- Header: `Authorization: Bearer {{ $env.API_KEY }}`

## Error Handling

The action exits with error code 1 if:
- Workflow file not found in `workflows-dir`
- Workflow execution fails
- Output files cannot be created

Check execution details on failure:

```yaml
- name: Debug on failure
  if: failure()
  run: |
    echo '${{ steps.run.outputs.execution-json }}' | jq '.'
```

## Requirements

1. **Manual Trigger**: Workflows must use `n8n-nodes-base.manualTrigger` (not webhook triggers)
2. **Workspace Checkout**: The action requires the workspace to be checked out first
3. **Workflow Files**: Must exist in `workflows-dir` with filename matching `<workflow-name>.json`

## Limitations

- Workflow must complete within CloudBees step timeout (default: 60 minutes)
- Output files limited to CloudBees output size limits
- Parameters passed as environment variables (string values only)
- No support for workflow credentials (use CloudBees secrets instead)
