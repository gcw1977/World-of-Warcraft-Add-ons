Litterbug Lite Classic v0.2.0-dev.1 — owner field-test candidate

Implements November 1 approved HUD architecture:
- Reserve normal inventory slots: 3–5 configurable; default 3.
- When free ordinary bag slots meet reserve, HUD auto-hides.
- With a shortage, shows cheapest eligible gray stacks, right aligned.
- If ordinary bags are full and no verified candidates exist, red warning.
- Excludes quivers, ammunition pouches, and other specialized bags.
- No DeleteCursorItem; drag a displayed slot with left mouse to pick up
  the underlying actual item, then drop it yourself through the game UI.
- Sort Trash sorts the displayed ranking by total stack vendor value and
  refreshes the inventory. It never physically rearranges your bags.
- Quest metadata must be readable and indicate the item is unprotected;
  if data is missing, a candidate is excluded rather than guessed.

Commands:
/lbl and /litterbug — toggle manual HUD inspection
/lbl show | hide | reset | diag

Preserves existing LitterbugLiteDB window position; adds reserveSlots.
Actual Classic UI drag/quest API availability must be field tested.
Backup the previous addon and SavedVariables before installing.
