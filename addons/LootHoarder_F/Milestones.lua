-- Proposed milestone thresholds; default Silent pending owner style selection.
local addon = LootHoarderForever
local milestoneThresholds = { 100, 500, 1000, 5000, 10000 }
local messageTemplates = {
    Deadpan = "%s has reached %d looted units. Statistical enthusiasm remains optional.",
    Sassy = "%s: %d units. Your bags have filed a formal complaint.",
    Goblin = "%s: %d units! That's inventory, baby. Potentially profitable inventory.",
    Epic = "Behold! %s has reached %d looted units. Let the legends record it!",
    Unhinged = "%s: %d units! THE LOOT HAS DEVELOPED A PERSONALITY AND IT WANTS MORE."
}
local function GetCrossedMilestoneThresholds(previousTotal, newTotal)
    local crossedThresholds = {}
    for _, threshold in ipairs(milestoneThresholds) do
        if previousTotal < threshold and newTotal >= threshold then
            table.insert(crossedThresholds, threshold)
        end
    end
    local firstRecurringThreshold = math.floor(math.max(previousTotal, 10000) / 10000) * 10000 + 10000
    for threshold = firstRecurringThreshold, newTotal, 10000 do
        table.insert(crossedThresholds, threshold)
    end
    return crossedThresholds
end
function addon.EvaluateMilestones(statisticName, previousTotal, newTotal)
    if not addon.persistenceAvailable then return end
    local characterRecord = addon.characterRecord
    local currentMode = characterRecord.humorMode or "Silent"
    for _, threshold in ipairs(GetCrossedMilestoneThresholds(previousTotal, newTotal)) do
        local milestoneKey = statisticName .. ":" .. tostring(threshold)
        if not characterRecord.announcedMilestones[milestoneKey] then
            -- Mark before attempting chat; reload cannot replay milestones.
            characterRecord.announcedMilestones[milestoneKey] = true
            if currentMode ~= "Silent" and messageTemplates[currentMode] then
                addon.Print(string.format(messageTemplates[currentMode], statisticName, threshold))
            end
        end
    end
end
