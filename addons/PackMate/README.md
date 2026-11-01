# PackMate v0.1.0 — WoW Classic Era

Install by unzipping the `PackMate` directory into `Interface/AddOns/` (or through WoW Manager).

This is an **initial playable build**, not yet verified in-game. Independent from GatherLedger and the other Ledger addons.

## Commands
`/pm` toggle HUD; `/pm show`; `/pm hide`; `/pm status`

Pet XP uses `GetPetExperience()`, loyalty uses `GetPetLoyalty()`, and training points use `GetPetTrainingPoints()`. Only **unspent training points** are known automatically; available but unpurchased Pet Trainer abilities cannot be reliably inferred without inspecting the trainer interface. The addon reports this limitation rather than falsely claiming a skill is purchasable. The first observation of an existing pet is baseline, not a level-up.


## v0.2.1 Mini HUD

Move the translucent HUD by dragging its background. Resize it using the bottom-right grip, in the same style as GatherLedger's Shopping List HUD. Position and dimensions are saved independently in PackMateDatabase.

- `/pm show` show HUD
- `/pm hide` hide HUD
- `/pm` toggle HUD
- `/pm reset` restore default HUD position and size
- `/pm status` print pet summary

Tracks level, current XP, XP to next level, observed XP gain, loyalty, and unspent training points. Existing pet-level notices are retained. The training-point count is *not* a claim that specific trainable abilities are available.

## Rename from PetLedger

The addon is now **PackMate v0.2.1**. SavedVariables are stored in `PackMateDatabase` and the new addon folder is `PackMate`. To preserve existing data from `PetLedger`, run the accompanying `Migrate-Ledger-Names.ps1` script while WoW is fully closed, **before** starting the game with the new addons. The migration script creates a backup of each old file. The former short slash command remains an alias.


Version 0.2.3: Reports observed pet XP gains to chat by default, including level-up transitions. /pm xp on and /pm xp off control notifications. XP changes are observed after a qualifying kill, rather than independently attributed to an individual mob.
