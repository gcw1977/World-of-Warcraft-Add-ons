# Classic DEV-03 risk and API uncertainty register

- HIGH — No owner Classic client access. Interface 11509, PLAYER_MONEY/GetMoney, Quest event payload, ReloadUI hook, C_Timer.After, native frame texture API and GetServerTime must be checked in actual target. All FIELD_NOT_TESTED.
- HIGH — /reload versus logout detection relies on hooksecurefunc(ReloadUI); unsupported reload paths may split sessions. No false guarantee until owner tests.
- HIGH — SavedVariables are client-serialized, not crash-safe. Pending events on crash and addon-disabled changes are not recoverable; gap epochs disclose coverage.
- HIGH — Unbounded raw history can exceed practical SavedVariables/memory budgets. No auto deletion. Startup integrity and index rebuild O(N); field profile at 10k/100k needed.
- HIGH — Quest amount correlation can be ambiguous. Category CORRELATED only, otherwise Unclassified. Merchant proximity, repairs, trade, AH and mail not classified without proven event-specific evidence.
- MEDIUM — UI templates, FontStrings, texture methods and window position need Classic compatibility tests. UI errors isolated from observer.
- MEDIUM — Missing GUID defers observation to prevent wrong-character ledger attribution. Any changes before identity availability cannot be reconstructed.
- MEDIUM — A read-only safe-mode failure prevents new ledger writes; existing data preserved. Owner backup/recovery required.
- MEDIUM — Currency integer bound (<2^53) and server timestamps need target validation.
- LOW — No alias /gob to avoid slash collision; /goblinomicon is sole entry point.
