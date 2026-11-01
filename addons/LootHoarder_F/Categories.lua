-- Category is based on the ITEM, never on how it was acquired.
-- Unknowns stay Other. Alcohol classification is intentionally unverified.
local addon = LootHoarderForever
local vettedAlcoholicItemIDs = {} -- Empty until owner-approved IDs are verified in Forever.
local vettedFoodItemIDs = {}
local vettedBeverageItemIDs = {}
function addon.ClassifyItem(itemIdentifier, itemLink)
    if type(itemIdentifier) ~= "number" then return "Other" end
    if vettedAlcoholicItemIDs[itemIdentifier] then return "Alcoholic beverages" end
    if vettedFoodItemIDs[itemIdentifier] then return "Food" end
    if vettedBeverageItemIDs[itemIdentifier] then return "Beverages" end
    if type(GetItemInfo) ~= "function" then
        addon.RecordDiagnostic("item_info_unavailable")
        return "Other"
    end
    local succeeded, itemName, resolvedLink, quality, itemLevel, minimumLevel,
        itemType, itemSubType, stackSize, equipLocation, iconPath, sellPrice,
        itemClassID, itemSubClassID = pcall(GetItemInfo, itemIdentifier)
    if not succeeded or not itemName then
        addon.RecordDiagnostic("item_info_uncached")
        return "Other"
    end
    if quality == 0 then return "Junk" end
    if itemClassID == 2 then return "Weapons" end
    if itemClassID == 4 then return "Armor" end
    if itemClassID == 3 then return "Gems" end
    if itemClassID == 9 then return "Recipes/patterns" end
    if itemClassID == 0 then
        if itemSubClassID == 1 then return "Potions" end
        if itemSubClassID == 2 or itemSubClassID == 3 then return "Elixirs/flasks" end
        -- Food/drink subtype cannot reliably distinguish alcohol, water, or food.
        return "Other"
    end
    if itemClassID == 7 then
        if itemSubClassID == 5 then return "Cloth" end
        if itemSubClassID == 6 then return "Leather/hides" end
        if itemSubClassID == 7 then return "Ore/stone" end
        if itemSubClassID == 9 then return "Herbs" end
    end
    return "Other"
end
