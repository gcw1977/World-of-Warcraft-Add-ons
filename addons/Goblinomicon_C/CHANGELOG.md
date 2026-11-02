## 2026-11-02 — 0.0.1-dev.9 — Classic UI and category drill-down
- Overview category rows now open a read-only Ledger filter for that category.
- Filtered Ledger includes all matching entries, paged newest first, with timestamp, amount, and running wallet.
- Clear Filter returns to all transactions. Time-period toggle retained for filtered view.
- Native Classic dialog border and standard buttons; hover feedback on transaction rows.
- Accounting, historical correction fields, and SavedVariables schema unchanged.
- Requires owner field-testing in Classic. Not a production release.

## 2026-11-02 — 0.0.1-dev.8 — Flight attribution fix
- Keep taxi destination selection evidence after taxi-map close (secure post-hook TakeTaxiNode).
- Observed wallet deduction remains authoritative; listed taxi fares are advisory.
- No retroactive change to existing SavedVariables. Client acceptance NOT_TESTED.

# Goblinomicon Classic — continuous development changelog

## 2026-11-01 22:20–22:30 CST — 0.0.1-dev.1, MeeSeeks, DEV-03 construction
- First preserved source and ZIP candidate; initial native frame compatibility not yet guarded.

## 2026-11-01 22:30 CST — 0.0.1-dev.2, MeeSeeks, DEV-03 construction
- Baseline: **GREENFIELD**, no Classic Goblinomicon_C source folder or retained version found on repository main and no matching construction branch at preflight. This Classic version was selected independently of Forever.
- Created Goblinomicon_C.toc, Data.lua, Observer.lua, UI.lua, Main.lua: GUID-partitioned append-only copper ledger, nonfinancial baseline/gap epochs, persistent login session with reload-hook continuation, conservative quest evidence and unclassified defaults, two-page native UI with paging and read-only diagnostics.
- Initial DEV-03 corrections: integrity verification now permits empty epochs; explicit startup gap amount; cached summaries with positive/negative category separation. Source changes are preserved in successive branch commits.
- Why: owner-approved Classic DEV-02 D1–D7 and subsequent four owner addenda, separate Classic/Forever lineages.
- Evidence: GitHub source commits and independent read-back; source/static and ZIP validation recorded in STATUS.md. No owner client available. FIELD_NOT_TESTED; no claim of production quality.
- Known risks: Classic interface 11509 reference not owner-verified, /reload hook behavior uncertain, very large ledger startup/index cost unmeasured, source attribution intentionally conservative.
- Candidate dev.1 preserved as prior ZIP and branch; dev.2 adds Classic texture fallback, monotonic clock fallback and stricter epoch validation.
- Status: DEVELOPMENT candidate, not TESTED/STABLE; no release, merge, tag or installation.
