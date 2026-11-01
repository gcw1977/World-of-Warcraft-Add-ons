local addonName, packMate = ...
packMate.Ledger = {}
local previousObservation

function packMate.Ledger.ResetBaseline()
    previousObservation = nil
end

function packMate.Ledger.Observe(identity, experience)
    if not identity or identity.availabilityState ~= "AVAILABLE" then
        previousObservation = nil
        return {calculationStatus = "NO_PET"}
    end
    if not experience or experience.availabilityState ~= "AVAILABLE" then
        previousObservation = nil
        return {calculationStatus = "EXPERIENCE_UNAVAILABLE"}
    end
    local current = {petGuid = identity.petGuid, petLevel = identity.petLevel,
        current = experience.current, required = experience.required}
    if not previousObservation or previousObservation.petGuid ~= current.petGuid then
        previousObservation = current
        return {calculationStatus = "SESSION_BASELINE"}
    end
    local previous = previousObservation
    previousObservation = current
    local gain
    local status
    local levelIncreased = current.petLevel > previous.petLevel
    if current.petLevel == previous.petLevel then
        if current.current < previous.current then
            return {calculationStatus = "DISCONTINUITY_REBASELINE"}
        end
        gain = current.current - previous.current
        status = gain > 0 and "SAME_LEVEL_GAIN" or "NO_CHANGE"
    elseif current.petLevel == previous.petLevel + 1 then
        if previous.required <= 0 or previous.current > previous.required then
            return {calculationStatus = "LEVEL_TRANSITION_INVALID", levelIncreased = true}
        end
        gain = previous.required - previous.current + current.current
        status = "SINGLE_LEVEL_GAIN"
    elseif current.petLevel > previous.petLevel + 1 then
        return {calculationStatus = "LEVEL_GAP", levelIncreased = true}
    else
        return {calculationStatus = "LEVEL_DECREASE_REBASELINE"}
    end
    if not gain or gain <= 0 then
        return {calculationStatus = status, levelIncreased = levelIncreased}
    end
    local committed, reason = packMate.Storage.AddObservedExperience(
        current.petGuid, identity.petName, current.petLevel, gain)
    if not committed then
        packMate.RecordDiagnostic("LEDGER", "WARN", reason)
    end
    return {calculationStatus = status, observedGain = gain,
        levelIncreased = levelIncreased, persisted = committed}
end
