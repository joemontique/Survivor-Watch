require 'SurvivorPhone/XPTracker'
local X=SurvivorPhoneXP

local function trim(rows,max)
    while #rows>max do table.remove(rows,1) end
end

local function bucket(t,skill,level,key,label)
    if not key or level==nil then return nil end
    t.actions[skill]=t.actions[skill] or {}
    local levelKey=tostring(level)
    t.actions[skill][levelKey]=t.actions[skill][levelKey] or {}
    local b=t.actions[skill][levelKey][key]
    if not b then
        b={key=key,label=label or key,level=level,samples={}}
        t.actions[skill][levelKey][key]=b
    end
    b.label=label or b.label or key
    b.samples=b.samples or {}
    return b
end

function X.observeActionResult(root,day,skill,amount,name,meta)
    meta=meta or {}
    amount=tonumber(amount)
    if not amount or amount<0 or amount~=amount or not meta.actionKey or meta.level==nil then return end
    local t=X.ensure(root,day)
    t.names[skill]=name or t.names[skill] or skill
    local b=bucket(t,skill,meta.level,meta.actionKey,meta.actionLabel)
    if not b then return end
    local last=b.samples[#b.samples]
    if meta.actionInstance and last and last.instance==meta.actionInstance then
        last.xp=amount;last.day=day;last.minute=meta.minute;last.world=meta.world;last.exact=true
    else
        table.insert(b.samples,{xp=amount,day=day,minute=meta.minute,world=meta.world,instance=meta.actionInstance,exact=true})
        trim(b.samples,8)
    end
    b.updatedDay=day;b.updatedMinute=meta.minute;b.updatedWorld=meta.world
    t.lastActionBySkill[skill]={skill=skill,level=meta.level,actionKey=meta.actionKey,actionLabel=meta.actionLabel,
        actionInstance=meta.actionInstance,day=day,minute=meta.minute,world=meta.world,exact=true}
end

-- If an exact completion sample was recorded before an XP event is observed, keep the
-- exact action value and let the base tracker record only the skill's total XP gain.
local baseAdd=X.add
function X.add(root,day,skill,amount,name,meta)
    if meta and meta.actionInstance and meta.actionKey and meta.level~=nil then
        local t=X.ensure(root,day)
        local bySkill=t.actions[skill]
        local byLevel=bySkill and bySkill[tostring(meta.level)]
        local b=byLevel and byLevel[meta.actionKey]
        local last=b and b.samples and b.samples[#b.samples]
        if last and last.exact and last.instance==meta.actionInstance then
            local copy={}
            for k,v in pairs(meta) do copy[k]=v end
            copy.actionKey=nil;copy.actionLabel=nil
            return baseAdd(root,day,skill,amount,name,copy)
        end
    end
    return baseAdd(root,day,skill,amount,name,meta)
end

return X
