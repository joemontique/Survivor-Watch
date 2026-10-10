require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/XPTracker'
require 'SurvivorPhone/Learning'
require 'SurvivorPhone/Activity'
require 'SurvivorPhone/SleepCoach'
SurvivorPhoneRecognition={snapshots={},levels={},sleeping={},perks=nil}
local A=SurvivorPhoneRecognition
function A.skillList()
    if A.perks then return A.perks end
    A.perks={}
    for i=0,PerkFactory.PerkList:size()-1 do
        local perk=PerkFactory.PerkList:get(i)
        if perk:getParent()~=Perks.None then
            table.insert(A.perks,{id=perk:getId(),name=perk:getName(),perk=perk:getType(),definition=perk})
            if perk:getId()~='Fishing' and perk:getId()~='Fitness' and perk:getId()~='Strength' and perk:getId()~='AnimalCare' and perk:getId()~='Husbandry' and perk:getId()~='Mechanics' and perk:getId()~='Carving' then
                local rule='Skill:'..perk:getId();local exists=false
                for _,value in ipairs(SurvivorPhonePlanner.recognitions) do if value==rule then exists=true end end
                if not exists then table.insert(SurvivorPhonePlanner.recognitions,rule) end
            end
        end
    end
    return A.perks
end
function A.result(player,rule,evidence,startMinute,duration)
    local root,planner,now=SurvivorPhoneData.get(player)
    SurvivorPhoneActivity.record(player,rule,evidence,now)
    if rule=='Generator interaction' then SurvivorPhoneLearning.touch(player,rule,now.worldMinute,now.worldMinute,now,true) end
    if not startMinute then
        for _,candidate in ipairs(SurvivorPhonePlanner.sorted(planner)) do
            local s=SurvivorPhonePlanner.state(planner,candidate)
            if candidate.recognition==rule and s.status~='done' and s.status~='skipped' then
                startMinute=s.startedAt
                duration=startMinute and now.minute>=startMinute and now.minute-startMinute or nil
                break
            end
        end
    end
    local task=SurvivorPhonePlanner.recognize(planner,rule,now.minute,evidence)
    if task then
        SurvivorPhoneLearning.observe(root,task,now,startMinute,duration,evidence)
        if SurvivorPhoneNotifications then SurvivorPhoneNotifications.emit(player,'routine','done:'..task.id..':'..now.day,task.name..' completed','planner') end
    end
    return task
end
function A.scan(player)
    if not player or isClient() or isServer() or player:isDead() then return end
    local root,_,now=SurvivorPhoneData.get(player)
    local tracker=SurvivorPhoneXP.ensure(root,now.day)
    SurvivorPhoneXP.observeWeight(root,now.day,now.worldMinute,player)
    local old=A.snapshots[player] or {};A.snapshots[player]=old
    local levels=A.levels[player] or {};A.levels[player]=levels
    local rules={AnimalCare='Animal care XP',Husbandry='Animal care XP',Mechanics='Mechanics XP',Carving='Carving XP'}
    for _,skill in ipairs(A.skillList()) do
        tracker.names[skill.id]=skill.name
        local value=player:getXp():getXP(skill.perk)
        local level=player:getPerkLevel(skill.perk)
        local previousLevel=levels[skill.id]
        if previousLevel==nil then previousLevel=level end
        if old[skill.id] and value>old[skill.id] then
            local amount=value-old[skill.id]
            local action=SurvivorPhoneActivity.xpContext(player,skill.id,now)
            local sameLevel=previousLevel==level
            SurvivorPhoneXP.add(root,now.day,skill.id,amount,skill.name,{
                minute=now.minute,world=now.worldMinute,level=previousLevel,currentLevel=level,
                actionKey=sameLevel and action and action.key or nil,
                actionLabel=sameLevel and action and action.label or nil,
                actionInstance=sameLevel and action and action.instance or nil
            })
            if skill.id~='Fishing' and skill.id~='Fitness' and skill.id~='Strength' then
                local rule=rules[skill.id] or 'Skill:'..skill.id
                SurvivorPhoneLearning.observeXP(player,rule,skill.name,amount,now)
                if not rules[skill.id] then A.result(player,rule,skill.name..' XP gained') end
            end
            if rules[skill.id] then
                SurvivorPhoneLearning.confirmXP(player,rules[skill.id])
                A.result(player,rules[skill.id],skill.name..' XP gained')
            end
        end
        old[skill.id]=value
        levels[skill.id]=level
    end
    local asleep=player:isAsleep()
    if A.sleeping[player]~=true and asleep then
        SurvivorPhoneSleepCoach.onSleepStarted(player,now)
    elseif A.sleeping[player]==true and not asleep then
        SurvivorPhoneSleepCoach.onWake(player,now)
        A.result(player,'Sleep completed','Observed sleep followed by waking')
        local report=SurvivorPhoneXP.wake(root,now)
        if report and SurvivorPhoneNotifications then
            local message=report.recorded and ('Morning report: '..string.format('%.1f',SurvivorPhoneXP.total(report.totals))..' XP on '..report.day) or ('Morning report: no record for '..report.day)
            SurvivorPhoneNotifications.emit(player,'wake','wake:'..now.day,message,'skills')
        end
    end
    A.sleeping[player]=asleep
end
return A
