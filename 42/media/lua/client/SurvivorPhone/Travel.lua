require 'SurvivorPhone/SaveData'
-- Only positions occupied by this survivor are recorded. No world/map data is read.
SurvivorPhoneTravel={runtime={},maxPoints=360,maxPlaces=40}
local T=SurvivorPhoneTravel
local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
function T.ensure(root)
    root.travel=root.travel or {points={},places={},nextId=1,segment=0}
    return root.travel
end
function T.position(player)
    if not player or not player.getX or not player.getY or not player.getZ then return end
    local x,y,z=player:getX(),player:getY(),player:getZ()
    if finite(x) and finite(y) and finite(z) then return {x=x,y=y,z=z} end
end
function T.distance(a,b)
    if not a or not b then return end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
function T.find(root,id)
    for _,place in ipairs(T.ensure(root).places) do if place.id==id then return place end end
end
function T.savePlace(player,name)
    name=tostring(name or ''):match('^%s*(.-)%s*$')
    if name=='' or #name>40 then return nil,'Use a place name of 1-40 characters.' end
    local pos=T.position(player);if not pos then return nil,'Current position is unavailable.' end
    local root,_,now=SurvivorPhoneData.get(player);local data=T.ensure(root)
    for _,place in ipairs(data.places) do
        if place.z==pos.z and T.distance(place,pos)<3 then return nil,'This spot is already saved as '..place.name..'.' end
    end
    if #data.places>=T.maxPlaces then return nil,'Up to 40 places can be saved.' end
    local place={id=data.nextId,name=name,x=pos.x,y=pos.y,z=pos.z,visits=1,inside=true,lastDay=now.day,lastMinute=now.minute,lastWorld=now.worldMinute}
    data.nextId=data.nextId+1;table.insert(data.places,place);return place
end
function T.poll(player)
    local root,_,now=SurvivorPhoneData.get(player)
    if root.settings.travelTracking==false or player:isAsleep() then T.runtime[player]=nil;return end
    local seconds=SurvivorPhoneClock.realSeconds()
    local runtime=T.runtime[player]
    if runtime and seconds>=runtime.real and seconds-runtime.real<5 then return end
    local pos=T.position(player);if not pos then return end
    local data=T.ensure(root)
    local split=not runtime or seconds<runtime.real or now.worldMinute<runtime.world or seconds-runtime.real>30
    if runtime and runtime.pos and (T.distance(pos,runtime.pos)>250 or pos.z~=runtime.pos.z) then split=true end
    if split then data.segment=data.segment+1 end
    T.runtime[player]={real=seconds,world=now.worldMinute,pos=pos}
    local last=data.points[#data.points]
    if split or not last or T.distance(pos,last)>=3 then
        table.insert(data.points,{x=pos.x,y=pos.y,z=pos.z,day=now.day,minute=now.minute,world=now.worldMinute,segment=data.segment})
    end
    while #data.points>T.maxPoints or (#data.points>0 and now.worldMinute-data.points[1].world>7*1440) do table.remove(data.points,1) end
    for _,place in ipairs(data.places) do
        local distance=T.distance(pos,place)
        local inside=pos.z==place.z and distance<=12
        if inside then
            if not place.inside then place.visits=place.visits+1 end
            place.inside=true;place.lastDay=now.day;place.lastMinute=now.minute;place.lastWorld=now.worldMinute
        elseif pos.z~=place.z or distance>18 then place.inside=false end
    end
end
function T.describe(place,pos)
    if not place then return '' end
    local distance=T.distance(place,pos)
    local text=place.name
    if distance then text=text..' / '..math.floor(distance+0.5)..' tiles away' end
    if pos and pos.z~=place.z then text=text..' / different floor' end
    return text
end
return T
