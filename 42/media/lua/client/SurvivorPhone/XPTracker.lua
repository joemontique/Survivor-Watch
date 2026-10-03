require 'SurvivorPhone/GameClock'
SurvivorPhoneXP={}
local X=SurvivorPhoneXP
function X.ensure(root,day)
    root.xpTracker=root.xpTracker or {day=day,totals={},history={}}
    local t=root.xpTracker; t.history=t.history or {}; t.names=t.names or {}
    if t.day~=day then
        if t.day then t.history[t.day]=t.totals end
        t.day=day; t.totals={}
        local days={}; for d in pairs(t.history) do table.insert(days,d) end; table.sort(days)
        while #days>30 do t.history[table.remove(days,1)]=nil end
    end
    t.totals=t.totals or {}; return t
end
function X.add(root,day,skill,amount,name)
    local t=X.ensure(root,day)
    if amount>0 and amount==amount then t.totals[skill]=(t.totals[skill] or 0)+amount; t.names[skill]=name or skill end
end
function X.total(t) local sum=0;for _,v in pairs(t or {}) do sum=sum+v end;return sum end
function X.rows(t,names)
    local rows={}; for k,v in pairs(t or {}) do if v>0 then table.insert(rows,{id=k,name=(names or {})[k] or k,xp=v}) end end
    table.sort(rows,function(a,b) if a.xp~=b.xp then return a.xp>b.xp end; return a.name<b.name end)
    return rows
end
function X.format(t) local rows={};for _,r in ipairs(X.rows(t)) do table.insert(rows,r.name..' +'..string.format('%.1f',r.xp)) end;return #rows>0 and table.concat(rows,' / ') or 'No XP recorded' end
function X.wake(root,now)
    local t=X.ensure(root,now.day)
    if t.lastWakeDay==now.day then return nil end
    t.lastWakeDay=now.day
    local day=SurvivorPhoneClock.previousDay(now.day)
    t.wakeReport={day=day,totals=t.history[day] or {},recorded=t.history[day]~=nil}
    return t.wakeReport
end
return X
