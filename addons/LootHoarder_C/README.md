# LootHoarder 0.1.3 — Classic Era test build

- Records offered loot when loot opens, independently of whether bags can accept it.
- Empty windows are recorded as zero-item outcomes; absent source identity is left unattributed.
- Recent source GUIDs (bounded to 600 per session) prevent repeat openings from inflating source/item observation totals. This is a best-effort session-level deduplication, not a permanent per-instance record.
- Excludes profession gathers using player spellcasts and `IsFishingLoot` when available; verify in game.
- `LOOT_SLOT_CLEARED` is tracked as a proxy for collection, not guaranteed bag-inventory confirmation.
- Opt-in skip filter for gray item stacks with total vendor price less than 1 silver; exempt quest items and missing item-price cache.

Commands:
- `/lh status`
- `/lh filter on`
- `/lh filter off`

**IMPORTANT:** To use selective auto-looting, turn Blizzard's built-in **Auto Loot OFF** in game Options, then `/lh filter on`. LH handles slot selection while the default loot window remains available for manual selection. With Blizzard auto-loot ON the filter cannot reliably prevent pickup and will warn once. Default behavior remains passive. Never enable two selective looters simultaneously.

API/runtime test needed on Classic Era, including empty corpses, full bags, repeated corpse opening, gather exclusion, gray threshold, quest loot, and auto-loot conflict. Lua ZIP package integrity alone is not an in-game test.
