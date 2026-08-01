---
description: Delete entities in the Obsidian vault (notes, tags, links)
argument-hint: <entity> "Note Name" [flags]
allowed-tools: Bash, Read
---

# Obsidian Delete — /obsidian-delete

## Guard (run first, early exit on failure)

```bash
VAULT="${OBSIDIAN_VAULT_PATH/#\~/$HOME}"
if [ -z "$OBSIDIAN_VAULT_PATH" ]; then echo "ERROR: OBSIDIAN_VAULT_PATH is not set."; exit 1; fi
if [ ! -d "${VAULT}/.obsidian" ]; then echo "ERROR: ${VAULT} is not a valid vault (no .obsidian/)."; exit 1; fi
```

## Entity: note (default)

```
/obsidian-delete note "Note Name" [--force]
```

1. **Resolve:** same search as `/obsidian-read note`. Multiple → disambiguate. None → exit.
2. **Show** first 20 lines for confirmation.
3. **Find backlinks** (warn — these become orphaned):
   ```bash
   { rg -n "\[\[${FILE}" "${VAULT}" --type md; rg -n ")(${FILE}" "${VAULT}" --type md; } 2>/dev/null | sed "s|${VAULT}/||"
   ```
   Without `--force`, ask for confirmation.
4. **Delete:** `git rm` if in repo, else `rm`. Clean up empty parent dirs (stop at vault root).
5. Report deletion and any orphaned backlinks.

## Entity: tag

```
/obsidian-delete tag "Note" --tag name
```

Delegates to `/obsidian-update tag --remove`. Resolve note, remove from frontmatter + body, report.

## Entity: link

```
/obsidian-delete link "Source" --target "Target"
```

Delegates to `/obsidian-update link --remove-link`. Resolve source, strip references, report.
