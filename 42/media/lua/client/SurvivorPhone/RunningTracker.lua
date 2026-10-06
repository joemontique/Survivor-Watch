require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/GameClock'

SurvivorPhoneRunning={runtime={},maxSessions=8}
local R=SurvivorPhoneRunning

local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end

local function position(player)
    if not player or not player.getX or not player.getY or not player.getZ then return nil end
    local x,y,z=player:getX(),player:getY(),player:getZ()
    if finite(x) and finite(y) and finite(z) then return {x=x,y=y,z=z} end
end

local function distance(a,b)
    if not a or not b or a.z~=b.z then return nil end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end

local function running(player)
    if not player or player:isDead() or player:isAsleep() then return false end
    if player.getVehicle then
        local ok,vehicle=pcall(function() return player:getVehicle() end)
        if ok and vehicle then return false end
    end
    local okRun,isRun=pcall(function() return player:IsRunning() end)
    local okSprint,isSprint=pcall(function() return player:isSprinting() end)
    return (okRun and isRun==true) or (okSprint and isSprint==true)
end

local function fitness(player)
    if not player or not Perks or not Perks.Fitness then return nil,nil end
    local xp=player:getXp()
    return xp and xp:getXP(Perks.Fitness) or nil,player:getPerkLevel(Perks.Fitness)
end

local function trim(rows,max)
    while #rows>max do table.remove(rows,1) end
end

function R.ensure(root,day)
    root.running=root.running or {version=1,byLevel={},recent={},day=day,today={seconds=0,gameMinutes=0,tiles=0,xp=0}}
    local d=root.running
    d.version=1;d.byLevel=d.byLevel or {};d.recent=d.recent or {}
    if d.day~=day then
        d.day=day;d.today={seconds=0,gameMinutes=0,tiles=0,xp=0}
    end
    d.today=d.today or {seconds=0,gameMinutes=0,tiles=0,xp=0}
    return d
end

local function start(player,root,now,seconds,pos,xp,level)
    local rt={
        root=root,day=now.day,level=level,startWorld=now.worldMinute,startReal=seconds,
        lastWorld=now.worldMinute,lastReal=seconds,lastPos=pos,lastXP=xp,
        seconds=0,gameMinutes=0,tiles=0,xp=0,xpEvents=0
    }
    R.runtime[player]=rt
    return rt
end

local function addSample(rt,data)
    if not rt then return end
    local key=tostring(rt.level or -1)
    data.byLevel[key]=data.byLevel[key] or {}
    local row={day=rt.day,level=rt.level,seconds=rt.seconds,gameMinutes=rt.gameMinutes,tiles=rt.tiles,xp=rt.xp,xpEvents=rt.xpEvents}
    table.insert(data.byLevel[key],row);trim(data.byLevel[key],R.maxSessions)
    table.insert(data.recent,row);trim(data.recent,12)
end

function R.finish(player,reason)
    local rt=R.runtime[player]
    if not rt then return nil end
    R.runtime[player]=nil
    local data=R.ensure(rt.root,rt.day)
    if rt.seconds>=2 or rt.tiles>=3 or rt.xp>0 then
        rt.reason=reason or 'stopped'
        addSample(rt,data)
        return rt
    end
end

function R.poll(player)
    if not player or isClient() or isServer() or player:isDead() then R.runtime[player]=nil;return end
    local root,_,now=SurvivorPhoneData.get(player)
    local data=R.ensure(root,now.day)
    local seconds=SurvivorPhoneClock.realSeconds()
    local pos=position(player)
    local xp,level=fitness(player)
    if not pos or xp==nil or level==nil then return end

    local rt=R.runtime[player]
    if rt and (rt.root~=root or rt.level~=level or seconds<rt.lastReal or now.worldMinute<rt.lastWorld or seconds-rt.lastReal>3) then
        R.finish(player,rt.level~=level and 'level-up' or 'interrupted')
        rt=nil
    end

    if rt then
        local xpGain=xp-(rt.lastXP or xp)
        if xpGain>0 and xpGain==xpGain then
            rt.xp=rt.xp+xpGain;rt.xpEvents=rt.xpEvents+1
            data.today.xp=(data.today.xp or 0)+xpGain
        end
    end

    local isRunning=running(player)
    if not isRunning then
        if rt then R.finish(player,'stopped') end
        return
    end

    if not rt then
        start(player,root,now,seconds,pos,xp,level)
        return
    end

    local dt=seconds-rt.lastReal
    local gameDt=now.worldMinute-rt.lastWorld
    local moved=distance(pos,rt.lastPos)
    if dt>=0 and dt<=3 and gameDt>=0 and gameDt<=15 and moved and moved<=20 then
        -- Count only intervals where the character actually changed position.
        if moved>0.01 then
            rt.seconds=rt.seconds+dt
            rt.gameMinutes=rt.gameMinutes+gameDt
            rt.tiles=rt.tiles+moved
            data.today.seconds=(data.today.seconds or 0)+dt
            data.today.gameMinutes=(data.today.gameMinutes or 0)+gameDt
            data.today.tiles=(data.today.tiles or 0)+moved
        end
    end
    rt.lastReal=seconds;rt.lastWorld=now.worldMinute;rt.lastPos=pos;rt.lastXP=xp
end

local function addTotals(total,row)
    if not row then return end
    total.xp=total.xp+(row.xp or 0)
    total.seconds=total.seconds+(row.seconds or 0)
    total.gameMinutes=total.gameMinutes+(row.gameMinutes or 0)
    total.tiles=total.tiles+(row.tiles or 0)
    total.events=total.events+(row.xpEvents or 0)
    total.sessions=total.sessions+1
end

function R.estimate(root,player,level,remaining)
    local data=R.ensure(root,SurvivorPhoneClock.now().day)
    local total={xp=0,seconds=0,gameMinutes=0,tiles=0,events=0,sessions=0}
    local rows=data.byLevel[tostring(level)] or {}
    for _,row in ipairs(rows) do addTotals(total,row) end
    local rt=player and R.runtime[player]
    if rt and rt.root==root and rt.level==level and rt.xp>0 then addTotals(total,rt) end

    local current=rt and rt.root==root and rt.level==level and rt or nil
    if total.xp<=0 then
        return {learned=false,current=current,today=data.today,sessions=0,events=0}
    end

    local xpPerSecond=total.seconds>0 and total.xp/total.seconds or nil
    local xpPerGameMinute=total.gameMinutes>0 and total.xp/total.gameMinutes or nil
    local xpPerTile=total.tiles>0 and total.xp/total.tiles or nil
    local secondsLeft=xpPerSecond and remaining and remaining/xpPerSecond or nil
    local gameMinutesLeft=xpPerGameMinute and remaining and remaining/xpPerGameMinute or nil
    local tilesLeft=xpPerTile and remaining and remaining/xpPerTile or nil
    local confirmed=total.sessions>=3 or total.events>=3
    return {
        learned=true,confirmed=confirmed,confidence=confirmed and 'Learned' or 'Provisional',
        xp=total.xp,seconds=total.seconds,gameMinutes=total.gameMinutes,tiles=total.tiles,
        sessions=total.sessions,events=total.events,
        xpPerMinute=xpPerSecond and xpPerSecond*60 or nil,
        xpPer100Tiles=xpPerTile and xpPerTile*100 or nil,
        secondsLeft=secondsLeft,gameMinutesLeft=gameMinutesLeft,tilesLeft=tilesLeft,
        current=current,today=data.today
    }
end

return R
