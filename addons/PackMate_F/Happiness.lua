local addonName, packMate = ...
packMate.Happiness = {}
local trackedPetGuid
local previousHappiness
local transitionTime
local consumedStages = {}
local reminderGraceSeconds = 10
local names = {[1] = "UNHAPPY", [2] = "CONTENT", [3] = "HAPPY"}

local function reset()
    trackedPetGuid = nil
    previousHappiness = nil
    transitionTime = nil
    consumedStages = {}
end

function packMate.Happiness.Reset()
    reset()
end

function packMate.Happiness.Reanchor(now)
    transitionTime = now
    consumedStages = {}
end

local function mode()
    return packMate.Storage.Settings().happinessAnnouncementMode
end

local function announceTransition(petName, happiness)
    if mode() == "mute" then return end
    if mode() == "stoic" then
        packMate.Chat(string.upper(petName) .. " STATUS CHANGED TO " .. names[happiness])
    elseif happiness == 2 then
        packMate.Chat(petName .. " is less than thrilled to be on this adventure. Perhaps a little snack is in order?", 3)
    elseif happiness == 1 then
        local uppercaseName = string.upper(petName)
        packMate.Chat(uppercaseName .. " IS APPALLED! " .. uppercaseName .. " DEMANDS MULTIPLE SNACKS...and maybe chin scritches.", 3)
    elseif happiness == 3 then
        packMate.Chat(petName .. " has forgiven you, you always give the BEST treats.")
    end
end

function packMate.Happiness.Evaluate(identity, happinessObservation, now)
    if not identity or identity.availabilityState ~= "AVAILABLE"
        or not happinessObservation or happinessObservation.availabilityState ~= "AVAILABLE"
        or not now then
        reset()
        return
    end
    local current = happinessObservation.value
    if trackedPetGuid ~= identity.petGuid or not previousHappiness then
        trackedPetGuid = identity.petGuid
        previousHappiness = current
        transitionTime = now
        consumedStages = {}
        return
    end
    if transitionTime and now < transitionTime then
        previousHappiness = current
        transitionTime = now
        consumedStages = {}
        return
    end
    if current ~= previousHappiness then
        previousHappiness = current
        transitionTime = now
        consumedStages = {}
        announceTransition(identity.petName, current)
        return
    end
    if mode() ~= "sassy" or current == 3 or not transitionTime then return end
    local elapsed = now - transitionTime
    local stages
    if current == 2 then
        stages = {{delay = 30, name = "CONTENT_30"}, {delay = 60, name = "CONTENT_60"}}
    else
        stages = {{delay = 60, name = "UNHAPPY_60"}, {delay = 180, name = "UNHAPPY_180"}}
    end
    for _, stage in ipairs(stages) do
        if not consumedStages[stage.name] and elapsed >= stage.delay then
            consumedStages[stage.name] = true
            if elapsed <= stage.delay + reminderGraceSeconds then
                if current == 2 then
                    packMate.Chat(identity.petName .. " is less than thrilled to be on this adventure. Perhaps a little snack is in order?", 3)
                elseif stage.name == "UNHAPPY_60" then
                    packMate.Chat(string.upper(identity.petName) .. " STOMPS FOOT PETULANTLY")
                else
                    packMate.Chat(identity.petName .. " is beginning to think you don't love and respect them anymore.")
                end
                return
            end
        end
    end
end

function packMate.Happiness.Name(happinessObservation)
    if happinessObservation and happinessObservation.availabilityState == "AVAILABLE" then
        return names[happinessObservation.value] or "UNKNOWN"
    end
    return "UNKNOWN"
end
