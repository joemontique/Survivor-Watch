require 'SurvivorPhone/SaveData'
SurvivorPhoneFishing={active={},version=4}
local F=SurvivorPhoneFishing
function F.ensure(root,day)
    if not root.fishing or root.fishing.statsVersion~=F.version then
        -- The old counter mixed game hours, epoch milliseconds and skill levels.
        -- Reset fishing only, once. Never touch XP totals or the player's schedule.
        root.fishing={statsVersion=F.version,casts=0,successful=0,empty=0,interrupted=0,
            totalSeconds=0,successSeconds=0,timed=0,successTimed=0,recent={},day=day,today={casts=0,successful=0}}
    end
    local d=root.fishing
    if d.day~=day then d.day=day;d.today={casts=0,successful=0} end
    return d
end
function F.begin(player,seconds,now)
    if F.active[player] then F.finish(player,'interrupted',seconds,now) end
    F.active[player]={start=seconds,day=now.day,minute=now.minute,world=now.worldMinute}
end
function F.reeled(player,seconds)
    local s=F.active[player]; if s and not s.stop then s.stop=seconds end
end
function F.finish(player,outcome,seconds,now)
    local s=F.active[player];if not s then return nil end
    F.active[player]=nil
    local root=SurvivorPhoneData.get(player);local d=F.ensure(root,now.day)
    local duration=(s.stop or seconds)-s.start
    local valid=duration>=0 and duration<=10800 and duration==duration
    local success=outcome=='success'
    d.casts=d.casts+1;d.today.casts=d.today.casts+1
    if success then d.successful=d.successful+1;d.today.successful=d.today.successful+1
    elseif outcome=='empty' then d.empty=d.empty+1 else d.interrupted=d.interrupted+1 end
    if valid then
        d.totalSeconds=d.totalSeconds+duration;d.timed=d.timed+1
        if success then d.successSeconds=d.successSeconds+duration;d.successTimed=d.successTimed+1 end
    end
    local row={seconds=valid and duration or nil,successful=success,outcome=outcome,day=now.day}
    table.insert(d.recent,row);while #d.recent>20 do table.remove(d.recent,1) end
    if SurvivorPhoneLearning and s.day==now.day and now.worldMinute>=s.world then
        SurvivorPhoneLearning.touch(player,'Fishing catch',s.world,now.worldMinute,now,true)
    end
    if success and SurvivorPhoneRecognition then
        -- A single cast is not the duration of a planned fishing session.
        SurvivorPhoneRecognition.result(player,'Fishing catch','Catch received + Fishing XP')
    end
    return row
end
function F.recentAverage(d,successOnly)
    local sum,count=0,0
    for _,r in ipairs(d.recent) do
        if r.seconds and (not successOnly or r.successful) then sum=sum+r.seconds;count=count+1 end
    end
    return count>0 and sum/count or nil,count
end
function F.update(player)
    local root,_,now=SurvivorPhoneData.get(player);F.ensure(root,now.day)
    if player:isDead() then F.active[player]=nil end
end
return F
