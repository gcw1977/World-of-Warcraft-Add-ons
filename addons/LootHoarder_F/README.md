# LootHoarder Forever — 0.1.0-dev.3

Independent Forever-only development candidate. Source custody is in the dedicated construction branch, not the stable branch. No gameplay validation or release approval has occurred.

## User interface

`/lh` opens one lifetime category-total screen; `/lh mode <Deadpan|Sassy|Goblin|Epic|Unhinged|Silent>` changes optional milestone commentary. `/lh diagnostics` displays bounded event and uncertainty counts. The default commentary mode is Silent. Proposed milestones: 100, 500, 1,000, 5,000, 10,000, then every 10,000 per category and overall; owner selection pending.

## Evidence and known limitations

Counts require all of: a loot-window item offer, one positively matched dead target/mouseover source GUID, a localized self-loot chat receipt, and a matching read-only inventory count increase within eight seconds. Ordinary manual loot and native Auto Loot are observed passively; neither is controlled by this addon. Multiple ambiguous item slots, missing APIs, uncertain provenance and profession-gathering casts fail closed.

**Known critical gap:** world containers cannot yet be positively distinguished from gathering nodes with the verified evidence available. They are therefore not counted. The feature remains incomplete pending Forever owner-led field tests. Skinning can resemble corpse loot; gathering cast detection uses provisional spell IDs and requires field verification. Native Auto Loot event order may cause undercounting.

**Known classification gap:** alcoholic item allowlist is empty; ambiguous food/drink items are assigned to Other. Item-cache misses and unsupported class IDs also fall back to Other; the addon does not infer categories from item names. Quest rewards, crafting, vendors, mail and trade are never observed as eligible windows.

No money, inventory mutation, loot actions, account-wide analytics, session dashboard or BI Core dependency. SavedVariables are separate from Classic.

The Interface value 16001 and all Forever event/API assumptions require owner validation against the live client. This code is NOT_TESTED in Forever.
