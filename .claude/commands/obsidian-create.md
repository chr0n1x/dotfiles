---
description: Create a new note in the Obsidian vault
argument-hint: note "Title" [--tags t1,t2] [--aliases a1,a2] [--dir path] [--content "text"]
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

Extract from `$ARGUMENTS`: `title` (required), `--tags`, `--aliases`, `--dir`, `--content`. Ask for title if missing.

### Check duplicates

```bash
rg -i --fixed-strings "$title" "${VAULT}" --type md -l 2>/dev/null | head -5
rg -i -F "id: ${title}" "${VAULT}" --type md -l 2>/dev/null
```

If matches found, show them and ask whether to proceed.

### Generate filename

```bash
FILENAME=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9一-鿿\-]//g')
FILEPATH="${VAULT}/${dir:-.}/${FILENAME}.md"
```

Append `-2`, `-3`, etc. if file already exists. `mkdir -p` the parent dir.

### Write file

Only include frontmatter blocks for fields that were provided. Omit empty `aliases`/`tags`.

```
---
id: <title>
aliases:
  - <a1>
tags:
  - <t1>
---

# <title>

<content>
```

Report vault-relative path and what was written.
