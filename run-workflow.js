#!/usr/bin/env node

/**
 * n8n Workflow Runner for CloudBees Unify
 *
 * This script:
 * 1. Imports workflows from a directory (if provided)
 * 2. Finds and executes the specified workflow
 * 3. Captures execution results
 * 4. Saves results to CLOUDBEES_OUTPUTS directory (or specified output dir)
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Configuration from environment variables
const WORKFLOW_NAME = process.env.WORKFLOW_NAME || process.argv[2];
const WORKFLOWS_DIR = process.env.WORKFLOWS_DIR || '/workflows';
const OUTPUT_DIR = process.env.CLOUDBEES_OUTPUTS || process.env.OUTPUT_DIR || '/tmp/outputs';
const SKIP_IMPORT = process.env.SKIP_IMPORT === 'true';

function log(message) {
  console.log(`[n8n-runner] ${message}`);
}

function error(message) {
  console.error(`[n8n-runner] ERROR: ${message}`);
}

function exec(command, options = {}) {
  try {
    return execSync(command, {
      encoding: 'utf8',
      stdio: options.silent ? 'pipe' : 'inherit',
      ...options
    });
  } catch (err) {
    if (options.allowError) {
      return err.stdout || '';
    }
    throw err;
  }
}

function importWorkflows() {
  if (SKIP_IMPORT) {
    log('Skipping workflow import (SKIP_IMPORT=true)');
    return;
  }

  if (!fs.existsSync(WORKFLOWS_DIR)) {
    log(`Workflows directory not found: ${WORKFLOWS_DIR}`);
    log('Skipping import step');
    return;
  }

  const files = fs.readdirSync(WORKFLOWS_DIR).filter(f => f.endsWith('.json'));
  if (files.length === 0) {
    log('No workflow JSON files found to import');
    return;
  }

  log(`Importing workflows from ${WORKFLOWS_DIR}...`);
  try {
    exec(`n8n import:workflow --input=${WORKFLOWS_DIR} --separate`, { silent: true });
    log(`Workflows imported successfully (${files.length} files)`);
  } catch (err) {
    // Import might fail if workflows already exist, which is fine
    log('Import completed (workflows may have already existed)');
  }
}

function findWorkflowId(workflowName) {
  log(`Finding workflow: ${workflowName}`);

  const output = exec('n8n list:workflow', { silent: true, allowError: true });
  const lines = output.split('\n');

  for (const line of lines) {
    if (line.includes(workflowName)) {
      // Format: "ID|Name" or just "ID Name"
      const parts = line.trim().split(/[|\s]+/);
      if (parts.length > 0) {
        const id = parts[0];
        log(`Found workflow ID: ${id}`);
        return id;
      }
    }
  }

  error(`Workflow "${workflowName}" not found`);
  log('\nAvailable workflows:');
  console.log(output);
  process.exit(1);
}

function executeWorkflow(workflowId) {
  log(`Executing workflow ID: ${workflowId}`);

  try {
    const result = exec(`n8n execute --id=${workflowId} --rawOutput`, { silent: true });
    return result;
  } catch (err) {
    error(`Workflow execution failed: ${err.message}`);
    if (err.stdout) {
      error('Output:');
      console.error(err.stdout);
    }
    if (err.stderr) {
      error('Errors:');
      console.error(err.stderr);
    }
    process.exit(1);
  }
}

function parseExecutionResult(output) {
  // The output might contain extra logs before/after the JSON
  // Try to extract the JSON object by finding matching braces
  const lines = output.split('\n');
  let jsonLines = [];
  let braceCount = 0;
  let inJson = false;

  for (const line of lines) {
    const trimmed = line.trim();

    // Start capturing when we hit an opening brace at the start
    if (!inJson && trimmed.startsWith('{')) {
      inJson = true;
      braceCount = 0;
    }

    if (inJson) {
      jsonLines.push(line);

      // Count braces to know when the JSON object ends
      for (const char of line) {
        if (char === '{') braceCount++;
        if (char === '}') braceCount--;
      }

      // When braces are balanced, we've reached the end of JSON
      if (braceCount === 0) {
        break;
      }
    }
  }

  const jsonStr = jsonLines.join('\n');

  try {
    return JSON.parse(jsonStr);
  } catch (err) {
    error('Failed to parse execution result as JSON');
    log('Attempted to parse:');
    console.log(jsonStr);
    log('\nRaw output:');
    console.log(output);
    throw err;
  }
}

function extractResultData(execution) {
  // Extract the actual workflow output data
  // n8n execution format typically has data in execution.data.resultData
  const resultData = {
    success: execution.finished === true,
    workflowId: execution.workflowId,
    executionId: execution.id,
    startedAt: execution.startedAt,
    stoppedAt: execution.stoppedAt,
    data: []
  };

  // Extract output from the last node
  if (execution.data && execution.data.resultData && execution.data.resultData.runData) {
    const runData = execution.data.resultData.runData;
    const nodeNames = Object.keys(runData);

    // Get the last executed node's output
    if (nodeNames.length > 0) {
      const lastNode = nodeNames[nodeNames.length - 1];
      const nodeRuns = runData[lastNode];

      if (nodeRuns && nodeRuns.length > 0) {
        const lastRun = nodeRuns[nodeRuns.length - 1];
        if (lastRun.data && lastRun.data.main && lastRun.data.main.length > 0) {
          resultData.data = lastRun.data.main[0];
        }
      }
    }
  }

  return resultData;
}

function saveResults(execution, resultData) {
  // Create output directory if it doesn't exist
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  log(`Saving results to ${OUTPUT_DIR}`);

  // Save result data (the actual workflow output)
  const resultFile = path.join(OUTPUT_DIR, 'result.json');
  fs.writeFileSync(resultFile, JSON.stringify(resultData, null, 2));
  log(`Result data saved to: ${resultFile}`);

  // Save execution details (full execution info)
  const executionFile = path.join(OUTPUT_DIR, 'execution.json');
  fs.writeFileSync(executionFile, JSON.stringify(execution, null, 2));
  log(`Execution details saved to: ${executionFile}`);

  // Also save a summary file
  const summary = {
    workflow: WORKFLOW_NAME,
    workflowId: execution.workflowId,
    executionId: execution.id,
    success: execution.finished === true,
    startedAt: execution.startedAt,
    stoppedAt: execution.stoppedAt,
    mode: execution.mode,
    resultDataCount: resultData.data.length
  };

  const summaryFile = path.join(OUTPUT_DIR, 'summary.json');
  fs.writeFileSync(summaryFile, JSON.stringify(summary, null, 2));
  log(`Summary saved to: ${summaryFile}`);

  return summary;
}

function main() {
  if (!WORKFLOW_NAME) {
    error('WORKFLOW_NAME environment variable or argument is required');
    log('Usage: node run-workflow.js <workflow-name>');
    log('   or: WORKFLOW_NAME=<workflow-name> node run-workflow.js');
    process.exit(1);
  }

  log('Starting n8n workflow execution');
  log(`Workflow: ${WORKFLOW_NAME}`);
  log(`Output directory: ${OUTPUT_DIR}`);

  // Step 1: Import workflows
  importWorkflows();

  // Step 2: Find workflow ID
  const workflowId = findWorkflowId(WORKFLOW_NAME);

  // Step 3: Execute workflow
  const output = executeWorkflow(workflowId);

  // Step 4: Parse results
  const execution = parseExecutionResult(output);
  const resultData = extractResultData(execution);

  // Step 5: Save results
  const summary = saveResults(execution, resultData);

  // Step 6: Print summary
  log('\n=== Execution Summary ===');
  log(`Workflow: ${summary.workflow}`);
  log(`Execution ID: ${summary.executionId}`);
  log(`Success: ${summary.success}`);
  log(`Duration: ${new Date(summary.stoppedAt) - new Date(summary.startedAt)}ms`);
  log(`Result items: ${summary.resultDataCount}`);
  log('=========================\n');

  if (!summary.success) {
    error('Workflow execution was not successful');
    process.exit(1);
  }

  log('Workflow execution completed successfully');
}

// Run the script
main();
