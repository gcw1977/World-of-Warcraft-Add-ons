-- BodyCount 0.3.0 - Classic Era encounter accounting
-- Keeps legacy lifetime damage/kill totals and introduces separate session summaries.
local frame = CreateFrame("Frame")
local playerGUID, petGUID
local activeEncounters = {}
local pendingFinalization = {}
local previousUnitGUID = nil
local ENCOUNTER_IDLE_SECONDS = 25
local DEATH_CREDIT_GRACE_SECONDS = 2
local MILESTONES = {[10]=true,[100]=true,[500]=true,[1000]=true,[5000]=true,[10000]=true}
local function announce(message) DEFAULT_CHAT_FRAME:AddMessage("|cffff7777[BC]|r "..message) end
local function refreshActors()
    playerGUID = UnitGUID("player")
    petGUID = UnitExists("pet") and UnitGUID("pet") or nil
end
local function isCreatureGUID(guid)
    return type(guid)=="string" and (guid:find("^Creature%-") or guid:find("^Vehicle%-")) ~= nil
end
local function creatureKey(guid,name)
    local creatureID = guid and guid:match("^[^%-]+%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
    return (creatureID and "npc:"..creatureID) or ("name:"..(name or "Unknown")), creatureID
end
local function creatureRecord(guid,name)
    local key,id=creatureKey(guid,name)
    local record=BodyCountDatabase.creatures[key]
    if not record then
        record={name=name or "Unknown",creatureID=id,kills=0,damage=0,effectiveDamage=0,overkill=0,playerDamage=0,petDamage=0}
        BodyCountDatabase.creatures[key]=record
    end
    record.encounters=record.encounters or 0
    record.assists=record.assists or 0
    record.unknown=record.unknown or 0
    record.unfinished=record.unfinished or 0
    return record,key
end
local function newSession()
    return {encounters=0,kills=0,assists=0,unknown=0,unfinished=0,damage=0,playerDamage=0,petDamage=0,overkill=0,records={}}
end
local function initializeDatabase()
    BodyCountDatabase=BodyCountDatabase or {}
    local database=BodyCountDatabase
    database.creatures=database.creatures or {}
    database.kills=database.kills or 0
    database.damage=database.damage or 0
    database.overkill=database.overkill or 0
    database.lifetimeEncounters=database.lifetimeEncounters or 0
    database.lifetimeAssists=database.lifetimeAssists or 0
    database.lifetimeUnknown=database.lifetimeUnknown or 0
    database.lifetimeUnfinished=database.lifetimeUnfinished or 0
    -- One new login rotates sessions. UI reloads on the same character preserve current session.
    local characterKey=(UnitGUID("player") or UnitName("player") or "unknown")
    if database.sessionCharacter ~= characterKey then
        database.sessionCharacter=characterKey
        database.currentSession=newSession()
        database.lastSession=nil
    elseif not database.currentSession then
        database.currentSession=newSession()
    end
    database.currentSession.records=database.currentSession.records or {}
    database.preferences=database.preferences or {sort="kills",filter="all"}
end
local function createEncounter(guid,name)
    if not isCreatureGUID(guid) then return nil end
    local encounter=activeEncounters[guid]
    if not encounter then
        encounter={guid=guid,name=name or "Unknown",started=GetTime(),lastActivity=GetTime(),tag="unknown",damage=0,playerDamage=0,petDamage=0,effectiveDamage=0,overkill=0,dead=false,credited=false}
        activeEncounters[guid]=encounter
    end
    if name and name~="" then encounter.name=name end
    encounter.lastActivity=GetTime()
    return encounter
end
local function inspectTag(unit)
    if not UnitExists(unit) or UnitIsDead(unit) then return end
    local guid=UnitGUID(unit)
    local encounter=guid and activeEncounters[guid]
    if not encounter or encounter.credited then return end
    if type(UnitIsTapDenied)~="function" or type(UnitIsTapped)~="function" then return end
    local record=creatureRecord(guid,encounter.name)
    if type(UnitCreatureType)=="function" then
        local kind=UnitCreatureType(unit)
        if kind and kind~="" then record.creatureType=kind end
    end
    if not UnitIsTapped(unit) then return end
    if UnitIsTapDenied(unit) then
        -- Never replace an observed friendly tag with an inconsistent later sample.
        if encounter.tag~="ours" then encounter.tag="other" end
    else
        encounter.tag="ours"
    end
end
local function sampleVisibleTags()
    inspectTag("target")
    inspectTag("mouseover")
    if UnitExists("pet") then inspectTag("pettarget") end
    for index=1,40 do inspectTag("nameplate"..index) end
end
local function finalizeEncounter(guid, forcedOutcome)
    local encounter=activeEncounters[guid]
    if not encounter then return end
    activeEncounters[guid]=nil
    pendingFinalization[guid]=nil
    local outcome=forcedOutcome
    if not outcome then
        if encounter.credited then outcome="kill"
        elseif encounter.dead and encounter.tag=="other" then outcome="assist"
        elseif encounter.dead then outcome="unknown"
        else outcome="unfinished" end
    end
    local record=creatureRecord(guid,encounter.name)
    record.encounters=record.encounters+1
    local database=BodyCountDatabase
    local session=database.currentSession
    database.lifetimeEncounters=database.lifetimeEncounters+1
    session.encounters=session.encounters+1
    if outcome=="kill" then
        -- The existing PARTY_KILL handler already increments lifetime kill counts.
        session.kills=session.kills+1
    elseif outcome=="assist" then
        record.assists=record.assists+1
        database.lifetimeAssists=database.lifetimeAssists+1
        session.assists=session.assists+1
    elseif outcome=="unknown" then
        record.unknown=record.unknown+1
        database.lifetimeUnknown=database.lifetimeUnknown+1
        session.unknown=session.unknown+1
    else
        record.unfinished=record.unfinished+1
        database.lifetimeUnfinished=database.lifetimeUnfinished+1
        session.unfinished=session.unfinished+1
    end
    session.damage=session.damage+encounter.damage
    session.playerDamage=session.playerDamage+encounter.playerDamage
    session.petDamage=session.petDamage+encounter.petDamage
    session.overkill=session.overkill+encounter.overkill
    local summary={name=encounter.name,guid=guid,tag=encounter.tag,outcome=outcome,damage=encounter.damage,playerDamage=encounter.playerDamage,petDamage=encounter.petDamage,overkill=encounter.overkill,ended=time()}
    database.recentEncounter=summary
    local records=session.records
    table.insert(records,summary)
    -- A fixed-size rolling detail buffer. Session totals never roll off.
    if #records>500 then table.remove(records,1) end
    if BodyCountRefreshUI then BodyCountRefreshUI() end
end
local function combatLogEvent()
    local e={CombatLogGetCurrentEventInfo()}
    local event=e[2]
    local source=e[4]
    local guid=e[8]
    local name=e[9]
    if not isCreatureGUID(guid) then return end
    if event=="PARTY_KILL" then
        local encounter=activeEncounters[guid]
        if not encounter or encounter.credited then return end
        encounter.credited=true
        encounter.tag="ours"
        encounter.dead=true
        pendingFinalization[guid]=nil
        local record=creatureRecord(guid,name)
        record.kills=(record.kills or 0)+1
        BodyCountDatabase.kills=BodyCountDatabase.kills+1
        if MILESTONES[record.kills] then announce(string.format("%d %s slain. The numbers are becoming concerning.",record.kills,record.name)) end
        finalizeEncounter(guid,"kill")
        return
    end
    if event=="UNIT_DIED" or event=="UNIT_DESTROYED" then
        local encounter=activeEncounters[guid]
        if encounter then
            encounter.dead=true
            pendingFinalization[guid]=GetTime()+DEATH_CREDIT_GRACE_SECONDS
        end
        return
    end
    local ours=source==playerGUID
    local pet=petGUID and source==petGUID
    if not ours and not pet then return end
    local damage,overkill
    if event=="SWING_DAMAGE" then damage,overkill=e[12],e[13]
    elseif event=="SPELL_DAMAGE" or event=="SPELL_PERIODIC_DAMAGE" or event=="RANGE_DAMAGE" then damage,overkill=e[15],e[16]
    else return end
    damage=tonumber(damage)
    if not damage or damage<=0 then return end
    local encounter=createEncounter(guid,name)
    if not encounter then return end
    sampleVisibleTags()
    overkill=math.max(0,tonumber(overkill) or 0)
    local effective=math.max(0,damage-overkill)
    encounter.damage=encounter.damage+damage
    encounter.effectiveDamage=encounter.effectiveDamage+effective
    encounter.overkill=encounter.overkill+overkill
    if ours then encounter.playerDamage=encounter.playerDamage+damage else encounter.petDamage=encounter.petDamage+damage end
    local record=creatureRecord(guid,name)
    record.damage=(record.damage or 0)+damage
    record.effectiveDamage=(record.effectiveDamage or 0)+effective
    record.overkill=(record.overkill or 0)+overkill
    if ours then record.playerDamage=(record.playerDamage or 0)+damage else record.petDamage=(record.petDamage or 0)+damage end
    BodyCountDatabase.damage=BodyCountDatabase.damage+damage
    BodyCountDatabase.overkill=BodyCountDatabase.overkill+overkill
end
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent",function(_,event,argument)
    if event=="ADDON_LOADED" and argument=="BodyCount" then initializeDatabase()
    elseif event=="PLAYER_LOGIN" then
        refreshActors()
        -- Sessions rotate on logout/login; the previous session is retained.
        local database=BodyCountDatabase
        if database then
            local loggedOut=database.wasLoggedOut
            if loggedOut then
                database.lastSession=database.currentSession
                database.currentSession=newSession()
                database.wasLoggedOut=false
                database.recentEncounter=nil
            end
        end
    elseif event=="PLAYER_LOGOUT" then
        for guid in pairs(activeEncounters) do finalizeEncounter(guid,"unfinished") end
        if BodyCountDatabase then BodyCountDatabase.wasLoggedOut=true end
    elseif event=="PLAYER_ENTERING_WORLD" or (event=="UNIT_PET" and argument=="player") then refreshActors()
    elseif event=="PLAYER_TARGET_CHANGED" or event=="UPDATE_MOUSEOVER_UNIT" or event=="NAME_PLATE_UNIT_ADDED" then sampleVisibleTags()
    elseif event=="COMBAT_LOG_EVENT_UNFILTERED" and BodyCountDatabase then combatLogEvent() end
end)
local tick=0
frame:SetScript("OnUpdate",function(_,elapsed)
    tick=tick+elapsed
    if tick<0.5 or not BodyCountDatabase then return end
    tick=0
    local now=GetTime()
    sampleVisibleTags()
    local ready={}
    for guid,encounter in pairs(activeEncounters) do
        if pendingFinalization[guid] and now>=pendingFinalization[guid] then
            table.insert(ready,{guid=guid})
        elseif not encounter.dead and now-encounter.lastActivity>ENCOUNTER_IDLE_SECONDS then
            table.insert(ready,{guid=guid,outcome="unfinished"})
        end
    end
    for _,entry in ipairs(ready) do finalizeEncounter(entry.guid,entry.outcome) end
end)
SLASH_BODYCOUNT1="/bc"
SLASH_BODYCOUNT2="/killquota"
SlashCmdList.BODYCOUNT=function(command)
    if not BodyCountDatabase then return end
    if command=="status" then
        announce(string.format("Kills: %d | Lifetime encounters: %d | Damage: %d | Assists: %d",BodyCountDatabase.kills,BodyCountDatabase.lifetimeEncounters,BodyCountDatabase.damage,BodyCountDatabase.lifetimeAssists))
    elseif command=="help" then announce("/bc opens the encounter ledger; /bc status prints totals; /bc reset moves window to center.") end
end
