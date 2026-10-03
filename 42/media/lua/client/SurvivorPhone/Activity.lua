require 'SurvivorPhone/SaveData'
-- One observation stream for the planner, guidance and future companions.
-- Seeing an action in the queue never means that it completed.
SurvivorPhoneActivity={current={},nextPoll={}}
local A=SurvivorPhoneActivity
A.actions={
    ISPetAnimal={'Animal care XP','Animal care'},ISMilkAnimal={'Animal care XP','Animal care'},
    ISFeedAnimalFromHand={'Animal care XP','Animal care'},
    ISInstallVehiclePart={'Mechanics XP','Mechanics'},ISUninstallVehiclePart={'Mechanics XP','Mechanics'},
    ISRepairVehiclePart={'Mechanics XP','Mechanics'},
    ISBuildAction={'Building completed','Building'},
    ISForageAction={'Foraging collected','Foraging'},
    ISSeedActionNew={'Farming interaction','Farming'},ISWaterPlantAction={'Farming interaction','Farming'},
    ISHarvestPlantAction={'Farming interaction','Farming'},ISFertilizeAction={'Farming interaction','Farming'},
    ISGeneratorInfoAction={'Generator interaction','Generator care'},ISActivateGenerator={'Generator interaction','Generator care'},
    ISPlugGenerator={'Generator interaction','Generator care'},ISFixGenerator={'Generator interaction','Generator care'},
    ISAddFuel={'Generator interaction','Generator care'},ISTakeGenerator={'Generator interaction','Generator care'}
}
A.names={['Fishing catch']='Fishing',['Animal care XP']='Animal care',['Mechanics XP']='Mechanics',
    ['Carving XP']='Carving',['Skill:Woodwork']='Carpentry',['Skill:PlantScavenging']='Foraging',
    ['Skill:Farming']='Farming',['Generator interaction']='Generator care',['Sleep completed']='Sleep',
    ['Building completed']='Building',['Foraging collected']='Foraging',['Farming interaction']='Farming'}
function A.ensure(root)
    root.activity=root.activity or {recent={}}
    root.activity.recent=root.activity.recent or {}
    return root.activity
end
function A.record(player,rule,evidence,now)
    local root=SurvivorPhoneData.get(player)
    local rows=A.ensure(root).recent
    local name=A.names[rule] or rule:gsub('^Skill:','')
    local last=rows[#rows]
    -- Aggregate repeated evidence within a game minute, without merging activities.
    if last and last.rule==rule and last.day==now.day and last.minute==now.minute then
        last.count=(last.count or 1)+1;last.evidence=evidence
    else
        table.insert(rows,{rule=rule,name=name,evidence=evidence,day=now.day,minute=now.minute,count=1})
        while #rows>60 do table.remove(rows,1) end
    end
    if rule~='Sleep completed' then
        A.current[player]={rule=rule,name=name,evidence=evidence,confirmed=true,world=now.worldMinute,real=SurvivorPhoneClock.realSeconds()}
    end
end
function A.poll(player)
    local now=SurvivorPhoneClock.now()
    local seconds=SurvivorPhoneClock.realSeconds()
    local current=A.current[player]
    if current and (now.worldMinute<current.world or now.worldMinute-current.world>10 or seconds-current.real>20 or seconds<current.real) then A.current[player]=nil end
    if player:isAsleep() then A.current[player]=nil;return end
    local queue=ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue(player)
    local action=queue and queue.queue and queue.queue[1]
    local spec=action and A.actions[action.Type]
    if spec and action.isStarted and action:isStarted() then
        action._survivorActivityStart=action._survivorActivityStart or now.worldMinute
        A.current[player]={rule=spec[1],name=spec[2],world=now.worldMinute,real=seconds,action=action,confirmed=false}
    elseif current and current.action then A.current[player]=nil end
end
function A.getCurrent(player,now)
    local item=A.current[player]
    if item and now.worldMinute>=item.world and now.worldMinute-item.world<=10 and SurvivorPhoneClock.realSeconds()-item.real<=20 then return item end
end
return A
