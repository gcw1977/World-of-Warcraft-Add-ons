-- Goblinomicon Classic dev.7: event-backed financial provenance.
-- No money changes or transaction rows are created from context alone.
local addonName, addon = ...
local ledgerContext = {evidence = {}, active = {}, capacity = 128}
local function Clock()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    if ok and type(value) == "number" and value == value then return value end
    return nil
end
local function Capture(category, amount, confidence, kind)
    local now = Clock()
    if not now then return end
    local queue = ledgerContext.evidence
    queue[#queue + 1] = {category = category, amount = amount,
        confidence = confidence, kind = kind, at = now, consumed = false}
    while #queue > ledgerContext.capacity do table.remove(queue, 1) end
end
local function EscapePattern(value)
    return (string.gsub(value, "([^%w])", "%%%1"))
end
local function OwnLootLine(message)
    if type(message) ~= "string" then return false end
    local template = type(LOOT_MONEY) == "string" and LOOT_MONEY
    if not template then return false end
    local start = string.find(template, "%%s", 1, true)
    if not start then
        -- Literal find above is intentionally defensive; some clients
        -- localize the placeholder while retaining ordinary percent syntax.
        start = string.find(template, "%s", 1, true)
    end
    if not start then return false end
    local prefix = string.sub(template, 1, start - 1)
    local suffix = string.sub(template, start + 2)
    if string.sub(message, 1, #prefix) ~= prefix then return false end
    if suffix ~= "" and string.sub(message, -#suffix) ~= suffix then return false end
    return true
end
local function ExtractDenomination(message, localizedName, compactSuffix)
    local label = _G[localizedName]
    if type(label) ~= "string" or label == "" then
        label = compactSuffix == "g" and "Gold" or
            (compactSuffix == "s" and "Silver" or "Copper")
    end
    local amount = string.match(message, "(%d+)%s*" .. EscapePattern(label))
    if not amount then
        amount = string.match(message, "(%d+)%s*" .. compactSuffix .. "%f[^%a]")
    end
    return tonumber(amount) or 0
end
local function CoinAmount(message)
    if not OwnLootLine(message) then return nil end
    local gold = ExtractDenomination(message, "GOLD", "g")
    local silver = ExtractDenomination(message, "SILVER", "s")
    local copper = ExtractDenomination(message, "COPPER", "c")
    if silver > 99 or copper > 99 then return nil end
    local amount = gold * 10000 + silver * 100 + copper
    return amount > 0 and addon.IsCopper(amount) and amount or nil
end
local function SetWindow(key, opened)
    if opened then ledgerContext.active[key] = Clock()
    else ledgerContext.active[key] = nil end
end
local function ContextActive(key, at)
    local started = ledgerContext.active[key]
    return type(started) == "number" and type(at) == "number"
        and at >= started - 1 and at - started < 120
end
local function Resolve(candidate)
    local change = candidate.afterCopper - candidate.beforeCopper
    local when = candidate.observedAt or Clock()
    if not when then return nil end
    local matches = {}
    local lootContext
    for _, evidence in ipairs(ledgerContext.evidence) do
        if not evidence.consumed and math.abs(when - evidence.at) <= 2 then
            if evidence.amount == change then
                matches[#matches + 1] = evidence
            elseif evidence.kind == "LOOT_WINDOW" and change > 0 then
                lootContext = evidence
            end
        end
    end
    if #matches == 1 then
        -- A unique exact-amount event takes precedence over any open UI frame.
        matches[1].consumed = true
        return matches[1].category, matches[1].confidence
    elseif #matches > 1 then
        return nil
    end
    local options = {}
    local function Offer(key, positive, negative)
        if ContextActive(key, when) then
            options[#options + 1] = change > 0 and positive or negative
        end
    end
    Offer("MERCHANT", "Vendor Sale", "Vendor Purchase")
    Offer("TRAINER", nil, "Training")
    Offer("MAIL", "Mail Receipt", "Mail Expense")
    Offer("AUCTION", "Auction Receipt", "Auction Expense")
    Offer("TRADE", "Trade Receipt", "Trade Expense")
    Offer("TAXI", nil, "Flight Path")
    local category
    for _, option in ipairs(options) do
        if option then
            if category and category ~= option then return nil end
            category = option
        end
    end
    if category then return category, "CORRELATED" end
    if lootContext and #options == 0 then
        lootContext.consumed = true
        return "Coin Loot", "CORRELATED"
    end
    return nil
end
-- Wrap the append boundary so the observer remains the only financial writer.
-- The higher-confidence quest match performed in Observer.lua remains intact.
local originalAppendTransaction = addon.AppendTransaction
function addon.AppendTransaction(candidate, category, confidence)
    if category == "Unclassified Income" or category == "Unclassified Expense" then
        local derived, strength = Resolve(candidate)
        if derived then category, confidence = derived, strength end
    end
    return originalAppendTransaction(candidate, category, confidence)
end
local frame = CreateFrame("Frame")
local function Register(eventName)
    local ok = pcall(frame.RegisterEvent, frame, eventName)
    if not ok then addon.NoteError("UNAVAILABLE_CONTEXT_" .. eventName) end
end
local events = {
    "CHAT_MSG_MONEY", "LOOT_OPENED",
    "MERCHANT_SHOW", "MERCHANT_CLOSED",
    "TRAINER_SHOW", "TRAINER_CLOSED",
    "MAIL_SHOW", "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "TRADE_SHOW", "TRADE_CLOSED",
    "TAXIMAP_OPENED", "TAXIMAP_CLOSED"
}
for _, eventName in ipairs(events) do Register(eventName) end
frame:SetScript("OnEvent", function(_, eventName, ...)
    if eventName == "CHAT_MSG_MONEY" then
        local message = ...
        if OwnLootLine(message) then
            local amount = CoinAmount(message)
            if amount then
                Capture("Coin Loot", amount, "CONFIRMED", "MONEY_MESSAGE")
            else
                -- Explicit personal money-loot chat, but unsupported
                -- localized amount encoding: correlate context conservatively.
                Capture("Coin Loot", nil, "CORRELATED", "LOOT_WINDOW")
            end
        end
    elseif eventName == "LOOT_OPENED" then
        Capture("Coin Loot", nil, "CORRELATED", "LOOT_WINDOW")
    elseif eventName == "MERCHANT_SHOW" then SetWindow("MERCHANT", true)
    elseif eventName == "MERCHANT_CLOSED" then SetWindow("MERCHANT", false)
    elseif eventName == "TRAINER_SHOW" then SetWindow("TRAINER", true)
    elseif eventName == "TRAINER_CLOSED" then SetWindow("TRAINER", false)
    elseif eventName == "MAIL_SHOW" then SetWindow("MAIL", true)
    elseif eventName == "MAIL_CLOSED" then SetWindow("MAIL", false)
    elseif eventName == "AUCTION_HOUSE_SHOW" then SetWindow("AUCTION", true)
    elseif eventName == "AUCTION_HOUSE_CLOSED" then SetWindow("AUCTION", false)
    elseif eventName == "TRADE_SHOW" then SetWindow("TRADE", true)
    elseif eventName == "TRADE_CLOSED" then SetWindow("TRADE", false)
    elseif eventName == "TAXIMAP_OPENED" then SetWindow("TAXI", true)
    elseif eventName == "TAXIMAP_CLOSED" then SetWindow("TAXI", false)
    end
end)
