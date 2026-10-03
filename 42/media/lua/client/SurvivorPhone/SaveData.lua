require 'SurvivorPhone/Planner'
require 'SurvivorPhone/Settings'
require 'SurvivorPhone/GameClock'
SurvivorPhoneData = {}
function SurvivorPhoneData.now() return SurvivorPhoneClock.now() end
function SurvivorPhoneData.get(player)
    local mod=player:getModData()
    mod.SurvivorPhone=mod.SurvivorPhone or {schemaVersion=1}
    local root=mod.SurvivorPhone
    SurvivorPhoneSettings.ensure(root)
    local now=SurvivorPhoneClock.now()
    local planner=SurvivorPhonePlanner.init(root,now.day)
    return root,planner,now
end
return SurvivorPhoneData
