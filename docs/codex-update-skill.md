# Codex-assisted Monika Updates

This document fixes the safety boundary for the bundled `monika-update` Codex
Skill. The Skill turns a request such as “Monikaを更新して” into the source
update procedure already defined by
[codex-installation.md](codex-installation.md), while adding deterministic
target resolution, rollback state, and self-update ordering.

## Target Identity

The default source is
`https://github.com/KijitoraFinch/Mitoujr_Alpha.git`, and the default moving
channel is `refs/heads/pre-alpha`. A moving ref is only a discovery input. The
Skill resolves it once to a full commit ID, prepares that exact commit, and
uses the commit ID in verification and the final report.

Explicit user source and revision values override the defaults. A target must
be a Git commit for this first Skill; archive digest updates remain available
through the general Installation Guide.

## Update State

Before mutation, the Skill records these values:

- selected opam switch;
- installed Monika executable path and `monika --version` output;
- current `monika_sugar` pin and its source target, when present;
- exact target source URL and commit ID;
- durable target checkout path.

These values are evidence and rollback inputs, not hidden mutable configuration.
The Skill does not write pipeline or command procedures into YAML or JSON.

## Durable Revision Sources

Each target commit is prepared in a revision-specific per-user data directory.
The installed opam pin must never point into a temporary directory, because
later opam operations need the source metadata and an update failure may require
the previous source.

An update does not modify or clean an existing checkout with local changes.
Older revision directories are not automatically deleted. Cleanup is a
separate user-authorized operation after confirming no active pin references
them.

## Effect Ordering

The update proceeds in this order:

1. resolve and record an exact target;
2. capture the current switch, executable, version, and pin;
3. prepare a clean, durable target checkout;
4. read the target revision's repository instructions;
5. complete target dependency, contract, build, test, golden, and distribution
   verification;
6. change the pin and explicitly reinstall `monika_sugar`;
7. execute the installed CLI verification;
8. replace `monika-report`;
9. replace `monika`;
10. replace `monika-update` last;
11. report evidence and require a new Codex thread for updated Skill discovery.

Target verification is read-only with respect to the current installation.
The package is changed before the Skills because a new Skill may depend on a
new CLI surface. The currently executing update Skill is replaced last because
its instructions are already loaded for the active thread.

## Failure and Rollback

A target verification failure leaves the installed package and Skills
unchanged. If package installation or installed-CLI verification fails, the
Skill restores and reinstalls the recorded previous pin when its source remains
available, then verifies the restored CLI.

Skill directories are staged on the destination filesystem and replaced as
whole directories with restorable backups. Copying new files over an existing
Skill is not sufficient because removed files could remain active. If any
Skill replacement fails, all three previous directories are restored.

The Skill reports a rollback only after the restored commands have executed.
It does not invent a recovery path when the previous source was not recorded or
is no longer available.

## Idempotency

Running the Skill again for the same commit revalidates observable installed
state. When the package identity, CLI checks, and all three Skill file sets are
already current, the update completes without reinstalling or replacing them.
This is an idempotent no-op, not a second update.
