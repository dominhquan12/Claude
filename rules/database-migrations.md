---
description: Liquibase migration rules — how to add/change entities and write manual changesets
---

## Golden Rule

**Never edit a committed changelog file.** Changelogs are immutable like git commits.

## Adding / Changing Entities (JDL Workflow)

1. Edit `jdl.jdl` — add/modify entity fields
2. Run `npx jhipster jdl jdl.jdl --force --skip-install`
3. JHipster generates new incremental changelog files (never modifies existing ones)
4. For new entities: manually add `<createSequence>` as the **first** changeset in the generated file (Hibernate requires a sequence)
5. Review `master.xml` — JHipster adds include lines automatically
6. Commit everything

## Manual Migrations

1. Create new file: `src/main/resources/config/liquibase/changelog/TIMESTAMP_description.xml`
2. Write the changeset (see `LIQUIBASE.md` for examples)
3. Add one line at the **end** of `master.xml`: `<include file="..."/>`

## Common Fixes

- **Checksum error (dev):** `docker compose -f src/main/docker/services.yml down -v && docker compose -f src/main/docker/services.yml up -d` — wipes and rebuilds the database
- **Checksum error (prod):** add `<validCheckSum>` with the old fingerprint to the changeset to accept the existing hash

See `LIQUIBASE.md` for the full migration guide with examples.
