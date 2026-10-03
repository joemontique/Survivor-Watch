require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/Notifications'

SurvivorPhoneSleepCoach={sleeping={}}
local S=SurvivorPhoneSleepCoach
local P=SurvivorPhonePlanner
local C=SurvivorPhoneClock

local function clamp(v,a,b) return math.max(a,math.min(b,v or a)) end
local function dayMinute(worldMinute) return math.floor(worldMinute%1440+0.5)%1440 end
local function round5(value) return math.floor(value/5+0.5)*5 end
local function median(values)
    table.sort(values)
    local n=#values
    if n==0 then return nil end
    return n%2==1 and values[(n+1)/2] or (values[n/2]+values[n/2+1])/2
end
local function lateBy(minute,bedtime)
    local value=(minute-bedtime+1440)%1440
    return value<=720 and value or -1
end
local function learnedMinute(rows,key,fallback)
    local values={}
    for i=#rows,1,-1 do
        local r=rows[i]
        if r and r[key] then
            local value=r[key]
            if key=='sleepMinute' and value<720 then value=value+1440 end
            table.insert(values,value)
            if #values>=10 then break end
        end
    end
    if #values<3 then return fallback,false,#values end
    return round5(median(values))%1440,true,#values
end
local function fatigueState(player)
    local fatigue,level=0,0
    if player and player.getStats then
        local ok,value=pcall(function() return player:getStats():get(CharacterStat.FATIGUE) end)
        fatigue=ok and tonumber(value) or 0
    end
    if player and player.getMoodles then
        local ok,value=pcall(function() return player:getMoodles():getMoodleLevel(MoodleType.TIRED) end)
        level=ok and tonumber(value) or 0
    end
    return fatigue or 0,level or 0
end
local function inventoryItems(player)
    local inv=player and player.getInventory and player:getInventory()
    local items=inv and inv.getItems and inv:getItems()
    if not items or not items.size or not items.get then return function() end end
    local i,n=0,items:size()
    return function()
        if i>=n then return nil end
        local item=items:get(i);i=i+1;return item
    end
end
local function canUseAlarm(item)
    if not item then return false end
    if not (item.setAlarmSet and item.setHour and item.setMinute and item.syncAlarmClock) then return false end
    if item.isDigital then
        local ok,value=pcall(function() return item:isDigital() end)
        if ok and value==false then return false end
    end
    if instanceof then
        local ok,value=pcall(function() return instanceof(item,'AlarmClock') or instanceof(item,'AlarmClockClothing') end)
        if ok and value then return true end
    end
    return true
end
local function nameOf(item)
    if not item then return nil end
    if item.getDisplayName then local ok,value=pcall(function() return item:getDisplayName() end);if ok and value then return value end end
    if item.getName then local ok,value=pcall(function() return item:getName() end);if ok and value then return value end end
    if item.getFullType then local ok,value=pcall(function() return item:getFullType() end);if ok and value then return value end end
    return 'alarm item'
end
local function idOf(item)
    if item and item.getID then local ok,value=pcall(function() return item:getID() end);if ok and value~=nil then return tostring(value) end end
end
local function typeOf(item)
    if item and item.getFullType then local ok,value=pcall(function() return item:getFullType() end);if ok then return value end end
end
local function alarmState(item)
    local state={}
    if item and item.isAlarmSet then local ok,value=pcall(function() return item:isAlarmSet() end);if ok then state.alarmSet=value==true end end
    if item and item.getHour then local ok,value=pcall(function() return item:getHour() end);if ok then state.hour=tonumber(value) end end
    if item and item.getMinute then local ok,value=pcall(function() return item:getMinute() end);if ok then state.minute=tonumber(value) end end
    return state
end
local function findAlarmItem(player,alarm)
    if not player or not alarm then return nil end
    local fallback
    for item in inventoryItems(player) do
        if canUseAlarm(item) then
            local id=idOf(item)
            if alarm.itemId and id==tostring(alarm.itemId) then return item end
            if not alarm.itemId and not fallback and alarm.itemType and typeOf(item)==alarm.itemType and nameOf(item)==alarm.item then fallback=item end
        end
    end
    return fallback
end
local function forceWakeTime(player)
    if player and player.getForceWakeUpTime then
        local ok,value=pcall(function() return player:getForceWakeUpTime() end)
        if ok then return tonumber(value) end
    end
end
local function playerForRoot(root)
    if not root or not getNumActivePlayers or not getSpecificPlayer then return nil end
    local count=getNumActivePlayers()
    for i=0,count-1 do
        local player=getSpecificPlayer(i)
        if player and player.getModData then
            local ok,mod=pcall(function() return player:getModData() end)
            if ok and mod and mod.SurvivorPhone==root then return player end
        end
    end
end

function S.ensure(root)
    root.sleepCoach=root.sleepCoach or {version=1,history={},alarm={}}
    local sc=root.sleepCoach
    sc.history=sc.history or {}
    sc.alarm=sc.alarm or {}
    sc.version=3
    return sc
end

function S.targets(root)
    local sc=S.ensure(root)
    local s=root.settings or {}
    local bed,bedLearned,bedCount=learnedMinute(sc.history,'sleepMinute',s.sleepTargetBedtime or 1380)
    local wake,wakeLearned,wakeCount=learnedMinute(sc.history,'wakeMinute',s.sleepTargetWake or 420)
    return bed,wake,{bedLearned=bedLearned,wakeLearned=wakeLearned,bedCount=bedCount,wakeCount=wakeCount}
end

function S.naturalSleepHours(fatigue,player)
    local hours=7+5*((clamp(fatigue or 0,0,1)-0.3)/0.7)
    if player and player.hasTrait then
        local okInsomniac,insomniac=pcall(function() return player:hasTrait(CharacterTrait.INSOMNIAC) end)
        local okLess,less=pcall(function() return player:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) end)
        local okMore,more=pcall(function() return player:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) end)
        if okInsomniac and insomniac then hours=hours*0.5 end
        if okLess and less then hours=hours*0.75 end
        if okMore and more then hours=hours*1.18 end
    end
    return clamp(hours,3,16)
end

function S.plan(root,now,player)
    local sc=S.ensure(root)
    local s=root.settings or {}
    local fatigue,level=fatigueState(player)
    local bedtime,wake,learned=S.targets(root)
    local natural=S.naturalSleepHours(fatigue,player)
    local minHours=s.sleepResetMinHours or 3
    local maxHours=s.sleepResetMaxHours or 6.5
    local base=math.floor(now.worldMinute/1440)*1440+wake
    while base<now.worldMinute+minHours*60 do base=base+1440 end
    local untilWake=(base-now.worldMinute)/60
    local duration=clamp(untilWake,minHours,maxHours)
    if untilWake>maxHours then duration=clamp(math.min(natural-1,maxHours),minHours,maxHours) end
    local targetWorld=now.worldMinute+duration*60
    local targetMinute=dayMinute(targetWorld)
    local naturalWake=dayMinute(now.worldMinute+natural*60)
    local afterBed=lateBy(now.minute,bedtime)
    local naturalWakeLate=(naturalWake-wake+1440)%1440
    local wouldLoseMorning=naturalWakeLate>=120 and naturalWakeLate<=720
    local tiredEnough=fatigue>=0.45 or level>=1
    local suggested=s.sleepResetEnabled~=false and tiredEnough and (afterBed>=60 or wouldLoseMorning)
    local reason
    if afterBed>=60 then reason='You are '..math.floor(afterBed/60)..'h '..(afterBed%60)..'m past the protected bedtime.'
    elseif wouldLoseMorning then reason='A full sleep is likely to push wake-up late into the day.'
    else reason='Your current sleep timing looks close enough to routine.' end
    return {bedtime=bedtime,wake=wake,learned=learned,naturalHours=natural,duration=duration,targetWorld=targetWorld,
        targetMinute=targetMinute,targetHour=targetMinute/60,fatigue=fatigue,level=level,suggested=suggested,reason=reason,
        summary='Wake around '..P.time(targetMinute)..' after about '..C.irlEta(duration*60)..'.'}
end

function S.syncAlarmItem(player,targetMinute,alarm)
    local hour=math.floor(targetMinute/60)%24
    local minute=targetMinute%60
    local item=findAlarmItem(player,alarm)
    if alarm and alarm.itemId and not item then
        return false,{previousAlarm=alarm.previousAlarm,error='The alarm item used by Sleep Reset is no longer carried.'}
    end
    if not item then
        for candidate in inventoryItems(player) do if canUseAlarm(candidate) then item=candidate;break end end
    end
    if not item then return false,{previousAlarm=alarm and alarm.previousAlarm or nil,error='No carried digital watch or alarm clock found.'} end
    local previous=alarm and alarm.previousAlarm or alarmState(item)
    local ok,err=pcall(function()
        item:setHour(hour)
        item:setMinute(minute)
        item:setAlarmSet(true)
        item:syncAlarmClock()
    end)
    return ok,{item=nameOf(item),itemId=idOf(item),itemType=typeOf(item),previousAlarm=previous,error=not ok and tostring(err) or nil}
end

function S.applyWake(player,plan,alarm)
    local result={forceWake=false,itemSynced=false,previousForceWake=alarm and alarm.previousForceWake or forceWakeTime(player)}
    if player and player.setForceWakeUpTime then
        local ok=pcall(function() player:setForceWakeUpTime(tonumber(plan.targetHour or plan.targetMinute/60)) end)
        result.forceWake=ok
    end
    local ok,item=S.syncAlarmItem(player,plan.targetMinute,alarm)
    result.itemSynced=ok
    result.item=item and item.item or alarm and alarm.item or nil
    result.itemId=item and item.itemId or alarm and alarm.itemId or nil
    result.itemType=item and item.itemType or alarm and alarm.itemType or nil
    result.previousAlarm=item and item.previousAlarm or alarm and alarm.previousAlarm or nil
    result.itemError=item and item.error or nil
    result.lastSyncReal=C.realSeconds()
    return result
end

function S.restoreNative(player,alarm)
    if not player or not alarm then return {forceWake=false,item=false} end
    local result={forceWake=false,item=false}
    if alarm.previousForceWake~=nil and player.setForceWakeUpTime then
        result.forceWake=pcall(function() player:setForceWakeUpTime(alarm.previousForceWake) end)
    end
    local item=findAlarmItem(player,alarm)
    local previous=alarm.previousAlarm
    if item and previous then
        result.item=pcall(function()
            if previous.hour~=nil then item:setHour(previous.hour) end
            if previous.minute~=nil then item:setMinute(previous.minute) end
            if previous.alarmSet~=nil then item:setAlarmSet(previous.alarmSet) end
            item:syncAlarmClock()
        end)
    end
    return result
end

function S.arm(player)
    local root,_,now=SurvivorPhoneData.get(player)
    local plan=S.plan(root,now,player)
    local sc=S.ensure(root)
    if sc.alarm and sc.alarm.armed then S.restoreNative(player,sc.alarm) end
    local sync=S.applyWake(player,plan,nil)
    sc.alarm={armed=true,active=false,day=now.day,armedMinute=now.minute,armedWorld=now.worldMinute,
        targetMinute=plan.targetMinute,targetWorld=plan.targetWorld,duration=plan.duration,bedtime=plan.bedtime,wake=plan.wake,
        reason=plan.reason,forceWake=sync.forceWake,itemSynced=sync.itemSynced,item=sync.item,itemId=sync.itemId,itemType=sync.itemType,
        previousForceWake=sync.previousForceWake,previousAlarm=sync.previousAlarm,itemError=sync.itemError,lastSyncReal=sync.lastSyncReal}
    if SurvivorPhoneNotifications then
        local msg='Sleep Reset armed for '..P.time(plan.targetMinute)..'. '..(sync.itemSynced and 'Watch/alarm synced.' or 'Tracker alarm will handle it.')
        SurvivorPhoneNotifications.emit(player,'sleep','sleep-reset:'..now.day..':'..now.minute,msg,'home')
    end
    return sc.alarm
end

function S.cancel(root,player,reason)
    local sc=S.ensure(root)
    local old=sc.alarm or {}
    player=player or playerForRoot(root)
    local restored=S.restoreNative(player,old)
    local now=SurvivorPhoneClock.now()
    sc.alarm={armed=false,active=false,cancelledDay=now and now.day or nil,cancelledMinute=now and now.minute or nil,
        cancelReason=reason or 'cancelled',restoredForceWake=restored.forceWake,restoredItem=restored.item}
    return sc.alarm
end

function S.perform(player,action)
    if action=='arm' then return S.arm(player) end
    if action=='cancel' then local root=SurvivorPhoneData.get(player);S.cancel(root,player,'user');return true end
end

function S.onSleepStarted(player,now)
    local root=SurvivorPhoneData.get(player)
    local sc=S.ensure(root)
    if sc.current and now.worldMinute-(sc.current.startWorld or now.worldMinute)>0 and now.worldMinute-(sc.current.startWorld or now.worldMinute)<60 then return end
    local fatigue,level=fatigueState(player)
    local alarm=sc.alarm or {}
    if alarm.armed then
        local plan=S.plan(root,now,player)
        local sync=S.applyWake(player,plan,alarm)
        alarm.active=true;alarm.sleepStart=now.worldMinute;alarm.sleepDay=now.day
        alarm.targetMinute=plan.targetMinute;alarm.targetWorld=plan.targetWorld;alarm.duration=plan.duration
        alarm.forceWake=sync.forceWake;alarm.itemSynced=sync.itemSynced;alarm.item=sync.item;alarm.itemId=sync.itemId;alarm.itemType=sync.itemType
        alarm.previousForceWake=alarm.previousForceWake~=nil and alarm.previousForceWake or sync.previousForceWake
        alarm.previousAlarm=alarm.previousAlarm or sync.previousAlarm
        alarm.itemError=sync.itemError;alarm.lastSyncReal=sync.lastSyncReal
        sc.alarm=alarm
    end
    sc.current={day=now.day,startMinute=now.minute,startWorld=now.worldMinute,fatigue=fatigue,level=level,reset=alarm.armed==true,
        targetMinute=alarm.targetMinute,duration=alarm.duration}
end

function S.onWake(player,now)
    local root=SurvivorPhoneData.get(player)
    local sc=S.ensure(root)
    local current=sc.current
    if current and now.worldMinute>=current.startWorld then
        local fatigue,level=fatigueState(player)
        table.insert(sc.history,{day=current.day,wakeDay=now.day,sleepMinute=current.startMinute,wakeMinute=now.minute,
            startWorld=current.startWorld,wakeWorld=now.worldMinute,duration=now.worldMinute-current.startWorld,
            fatigueBefore=current.fatigue,fatigueAfter=fatigue,levelBefore=current.level,levelAfter=level,reset=current.reset==true,
            targetMinute=current.targetMinute})
        while #sc.history>40 do table.remove(sc.history,1) end
    end
    sc.current=nil
    if sc.alarm and sc.alarm.active then
        local alarm=sc.alarm
        local restored=S.restoreNative(player,alarm)
        alarm.armed=false;alarm.active=false;alarm.completedDay=now.day;alarm.completedMinute=now.minute
        alarm.restoredForceWake=restored.forceWake;alarm.restoredItem=restored.item
        if SurvivorPhoneNotifications then
            SurvivorPhoneNotifications.emit(player,'sleep','sleep-reset-wake:'..now.day,'Sleep Reset woke you around '..P.time(now.minute)..'. Routine learning will use this wake-up.', 'home')
        end
    end
end

function S.poll(player)
    local root,_,now=SurvivorPhoneData.get(player)
    local sc=S.ensure(root)
    local alarm=sc.alarm or {}
    if alarm.armed and player:isAsleep() then
        local seconds=C.realSeconds()
        local needsRetry=alarm.forceWake~=true or alarm.itemSynced~=true
        local canRetry=not alarm.lastSyncReal or seconds<alarm.lastSyncReal or seconds-alarm.lastSyncReal>=5
        if needsRetry and canRetry then
            local sync=S.applyWake(player,{targetMinute=alarm.targetMinute,targetHour=(alarm.targetMinute or 0)/60},alarm)
            alarm.forceWake=sync.forceWake;alarm.itemSynced=sync.itemSynced;alarm.item=sync.item;alarm.itemId=sync.itemId;alarm.itemType=sync.itemType
            alarm.previousForceWake=alarm.previousForceWake~=nil and alarm.previousForceWake or sync.previousForceWake
            alarm.previousAlarm=alarm.previousAlarm or sync.previousAlarm
            alarm.itemError=sync.itemError;alarm.lastSyncReal=sync.lastSyncReal;sc.alarm=alarm
        end
    elseif alarm.armed and now.worldMinute-(alarm.armedWorld or now.worldMinute)>720 then
        S.cancel(root,player,'expired')
    end
end

function S.card(root,now,player)
    local sc=S.ensure(root)
    local alarm=sc.alarm or {}
    if alarm.armed then
        return {key='sleep-reset:armed',title='Sleep Reset armed',reason='Alarm target '..P.time(alarm.targetMinute)..'. It will wake you after about '..C.irlEta((alarm.duration or 0)*60)..' so tomorrow does not slide away.',app='home',sleepAction='cancel',urgent=true}
    end
    local plan=S.plan(root,now,player)
    if plan.suggested then
        return {key='sleep-reset:'..P.time(plan.targetMinute),title='Use Sleep Reset',reason=plan.reason..' '..plan.summary..' This is a conservative reset, not a full-night rest.',app='home',sleepAction='arm',urgent=true}
    end
end

return S
