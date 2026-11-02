-- Goblinomicon Forever: sole observer of the live character wallet.
local Addon = GoblinomiconForever
Addon.Wallet = {}
local Wallet = Addon.Wallet

function Wallet.Read()
    if type(GetMoney) ~= "function" then return nil, "GETMONEY_UNAVAILABLE" end
    local ok, copper = pcall(GetMoney)
    if not ok or not Addon.IsAccessible(copper) then return nil, "WALLET_INACCESSIBLE" end
    if not Addon.ValidCopper(copper) then return nil, "WALLET_INVALID" end
    return copper
end

-- UI and diagnostics never invoke this mutating observer.
function Wallet.Observe(trigger, isReconciliation)
    if not Addon.runtime.ready or Addon.runtime.captureStatus == "QUARANTINED" then
        return nil, "NOT_READY"
    end
    local character = Addon.Persistence.GetCurrentCharacter()
    if not character or not Addon.runtime.currentSessionId then
        return nil, "IDENTITY_UNAVAILABLE"
    end
    local copper, errorCode = Wallet.Read()
    if copper == nil then
        Addon.runtime.captureStatus = "SUSPENDED"
        Addon.runtime.needsReconciliation = true
        Addon.Note("WARN", "Wallet", errorCode)
        return nil, errorCode
    end
    local reconcile = isReconciliation == true or Addon.runtime.needsReconciliation == true
    local sequence, ledgerError = Addon.Ledger.Observe(character, copper, trigger, reconcile)
    if sequence == nil then
        Addon.runtime.captureStatus = "FAIL"
        Addon.Note("FAIL", "Ledger", ledgerError or "UNKNOWN_APPEND_FAILURE")
        return nil, ledgerError
    end
    Addon.runtime.needsReconciliation = false
    Addon.runtime.captureStatus = "CAPTURING"
    Addon.runtime.lastObservedCopper = copper
    Addon.runtime.lastObservedAt = Addon.Now()
    if Addon.UI and Addon.UI.RefreshIfVisible then Addon.UI.RefreshIfVisible() end
    return sequence
end
