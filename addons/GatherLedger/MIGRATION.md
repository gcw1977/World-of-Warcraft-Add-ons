# GatherLedger 0.4.7 — additive migration

This is a one-time compatibility build. Keep your verified WTF backup.

- Gathering observations: `GatherLedgerDB.records[].items[].observedQuantity` is copied from legacy `quantity`. Gathering statistics read `observedQuantity`, with fallback to the legacy field during migration.
- Shopping goals: `GatherLedgerDB.shopping.goals[itemID].requiredQuantity` is copied from legacy `quantity`. Shopping calculations use the target field, and compare it **only** with inventory snapshots.
- Inventory: `GatherLedgerDB.shopping.characters` snapshots remain independent and unchanged. The stored map value is the most recently observed count per item, not a historical yield.
- Reference catalog: crafting-item names and IDs, not observations or inventory.

Both legacy quantity fields remain for one build, permitting rollback. After running the addon, log out normally to write SavedVariables, verify that both sections survive a reload, and take a verified backup. A later cleanup release can remove legacy reads and writes.
