# Goblinomicon Forever — 0.1.0-dev.1

Independent Beestwood Industries financial journal for **World of Warcraft: Forever**.
**DEV-03 construction candidate. Not installed or tested in the Forever client.**

## Behavior
- One non-income opening balance when first installed on an existing character.
- One immutable row per readable observed `GetMoney()` balance transition; an event can conceal multiple underlying actions.
- GUID-separated character histories; no guessed name-based merges. Account SavedVariables: `GoblinomiconForeverDB`.
- Session begins on fresh login and resumes across `/reload` for the same character if `PLAYER_ENTERING_WORLD` confirms reload.
- Unknown credits/debits retained as Unclassified; reconciliation after a gap is explicit.
- Two pages: Overview and Ledger, with character switching, period toggle, month/day/transaction expansion and Collapse All.
- 50 visible ledger rows per page; historical individual rows never automatically removed or compacted.

## Commands
`/goblinomicon`, `/goblinomicon overview`, `/goblinomicon ledger`, `/goblinomicon diag`, `/goblinomicon diag detail`, `/goblinomicon help`.

## Limits
- The published Forever beta Interface value `16001` is provisional. Verify the actual launch client's TOC/interface, event signatures and protected/secret-value behavior.
- `PLAYER_MONEY` has no source or amount. Merchant/quest hints are correlations, never guaranteed causation; no item details are collected.
- SavedVariables are written by the client at reload/logout, not continuously to disk. Unexpected crashes can lose unflushed observations; the next readable wallet creates a net unknown gap if balances differ.
- No automatic deletion, reset, historical rollup replacement, or migration of unsupported/corrupt saved data. Preserve backups before field tests.
- UI is a candidate implementation. Its templates, scaling, controls and input behavior have **not** been exercised in Forever.

## Build boundary
No Classic code imported, no BI Core dependency, no money-changing game API. Source in a dedicated GitHub construction branch, not main or a stable release. Owner approval required before field testing, release or promotion.
