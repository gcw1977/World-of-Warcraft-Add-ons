# Classic owner field-test checklist — 0.0.1-dev.2 (NOT_TESTED)

Before testing, back up any GoblinomiconClassicAccountData SavedVariables and use an isolated test character or copy. Record date/time, actual GetBuildInfo tuple, candidate commit/hash, initial copper, observed events, actual result and screenshots.

1. Fresh installation with nonzero wallet: opening baseline equals wallet; zero income and zero rows.
2. Gain copper in two separately observed PLAYER_MONEY changes: two signed records, increasing sequence and correct after-balances; duplicate unchanged PLAYER_MONEY makes no extra row.
3. Spend copper with no proven source: Unclassified Expense, exact signed amount and running balance.
4. Quest money reward: one observed credit; only if exact unique evidence within time window, Quest Reward / CORRELATED; no duplicate event transaction.
5. Vendor sale/purchase, repair, trainer, taxi, AH, mail, trade cancel/complete: only observed wallet deltas count; unproved sources remain unclassified, no invented items or fees.
6. /reload: same session ID and no duplicate baseline/row; logout/login: new session ID; character switch: separate GUID ledger. Check ReloadUI hook across UI reload paths.
7. Disable addon, change wallet, re-enable: new coverage epoch GAP, no fabricated adjustment transaction.
8. Corrupt/future-version copied SavedVariables: read-only safe mode, original preserved; never test on sole original.
9. /goblinomicon and ledger and diag: two pages, period switch, all categories, character cycling, month/day expansion, All/Month/Day, Collapse All, 20-row page controls and running balance invariant.
10. 10k and 100k synthetic transactions on isolated fixture: verify no truncation, O(N) startup/index costs and frame responsiveness; do not call performance PASS without measurements.
11. Verify window drag/reload placement, UI scale, readable +/- coin values, fallback when optional UI unavailable; observer continues when UI hidden.
12. Force journal failure in isolated fixture: error visible, pending transition not falsely reported as saved. Validate after restart.
13. Check no raw mail/chat/private names in saved ledger; no cross-client/other-addon changes.
14. Record exact Classic Era interface/API availability and any unsupported events; mark each FIELD_PASS/FAIL only from actual observed results.

Acceptance: all required checks documented and failures remediated before release. This file is a plan, not evidence of executed tests.
