local addon, ns = ...

local LibMobs = LibStub("LibMobs")
assert(LibMobs, "Filger requires LibMobs")

-- Blizzard
local NUM_RAID_ICONS = _G.NUM_RAID_ICONS or 8


local UnitGUID = _G.UnitGUID
local UnitExists = _G.UnitExists
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local SetRaidTarget = _G.SetRaidTarget
local CanBeRaidTarget = _G.CanBeRaidTarget
local IsInGroup =_G.IsInGroup
local UnitIsGroupLeader =_G.UnitIsGroupLeader
local UnitIsGroupAssistant =_G.UnitIsGroupAssistant
local IsInInstance =_G.IsInInstance

-- local UnitGUID = _G.UnitGUID
-- local UnitExists = _G.UnitExists
-- local UnitIsDead = _G.UnitIsDead
-- local UnitAffectingCombat = _G.UnitAffectingCombat
-- local GetRaidTargetIndex = _G.GetRaidTargetIndex
-- local SetRaidTarget = _G.SetRaidTarget
-- local CanBeRaidTarget = _G.CanBeRaidTarget
-- local UnitInRange = _G.UnitInRange

-- Mine
local NUM_NAMEPLATES = 40

local RAID_ICONS = {
    [8] = "Skull",   -- Skull
    [7] = "Cross",   -- X
    [6] = "Square",  -- Square
    [5] = "Moon",    -- Moon
    [4] = "Triangle", -- Triangle
    [3] = "Diamond",  -- Diamond
    [2] = "Circle",   -- Circle
    [1] = "Star"      -- Star
}

local element_proto = {
    units = {}, -- store units by guid
    all = {},
    actives = {},
    assignedIcons = {}, -- store which unit was assigned by the addon
    manuallyAssignedIcons = {} -- store which unit was assigned by others
}

function element_proto:print(...)
    print("|cffff8000" .. addon .. ":|r", ...)
end

function element_proto:GetAvailableIcon()
    for index = NUM_RAID_ICONS, 1, -1 do
        if self.assignedIcons[index] == nil and self.manuallyAssignedIcons[index] == nil and RAID_ICONS[index] then
            return index
        end
    end
    return nil
end

do
    local units = {
        "player",
        "pet",
        "party1",
        "party2",
        "party3",
        "party4",
    }

    for index = 1, NUM_NAMEPLATES do
        table.insert(units, "nameplate" .. index)
    end

    for index = 1, 40 do
        table.insert(units, "raid" .. index)
    end

    for index = 1, 4 do
        table.insert(units, "party" .. index)
    end

    for index = 1, 8 do
        table.insert(units, "boss" .. index)
    end

    -- table.insert(units, "player")
    -- table.insert(units, "target")
    -- table.insert(units, "focus")
    -- table.insert(units, "pet")
    -- table.insert(units, "targettarget")
    -- table.insert(units, "focustarget")
    -- table.insert(units, "mouseover")

    function element_proto:GetUnitByGUID(guid)
        if guid then
            for _, unit in next, units do
                if UnitGUID(unit) == guid then
                    return unit
                end
            end
        end
        return nil
    end

    function element_proto:GetRaidTargetUnit(index)
        for _, unit in next, units do
            if UnitExists(unit) and GetRaidTargetIndex(unit) == index then
                return unit
            end
        end
        return nil
    end
    
    function element_proto:UpdateManuallyAssignedRaidTargetUnit(unit)
        if not unit then return end
        if not UnitExists(unit) then return end

        local name = UnitName(unit)
        local guid = UnitGUID(unit)
        
        -- needed ???
        self.units[guid] = unit

        local index = GetRaidTargetIndex(unit)
        if RAID_ICONS[index or 0] then
            if self.assignedIcons[index] then
                -- the raid target was assigned by the addon itself
                self.manuallyAssignedIcons[index] = nil
            else
                -- the raid target was assigned by somebody else
                self.manuallyAssignedIcons[index] = { unit = unit, guid = guid, name = name }
            end
        end
    end

    function element_proto:UpdateManuallyAssignedRaidTargets()
        for _, unit in next, units do
           self:UpdateManuallyAssignedRaidTargetUnit(unit)
        end
    end
end

element_proto.SortData = function(a, b)
    if (a.priority ~= b.priority) then
        return a.priority > b.priority
    end
    return a.unit < b.unit
end

function element_proto:FilterData(data)
    return data.npcID and CanBeRaidTarget(data.unit) and (not data.ignored)
end

function element_proto:ProcessData(unit)
    if UnitExists(unit) then
        local name = UnitName(unit)
        local guid = UnitGUID(unit)
        local inRange, checkedRange = UnitInRange(unit)

        local guidInfo = LibMobs:ParseCreatureGUID(guid)
        if guidInfo then
            local mobInfo = LibMobs:GetMob(guidInfo.instanceID, guidInfo.npcID)
            if mobInfo then
                local unitInfo = {
                    unit = unit,
                    guid = guid,
                    name = name,
                    inRange = inRange
                }
                return Mixin(unitInfo, guidInfo, mobInfo)
            end
        end
    end
    return nil
end

function element_proto:AssignUnit(data)
    local element = self
    local unit = data.unit

    -- element:print(data.unit, data.guid, data.name, data.priority, data.ignored)

    -- ignore if unit already have a raid target
    if GetRaidTargetIndex(unit) then return end

    -- check if there is a raid target not in use
    local index = self:GetAvailableIcon()
    if index then
        -- check if you are in combat
        local threat = UnitThreatSituation("player", unit)
        local inCombat = UnitAffectingCombat(unit)
        element:print("UNIT ASSIGNED", RAID_ICONS[index], unit, data.guid, data.name, "threat", threat, "combat", inCombat)
        if threat ~= nil or inCombat then
            SetRaidTarget(unit, index)
            self.assignedIcons[index] = data
        end
    end
end

function element_proto:Update(event, unit)
    local element = self

    local changed = false

    if not unit then
        element.all = table.wipe(element.all or {})
        element.actives = table.wipe(element.actives or {})
        
        for index = 1, NUM_NAMEPLATES do
            unit = "nameplate" .. index
            local data = element:ProcessData(unit)
            if data then
                element.all[data.guid] = data

                if element:FilterData(data) then
                    element.actives[data.guid] = true
                end
            end
        end

        changed = true
    else
        local data = element:ProcessData(unit)
        if data then
            local guid = data.guid
            if UnitIsDead(unit) then
                element.all[guid] = nil
                element.actives[guid] = nil
                element.assignedIcons[guid] = nil
                element.manuallyAssignedIcons[guid] = nil
                changed = true
            else
                element.all[guid] = data
                if element:FilterData(data) then
                    element.actives[guid] = true
                    changed = true
                end
            end
        end
    end

    if changed then
        element.sorted = table.wipe(element.sorted or {})

        for guid, _ in next, element.actives do
            table.insert(element.sorted, element.all[guid])
        end

        table.sort(element.sorted, element.SortData)

        local max = math.min(#element.sorted, NUM_RAID_ICONS)

        for index = 1, max do
            element:AssignUnit(element.sorted[index])
        end
    end
end

function element_proto:Start()
    self:print("Starting...")
    self:RegisterEvent("RAID_TARGET_UPDATE")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function element_proto:Stop()
    self:print("Stoping...")
    self:UnregisterEvent("RAID_TARGET_UPDATE")
    self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function element_proto:PLAYER_LOGIN()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("PLAYER_LOGIN")
end

function element_proto:Initialize()
    local isLeader = not IsInGroup() or UnitIsGroupLeader("player")
    local isInInstance, instanceType = IsInInstance()
    if isLeader and instanceType == "party" then
        self:Start()
        self:UpdateManuallyAssignedRaidTargets()
    else
        self:Stop()
    end
end

function element_proto:PLAYER_ENTERING_WORLD()
    self:Initialize()
end

function element_proto:GROUP_ROSTER_UPDATE()
    self:Initialize()
end

function element_proto:PLAYER_REGEN_ENABLED()
end

function element_proto:PLAYER_REGEN_DISABLED()
    local element = self
    C_Timer.After(0.75, function()
        element:Update("PLAYER_REGEN_DISABLED")
    end)
end

function element_proto:NAME_PLATE_UNIT_ADDED(unit)
    local element = self
    element:UpdateManuallyAssignedRaidTargetUnit(unit)
    C_Timer.After(0.5, function()
        element:Update("NAME_PLATE_UNIT_ADDED", unit)
    end)
end

function element_proto:NAME_PLATE_UNIT_REMOVED(unit)
    local element = self
    element:UpdateManuallyAssignedRaidTargetUnit(unit)
    C_Timer.After(0.5, function()
        element:Update("NAME_PLATE_UNIT_REMOVED", unit)
    end)

end

function element_proto:RAID_TARGET_UPDATE()
    local element = self
    element:UpdateManuallyAssignedRaidTargets()
end

function element_proto:COMBAT_LOG_EVENT_UNFILTERED(unit)
    local _, subevent, _, _, _, _, _, destGUID, _, _, _ = CombatLogGetCurrentEventInfo()
    if subevent == "UNIT_DIED" then
        local unit = self:GetUnitByGUID(destGUID)
        if unit then
            local iconIndex = GetRaidTargetIndex(unit)
            if iconIndex then
                -- enable reuse of raid targets
                self.assignedIcons[iconIndex] = nil
                self.manuallyAssignedIcons[iconIndex] = nil
            end
        end
    end
end

function element_proto:OnEvent(event, ...)
    if self[event] then
        self[event](self, ...)
    else
        self:print(event, ...)
    end
end

local frame = Mixin(CreateFrame("Frame"), element_proto)
frame:RegisterEvent("PLAYER_LOGIN")
-- frame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- frame:RegisterEvent("GROUP_ROSTER_UPDATE")          -- check if player if the group leader
-- frame:RegisterEvent("PLAYER_REGEN_ENABLED")         -- player get out combat
-- frame:RegisterEvent("PLAYER_REGEN_DISABLED")        -- player get into combat
-- frame:RegisterEvent("RAID_TARGET_UPDATE")           -- check for manually set raid targets (do not trigger on reload)
-- frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")        -- enemy appears
-- frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")      -- enemy dies
-- frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")  -- enemy dies
frame:SetScript("OnEvent", frame.OnEvent)
