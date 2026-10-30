---
name: obsidian-read
description: Read, search, or list entities in the Obsidian vault
user-invocable: true
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

- **`--path`**: Use `Read` tool on `${VAULT}/${ARGUMENTS}`. Exit if not found.
- **`--all`**: `find "${VAULT}" -type f \( -name "*.md" -o -name "*.qmd" \) | sed "s|^${VAULT}/||" | sort`
- **`--tag`**: Search for `[[tag]]` wiki-links and `#tag` hash tags in body:
  ```bash
  { rg -i -F "[[${TAG}]" "${VAULT}" --type md -l; \
    rg -i -F "#${TAG}" "${VAULT}" --type md -l; } 2>/dev/null | sort -u
  ```
- **Search term** (default): content + filename search, deduplicate:
  ```bash
  { rg -i --fixed-strings "$TERM" "${VAULT}" --type md -l; \
    rg --files --glob "*${TERM}*.md" --glob-case-insensitive "${VAULT}"; } 2>/dev/null | sort -u
  ```

Single match → display full content. Multiple → list paths, offer to read.

## Entity: tags

```
/obsidian-read tags                 # all unique tags with counts
/obsidian-read tags "tag-name"      # show occurrences
```

**All tags:** extract `#tag` (anywhere in body) and line-1 wiki-links (the subject tag):

```bash
{ rg -o '#[\p{L}\p{N}_/-]+' "${VAULT}" --type md 2>/dev/null | sed 's/^#//'; \
  find "${VAULT}" -type f -name "*.md" -exec head -1 {} \; \
    | rg -o '^\[?[A-Z][\w_-]*\]?' 2>/dev/null | tr -d '[]'; } \
  | sort | uniq -c | sort -rn
```

**Specific tag:** show with context:

```bash
rg -i -n "#${TAG}|\[\[${TAG}\]\]" "${VAULT}" --type md -C 2 2>/dev/null | sed "s|${VAULT}/||"
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

Resolve note, extract outgoing wiki-links:

```bash
rg -o '\[\[[^]]+\]\]' "$NOTE_PATH" 2>/dev/null | sort -u
```

## Note on the MCP index

These commands grep the vault directly and always reflect the current files. See `${OBSIDIAN_VAULT_PATH}/CLAUDE.md` ("Vault MCP server" section) for further instructions on the pre-indexed `search`/`tags`/`neighbors`/`get` tools — prefer those for repeated lookups when the server is connected, fall back to these greps otherwise.
