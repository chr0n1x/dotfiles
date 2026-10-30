---
name: obsidian-create
description: Create a new note in the Obsidian vault
user-invocable: true
argument-hint: note "Title" [--tags t1,t2] [--dir path] [--content "text"]
allowed-tools: Bash, Read, Write, Edit
---

# Obsidian Create — /obsidian-create

## Guard (run first, early exit on failure)

```bash
VAULT="${OBSIDIAN_VAULT_PATH/#\~/$HOME}"
if [ -z "$OBSIDIAN_VAULT_PATH" ]; then echo "ERROR: OBSIDIAN_VAULT_PATH is not set."; exit 1; fi
if [ ! -d "${VAULT}/.obsidian" ]; then echo "ERROR: ${VAULT} is not a valid vault (no .obsidian/)."; exit 1; fi
```

## Entity: note (default)

Extract from `$ARGUMENTS`: `title` (required), `--tags`, `--dir`, `--content`. Ask for title if missing.

### Check duplicates

```bash
rg -i --fixed-strings "$title" "${VAULT}" --type md -l 2>/dev/null | head -5
```

If matches found, show them and ask whether to proceed.

### Generate filename

```bash
FILENAME=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9一-鿿\-]//g')
FILEPATH="${VAULT}/${dir:-.}/${FILENAME}.md"
```

Append `-2`, `-3`, etc. if file already exists. `mkdir -p` the parent dir.

### Write file

Format matches your vault convention: no frontmatter, subject on line 1 (this IS the primary tag), tags from `--tags` appended to line 1, then `====` underline and body.

```
<Subject> [[tag1]] [[tag2]] <optional intro sentence>.
====

<content>
```

Rules:
- Line 1: Title capitalized, followed by space-separated wiki-linked tags from `--tags` (if any), optional intro text
- Line 2: `====`
- Blank line, then body/content
- If no `--tags` and no content, just `<Subject>\n====\n\n`

Report vault-relative path and what was written.

## Index

See `${OBSIDIAN_VAULT_PATH}/CLAUDE.md` ("Vault MCP server" section) for further instructions on how the search index is kept current after writes.
