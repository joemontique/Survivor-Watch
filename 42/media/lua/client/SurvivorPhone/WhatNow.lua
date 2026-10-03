require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/Travel'
require 'SurvivorPhone/SleepCoach'
SurvivorPhoneWhatNow={}
local W=SurvivorPhoneWhatNow
local P=SurvivorPhonePlanner
local needs={hunger={title='Make time to eat'},thirst={title='Make time to drink'},fatigue={title='Plan some rest'},endurance={title='Recover your stamina'}}
function W.ensure(root)
    root.guidance=root.guidance or {hidden={}}
    root.guidance.hidden=root.guidance.hidden or {}
    return root.guidance
end
local function allowed(root,item,now)
    local data=W.ensure(root)
    for key,entry in pairs(data.hidden) do
        if entry.day~=now.day or entry.untilMinute and entry.untilMinute<=now.worldMinute then data.hidden[key]=nil end
    end
    return not data.hidden[item.key]
end
function W.decide(root,item,decision,now)
    if not item or not item.key then return end
    W.ensure(root).hidden[item.key]={day=now.day,untilMinute=decision=='snooze' and now.worldMinute+30 or nil}
end
function W.choose(root,now,player)
    if player and player:isAsleep() then return {key='sleep',title='Rest and recover',reason='Forecasts will recalibrate after you wake.',app='home',passive=true} end
    local sleep=player and SurvivorPhoneSleepCoach.card(root,now,player)
    if sleep and allowed(root,sleep,now) then return sleep end
    local items={};local lead=root.settings.leadMinutes or 30
    for _,bar in ipairs((root.needs or {}).bars or {}) do
        local spec=needs[bar.key]
        if spec and (bar.level>0 and (bar.key~='endurance' or bar.level>=2) or bar.eta and bar.eta<=lead) then
            local reached=bar.level>0
            local reason=reached and (bar.status..' is active. Check your '..(bar.key=='fatigue' and 'rest' or bar.label:lower())..' before a long activity.')
                or (bar.warning..' is estimated in '..SurvivorPhoneClock.irlEta(bar.eta)..'. Leave a '..lead..'-minute game-time buffer.')
            table.insert(items,{key='need:'..bar.key..':'..bar.level,title=spec.title,reason=reason,app='home',need=bar.key,
                rank=reached and 100+bar.level*10+((bar.key=='thirst' or bar.key=='hunger') and bar.level>=3 and 30 or 0) or 80+(lead-bar.eta)/math.max(1,lead),urgent=true})
        end
    end
    table.sort(items,function(a,b) if a.rank~=b.rank then return a.rank>b.rank end;return a.key<b.key end)
    for _,item in ipairs(items) do if allowed(root,item,now) then return item end end
    if root.planner.freeRoam then return {key='free',title='Room to roam',reason='Routine guidance is quiet. Your condition, XP and activity observations still update.',app='planner',passive=true} end
    local active=player and SurvivorPhoneFishing and SurvivorPhoneFishing.active[player]
    if active then
        local item={key='fishing',title=active.stop and 'Finish landing this catch' or 'Stay with this cast',reason='Fishing is underway. Real elapsed cast time is recorded in Progress.',app='skills'}
        if allowed(root,item,now) then return item end
    end
    local observed=player and SurvivorPhoneActivity and SurvivorPhoneActivity.getCurrent(player,now)
    if observed then
        local item={key='detected:'..observed.rule,title=(observed.confirmed and 'Continue ' or 'In progress: ')..observed.name,
            reason=observed.confirmed and ('Confirmed: '..observed.evidence..'. Tracking continues after planner completion.') or 'This activity is underway. It will only complete a matching task when its result is confirmed.',app='planner'}
        if allowed(root,item,now) then return item end
    end
    local session=player and SurvivorPhoneLearning and SurvivorPhoneLearning.sessions[player]
    if session and session.confirmed and now.worldMinute>=session.last and now.worldMinute-session.last<=10 then
        local item={key='activity:'..session.group,title='Continue '..(session.name or session.group),reason='Recent activity is still being observed, even if its planner task is already done.',app='planner'}
        if allowed(root,item,now) then return item end
    end
    local ranked={}
    local pos=player and SurvivorPhoneTravel.position(player)
    local passed=0
    for _,task in ipairs(P.sorted(root.planner)) do
        local state=P.state(root.planner,task)
        if state.status~='done' and state.status~='skipped' and not (state.snoozeUntil and now.minute<state.snoozeUntil) then
            local due=state.snoozeUntil or task.start
            local expired=task.finish and now.minute>=task.finish and state.status~='active'
            if expired then passed=passed+1 end
            local rank=state.status=='active' and 120 or expired and 5 or due and due<=now.minute and 70 or due and due<=now.minute+lead and 50 or not due and 40 or 20
            rank=rank+(task.priority=='High' and 14 or task.priority=='Low' and -8 or 0)-(task.kind=='Optional' and 12 or 0)
            local place=SurvivorPhoneTravel.find(root,task.placeId)
            local distance=place and pos and SurvivorPhoneTravel.distance(place,pos)
            if distance and not expired then rank=rank+(distance<=12 and place.z==pos.z and 6 or distance<=100 and 2 or 0) end
            local remaining=task.finish and task.finish-now.minute
            if not expired and remaining and remaining>0 and remaining<=lead then rank=rank+8 end
            table.insert(ranked,{task=task,state=state,rank=rank,due=due or 1440,expired=expired,place=place,remaining=remaining})
        end
    end
    table.sort(ranked,function(a,b) if a.rank~=b.rank then return a.rank>b.rank end;if a.due~=b.due then return a.due<b.due end;return a.task.id<b.task.id end)
    for _,row in ipairs(ranked) do
        local task,state=row.task,row.state
        local why=state.status=='active' and 'You started this activity. Continue when it suits you.'
            or row.expired and ('Its window has passed. You can still finish it today, or skip it if it no longer fits.')
            or task.start and (row.due<=now.minute and ('Planned for '..P.time(row.due)..'. '..(task.priority=='High' and 'A high-priority activity.' or 'Still available today.')) or ('Next scheduled for '..P.time(row.due)..'. There is time to prepare.'))
            or 'An anytime activity from your plan.'
        if row.remaining and row.remaining>0 then why=why..' Window ends at '..P.time(task.finish)..'.' end
        if task.kind=='Optional' then why=why..' This activity is optional.' end
        if not row.expired and passed>0 then why=why..' '..passed..' earlier window'..(passed==1 and ' has' or 's have')..' passed.' end
        if row.place then why=why..' '..SurvivorPhoneTravel.describe(row.place,pos)..'. Last visited '..row.place.lastDay..' at '..P.time(row.place.lastMinute)..'.' end
        local item={key='task:'..task.id..':'..state.status,title=task.name,reason=why,app='planner',taskId=task.id}
        if allowed(root,item,now) then return item end
    end
    return {key='clear',title='Your next move is yours',reason='No more guidance needs your attention right now. Review your plan or enjoy some free time.',app='planner',passive=true}
end
return W
