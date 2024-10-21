local addon, ns = ...

local LibMobs = LibStub("LibMobs")
assert(LibMobs, "Filger requires LibMobs")

-- Blizzard
local NUM_RAID_ICONS = _G.NUM_RAID_ICONS or 8

local CanBeRaidTarget = _G.CanBeRaidTarget
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local IsInGroup =_G.IsInGroup
local IsInInstance =_G.IsInInstance
local SetRaidTarget = _G.SetRaidTarget
local UnitAffectingCombat = _G.UnitAffectingCombat
local UnitExists = _G.UnitExists
local UnitGUID = _G.UnitGUID
local UnitInRange = _G.UnitInRange
local UnitIsDead = _G.UnitIsDead
local UnitIsGroupAssistant =_G.UnitIsGroupAssistant
local UnitIsGroupLeader =_G.UnitIsGroupLeader

-- Mine
if true then return end

local UPDATE_INTERVAL = 1
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

local COMBAT_EVENTS = {
    ["DAMAGE_SHIELD"] = true, -- reflecting damage
    ["DAMAGE_SPLIT"] = true, -- shared damage effects
    ["RANGE_DAMAGE"] = true, -- ranged attacks
    ["SPELL_DAMAGE"] = true, -- spell-based damage
    ["SPELL_HEAL"] = true, -- healing events
    ["SPELL_AURA_APPLIED"] = true,
    ["SPELL_MISSED"] = true, -- misses during combat
    ["SWING_DAMAGE"] = true, -- melee attacks
    ["SWING_MISSED"] = true,
    ["SPELL_CAST_SUCCESS"] = true,
}

local element_proto = {
    units = {}, -- store units by guid
    all = {},
    actives = {},
    assignedIcons = {}, -- store which unit was assigned by the addon
    manuallyAssignedIcons = {}, -- store which unit was assigned by others
    enemies = {}, -- store which unit you are in combat with
    queue = {}, -- store units to process later
    interval = 0
}

function element_proto:print(...)
    print("|cffff8000" .. addon .. ":|r", ...)
end

function element_proto:GetRaidTarget(unit, guid)
    return GetRaidTargetIndex(unit) or self.assignedIcons[guid or 0] or self.manuallyAssignedIcons[guid or 0] or nil
end

function element_proto:SetRaidTarget(unit, iconIndex, guid)
    -- remove old one
    local oldGUID = self.assignedIcons[iconIndex] or self.manuallyAssignedIcons[iconIndex]
    self:RemoveRaidTarget(nil, iconIndex, oldGUID)
    
    -- update icon
    local data = { unit = unit, guid = guid, name = UnitName(unit) }
    self.assignedIcons[iconIndex] = data
    self.assignedIcons[guid] = iconIndex
    self.manuallyAssignedIcons[iconIndex] = nil
    self.manuallyAssignedIcons[guid] = nil

    SetRaidTarget(unit, iconIndex)
end

function element_proto:RemoveRaidTarget(unit, iconIndex, guid)
    -- if unit then
    --     SetRaidTarget(unit, nil)
    -- end
    if iconIndex then
        self.assignedIcons[iconIndex] = nil
        self.manuallyAssignedIcons[iconIndex] = nil
    end
    if guid then
        self.assignedIcons[guid] = nil
        self.manuallyAssignedIcons[guid] = nil
    end
end

function element_proto:GetAvailableIcon()
    for iconIndex = NUM_RAID_ICONS, 1, -1 do
        if self.assignedIcons[iconIndex] == nil and self.manuallyAssignedIcons[iconIndex] == nil and RAID_ICONS[iconIndex] then
            return iconIndex
        end
    end
    return nil
end

function element_proto:IsInCombat(unit, guid)
    local threat = UnitThreatSituation("player", unit)
    local inCombat = UnitAffectingCombat(unit)
    local isTargetingPlayer = UnitIsUnit(unit .. "target", "player")
    return (self.enemies[guid] == true) or (threat ~= nil) or (inCombat == true) or isTargetingPlayer
end

do
    local units = {
        ["player"] = true,
        ["pet"] = true,
        -- "party1",
        -- "party2",
        -- "party3",
        -- "party4",
    }

    for index = 1, NUM_NAMEPLATES do
        units["nameplate" .. index] = true
    end

    -- for index = 1, 40 do
    --     table.insert(units, "raid" .. index)
    -- end

    -- for index = 1, 4 do
    --     table.insert(units, "party" .. index)
    -- end

    -- for index = 1, 8 do
    --     table.insert(units, "boss" .. index)
    -- end

    -- table.insert(units, "player")
    -- table.insert(units, "target")
    -- table.insert(units, "focus")
    -- table.insert(units, "pet")
    -- table.insert(units, "targettarget")
    -- table.insert(units, "focustarget")
    -- table.insert(units, "mouseover")

    function element_proto:BuildUnitList()
        local numMembers = GetNumGroupMembers()
        if IsInRaid() then
            for index = 1, 40 do
                units["raid" .. index] = (index <= numMembers) and true or nil
            end
            for index = 1, 4 do
                units["party" .. index] = nil
            end
        elseif IsInGroup() then
            for index = 1, 4 do
                units["party" .. index] = (index <= numMembers) and true or nil
            end
        end
    end

    function element_proto:GetUnitByGUID(guid)
        if guid then
            for unit, _ in next, units do
                if UnitGUID(unit) == guid then
                    return unit
                end
            end
        end
        return nil
    end

    function element_proto:GetRaidTargetUnit(index)
        for unit, _ in next, units do
            if UnitExists(unit) and GetRaidTargetIndex(unit) == index then
                return unit
            end
        end
        return nil
    end
    
    function element_proto:UpdateManuallyAssignedRaidTargetUnit(unit)
        if unit and UnitExists(unit) then
            local name = UnitName(unit)
            local guid = UnitGUID(unit)
            
            -- needed ???
            self.units[guid] = unit

            local iconIndex = self:GetRaidTarget(unit, guid)
            if RAID_ICONS[iconIndex or 0] then
                if self.assignedIcons[iconIndex] then
                    -- the raid target was assigned by the addon itself
                    self.manuallyAssignedIcons[iconIndex] = nil
                    self.manuallyAssignedIcons[guid] = nil
                else
                    -- the raid target was assigned by somebody else
                    self.manuallyAssignedIcons[iconIndex] = { unit = unit, guid = guid, name = name }
                    self.manuallyAssignedIcons[guid] = iconIndex
                end
            end
        end
    end

    function element_proto:UpdateManuallyAssignedRaidTargets()
        self.manuallyAssignedIcons = table.wipe(self.manuallyAssignedIcons or {})
        for unit, _ in next, units do
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

        -- break GUID into useful information, such as instanceID, zoneID, npcID, etc.
        local guidInfo = LibMobs:ParseCreatureGUID(guid)
        if guidInfo then
            -- check if unit is a important npc that should be watched
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

function element_proto:AssignUnit(event, data)
    local unit = data.unit
    local guid = data.guid

    -- ignore if unit already have a raid target
    local currentIconIndex = self:GetRaidTarget(unit, guid)
    if currentIconIndex then return end

    -- check if there is a raid target not in use
    local iconIndex = self:GetAvailableIcon()
    if iconIndex then
        -- if the unit is combat with the player, we can mark it
        if self:IsInCombat(unit, guid) then
            SetRaidTarget(unit, iconIndex)
            self.assignedIcons[iconIndex] = data
            self.assignedIcons[guid] = iconIndex
            self:print("ASSIGNED", event, currentIconIndex, iconIndex, RAID_ICONS[iconIndex], data.unit, data.name, data.npcID, data.priority)
        else
            -- add to queue to process later
            table.insert(self.queue, data)
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

                local iconIndex = element:GetRaidTarget(unit, guid)
                element:RemoveRaidTarget(unit, guid, iconIndex)
                
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
            element:AssignUnit(event, element.sorted[index])
        end
    end
end

function element_proto:Start()
    -- can for manually assigned raid targets
    self:UpdateManuallyAssignedRaidTargets()

    -- start listening to events
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("RAID_TARGET_UPDATE")
end

function element_proto:Stop()
    -- stop listening to events
    self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("RAID_TARGET_UPDATE")
end

function element_proto:PLAYER_LOGIN()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterEvent("PLAYER_LOGIN")
end

function element_proto:Initialize()
    self:BuildUnitList()

    local isLeader = not IsInGroup() or UnitIsGroupLeader("player")
    local isInInstance, instanceType = IsInInstance()
    if isLeader and instanceType == "party" then
        self:Start()
    else
        self:Stop()
    end
end

function element_proto:PLAYER_ENTERING_WORLD()
    self.enemies = table.wipe(self.enemies or {})
    self:Initialize()
end

function element_proto:GROUP_ROSTER_UPDATE()
    self:Initialize()
end

function element_proto:PLAYER_REGEN_ENABLED()
    -- stop processing the queue
    self:SetScript("OnUpdate", nil)
    
end

function element_proto:PLAYER_REGEN_DISABLED()
    self:Update("PLAYER_REGEN_DISABLED")

    -- start queue processing
    self.interval = 0
    self:SetScript("OnUpdate", self.OnUpdate)
end

function element_proto:NAME_PLATE_UNIT_ADDED(unit)
    local guid = UnitGUID(unit)
    if guid then
        self.units[guid] = unit
    end

    -- self:UpdateManuallyAssignedRaidTargetUnit(unit)
    self:Update("NAME_PLATE_UNIT_ADDED", unit)
end

function element_proto:NAME_PLATE_UNIT_REMOVED(unit)
    local guid = UnitGUID(unit)
    if guid then
        self.units[guid] = nil
    end

    -- self:UpdateManuallyAssignedRaidTargetUnit(unit)
    self:Update("NAME_PLATE_UNIT_REMOVED", unit)
end

function element_proto:RAID_TARGET_UPDATE()
    self:UpdateManuallyAssignedRaidTargets()
end

function element_proto:COMBAT_LOG_EVENT_UNFILTERED(unit)
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
    if subevent == "UNIT_DIED" and destGUID then
        -- we are not in combat anymore
        self.enemies[destGUID] = nil

        -- free the raid target icon to be reused
        local unit = self.units[destGUID] or self:GetUnitByGUID(destGUID)
        if unit then
            self.units[destGUID] = nil
            local iconIndex = self:GetRaidTarget(unit, destGUID)
            self:RemoveRaidTarget(unit, iconIndex, destGUID)
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

function element_proto:OnEvent(event, ...)
    if self[event] then
        self[event](self, ...)
    else
        self:print(event, ...)
    end
end

function element_proto:OnUpdate(elapsed)
    self.interval = (self.interval or 0) - (elapsed or 1)
    if self.interval <= 0 then
        local length = #self.queue
        if length > 0 then
            for index = length, 1, -1 do
                local data = self.queue[index]
                self:AssignUnit("QUEUE", data)
                table.remove(self.queue, index)
            end
        end
        self.interval = UPDATE_INTERVAL
    end
end

local frame = Mixin(CreateFrame("Frame"), element_proto)
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", frame.OnEvent)

local table_length = function(value)
    local n = 0
    for k, v in next, value do
        n = n + 1
    end
    return n
end


function frame:Resume()
    for name, value in next, self do
        local _type = type(value)
        if _type ~= "function" and _type ~= "userdata" then
            if _type == "table" then
                local length = table_length(value)
                self:print(name, value, length)
                -- skip
            else
                self:print(name, value)
            end
        end
    end
    self:print(" ----- ")

    -- frame:print("units", table_length(frame.units))
    -- frame:print("all", table_length(frame.all))
    -- frame:print("actives", table_length(frame.actives))

    -- local assignedIconsLength = table_length(frame.assignedIcons)
    -- frame:print("assignedIcons", assignedIconsLength)
    
    -- if assignedIconsLength > 0 then
    --     for k, v in next, frame.assignedIcons do
    --         frame:print(k, v.unit, v.guid, v.name, UnitIsDead(v.unit))
    --     end
    -- end
    
    -- local manuallyAssignedIconsLength = table_length(frame.manuallyAssignedIcons)
    -- frame:print("manuallyAssignedIcons", table_length(frame.manuallyAssignedIcons))

    -- if manuallyAssignedIconsLength > 0 then
    --     for k, v in next, frame.manuallyAssignedIcons do
    --         frame:print(k, v.unit, v.guid, v.name, UnitIsDead(v.unit))
    --     end
    -- end

    -- frame:print("enemies", table_length(frame.enemies))
    -- frame:print("queue", #frame.queue)
    -- frame:print("interval", frame.interval)
end

function frame:Reset()
    self.units = table.wipe(self.units or {})
    self.enemies = table.wipe(self.enemies or {})
    self.assignedIcons = table.wipe(self.assignedIcons or {})
    self.manuallyAssignedIcons = table.wipe(self.manuallyAssignedIcons or {})
    self.all = table.wipe(self.all or {})
    self.actives = table.wipe(self.actives or {})
    self.sorted = table.wipe(self.sorted or {})
    self.queue = table.wipe(self.queue or {})
end

SLASH_AUTOMARKER1 = "/marker"
SlashCmdList["AUTOMARKER"] = function(cmd)
    if cmd == "reset" then
        frame:Reset()
    else
        frame:Resume()
    end
end
