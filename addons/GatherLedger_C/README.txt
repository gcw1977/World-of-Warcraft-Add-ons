GatherLedger 0.4.6 — consistency audit
GatherLedger v0.4.0 — Classic Era testing build

UPGRADE
Drop this ZIP into your existing WoW Addon Inbox and install with WoW Manager.
The addon folder and SavedVariables key (GatherLedgerDB) are unchanged.
No historical data, inventory snapshots or shopping targets are reset.

WHAT IS NEW
- Bundled offline name/ID catalog of 166 curated crafting and gathering items
  across 9 material groups, in CraftingItems.lua.
- Shopping item suggestions work for cataloged reagents without first looting them.
- Numeric IDs and shift-click item links remain supported.
- Items encountered during gameplay may be learned for future autocomplete.
- Suggestions prefer names beginning with the typed text.
- Fixed-row shopping display introduced in v0.3.9 remains in use.

QUICK TEST
1. /gshop
2. Enter Heavy Leather by NAME and set a target.
3. Try typing Mithril, Dreamfoil, Strange Dust, Fine Thread.
4. Add or edit a quantity; confirm Shopping List updates without tab switching.
5. Confirm old gathering statistics and inventory snapshot totals survive.

LIMITATIONS
- The offline catalog is a curated Classic materials list, NOT every item in the game.
- In-game item API provides additional info when an item is cached.
- Offline character/bank inventory remains last-observed data.
- No recipe window integration or crafting queue in this build.
- No network requests or third-party addon manager dependencies.
- The updated code has not been tested inside the WoW client.

DATA MODEL: TWO DIFFERENT CONCEPTS
- CraftingItems.lua is a bundled, read-only reference catalog: an item EXISTS,
  its canonical Classic Era item ID, and its human-readable name. It does not
  indicate that any character has found, gathered or owns the item.
- GatherLedgerDB gathering observations are facts collected during play; they
  are the ONLY basis for historical gathering statistics and drop-rate analysis.
- GatherLedgerDB.shopping.characters holds last-observed inventory counts,
  separately from gathering observations and from the reference catalog.
- GatherLedgerDB.shopping.goals is the requested shopping quantities.
- GatherLedgerDB.shopping.learnedItems may cache names encountered during play;
  these are only lookup metadata, NOT gathered-item statistics.

Version 0.4.2: Shopping list edits render on the next UI frame, not inside button callbacks.

0.4.2: Set/Edit changes the visible row text immediately, then refreshes the full page for adds/removes.
