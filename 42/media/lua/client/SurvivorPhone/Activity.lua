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

local function safeText(fn)
    local ok,value=pcall(fn)
    if ok and value~=nil then return tostring(value) end
end

local function actionDetail(action)
    if not action then return nil end
    local t=action.Type or 'Action'
    if t=='ISInstallVehiclePart' or t=='ISUninstallVehiclePart' or t=='ISRepairVehiclePart' then
        local part=action.part
        local partName=part and (safeText(function() return part:getInventoryItem() and part:getInventoryItem():getDisplayName() end)
            or safeText(function() return part:getId() end))
        local verb=t=='ISInstallVehiclePart' and 'Install' or t=='ISUninstallVehiclePart' and 'Remove' or 'Repair'
        return 'Mechanics:'..t..':'..(partName or 'part'),verb..' '..(partName or 'vehicle part')
    end
    if t=='ISPetAnimal' then return 'Animal:pet','Pet animal' end
    if t=='ISMilkAnimal' then return 'Animal:milk','Milk animal' end
    if t=='ISFeedAnimalFromHand' then return 'Animal:feed','Feed animal' end
    if t=='ISBuildAction' then return 'Build:'..t,'Build' end
    if t=='ISForageAction' then return 'Forage:'..t,'Forage' end
    if t=='ISSeedActionNew' then return 'Farm:seed','Plant seeds' end
    if t=='ISWaterPlantAction' then return 'Farm:water','Water plant' end
    if t=='ISHarvestPlantAction' then return 'Farm:harvest','Harvest plant' end
    if t=='ISFertilizeAction' then return 'Farm:fertilize','Fertilize plant' end
    return t,t:gsub('^IS',''):gsub('Action$',''):gsub('(%l)(%u)','%1 %2')
end

function A.xpContext(player,skillId,now)
    local current=A.current[player]
    if not current or not current.action then return nil end
    local seconds=SurvivorPhoneClock.realSeconds()
    if current.real and (seconds<current.real or seconds-current.real>8) then return nil end
    if current.world and now and (now.worldMinute<current.world or now.worldMinute-current.world>2) then return nil end
    local spec=A.actions[current.action.Type]
    if skillId=='Mechanics' and (not spec or spec[1]~='Mechanics XP') then return nil end
    if (skillId=='AnimalCare' or skillId=='Husbandry') and (not spec or spec[1]~='Animal care XP') then return nil end
    local key,label=actionDetail(current.action)
    if not key then return nil end
    return {key=key,label=label,type=current.action.Type,instance=tostring(current.action)}
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
