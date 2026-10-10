require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/XPActionResults'

SurvivorPhoneMechanicsXP={}
local M=SurvivorPhoneMechanicsXP

local function localPlayer(player)
    return player and not isClient() and not isServer() and not player:isDead()
end

local function safeText(fn)
    local ok,value=pcall(fn)
    if ok and value~=nil then return tostring(value) end
end

local function describe(action,name)
    local part=action and action.part
    local itemName
    if name=='ISInstallVehiclePart' then
        itemName=action.item and safeText(function() return action.item:getDisplayName() end)
    else
        itemName=part and safeText(function()
            local item=part:getInventoryItem()
            return item and item:getDisplayName()
        end)
    end
    itemName=itemName or (part and safeText(function() return part:getId() end)) or 'vehicle part'
    local verb=name=='ISInstallVehiclePart' and 'Install' or name=='ISUninstallVehiclePart' and 'Remove' or 'Repair'
    return 'Mechanics:'..name..':'..itemName,verb..' '..itemName
end

local function wrap(name)
    local class=_G[name]
    if not class or not class.complete then return false end
    class._survivorWatchMechanicsXP=rawget(class,'_survivorWatchMechanicsXP') or {}
    if class._survivorWatchMechanicsXP.complete then return true end
    local original=class.complete
    class.complete=function(self,...)
        local player=self.character
        local beforeXP,beforeLevel,key,label,instance
        if localPlayer(player) then
            beforeXP=player:getXp():getXP(Perks.Mechanics)
            beforeLevel=player:getPerkLevel(Perks.Mechanics)
            key,label=describe(self,name)
            instance=tostring(self)
        end
        local result=original(self,...)
        if beforeXP~=nil and result==true and localPlayer(player) then
            local afterXP=player:getXp():getXP(Perks.Mechanics)
            local afterLevel=player:getPerkLevel(Perks.Mechanics)
            local root,_,now=SurvivorPhoneData.get(player)
            SurvivorPhoneXP.observeActionResult(root,now.day,'Mechanics',math.max(0,afterXP-beforeXP),'Mechanics',{
                minute=now.minute,world=now.worldMinute,level=beforeLevel,currentLevel=afterLevel,
                actionKey=key,actionLabel=label,actionInstance=instance
            })
        end
        return result
    end
    class._survivorWatchMechanicsXP.complete=true
    return true
end

function M.install()
    if isClient() or isServer() then return end
    pcall(require,'Vehicles/TimedActions/ISInstallVehiclePart')
    pcall(require,'Vehicles/TimedActions/ISUninstallVehiclePart')
    pcall(require,'Vehicles/TimedActions/ISRepairVehiclePart')
    wrap('ISInstallVehiclePart')
    wrap('ISUninstallVehiclePart')
    wrap('ISRepairVehiclePart')
end

return M
