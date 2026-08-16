---
description: Update entities in the Obsidian vault (tags, links, content)
argument-hint: <entity> "Note Name" <flags...>
allowed-tools: Bash, Read, Write, Edit
---

# Obsidian Update — /obsidian-update

## Guard (run first, early exit on failure)

```bash
VAULT="${OBSIDIAN_VAULT_PATH/#\~/$HOME}"
if [ -z "$OBSIDIAN_VAULT_PATH" ]; then echo "ERROR: OBSIDIAN_VAULT_PATH is not set."; exit 1; fi
if [ ! -d "${VAULT}/.obsidian" ]; then echo "ERROR: ${VAULT} is not a valid vault (no .obsidian/)."; exit 1; fi
```

### Resolve note (shared step)

Search by content + filename. Multiple matches → ask user. None → exit.

```bash
{ rg -i --fixed-strings "$NAME" "${VAULT}" --type md -l; \
  rg --files --glob "*${NAME}*.md" --glob-case-insensitive "${VAULT}"; } 2>/dev/null | sort -u | head -5
```

Read resolved file with `Read`.

## Entity: note (default)

| Flag | Action |
|---|---|
| `--add-tag t1,t2` | Append `[[t1]] [[t2]]` to line 1 (subject tag line). Create line 1 if missing. |
| `--remove-tag t1` | Remove `[[t1]]` and `#t1` from body text. Use `Edit`. |
| `--content "text"` | Replace body (everything after `====`). |
| `--append "text"` | Append to end of file (blank line separator). |
| `--move "path/"` | Move file, update backlinks (see below). Use `git mv` if in repo. |
| `--rename "Title"` | Update line 1 subject and heading. Rename file. Update backlinks. |

Use `Edit` for all modifications.

### Backlink maintenance (move/rename)

```bash
rg -l "\[\[${OLD}" "${VAULT}" --type md 2>/dev/null
rg -l ")(${OLD}" "${VAULT}" --type md 2>/dev/null
```

Ask confirmation before modifying other files. Use `Edit` to update references.

### Report

Show what was changed and which file(s) were modified.

## Index

See `${OBSIDIAN_VAULT_PATH}/CLAUDE.md` ("Vault MCP server" section) for further instructions on reindexing — note that `--move`/`--rename` need an explicit reindex (they change paths and graph edges).

## Entity: tag

Shortcut syntax — delegates to `note --add-tag` / `--remove-tag`.

```
/obsidian-update tag "Note" --add t1
/obsidian-update tag "Note" --remove t1
```

## Entity: link

```
/obsidian-update link "Source" --add-link "Target"
/obsidian-update link "Source" --remove-link "Target"
```

Resolve both notes. `--add-link`: check for existing `[[target]]`, append wiki link if absent. `--remove-link`: find and strip reference. Use `Edit`.
