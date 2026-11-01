local addonFrame = CreateFrame("Frame", "PackMateEventFrame")
local petDisplay = CreateFrame("Frame", "PackMateDisplay", UIParent, "BackdropTemplate")
petDisplay:SetSize(165, 49)
petDisplay:SetResizable(true)
-- Modern Classic clients replaced SetMinResize/SetMaxResize with SetResizeBounds.
if petDisplay.SetResizeBounds then
 petDisplay:SetResizeBounds(145, 48, 280, 90)
elseif petDisplay.SetMinResize and petDisplay.SetMaxResize then
 petDisplay:SetMinResize(145, 48)
 petDisplay:SetMaxResize(280, 90)
end
petDisplay:SetFrameStrata("MEDIUM")
petDisplay:SetPoint("CENTER", UIParent, "CENTER", 0, -155)
petDisplay:SetMovable(true)
petDisplay:EnableMouse(true)
petDisplay:RegisterForDrag("LeftButton")
petDisplay:SetClampedToScreen(true)
petDisplay:Hide()
petDisplay:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=14,insets={left=3,right=3,top=3,bottom=3}})
petDisplay:SetBackdropColor(0,0,0,0.35)
petDisplay:SetBackdropBorderColor(0.4,0.4,0.4,0.45)
petDisplay:SetScript("OnDragStart", function(self) self:StartMoving() end)
petDisplay:SetScript("OnDragStop", function(self)
 self:StopMovingOrSizing()
 local anchor, _, relativeAnchor, horizontalOffset, verticalOffset = self:GetPoint()
 PackMateDatabase.position = {anchor=anchor, relativeAnchor=relativeAnchor, x=horizontalOffset, y=verticalOffset}
end)
-- Grip matches GatherLedger's Shopping List HUD. Drag the background to move,
-- drag the lower-right corner to resize. Save dimensions on mouse release.
local resizeGrip = CreateFrame("Button", nil, petDisplay)
resizeGrip:SetSize(17, 17)
resizeGrip:SetPoint("BOTTOMRIGHT", petDisplay, "BOTTOMRIGHT", 0, 0)
resizeGrip:SetFrameLevel(petDisplay:GetFrameLevel() + 2)
local resizeIcon = resizeGrip:CreateTexture(nil, "OVERLAY")
resizeIcon:SetAllPoints()
resizeIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetNormalTexture(resizeIcon)
resizeGrip:SetScript("OnMouseDown", function(_, mouseButton)
 if mouseButton == "LeftButton" then petDisplay:StartSizing("BOTTOMRIGHT") end
end)
resizeGrip:SetScript("OnMouseUp", function(_, mouseButton)
 if mouseButton ~= "LeftButton" then return end
 petDisplay:StopMovingOrSizing()
 if PackMateDatabase then
  PackMateDatabase.size = {width=petDisplay:GetWidth(), height=petDisplay:GetHeight()}
 end
end)
-- Three compact text rows; no name or progress bar.
local experienceText = petDisplay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
experienceText:SetPoint("TOPLEFT", petDisplay, "TOPLEFT", 7, -6)
experienceText:SetJustifyH("LEFT")

local loyaltyText = petDisplay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
loyaltyText:SetPoint("TOPLEFT", experienceText, "BOTTOMLEFT", 0, -2)
loyaltyText:SetJustifyH("LEFT")

local trainingText = petDisplay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
trainingText:SetPoint("TOPLEFT", loyaltyText, "BOTTOMLEFT", 0, -2)
trainingText:SetJustifyH("LEFT")

local function announce(message)
 DEFAULT_CHAT_FRAME:AddMessage("|cff76c9ee[PM]|r "..message)
end
-- Happiness controls reuse the existing three HUD lines; no fourth indicator.
local happinessNames = {[1]="UNHAPPY", [2]="CONTENT", [3]="HAPPY"}
local happinessColors = {
 [1]={1.00,0.24,0.24}, [2]={1.00,0.88,0.15}, [3]={0.25,1.00,0.32}
}
local activeHappinessPetGUID = nil
local lastObservedHappiness = nil
local happinessChangedAt = nil
local deliveredReminderStages = {}

local function resetHappinessTracking()
 activeHappinessPetGUID = nil
 lastObservedHappiness = nil
 happinessChangedAt = nil
 deliveredReminderStages = {}
end

local function showHappinessMessage(message, repeatCount)
 if not PackMateDatabase or PackMateDatabase.happinessMode == "mute" then return end
 for messageIndex=1,(repeatCount or 1) do announce(message) end
end

local function announceHappinessChange(petName, happiness)
 if PackMateDatabase.happinessMode == "mute" then return end
 if PackMateDatabase.happinessMode == "stoic" then
  showHappinessMessage(string.format("%s STATUS CHANGED TO %s", petName:upper(), happinessNames[happiness]))
 elseif happiness == 2 then
  showHappinessMessage(petName .. " is less than thrilled to be on this adventure. Perhaps a little snack is in order?", 3)
 elseif happiness == 1 then
  showHappinessMessage(petName:upper() .. " IS APPALLED! " .. petName:upper() .. " DEMANDS MULTIPLE SNACKS...and maybe chin scritches.", 3)
 elseif happiness == 3 then
  showHappinessMessage(petName .. " has forgiven you, you always give the BEST treats.")
 end
end

local function updateHappiness(petGUID, petName)
 if not petGUID then
  resetHappinessTracking()
  return
 end
 local happiness = nil
 if type(GetPetHappiness) == "function" then
  happiness = GetPetHappiness()
 elseif C_PetInfo and type(C_PetInfo.GetPetHappiness) == "function" then
  happiness = C_PetInfo.GetPetHappiness()
 end
 happiness = tonumber(happiness)
 local happinessColor = happinessColors[happiness]
 if happinessColor then
  experienceText:SetTextColor(unpack(happinessColor))
  loyaltyText:SetTextColor(unpack(happinessColor))
  trainingText:SetTextColor(unpack(happinessColor))
 else
  experienceText:SetTextColor(1,1,1)
  loyaltyText:SetTextColor(1,1,1)
  trainingText:SetTextColor(1,1,1)
 end
 if not happinessNames[happiness] then
  resetHappinessTracking()
  return
 end
 if activeHappinessPetGUID ~= petGUID then
  -- First observation establishes the baseline. Never invent an earlier mood change.
  activeHappinessPetGUID = petGUID
  lastObservedHappiness = happiness
  happinessChangedAt = GetTime()
  deliveredReminderStages = {}
  return
 end
 if happiness ~= lastObservedHappiness then
  lastObservedHappiness = happiness
  happinessChangedAt = GetTime()
  deliveredReminderStages = {}
  announceHappinessChange(petName, happiness)
  return
 end
 if PackMateDatabase.happinessMode ~= "sassy" or not happinessChangedAt then return end
 local secondsSinceChange = GetTime() - happinessChangedAt
 if happiness == 2 then
  for reminderStage, reminderSeconds in ipairs({30,60}) do
   if secondsSinceChange >= reminderSeconds and not deliveredReminderStages[reminderStage] then
    deliveredReminderStages[reminderStage] = true
    showHappinessMessage(petName .. " is less than thrilled to be on this adventure. Perhaps a little snack is in order?", 3)
   end
  end
 elseif happiness == 1 then
  if secondsSinceChange >= 60 and not deliveredReminderStages[1] then
   deliveredReminderStages[1] = true
   showHappinessMessage(petName:upper() .. " STOMPS FOOT PETULANTLY")
  end
  if secondsSinceChange >= 180 and not deliveredReminderStages[2] then
   deliveredReminderStages[2] = true
   showHappinessMessage(petName .. " is beginning to think you don't love and respect them anymore.")
  end
 end
end

local function currentPetIdentity()
 if not UnitExists("pet") or not UnitIsUnit("pet","pet") then return nil end
 local guid=UnitGUID("pet")
 if not guid then return nil end
 return guid, UnitName("pet") or "Pet", UnitLevel("pet") or 0
end
local function updatePetInformation()
 local petGUID, petName, petLevel=currentPetIdentity()
 if not petGUID then petDisplay:Hide(); updateHappiness(nil, nil); return end
 if not PackMateDatabase then return end
 local petRecord=PackMateDatabase.pets[petGUID] or {name=petName, level=petLevel, totalObservedExperience=0}
 local currentExperience, requiredExperience=GetPetExperience()
 currentExperience=tonumber(currentExperience) or 0
 requiredExperience=tonumber(requiredExperience) or 0
 local oldLevel=petRecord.level
 -- Pet XP changes usually occur immediately after a qualifying kill. We report
 -- observed pet-XP changes, not an inferred XP value from the player's XP chat.
 -- Treat the first observation of a pet as a baseline, not a new kill.
 local experienceGained = 0
 if petRecord.lastExperience ~= nil and oldLevel ~= nil then
  if petLevel == oldLevel and currentExperience > petRecord.lastExperience then
   experienceGained = currentExperience - petRecord.lastExperience
  elseif petLevel == oldLevel + 1 and petRecord.lastRequiredExperience and petRecord.lastRequiredExperience > 0 then
   experienceGained = math.max(0, petRecord.lastRequiredExperience - petRecord.lastExperience) + currentExperience
  end
 end
 if experienceGained > 0 and PackMateDatabase.announceExperience ~= false and PackMateDatabase.happinessMode ~= "mute" then
  announce(string.format("%s received %d XP, current: %d/%d", petName, experienceGained, currentExperience, requiredExperience))
 end
 if oldLevel and petLevel > oldLevel then
   if PackMateDatabase.happinessMode ~= "mute" then announce(string.format("%s reached level %d!",petName,petLevel)) end
   if petRecord.lastRequiredExperience and petRecord.lastExperience and petLevel == oldLevel+1 then
     petRecord.totalObservedExperience=(petRecord.totalObservedExperience or 0)+math.max(0,petRecord.lastRequiredExperience-petRecord.lastExperience)+currentExperience
   end
 end
 if petRecord.lastExperience and petRecord.level == petLevel and currentExperience > petRecord.lastExperience then
   petRecord.totalObservedExperience=(petRecord.totalObservedExperience or 0)+(currentExperience-petRecord.lastExperience)
 end
 petRecord.level=petLevel; petRecord.name=petName; petRecord.lastExperience=currentExperience; petRecord.lastRequiredExperience=requiredExperience
 local loyalty=type(GetPetLoyalty)=="function" and GetPetLoyalty() or nil
 local totalTrainingPoints, spentTrainingPoints=0,0
 if type(GetPetTrainingPoints)=="function" then totalTrainingPoints,spentTrainingPoints=GetPetTrainingPoints() end
 totalTrainingPoints=tonumber(totalTrainingPoints) or 0
 spentTrainingPoints=tonumber(spentTrainingPoints) or 0
 local freeTrainingPoints=math.max(0,totalTrainingPoints-spentTrainingPoints)
 petRecord.loyalty=loyalty; petRecord.availableTrainingPoints=freeTrainingPoints
 PackMateDatabase.pets[petGUID]=petRecord
 if oldLevel and petLevel > oldLevel and freeTrainingPoints > 0 and PackMateDatabase.happinessMode ~= "mute" then
  announce(string.format("%s has %d unused training points. Check Beast Training for skills you can teach.",petName,freeTrainingPoints))
 end
 if requiredExperience > 0 then
  experienceText:SetText(string.format("XP: %d/%d - %.1f%%", currentExperience, requiredExperience, currentExperience * 100 / requiredExperience))
 else
  experienceText:SetText("XP: unavailable")
 end
 loyaltyText:SetText("Loyalty: " .. tostring(loyalty or "N/A"))
 trainingText:SetText(string.format("Unused TP: %d", freeTrainingPoints))
 updateHappiness(petGUID, petName)
 if PackMateDatabase.visible ~= false then petDisplay:Show() end
end
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
addonFrame:RegisterEvent("UNIT_PET")
addonFrame:RegisterEvent("UNIT_LEVEL")
pcall(addonFrame.RegisterEvent, addonFrame, "UNIT_PET_EXPERIENCE")
pcall(addonFrame.RegisterEvent, addonFrame, "PET_BAR_UPDATE")
pcall(addonFrame.RegisterEvent, addonFrame, "PET_TALENT_UPDATE")
-- PET_HAPPINESS_UPDATE was removed from some Classic builds. The existing
-- one-second OnUpdate polling handles mood changes without this event.
-- Do not register PET_HAPPINESS_UPDATE: it aborts the entire addon at startup.
addonFrame:SetScript("OnEvent",function(self,event,argument)
 if event=="ADDON_LOADED" then
  if argument~="PackMate" then return end
  PackMateDatabase=PackMateDatabase or {pets={},visible=true}
  PackMateDatabase.pets=PackMateDatabase.pets or {}
  if PackMateDatabase.announceExperience == nil then PackMateDatabase.announceExperience = true end
  if PackMateDatabase.happinessMode ~= "sassy" and PackMateDatabase.happinessMode ~= "stoic" and PackMateDatabase.happinessMode ~= "mute" then PackMateDatabase.happinessMode = "sassy" end
  -- Migrate old, oversized HUD settings to the compact layout once.
  if PackMateDatabase.hudLayoutVersion ~= 4 then
   PackMateDatabase.size={width=165,height=49}
   PackMateDatabase.hudLayoutVersion=4
  end
  if PackMateDatabase.size then
   petDisplay:SetSize(math.max(145,math.min(280,PackMateDatabase.size.width or 165)), math.max(48,math.min(90,PackMateDatabase.size.height or 49)))
  end
  if PackMateDatabase.position then
   local p=PackMateDatabase.position
   petDisplay:ClearAllPoints()
   petDisplay:SetPoint(p.anchor or "CENTER",UIParent,p.relativeAnchor or "CENTER",p.x or 0,p.y or 0)
  end
  petDisplay:Hide(); return
 end
 if event=="UNIT_LEVEL" and argument~="pet" then return end
 if event=="UNIT_PET" and argument~="player" then return end
 if PackMateDatabase then updatePetInformation() end
end)
local elapsedSinceRefresh=0
addonFrame:SetScript("OnUpdate",function(_,elapsed)
 elapsedSinceRefresh=elapsedSinceRefresh+elapsed
 if elapsedSinceRefresh>=1 then
  elapsedSinceRefresh=0
  if PackMateDatabase then updatePetInformation() end
 end
end)
SLASH_PACKMATE1="/pm"
SLASH_PACKMATE2="/petledger"
SLASH_PACKMATE3="/packmate"
SlashCmdList.PACKMATE=function(command)
 if not PackMateDatabase then return end
 command=(command or ""):lower():match("^%s*(.-)%s*$")
 if command=="sassy" or command=="stoic" or command=="mute" then
  PackMateDatabase.happinessMode=command
  -- Switching modes discards prior escalation timers, without sending stale messages.
  happinessChangedAt=GetTime()
  deliveredReminderStages={}
  if command~="mute" then announce("Happiness announcements: " .. command .. ".") end
 elseif command=="show" then PackMateDatabase.visible=true;updatePetInformation()
 elseif command=="hide" then PackMateDatabase.visible=false;petDisplay:Hide()
 elseif command=="reset" then
  PackMateDatabase.size={width=165,height=49}
  PackMateDatabase.hudLayoutVersion=4
  petDisplay:SetSize(165,49)
  petDisplay:ClearAllPoints()
  petDisplay:SetPoint("CENTER", UIParent, "CENTER", 0, -155)
  PackMateDatabase.position={anchor="CENTER",relativeAnchor="CENTER",x=0,y=-155}
  PackMateDatabase.visible=true
  updatePetInformation()
 elseif command=="xp on" then
  PackMateDatabase.announceExperience=true
  announce("Pet XP chat notifications enabled.")
 elseif command=="xp off" then
  PackMateDatabase.announceExperience=false
  announce("Pet XP chat notifications disabled.")
 elseif command=="status" then
  local petGUID,petName=currentPetIdentity()
  if not petGUID then announce("No active pet.");return end
  local record=PackMateDatabase.pets[petGUID]
  updatePetInformation()
  record=PackMateDatabase.pets[petGUID]
  announce(string.format("%s: level %d; %d unspent training points. Visit a Pet Trainer and use Beast Training to see available skills.",petName,record.level,record.availableTrainingPoints or 0))
  announce(string.format("Observed pet XP total: %d",record.totalObservedExperience or 0))
 elseif command=="" or command=="help" then
  announce("Mode: " .. PackMateDatabase.happinessMode .. ". /pm sassy | stoic | mute; /pm show | hide | reset | status | xp on | xp off")
 else announce("Unknown command. Use /pm help.") end
end
