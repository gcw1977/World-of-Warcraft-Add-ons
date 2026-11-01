-- LootHoarder Forever 0.1.0-dev.3: shared constants and guarded diagnostics.
LootHoarderForever = LootHoarderForever or {}
local addon = LootHoarderForever
addon.version = "0.1.0-dev.3"
addon.schemaVersion = 1
addon.categoryNames = {
    "Food", "Beverages", "Alcoholic beverages", "Potions", "Elixirs/flasks",
    "Cloth", "Ore/stone", "Herbs", "Leather/hides", "Weapons", "Armor",
    "Recipes/patterns", "Gems", "Junk", "Other"
}
addon.humorModes = { "Deadpan", "Sassy", "Goblin", "Epic", "Unhinged", "Silent" }
addon.disclaimer = "Totals include only items acquired through ordinary looting of creatures and world containers. Items gathered through professions—including Skinning, Mining, and Herbalism—are NOT included."
addon.diagnosticCounts = {}
addon.runtime = { windowsSeen = 0, confirmedReceipts = 0, excludedWindows = 0, ambiguousReceipts = 0 }
function addon.RecordDiagnostic(diagnosticKey)
    local previousCount = addon.diagnosticCounts[diagnosticKey] or 0
    addon.diagnosticCounts[diagnosticKey] = previousCount + 1
end
function addon.Print(messageText)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffd8b35aLootHoarder Forever:|r " .. tostring(messageText))
    end
end
function addon.SafeCall(diagnosticKey, callbackFunction, ...)
    if type(callbackFunction) ~= "function" then
        addon.RecordDiagnostic(diagnosticKey .. "_unavailable")
        return false
    end
    local succeeded, firstResult, secondResult, thirdResult, fourthResult =
        pcall(callbackFunction, ...)
    if not succeeded then
        addon.RecordDiagnostic(diagnosticKey .. "_error")
        return false
    end
    return true, firstResult, secondResult, thirdResult, fourthResult
end
function addon.GetNow()
    if type(GetTime) == "function" then
        local succeeded, currentTime = pcall(GetTime)
        if succeeded and type(currentTime) == "number" then
            return currentTime
        end
    end
    return 0
end
