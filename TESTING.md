# Testing Guide

## Complete Workflow Cycle

### 1. Clean Start (Optional)
```bash
make clean
```

### 2. Import Workflows from Git
```bash
make import-workflows
```

This imports all JSON files from `n8n-workflows/` into the local database.

### 3. Test with Structured CI Output
```bash
make run-ci WORKFLOW_NAME=hello-workflow
```

### 4. View the Results
```bash
cat outputs/summary.json | jq '.'
cat outputs/result.json | jq '.data'
```

## Expected Output Structure

### outputs/summary.json
High-level execution metadata:
```json
{
  "workflow": "hello-workflow",
  "success": true,
  "startedAt": "2026-04-02T19:31:11.848Z",
  "stoppedAt": "2026-04-02T19:31:12.711Z",
  "mode": "cli",
  "resultDataCount": 1
}
```

### outputs/result.json
Workflow output data:
```json
{
  "success": true,
  "startedAt": "2026-04-02T19:31:11.848Z",
  "stoppedAt": "2026-04-02T19:31:12.711Z",
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

### outputs/execution.json
Full execution details (for debugging).

## Editing Workflows

### 1. Start the Server
```bash
make start-server
```

### 2. Edit in UI
Open http://localhost:5678 and create/edit workflows.

### 3. Export Changes
```bash
make export-workflows
```

### 4. Commit to Git
```bash
git add n8n-workflows/
git commit -m "Update workflows"
```

### 5. Stop the Server
```bash
make stop-server
```

## CloudBees Testing

1. Ensure `n8n-workflows/` directory is committed to git
2. Commit `run-workflow.js` script
3. Push to your repository
4. Trigger the workflow in CloudBees Unify
5. Check `$CLOUDBEES_OUTPUTS` for the result files

The CloudBees workflow will automatically:
- Import workflows from `n8n-workflows/`
- Execute the specified workflow
- Save results to `$CLOUDBEES_OUTPUTS`

## Environment Variables

The workflow can access environment variables via `$env.VARIABLE_NAME` in n8n:

### Using .env File

```bash
echo "NAME=Alice" > .env
make run-ci WORKFLOW_NAME=hello-workflow
```

### Passing on Command Line

```bash
NAME=Bob make run-ci WORKFLOW_NAME=hello-workflow
```

Command line values override `.env` file values.

### Multiple Variables

```bash
NAME=Charlie API_KEY=secret123 make run-ci WORKFLOW_NAME=hello-workflow
```

Note: Currently only `NAME` is automatically passed through. For other variables, add them to your `.env` file.

## Troubleshooting

### Workflow not found
```bash
make list-workflows
```

If workflows aren't showing up, import them:
```bash
make import-workflows
```

### Check workflow files
```bash
ls -lh n8n-workflows/
```

### Check execution logs
```bash
cat outputs/execution.json | jq '.data.resultData'
```

### Python warning
The "Failed to start Python task runner" warning is normal and can be ignored - it doesn't affect JavaScript-based workflows.

### Migration messages
Database migration messages during import are normal on first run.

## Quick Commands

```bash
# Full cycle test
make clean && make import-workflows && make run-ci WORKFLOW_NAME=hello-workflow

# View result
cat outputs/result.json | jq '.data[0].json'

# Edit, export, and test
make start-server
# ... edit in UI ...
make export-workflows
make stop-server
make run-ci WORKFLOW_NAME=my-workflow
```
