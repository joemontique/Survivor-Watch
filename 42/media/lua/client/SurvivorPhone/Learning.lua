require 'SurvivorPhone/Planner'
SurvivorPhoneLearning={sessions={}}
local L=SurvivorPhoneLearning
function L.ensure(root)
    root.learning=root.learning or {tasks={},ignored={},version=1}
    root.learning.activityDays=root.learning.activityDays or {}
    root.learning.recent=root.learning.recent or {}
    root.learning.groups=root.learning.groups or {}
    root.learning.decisions=root.learning.decisions or {}
    root.learning.skips=root.learning.skips or {}
    root.learning.audit=root.learning.audit or {}
    return root.learning
end
function L.observe(root,task,now,startMinute,duration,evidence)
    if not root.settings.learning then return end
    local all=L.ensure(root); local id=tostring(task.id)
    all.tasks[id]=all.tasks[id] or {}; local rows=all.tasks[id]
    -- At most one comparable observation per task/day. A lone XP tick never implies duration.
    if #rows>0 and rows[#rows].day==now.day then
        if duration and not rows[#rows].duration then rows[#rows]={day=now.day,minute=startMinute or now.minute,duration=duration,evidence=evidence} end
        return
    end
    table.insert(rows,{day=now.day,minute=startMinute or now.minute,duration=duration,evidence=evidence,arrivalVerified=startMinute~=nil})
    while #rows>20 do table.remove(rows,1) end
end
L.groups={ISPetAnimal='Animal care XP',ISMilkAnimal='Animal care XP',ISFeedAnimal='Animal care XP',
    ISInstallVehiclePart='Mechanics XP',ISUninstallVehiclePart='Mechanics XP',ISRepairVehiclePart='Mechanics XP',
    ISGeneratorInfoAction='Generator interaction',ISActivateGenerator='Generator interaction',
    ISPlugGenerator='Generator interaction',ISFixGenerator='Generator interaction',ISAddFuel='Generator interaction'}
function L.flush(player)
    local session=L.sessions[player];L.sessions[player]=nil
    local root=SurvivorPhoneData.get(player);if not root.settings.learning then return end
    local learning=L.ensure(root);learning.pending=nil
    if not session or not session.confirmed or session.last<session.start then return end
    local duration=session.last-session.start
    local record={day=session.day,minute=session.minute,duration=duration,group=session.group,needs=session.needs,name=session.name,xp=session.xp or 0}
    table.insert(learning.recent,record);while #learning.recent>40 do table.remove(learning.recent,1) end
    local function addDay(rows)
        local last=rows[#rows]
        if last and last.day==session.day then last.minute=math.min(last.minute,session.minute);last.duration=(last.duration or 0)+duration;last.xp=(last.xp or 0)+(session.xp or 0)
        else table.insert(rows,{day=record.day,minute=record.minute,duration=record.duration,needs=record.needs,xp=record.xp,arrivalVerified=true}) end
        while #rows>20 do table.remove(rows,1) end
    end
    local group=learning.groups[session.group] or {name=session.name or session.group,rows={}}
    learning.groups[session.group]=group;addDay(group.rows)
    local chosen,score
    for _,task in ipairs(SurvivorPhonePlanner.sorted(root.planner)) do
        if task.recognition==session.group then
            local value=math.abs((task.start or session.minute)-session.minute)
            if root.planner.day==session.day and SurvivorPhonePlanner.state(root.planner,task).status=='active' then value=-1 end
            if not score or value<score then chosen,score=task,value end
        end
    end
    if chosen then local id=tostring(chosen.id);learning.activityDays[id]=learning.activityDays[id] or {};addDay(learning.activityDays[id]) end
end
function L.touch(player,group,startWorld,endWorld,now,confirmed)
    local root=SurvivorPhoneData.get(player)
    if not root.settings.learning or startWorld>endWorld or endWorld-startWorld>1440 then return end
    local startMinute=now.minute-(now.worldMinute-startWorld)
    -- A daily slot cannot be inferred from a session crossing midnight.
    if startMinute<0 then L.flush(player);return end
    local session=L.sessions[player]
    if session and (session.group~=group or session.day~=now.day or startWorld-session.last>10 or endWorld<session.last) then L.flush(player);session=nil end
    if not session then
        local context={};for _,bar in ipairs((root.needs or {}).bars or {}) do context[bar.key]={level=bar.level,eta=bar.eta} end
        session={group=group,day=now.day,minute=startMinute,start=startWorld,last=endWorld,needs=context};L.sessions[player]=session
    end
    session.last=math.max(session.last,endWorld);session.confirmed=session.confirmed or confirmed
    local pending={};for k,v in pairs(session) do pending[k]=v end;L.ensure(root).pending=pending
end
function L.completeAction(action)
    if action._survivorObserved and not action._survivorLearningDone then
        action._survivorLearningDone=true
        local now=SurvivorPhoneClock.now()
        L.touch(action.character,action._survivorObserved.group,action._survivorObserved.world,now.worldMinute,now,true)
    end
end
function L.confirmXP(player,group)
    local s=L.sessions[player];if s and s.group==group then s.confirmed=true end
end
function L.observeXP(player,group,name,amount,now)
    local root=SurvivorPhoneData.get(player)
    if not root.settings.learning or player:isAsleep() or group=='Fishing catch' or group=='Skill:Fitness' or group=='Skill:Strength' then return end
    L.touch(player,group,now.worldMinute,now.worldMinute,now,true)
    local s=L.sessions[player]
    if s then s.name=name;s.xp=(s.xp or 0)+amount;L.ensure(root).pending.name=name;L.ensure(root).pending.xp=s.xp end
end
function L.recordPlannerAction(root,task,action,now)
    if not root.settings.learning then return end
    local learning=L.ensure(root);local key=tostring(task.id)
    learning.skips[key]=learning.skips[key] or {}
    if action=='skipped' then learning.skips[key][now.day]=true
    elseif action=='pending' or action=='done' or action=='start' then learning.skips[key][now.day]=nil end
    local days={};for day in pairs(learning.skips[key]) do table.insert(days,day) end;table.sort(days)
    while #days>30 do learning.skips[key][table.remove(days,1)]=nil end
end
function L.poll(player)
    local root,_,now=SurvivorPhoneData.get(player)
    local learning=L.ensure(root)
    if not root.settings.learning then L.sessions[player]=nil;learning.pending=nil;return end
    if learning.pending and not L.sessions[player] then L.sessions[player]=learning.pending;learning.pending=nil;L.flush(player) end
    if player:isAsleep() then L.flush(player);return end
    local fish=SurvivorPhoneFishing and SurvivorPhoneFishing.active[player]
    if fish and not fish.stop then L.touch(player,'Fishing catch',fish.world,now.worldMinute,now,false) end
    if ISTimedActionQueue then
        local queue=ISTimedActionQueue.getTimedActionQueue(player)
        local action=queue and queue.queue and queue.queue[1]
        if action and action.isStarted and action:isStarted() and not action._survivorLearningDone then
            local spec=SurvivorPhoneActivity and SurvivorPhoneActivity.actions[action.Type]
            local group=spec and spec[1] or L.groups[action.Type]
            if group then
                action._survivorObserved=action._survivorObserved or {world=now.worldMinute,group=group}
                L.touch(player,group,action._survivorObserved.world,now.worldMinute,now,false)
            end
        end
    end
    local session=L.sessions[player]
    if session and now.worldMinute-session.last>10 then L.flush(player) end
end
return L
