---
description: Read, search, or list entities in the Obsidian vault
argument-hint: <entity> <search term or flags>
allowed-tools: Bash, Read
---

# Obsidian Read — /obsidian-read

## Guard (run first, early exit on failure)

```bash
VAULT="${OBSIDIAN_VAULT_PATH/#\~/$HOME}"
if [ -z "$OBSIDIAN_VAULT_PATH" ]; then echo "ERROR: OBSIDIAN_VAULT_PATH is not set."; exit 1; fi
if [ ! -d "${VAULT}/.obsidian" ]; then echo "ERROR: ${VAULT} is not a valid vault (no .obsidian/)."; exit 1; fi
```

## Entity: note (default)

```
/obsidian-read note "term"           # search content + filenames
/obsidian-read note --path "rel/"    # exact path
/obsidian-read note --all            # list all notes
/obsidian-read note --tag "tag"      # find by tag
```

- **`--path`**: `cat "${VAULT}/${ARGUMENTS}"` (or use Read tool). Exit if not found.
- **`--all`**: `find "${VAULT}" -type f \( -name "*.md" -o -name "*.qmd" \) | sed "s|^${VAULT}/||" | sort`
- **`--tag`**: search both `#tag` and `[tag]` formats:
  ```bash
  { rg -i -F "#${TAG}" "${VAULT}" --type md -l; rg -i -F "- ${TAG}" "${VAULT}" --type md -l; rg -i "tags:.*${TAG}" "${VAULT}" --type md -l; } 2>/dev/null | sort -u
  ```
- **Search term** (default): content + filename search, deduplicate, show vault-relative paths:
  ```bash
  { rg -i --fixed-strings "$TERM" "${VAULT}" --type md -l; rg --files --glob "*${TERM}*.md" --glob-case-insensitive "${VAULT}"; } 2>/dev/null | sort -u
  ```

Single match → display full content. Multiple → list paths, offer to read.

## Entity: tags

```
/obsidian-read tags                 # all unique tags with counts
/obsidian-read tags "tag-name"      # show occurrences
```

**All tags:** extract `#tag` (anywhere in body) and `[tag]` (line-start only, first 5 lines of each file to avoid help text):

```bash
{ rg -oh '#[\p{L}\p{N}_/-]+' "${VAULT}" --type md 2>/dev/null | sed 's/^#//'; \
  find "${VAULT}" -type f -name "*.md" -exec head -5 {} \; \
    | rg -oh '^\s*\[([A-Z][\w_-]*)\]' 2>/dev/null | sed 's/^[[:space:]]*\[\(.*\)\]/\1/'; } \
  | sort | uniq -c | sort -rn
```

**Specific tag:** show with context (exclude code blocks):

```bash
rg -i -n "#${TAG}" "${VAULT}" --type md -C 2 2>/dev/null | sed "s|${VAULT}/||"
```

## Entity: backlinks

```
/obsidian-read backlinks "note-name"
```

Resolve note filename, then search for incoming wiki and markdown links (mimics obsidian.nvim `find_backlinks`):

```bash
{ rg -i -n "\[\[${NAME}" "${VAULT}" --type md; \
  rg -i -n ")(${NAME}" "${VAULT}" --type md; } 2>/dev/null | sed "s|${VAULT}/||" | sort -t: -k1,1
```

## Entity: links

```
/obsidian-read links "note-name"
```

Resolve note, extract outgoing links:

```bash
rg -oh '\[\[[^]]+\]\]' "$NOTE_PATH" 2>/dev/null | sort -u
```
