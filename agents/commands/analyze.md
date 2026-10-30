---
name: analyze
description: Map a codebase's structural shapes, data flows, translation
  layers, and knowledge ownership. Use when joining a new codebase, before
  a large refactor, or when asking "who owns what and where are the hot
  zones."
user-invocable: true
argument-hint: "optional target directory (default: pwd)"
---

# Analyze — /analyze

Architectural X-ray of a codebase. Two outputs:

1. **Structural map** — primary shapes, entry points, translation layers,
   data flow, and the entities everything orbits around.
2. **Knowledge map** — who owns what, cross-referenced with the structural
   map so you know who to ask about each hot zone.

## Step 1: Resolve target directory

If the user provided an argument in `$ARGUMENTS`, use it as the target
directory (must be inside the repo). Otherwise default to `$(pwd)`. Verify
it exists and is within the git working tree before proceeding.

```bash
TARGET_DIR="${ARGUMENTS:-$(pwd)}"
cd "$TARGET_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
```

## Step 2: Discover the language and framework

Identify the primary language(s) and framework(s) from dependency files,
config files, and directory layout. This determines what "entry point,"
"translation layer," and "primary entity" mean for the rest of the
analysis.

```bash
# Common dependency/config files
ls go.mod package.json Cargo.toml pyproject.toml Gemfile composer.json pom.xml build.gradle requirements.txt 2>/dev/null
# Framework hints (adapt to what dependency files reveal)
grep -rl "graphql\|gqlgen\|apollo\|grpc\|proto\|fastapi\|gin\|chi\|actix" --include="*.go" --include="*.ts" --include="*.py" --include="*.rs" --include="*.toml" . 2>/dev/null | head -5
```

## Step 3: Find entry points

Locate where external requests or commands enter the system. The patterns
vary by framework:

- **HTTP/REST**: router setup, route registration, handler files
- **GraphQL**: schema files, resolver registration, query/mutation definitions
- **gRPC**: `.proto` files, server registration
- **CLI**: command registration, `main()` / `argparse` / `cobra` / `clap`
- **Message queue / event**: consumer registration, topic subscriptions
- **Cron / scheduled**: task registration

```bash
# Entry point patterns (adapt to language/framework found in Step 2)
grep -rn "func main\|fn main\|def main\|if __name__\|@cli\|@command\
  \|router\|HandleFunc\|@app\." --include="*.go" --include="*.rs" \\
  --include="*.py" --include="*.ts" --include="*.js" . 2>/dev/null | head -20
# GraphQL specific
find . -name "*.graphql" -o -name "*.gql" -o -name "schema.*" -o -name "resolvers.*" 2>/dev/null | head -10
# gRPC specific
find . -name "*.proto" 2>/dev/null | head -10
```

When the primary language is supported by **ast-grep** (see the `ast-grep`
skill), combine it with text grep: grep finds candidate regions (call sites,
imports, string markers), ast-grep confirms the actual structure (function
signatures, handler registration shapes, class hierarchies). Use ast-grep when
the question is "what does this code *look like*", and rg when it is "where
does X appear".

## Step 4: Trace the primary data flow

Starting from the entry point(s), follow the request path through the
system. At each stage, note:

- The key type/struct/class that carries the data
- Where it transforms (DTO → domain model → DB row → response)
- The function/method that performs the transformation

This is the "happy path" — the main request type the application handles,
traced from external request to external response. Name the 5-10 types
that everything else orbits around.

Use `index` on the entry point files, then follow the imports/requires.
Do not read every file — follow the data, not the code.

## Step 5: Identify translation layers

Translation layers are boundaries where data changes shape or
representation:

- **API boundary**: request DTO → internal model (validation, parsing)
- **Domain boundary**: internal model → domain entity (business logic)
- **Storage boundary**: domain entity → DB row / cache entry (persistence)
- **Protocol boundary**: proto/GraphQL → internal struct (serialization)
- **Config boundary**: env vars / config file → typed config struct

For each layer, name the file(s) and the key types on each side. These
are the places where bugs hide (shape mismatches, missing fields, silent
drops).

## Step 6: Run git ownership queries

Run these from the target directory (or from `src/`/`app/` when possible,
to skip lockfiles and generated code):

### 6a. File churn hotspots

```bash
git log --format=format: --name-only --since="1 year ago" | sort | uniq -c | sort -nr | head -20
```

### 6b. Contributors by file (knowledge ownership)

For each of the top 10 files from 6a, find who has committed to it most:

```bash
git log --format=format: --name-only --since="1 year ago" \\
  | sort | uniq -c | sort -nr | head -10 | tail -n +2 \\
  | while read -r f; do
    echo "=== $f ==="
    git shortlog -sn --no-merges -- "$f" | head -3
  done
```

### 6c. Bug clusters

```bash
git log -i -E --grep="fix|bug|broken" --name-only --format='' \\
  | sort | uniq -c | sort -nr | head -20
```

### 6d. Bus factor

```bash
git shortlog -sn --no-merges
```

### 6e. Firefighting frequency

```bash
git log --oneline --since="1 year ago" | \\
  grep -iE 'revert|hotfix|emergency|rollb[ack]'
```

## Step 7: Present findings

### Structural Map

Present in this order:

1. **Language/framework** — one line
2. **Entry points** — where requests/commands enter, with file:line refs
3. **Primary data flow** — the happy path, naming key types at each stage
4. **Primary entities** — the 5-10 types everything orbits around
5. **Translation layers** — each boundary, the types on each side, file refs

### Knowledge Map

For each hot zone (file appearing in both churn 6a and bug clusters 6c):


- The file and what it does (one line)
- Who owns it (top contributor from 6b)
- Risk level: high (churn + bug + single owner), medium (churn or bug),
  low (neither)

Flag explicitly:
- Files with a single owner at 60%+ of commits AND no commits in 6+
  months (bus factor risk)
- Files appearing in both churn and bug lists (keep breaking, keep
  patched, never fixed)
- Sharp velocity declines (from 6d) or high firefighting frequency
  (from 6e)

### Who to Ask

A short list: "Ask X about Y" — the top 3-5 questions the codebase can't
answer on its own, matched to the person most likely to know the answer
based on their commit history.

Keep the presentation concise. No fluff, no restate-the-question preamble.
