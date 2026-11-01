# Beestwood Industries — Addon Versioning Standard
Effective 2026-11-01. This is the authoritative numbering policy for **all** BI addon construction missions.

## Client lineage
- Every existing Classic addon under `addons/*_C/` **keeps its historical version sequence**. Do not reset, normalize, renumber or infer any Classic versions.
- Every Forever addon under `addons/*_F/` is an **independent new product/codebase**, even where Classic code provides ideas or an implementation reference.
- The **first actually constructed and durably preserved Forever development candidate per addon** is `0.1.0-dev.1`, regardless of legacy Classic version or earlier unpublished/unretained prototype labels.
- Each new, distinct packaged candidate increments its prerelease sequence: `0.1.0-dev.2`, `0.1.0-dev.3`, etc. Never assign the same complete version to different package bytes.
- Later phases may use `0.1.0-beta.1`, `0.1.0-rc.1`, and approved product increments in MAJOR.MINOR.PATCH format. An unsuffixed `0.x.y` is **not automatically owner-approved stable**.
- `1.0.0` is reserved for the **first owner-approved stable milestone**. Only owner approval promotes a release or moves a stable tag.
- DEV-01 through DEV-06 are **workflow stage identifiers**, not package version components. An assessment/design report does not cause a software-version bump.
- Git commits preserve source lineage; stable tags must be addon-specific, for example `PackMate_F/v1.0.0`. Do not archive duplicate full source trees solely to maintain history.

## Mandatory pre-construction and publication checks
1. Read this file and the specific addon `README.md`/version ledger, then inspect all extant tags, package metadata, versions in source, and construction candidates on branches. Establish the latest real retained version before assigning the next value; do not assume a number from a work-order example.
2. Set a single version string in TOC metadata, source metadata, package filename, manifest, and deliverable references. Assert that those agree before a build can pass.
3. Never rewrite the numbers appearing in immutable historic reports, hashes, commits or archives. If earlier planned work orders specify a conflicting prototype number, use this policy for **future artifacts** and record a dated correction/addendum in the work order instead of altering history.
4. Construct on isolated development branches and make the entire candidate source durably fetchable from GitHub before declaring construction handoff complete; provide the commit SHA and branch. No agent may silently merge into main or tag a stable release.
5. Changes to version policy require explicit owner approval. All agents handling Forever addons must check this standard at mission start.

## Forever addon registrations
- `BICore_F`: first future candidate `0.1.0-dev.1`
- `BodyCount_F`: first future candidate `0.1.0-dev.1`
- `Completionist_F`: first future candidate `0.1.0-dev.1`
- `Goblinomicon_F`: first future candidate `0.1.0-dev.1`
- `Litterbug_F`: first future candidate `0.1.0-dev.1`
- `LootHoarder_F`: first future candidate `0.1.0-dev.1`
- `PackMate_F`: first retained candidate `0.1.0-dev.1`; historic lost prototype labelled `0.4.0-dev03.1` stays unchanged in original records
- `ResourceHog_F`: first future candidate `0.1.0-dev.1`

This is a **versioning declaration**, not a claim that any particular candidate code, ZIP, test, or release already exists.
