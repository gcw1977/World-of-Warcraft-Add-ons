# GatherLedger 0.6.14

- Added **Remove Reagents** beside **Add Reagents** in profession recipe importer.
- Both actions use the selected recipe and shared Crafts count.
- Removal subtracts requirements from Shopping List only, clamps at zero, and deletes zero-target items.
- Unresolvable reagents cancel the entire change; gathering statistics and inventory snapshots are untouched.
- Existing panel alignment settings are preserved.
