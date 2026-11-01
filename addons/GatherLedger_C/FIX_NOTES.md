# GatherLedger 0.4.8 — Shopping list display synchronization

- Starts from v0.4.7 migration release, not v0.4.3 experimental editing behavior.
- While the Shopping List tab is visible, checks a lightweight signature of item IDs, required quantities, and last-observed owned quantities every 0.10 seconds. Updates the existing four row controls only when that signature changes.
- Opening the tab triggers an immediate refresh.
- Add/Set/Remove still update saved goals immediately.
- Gathering statistics are not read by the Shopping List, and the saved schema is not modified.
- This is a targeted fix requiring in-game verification; no WoW runtime available here.
