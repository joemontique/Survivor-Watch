-- Calendar and planning use game time. Only elapsed activity/animation clocks use milliseconds.
SurvivorPhoneClock = {}
local C = SurvivorPhoneClock
local monthNames={'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'}
function C.now()
    local g = getGameTime()
    local year,month,day=g:getYear(),g:getMonth()+1,g:getDay()+1
    return {day=string.format('%04d-%02d-%02d',year,month,day),
        dateText=string.format('%s %02d, %04d',monthNames[month] or tostring(month),day,year),
        minute=g:getHour()*60+g:getMinutes(), worldMinute=g:getWorldAgeHours()*60}
end
function C.previousDay(day)
    local y,m,d=day:match('^(%d+)%-(%d+)%-(%d+)$')
    y,m,d=tonumber(y),tonumber(m),tonumber(d)
    if not y then return nil end
    d=d-1
    if d==0 then
        m=m-1; if m==0 then m=12; y=y-1 end
        local days={31,28,31,30,31,30,31,31,30,31,30,31}
        if y%4==0 and (y%100~=0 or y%400==0) then days[2]=29 end
        d=days[m]
    end
    return string.format('%04d-%02d-%02d',y,m,d)
end
function C.realSeconds() return getTimestampMs()/1000 end
function C.duration(seconds)
    if not seconds or seconds<0 or seconds~=seconds then return '--' end
    seconds=math.floor(seconds+0.5)
    if seconds<60 then return seconds..'s' end
    if seconds<3600 then return math.floor(seconds/60)..'m '..(seconds%60)..'s' end
    return math.floor(seconds/3600)..'h '..math.floor(seconds%3600/60)..'m'
end
function C.shortDuration(seconds)
    if not seconds or seconds<0 or seconds~=seconds then return '--' end
    seconds=math.max(1,math.floor(seconds+0.5))
    if seconds<60 then return seconds..'s' end
    if seconds<600 then
        local mins=math.floor(seconds/60)
        local secs=seconds%60
        return secs>0 and mins..'m '..secs..'s' or mins..'m'
    end
    if seconds<3600 then return math.floor(seconds/60+0.5)..'m' end
    local hours=math.floor(seconds/3600)
    local mins=math.floor((seconds%3600)/60+0.5)
    if mins>=60 then hours=hours+1;mins=0 end
    return mins>0 and hours..'h '..mins..'m' or hours..'h'
end
function C.realSecondsForGameMinutes(minutes)
    if not minutes or minutes<=0 or minutes~=minutes then return nil end
    local realMinutesPerDay=60
    local speed=1
    local g=getGameTime and getGameTime()
    if g and g.getMinutesPerDay then
        local ok,value=pcall(function() return g:getMinutesPerDay() end)
        value=ok and tonumber(value) or nil
        if value and value>0 then realMinutesPerDay=value end
    end
    if g and g.getTrueMultiplier then
        local ok,value=pcall(function() return g:getTrueMultiplier() end)
        value=ok and tonumber(value) or nil
        if value and value>0.01 then speed=value end
    end
    return minutes*realMinutesPerDay*60/1440/speed
end
function C.irlEta(minutes)
    local seconds=C.realSecondsForGameMinutes(minutes)
    if not seconds then return '--' end
    return 'about '..C.shortDuration(seconds)..' IRL'
end
return C
