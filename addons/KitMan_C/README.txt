KitMan v0.1.0 (Classic Era)

This addon provides a small management window around Blizzard's native
C_EquipmentSet API. Saved sets work with Blizzard's /equipset macros.

GET STARTED
1. Equip the gear you want for combat.
2. /km -> leave Fighting in the name field -> Save New Set.
3. Equip your fishing rod and other fishing gear.
4. Change the name field to Fishing -> Save New Set.
5. Use the Equip buttons or /km equip Fighting and /km equip Fishing.

CHAT COMMANDS
/km or /kitman        Open the interface.
/km save NAME         Save currently equipped items as NAME. Prompts if it exists.
/km equip NAME        Equip a named set while outside combat.
/km list              Print existing set names to chat.
/km help              Show available commands.

NOTES
- Native equipment sets cannot be equipped in combat.
- Saving over an existing set requires confirmation.
- Deleting a set does not delete gear.
- Sets are managed by WoW, not duplicated in KitMan SavedVariables.
- Only the movable window position is stored in KitManDB.
- Unavailable equipped items may prevent a complete switch.
- Tested by static review only. Needs in-game confirmation.
