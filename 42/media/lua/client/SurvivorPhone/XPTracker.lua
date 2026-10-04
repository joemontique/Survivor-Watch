require 'SurvivorPhone/GameClock'
SurvivorPhoneXP={}
local X=SurvivorPhoneXP

local function trim(rows,max)
    while #rows>max do table.remove(rows,1) end
end

function X.ensure(root,day)
    root.xpTracker=root.xpTracker or {day=day,totals={},history={}}
    local t=root.xpTracker
    t.history=t.history or {}
    t.names=t.names or {}
    t.actions=t.actions or {}
    t.lastBySkill=t.lastBySkill or {}
    t.recentGains=t.recentGains or {}
    t.weight=t.weight or {samples={}}
    t.weight.samples=t.weight.samples or {}
    if t.day~=day then
        if t.day then t.history[t.day]=t.totals end
        t.day=day;t.totals={}
        local days={};for d in pairs(t.history) do table.insert(days,d) end;table.sort(days)
        while #days>30 do t.history[table.remove(days,1)]=nil end
    end
    t.totals=t.totals or {}
    return t
end

local function actionBucket(t,skill,level,key,label)
    if not key then return nil end
    t.actions[skill]=t.actions[skill] or {}
    local byLevel=t.actions[skill]
    local levelKey=tostring(level or -1)
    byLevel[levelKey]=byLevel[levelKey] or {}
    local bucket=byLevel[levelKey][key]
    if not bucket then
        bucket={key=key,label=label or key,level=level,samples={}}
        byLevel[levelKey][key]=bucket
    end
    bucket.label=label or bucket.label or key
    bucket.samples=bucket.samples or {}
    return bucket
end

local function closeEnough(a,b)
    if not a or not b then return false end
    local scale=math.max(math.abs(a),math.abs(b),0.01)
    return math.abs(a-b)<=math.max(0.05,scale*0.08)
end

function X.rate(bucket)
    local samples=bucket and bucket.samples or {}
    local n=#samples
    if n==0 then return nil,'Learning',false,0 end
    local last=samples[n].xp
    if n==1 then return last,'Learning',false,1 end
    local previous=samples[n-1].xp
    if not closeEnough(last,previous) then return last,'Updating',false,1 end
    local values={last,previous}
    for i=n-2,math.max(1,n-4),-1 do
        if closeEnough(samples[i].xp,last) then table.insert(values,samples[i].xp) else break end
    end
    local sum=0
    for _,value in ipairs(values) do sum=sum+value end
    local rate=sum/#values
    return rate,#values>=3 and 'Stable' or 'Estimated',true,#values
end

function X.add(root,day,skill,amount,name,meta)
    local t=X.ensure(root,day)
    if not amount or amount<=0 or amount~=amount then return end
    t.totals[skill]=(t.totals[skill] or 0)+amount
    t.names[skill]=name or skill
    meta=meta or {}
    local row={skill=skill,name=name or skill,xp=amount,day=day,minute=meta.minute,world=meta.world,
        level=meta.level,currentLevel=meta.currentLevel,actionKey=meta.actionKey,actionLabel=meta.actionLabel}
    t.lastBySkill[skill]=row
    table.insert(t.recentGains,row);trim(t.recentGains,40)
    if meta.actionKey and meta.level~=nil and meta.level<10 then
        local bucket=actionBucket(t,skill,meta.level,meta.actionKey,meta.actionLabel)
        table.insert(bucket.samples,{xp=amount,day=day,minute=meta.minute,world=meta.world})
        trim(bucket.samples,8)
        bucket.updatedDay=day;bucket.updatedMinute=meta.minute;bucket.updatedWorld=meta.world
    end
end

function X.total(t)
    local sum=0;for _,v in pairs(t or {}) do sum=sum+v end;return sum
end

function X.rows(t,names)
    local rows={}
    for k,v in pairs(t or {}) do
        if v>0 then table.insert(rows,{id=k,name=(names or {})[k] or k,xp=v}) end
    end
    table.sort(rows,function(a,b) if a.xp~=b.xp then return a.xp>b.xp end;return a.name<b.name end)
    return rows
end

function X.format(t)
    local rows={};for _,r in ipairs(X.rows(t)) do table.insert(rows,r.name..' +'..string.format('%.1f',r.xp)) end
    return #rows>0 and table.concat(rows,' / ') or 'No XP recorded'
end

function X.skillState(player,skill)
    if not player or not skill or not skill.perk then return nil end
    local definition=skill.definition
    local level=player:getPerkLevel(skill.perk)
    local total=player:getXp():getXP(skill.perk)
    if not definition or not definition.getXpForLevel then
        return {level=level,total=total,current=nil,cost=nil,remaining=nil,endTotal=nil,ratio=0,maxed=level>=10}
    end
    local startTotal=0
    for i=1,level do
        local ok,value=pcall(function() return definition:getXpForLevel(i) end)
        if ok and value then startTotal=startTotal+(tonumber(value) or 0) end
    end
    if level>=10 then
        return {level=level,total=total,startTotal=startTotal,endTotal=total,current=0,cost=0,remaining=0,ratio=1,maxed=true}
    end
    local ok,cost=pcall(function() return definition:getXpForLevel(level+1) end)
    cost=ok and tonumber(cost) or nil
    if not cost or cost<=0 then return {level=level,total=total,startTotal=startTotal,endTotal=nil,current=nil,cost=nil,remaining=nil,ratio=0,maxed=false} end
    local current=math.max(0,total-startTotal)
    local endTotal=startTotal+cost
    local remaining=math.max(0,endTotal-total)
    return {level=level,total=total,startTotal=startTotal,endTotal=endTotal,current=current,cost=cost,remaining=remaining,ratio=math.max(0,math.min(1,current/cost)),maxed=false}
end

function X.estimate(root,day,skill,level,remaining)
    local t=X.ensure(root,day)
    local last=t.lastBySkill[skill]
    if not last or last.level~=level or not last.actionKey then return nil end
    local bySkill=t.actions[skill]
    local byLevel=bySkill and bySkill[tostring(level)]
    local bucket=byLevel and byLevel[last.actionKey]
    if not bucket then return nil end
    local rate,confidence,confirmed,count=X.rate(bucket)
    local repeats=confirmed and rate and rate>0 and remaining and math.ceil(remaining/rate) or nil
    return {rate=rate,confidence=confidence,confirmed=confirmed,count=count,repeats=repeats,
        actionKey=bucket.key,actionLabel=bucket.label or last.actionLabel or bucket.key,last=last}
end

function X.observeWeight(root,day,worldMinute,player)
    local t=X.ensure(root,day)
    local nutrition=player and player:getNutrition()
    if not nutrition then return nil end
    local ok,weight=pcall(function() return nutrition:getWeight() end)
    if not ok or not weight or weight~=weight then return nil end
    local w=t.weight
    if not w.lastWorld or worldMinute<w.lastWorld or worldMinute-w.lastWorld>=60 then
        table.insert(w.samples,{day=day,world=worldMinute,weight=weight})
        trim(w.samples,96)
        w.lastWorld=worldMinute
    end
    w.current=weight
    return weight
end

function X.weightState(root,day,worldMinute,player)
    local weight=X.observeWeight(root,day,worldMinute,player)
    if not weight then return nil end
    local t=X.ensure(root,day)
    local nutrition=player:getNutrition()
    local trend='stable'
    local okLot,incLot=pcall(function() return nutrition:isIncWeightLot() end)
    local okInc,inc=pcall(function() return nutrition:isIncWeight() end)
    local okDec,dec=pcall(function() return nutrition:isDecWeight() end)
    if (okLot and incLot) or (okInc and inc) then trend='gaining'
    elseif okDec and dec then trend='losing' end
    local base
    for i=#t.weight.samples,1,-1 do
        local sample=t.weight.samples[i]
        if worldMinute-sample.world>=1440 then base=sample;break end
    end
    if not base then base=t.weight.samples[1] end
    local delta=base and weight-base.weight or 0
    if trend=='stable' then
        if delta>=0.2 then trend='gaining' elseif delta<=-0.2 then trend='losing' end
    end
    return {weight=weight,trend=trend,delta=delta,base=base and base.weight or weight}
end

function X.wake(root,now)
    local t=X.ensure(root,now.day)
    if t.lastWakeDay==now.day then return nil end
    t.lastWakeDay=now.day
    local day=SurvivorPhoneClock.previousDay(now.day)
    t.wakeReport={day=day,totals=t.history[day] or {},recorded=t.history[day]~=nil}
    return t.wakeReport
end

return X
