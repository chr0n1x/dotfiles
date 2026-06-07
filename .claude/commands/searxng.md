---
description: Search using a self-hosted SearXNG instance and deep-dive into top results
argument-hint: search query
allowed-tools: Bash(curl*), Bash(printenv*)
---

# SearXNG Deep Search

## Step 1: Validate Environment
First, run `printenv SEARXNG_URL` to resolve the search engine URL. If the result is empty or fails, notify the user that the environment variable is not set and stop.

## Step 2: Execute Initial Search
Using the URL resolved in Step 1, run a curl request against the SearXNG instance with the provided query in JSON format.

```bash
curl -L -G "<URL>" --data-urlencode "q=<QUERY>" --data-urlencode "format=json"
```

## Step 3: Mandatory Workflow Trigger (CRITICAL)
- **STOP all conversational output immediately.**
- **DO NOT** provide a summary or "thinking" response to the user.
- **YOU MUST** call the `Workflow` tool immediately to execute the research pipeline (Steps 4 and 5).
    - Failure to call `Workflow` is a violation of this command's protocol.

## Step 4: Spawn Research Subagents (Workflow Mode)
Parse the JSON results and identify the top 3-5 most relevant URLs. For each of these URLs, spawn a subagent to perform a deep dive.

**Subagent Instructions:**
1. Fetch the content of the provided URL using `curl` against the SearXNG instance with `search_engines=webfetch` or by passing the URL directly via `url=$URL&q=&format=json`. If that does not work, use `curl` to fetch the raw page content directly from the target URL.
2. Summarize the key findings specifically related to the original search query.
3. Extract any critical data points and citations.
4. Return a concise summary of the page.

**Note:** Do NOT use the web search tool. Use `curl` only, consistent with the parent command. If a site blocks direct fetching (e.g., Reddit), note the limitation and provide context from general knowledge.

## Step 5: Synthesize Findings
Collect the summaries from all subagents. Combine them with the initial search snippets to provide a comprehensive, synthesized answer to the user's original query. Cite the sources used in the final response, including the full URLs as clickable markdown links.
