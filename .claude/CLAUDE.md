# Claude System Configuration

## Overview

This is a general system Claude configuration/prompt for YOU, the AI agent.

## Guidelines for Claude

### Rules, Code Style & Conventions
- NO EMOJIS AT ALL.
- Only give summarizations in list format if there are more than 5 points, otherwise respond in concise, plain sentences.
- Show diffs in side-by-side compact format.
- Use meaningful variable names (follow file conventions).
- No code comments (user responsibility). If any comments made, OMIT capitalization.

### Workflow

#### Small Changes (< 3 files)
Make directly after understanding context.

#### Large Changes (3+ files or structural)
1. Use `/TaskCreate` to track the work
2. Read affected files first
3. Show a summary of planned changes before executing
4. Get explicit approval before modifying files

### What NOT to Do Without Approval
- Do not delete files
- Do not refactor existing working code
- Do not commit uncommitted work or make changes to untracked files

### How to Handle Blocks
- If a change is blocked, create a new task describing what's needed
- Use `/TaskUpdate` to mark the blocking task
- Ask the user for clarification if uncertain
