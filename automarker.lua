local addon, ns = ...

local LibMobs = LibStub("LibMobs")
assert(LibMobs, "Filger requires LibMobs")

-- Blizzard
local NUM_RAID_ICONS = _G.NUM_RAID_ICONS or 8
local MAX_RAID_MEMBERS = _G.MAX_RAID_MEMBERS or 40
local MAX_PARTY_MEMBERS = _G.MAX_PARTY_MEMBERS or 4

local CanBeRaidTarget = _G.CanBeRaidTarget
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local IsInGroup =_G.IsInGroup
local IsInRaid =_G.IsInRaid
local IsInInstance =_G.IsInInstance
-- local SetRaidTarget = _G.SetRaidTarget
local UnitAffectingCombat = _G.UnitAffectingCombat
local UnitThreatSituation = _G.UnitThreatSituation
local UnitExists = _G.UnitExists
local UnitName = _G.UnitName
local UnitGUID = _G.UnitGUID
-- local UnitInRange = _G.UnitInRange
local UnitIsDead = _G.UnitIsDead
local UnitIsUnit = _G.UnitIsUnit
local UnitIsGroupAssistant =_G.UnitIsGroupAssistant
local UnitIsGroupLeader =_G.UnitIsGroupLeader
local CombatLogGetCurrentEventInfo =_G.CombatLogGetCurrentEventInfo
local CombatLog_Object_IsA =_G.CombatLog_Object_IsA
local GetNumGroupMembers =_G.GetNumGroupMembers

-- Mine
local NUM_NAMEPLATES = 40
local UPDATE_INTERVAL = 1

local COMBAT_EVENTS = {
    ["DAMAGE_SHIELD"] = true,
    ["DAMAGE_SPLIT"] = true,
    ["RANGE_DAMAGE"] = true,
    ["SPELL_AURA_APPLIED"] = true,
    ["SPELL_CAST_SUCCESS"] = true,
    ["SPELL_DAMAGE"] = true,
    ["SPELL_HEAL"] = true,
    ["SPELL_MISSED"] = true,
    ["SWING_DAMAGE"] = true,
    ["SWING_MISSED"] = true,
}

local RAID_ICONS = {
    [8] = "Skull",
    [7] = "Cross",
    [6] = "Square",
    [5] = "Moon",
    [4] = "Triangle",
    [3] = "Diamond",
    [2] = "Circle",
    [1] = "Star"
}

local element_proto = {
    _combat = false,

    units = {},
    guids = {},
    enemies = {},
    nameplates = {},
    -- loop
    all = {},
    actives = {},
    sorted = {},
    queue = {},
    -- icons
    assignedIcons = {},
    manuallyAssignedIcons = {},
}

do
    local units = {
        ["player"] = true,
        ["pet"] = true,
        -- ["target"] = nil,
        -- ["focus"] = nil,
        -- ["mouseover"] = nil,
        -- ["party1"] = nil,
        -- ["party2"] = nil,
        -- ["party3"] = nil,
        -- ["party4"] = nil,
    }

    function element_proto:print(...)
        print("|cffff8000AutoMarker|r", ...)
    end

    function element_proto:table_length(tbl)
        local n = 0
        for k, v in next, tbl do
            n = n + 1
        end
        return n
    end

    function element_proto:AddUnit(unit, guid)
        if unit and not guid then
            guid = UnitGUID(unit)
        end
        self.units[guid or "none"] = unit
        self.guids[unit or "none"] = guid
    end

    function element_proto:RemoveUnit(unit, guid)
        if unit and not guid then
            guid = UnitGUID(unit)
        end
        self.units[guid or "none"] = nil
        self.guids[unit or "none"] = nil
    end

    function element_proto:GetUnitByGUID(guid)
        local unit = self.units[guid]
        if self.guids[unit] == guid then
            return unit
        end
        return nil
    end

    function element_proto:GetRaidTargetIndex(unit, guid)
        return GetRaidTargetIndex(unit) or self.manuallyAssignedIcons[guid] or self.assignedIcons[guid]
    end

    function element_proto:SetRaidTargetIndex(data, index)
        SetRaidTarget(data.unit, index)
        self.assignedIcons[index] = data
        self.assignedIcons[data.guid] = index
    end

    function element_proto:GetNextRaidTargetIndex()
        for iconIndex = NUM_RAID_ICONS, 1, -1 do
            if self.assignedIcons[iconIndex] == nil and self.manuallyAssignedIcons[iconIndex] == nil then
                return iconIndex
            end
        end
        return nil
    end

    function element_proto:UpdateManuallyAssignedUnit(unit)
        if unit and UnitExists(unit) then
            local name = UnitName(unit)
            local guid = UnitGUID(unit)

            local iconIndex = GetRaidTargetIndex(unit)
            if iconIndex and RAID_ICONS[iconIndex] then
                if self.assignedIcons[iconIndex] then
                    -- the raid target was assigned by the addon itself
                    self.manuallyAssignedIcons[iconIndex] = nil
                    self.manuallyAssignedIcons[guid] = nil
                else
                    -- the raid target was assigned by somebody else
                    self.manuallyAssignedIcons[iconIndex] = { unit = unit, guid = guid }
                    self.manuallyAssignedIcons[guid] = iconIndex
                end
            end
        end
    end

    function element_proto:UpdateManuallyAssigned()
        if IsInRaid() then
            for index = 1, MAX_RAID_MEMBERS do
                local unit = "raid" .. index
                units[unit] = UnitExists(unit)
            end

            for index = 1, MAX_PARTY_MEMBERS do
                local unit = "party" .. index
                units[unit] = nil
            end
        elseif IsInGroup() then
            for index = 1, MAX_PARTY_MEMBERS do
                local unit = "party" .. index
                units[unit] = UnitExists(unit)
            end
        else
            for index = 1, MAX_RAID_MEMBERS do
                local unit = "raid" .. index
                units[unit] = nil
            end

            for index = 1, MAX_PARTY_MEMBERS do
                local unit = "party" .. index
                units[unit] = nil
            end
        end

        self.manuallyAssignedIcons = table.wipe(self.manuallyAssignedIcons or {})

        -- validate units
        for unit, _ in next, units do
            self:UpdateManuallyAssignedUnit(unit)
        end
        
        -- validate nameplates
        for unit, _ in next, self.nameplates do
            self:UpdateManuallyAssignedUnit(unit)
        end
    end

    function element_proto:IsInCombat(unit, guid)
        return (UnitThreatSituation("player", unit) ~= nil) -- check if you have threat
            or (UnitAffectingCombat(unit)) -- check if you in combat
            or (self.enemies[guid]) -- check if unit attack you or any group member
            or (UnitIsUnit(unit .. "target", "player")) -- check if unit is targeting you
    end

    function element_proto:UnitIsInCombatWithParty(unit)
        for member, _ in next, units do
            if not UnitIsUnit(member, unit) and  UnitThreatSituation(member, unit) ~= nil then
                return true
            end
        end
        return self:IsInCombat(unit)
    end
end

--[[
    FUNCTION element_proto:Enable()
    Check conditions to see if we can automatically mark units
--]]
function element_proto:Enable()
    -- check if player is inside a instance
    local isInInstance, instanceType = IsInInstance()
    local instanceName, _, _, _, _, _, _, instanceID, _, _ = GetInstanceInfo()
    self.__instanceID = instanceID
    
    -- check if player is in a raid/party group
    local isInGroup, isInRaid = IsInGroup(), IsInRaid()
    self.__inGroup = isInGroup or isInRaid

    -- check if player if the group leader
    local isLeader, isAssistant = UnitIsGroupLeader("player"), UnitIsGroupAssistant("player")
    self.__isLeader = isLeader or not self.__inGroup
    
    -- enabled when:
    -- the player is inside an instance
    -- the player is the group leader or if he is solo
    local enabled = isInInstance and (isLeader or (not isInGroup) or (not isInRaid))
    
    if enabled and not self.__init then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("RAID_TARGET_UPDATE")
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self.__init = true
    elseif not enabled then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self:UnregisterEvent("RAID_TARGET_UPDATE")
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self.__init = false
    end
end

function element_proto:AssignRaidIcon(event, data)
    if not data then return end

    local unit = data.unit
    local guid = data.guid

    -- ignore if unit already have a raid target
    -- if GetRaidTargetIndex(unit) then return end
    if self.assignedIcons[guid] or self.manuallyAssignedIcons[guid] then return end

    -- check if there is a raid target not in use
    local iconIndex = self:GetNextRaidTargetIndex()
    if iconIndex and self:UnitIsInCombatWithParty(unit) then
        self:SetRaidTargetIndex(data, iconIndex)
    else
        table.insert(self.queue, data)
    end
end

element_proto.SortData = function(a, b)
    if (a.priority ~= b.priority) then
        return a.priority > b.priority
    end
    return a.unit < b.unit
end

function element_proto:FilterData(data)
    return data and data.unit and CanBeRaidTarget(data.unit) and data.npcID and data.mark
end

function element_proto:ProcessData(unit)
    if UnitExists(unit) then
        local name = UnitName(unit)
        local guid = UnitGUID(unit)

        -- break GUID into useful information, such as instanceID, zoneID, npcID, etc.
        local guidInfo = LibMobs:ParseCreatureGUID(guid) or {}

        -- check if unit is a important npc that should be watched
        local creatureInfo = LibMobs:GetCreature(guidInfo.instanceID, guidInfo.npcID) or { priority = -1 }

        return Mixin({ unit = unit, guid = guid, name = name }, guidInfo, creatureInfo)
    end
    return nil
end

--[[
    FUNCTION element_proto:Update(event, unit)
--]]
function element_proto:Update(event, unit)
    if not self.__init then return end

    local changed = false

    if not unit then
        self.all = table.wipe(self.all or {})
        self.actives = table.wipe(self.actives or {})

        for unit, _ in next, self.nameplates do
            local data = self:ProcessData(unit)
            if data then
                self.all[data.guid] = data

                if self:FilterData(data) then
                    self.actives[data.guid] = true
                end
            end
        end

        changed = true
    else
        if UnitIsDead(unit) then
            local guid = UnitGUID(unit)
            self.all[guid] = nil
            self.actives[guid] = nil

            local iconIndex = GetRaidTargetIndex(unit) or self.manuallyAssignedIcons[iconIndex or 0] or self.assignedIcons[iconIndex or 0]
            if iconIndex then
                self.assignedIcons[iconIndex] = nil
                self.manuallyAssignedIcons[iconIndex] = nil
            end

            changed = true
        else
            local data = self:ProcessData(unit)
            if data then
                self.all[data.guid] = data

                if self:FilterData(data) then
                    self.actives[data.guid] = true
                    changed = true
                end
            end
        end
    end

    if changed then
        self.sorted = table.wipe(self.sorted or {})
        -- self.queue = table.wipe(self.queue or {})

        for guid, _ in next, self.actives do
            table.insert(self.sorted, self.all[guid])
        end

        table.sort(self.sorted, self.SortData)

        -- local max = math.min(#self.sorted, NUM_RAID_ICONS)
        -- for index = 1, max do
        --     self:AssignRaidIcon(event, self.sorted[index])
        -- end
        for index, data in next, self.sorted do
            self:AssignRaidIcon(event, data, index)
        end
    end
end

function element_proto:PLAYER_REGEN_ENABLED()
    self._combat = false
    -- stop processing the queue
    self:SetScript("OnUpdate", nil)

    for index = 1, NUM_RAID_ICONS do
        self:print(index, RAID_ICONS[index], self.assignedIcons[index], self.manuallyAssignedIcons[index])
    end
end

function element_proto:PLAYER_REGEN_DISABLED()
    self._combat = true
    -- start queue processing
    self.interval = 0
    self:SetScript("OnUpdate", self.OnUpdate)
    self:Update("PLAYER_REGEN_DISABLED")
end

function element_proto:NAME_PLATE_UNIT_ADDED(unit)
    local guid = UnitGUID(unit)
    
    -- register nameplate
    self.nameplates[unit] = guid

    self:AddUnit(unit, guid)

    self:Update("NAME_PLATE_UNIT_ADDED", unit)
end

function element_proto:NAME_PLATE_UNIT_REMOVED(unit)
    local guid = UnitGUID(unit)
    
    -- unregister nameplate
    self.nameplates[unit] = nil
    
    self:RemoveUnit(unit, guid)
    self:Update("NAME_PLATE_UNIT_REMOVED", unit)
end

function element_proto:RAID_TARGET_UPDATE()
    self:UpdateManuallyAssigned()
end

function element_proto:COMBAT_LOG_EVENT_UNFILTERED()
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
    if subevent == "UNIT_DIED" and destGUID then
        local unit = self:GetUnitByGUID(destGUID)
        if unit and unit:match("nameplate%d") then
            self.units[destGUID] = nil
            self.guids[unit] = nil
        end

        local iconIndex = self.assignedIcons[destGUID] or self.manuallyAssignedIcons[destGUID]
        if iconIndex then
            self.assignedIcons[destGUID] = nil
            self.assignedIcons[iconIndex] = nil
            self.manuallyAssignedIcons[destGUID] = nil
            self.manuallyAssignedIcons[iconIndex] = nil
        end
    elseif COMBAT_EVENTS[subevent] then
        -- check if the source is an enemy
        local isSourceEnemy = CombatLog_Object_IsA(sourceFlags, COMBATLOG_FILTER_HOSTILE_UNITS)

        -- check if the destination is the player, a party member, or a raid member
        local isDestPlayerOrGroup = CombatLog_Object_IsA(destFlags, COMBATLOG_FILTER_ME) or
                                    CombatLog_Object_IsA(destFlags, COMBATLOG_FILTER_MY_PARTY) or
                                    CombatLog_Object_IsA(destFlags, COMBATLOG_FILTER_MY_RAID)

        if isSourceEnemy and isDestPlayerOrGroup then
            self.enemies[sourceGUID] = true
        end
    end
end

--[[
    trigers when:
        - player enters in a group
        - add/remove group member
        - group member zone into the instance
--]]
function element_proto:GROUP_ROSTER_UPDATE()
    self:Enable()
end

function element_proto:PLAYER_ENTERING_WORLD(isLogin, isReload)
    self:UpdateManuallyAssigned()
    self:Enable()
end

function element_proto:PLAYER_LOGIN()
    self.__init = true

    -- check if you can mark units
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- scan nameplates
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

    -- this is not needed anymore
    self:UnregisterEvent("PLAYER_LOGIN")
end

function element_proto:OnEvent(event, ...)
    if self[event] then
        self[event](self, ...)
    end
end

function element_proto:OnUpdate(elapsed)
    self.interval = (self.interval or 0) - (elapsed or 1)
    if self.interval <= 0 then
        for index = 1, #self.queue do
            local data = table.remove(self.queue, 1)
            self:AssignRaidIcon("QUEUE", data)
        end

        table.sort(self.queue, self.SortData)

        self.interval = UPDATE_INTERVAL
    end
end

local frame = Mixin(CreateFrame("Frame"), element_proto)
-- frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", frame.OnEvent)
