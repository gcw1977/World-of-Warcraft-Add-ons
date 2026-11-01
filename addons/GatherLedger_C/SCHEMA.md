# GatherLedger data contract (v0.4.6)

The reference catalog (`GatherLedgerCraftingItems` in `CraftingItems.lua`) only maps item IDs to material names. It never records ownership or drops.

`GatherLedgerDB.records` is an append-only list of actual skinning observations. Each record carries `items`, whose entries use `itemID`, `name`, `quantity`, and `classification`. Here `quantity` means actual item yield.

`GatherLedgerDB.shopping.goals[itemID]` stores `{itemID, name, quantity}`. Here `quantity` is the desired target, not the collected amount. This saved field stays unchanged for backward compatibility; source-code local variables are now named `requiredQuantity`.

`GatherLedgerDB.shopping.characters[realm:character].bags` and `.bank` each contain `{items = {[itemID]=count}, observedAt=timestamp}`; snapshots are latest observed only.

`GatherLedgerDB.shopping.learnedItems[itemID]` stores names discovered during play; distinct from catalog and historical gathering records.

Key invariants: shopping goals use `.quantity`, never `.needed`; UI row projections also use `.quantity`. No UI-only field is written into saved records. Saved root identifier remains `GatherLedgerDB`.


## v0.5.0
Historical skinning items store `observedQuantity`; shopping goals store `requiredQuantity`. Inventory snapshots store item counts by ID and location. The legacy saved field `quantity` is read only during automatic migration and then removed from migrated records. Back up WTF before installing.
