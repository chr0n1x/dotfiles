# agents/tools/goflect - memory seed

`seed.json` is a `goflect/v1` memory export carrying the user's global
anchor memories: agent behavior rules (mutation gates, polling bans,
comment and answer style) and the goflect memory-system doctrine.
It is portable by design - no machine paths, no personal identity data.

## import

Requires goflect with Chroma reachable (managed container or `[chroma]`
server in the config); the file is only read through `goflect import`.

```sh
goflect import --dry-run seed.json   # reports added/unchanged, writes nothing
goflect import seed.json
```

Import keeps IDs, skips identical memories, and aborts unchanged if an ID
exists with different content - safe to re-run any time.
Vectors ship bundled (`embeddings` section), so a fresh store needs no
re-embedding pass as long as memory text stays byte-identical.

## what is deliberately absent

- memories scoped to directories or projects - those belong to their repos,
  not this seed;
- memories naming the user or their local files (git identity, tests-first);
- the memory citing host-local process topology - directory-scoped and it
  names machine ports; where an anchor cites that ID the citation dangles
  by design.

## regenerate

From the source machine, keep global anchors, drop identity-bearing ones:

```sh
goflect memory-export --output all.json --force
jq '[.memories[] | select(.anchor == true
  and ((.scope.directories // []) | length == 0)
  and ((.scope.projects // []) | length == 0)) | .id]' all.json > ids.json
jq --slurpfile ids ids.json '
  .memories = [.memories[] | select(.id as $i | $ids[0] | index($i))]
  | .directoryProjects = {}
  | .embeddings = [.embeddings[]?
      | .vectors |= with_entries(select(.key as $k | $ids[0] | index($k)))
      | select(.vectors != {})]' all.json > seed.json
```

Then resolve references: collect ID-shaped tokens from the kept bodies,
and add back every cited memory that is globally scoped and free of
identity data, carrying its vectors along - the anchors' fetch signals
should resolve inside the seed.

Then re-check seed.json for identity leaks - grep for the tokens the
excluded memories name: real name, email, usernames, hostnames, home
paths - and verify with `goflect import --dry-run seed.json`.
Exclusions by ID go in the `select` as `startswith("<id>") | not`.
Never hand-edit `seed.json`: edited text mismatches the bundled vector
digests and imports with stale, skipped vectors.
