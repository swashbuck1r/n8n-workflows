#!/bin/bash
set -e

echo "=== CloudBees n8n Workflow Runner ==="
echo "Workflow: $WORKFLOW_NAME"
echo "Workflows dir: $WORKFLOWS_DIR"
echo ""

# Run the node script
exec /usr/local/bin/node /workspace/run-workflow.js
