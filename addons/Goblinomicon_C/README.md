# Goblinomicon — Classic Era

Beestwood Industries independent Classic Era financial journal. **Development candidate 0.0.1-dev.2; not owner field-tested, not released.** No dependency on BI Core or any Forever addon.

## Installation candidate layout

Place the **Goblinomicon_C** directory (containing Goblinomicon_C.toc, Data.lua, Observer.lua, UI.lua and Main.lua) in the Classic Era Interface/AddOns directory **only for isolated owner field testing with backed-up SavedVariables**. The TOC declares reference interface 11509; exact installed client interface must be checked. Never install over a known-good addon.

Commands: `/goblinomicon` (Overview), `/goblinomicon ledger`, `/goblinomicon diag`, `/goblinomicon help`.

## Financial contract

- First valid GetMoney observation is the opening wallet baseline, never income.
- Each distinct observed nonzero wallet change produces one signed copper record, after a short optional context window. Multiple unobserved underlying changes cannot be reconstructed.
- Unknown sources are **Unclassified Income** or **Unclassified Expense**; exact quest-reward correlation may label **Quest Reward** with CORRELATED confidence, never CONFIRMED without owner field proof.
- Ledger entries are never automatically deleted, rolled up or compacted. Each character is isolated by GUID; names and realms are display labels.
- A different wallet on restart opens a new nonfinancial coverage epoch with explicit gap amount, not fabricated income/expense.
- A session starts at character login and is intended to survive /reload. This uses an optional ReloadUI hook and **requires in-client verification**; unsupported reload paths may create a new session.
- Overview has lifetime/session totals, all active category totals, current character default and character cycling. Ledger has month/day hierarchy, Expand All/Month/Day, Collapse All and 20-row paging. Index and totals are derived, not authoritative.

## Limitations / integrity

WoW SavedVariables serialize at client-controlled reload/logout. A crash, corruption, disabled addon or missed event can lose history; the addon cannot guarantee indefinite storage independently of the client. Large-history index rebuild and startup verification are O(N) and need owner performance testing. Merchant, repairs, AH, trade and mail are conservatively **unclassified** until source-specific events have been proven in Classic. Unsupported/future saved schema triggers read-only safe mode without overwriting existing data.

No gameplay automation, direct money actions, account-wide combined totals, telemetry, data reset or destructive migration.

See FIELD_TESTS.md, RISKS.md and CHANGELOG.md for validation gates and provenance.
