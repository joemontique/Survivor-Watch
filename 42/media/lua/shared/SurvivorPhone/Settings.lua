SurvivorPhoneSettings = {}
local S=SurvivorPhoneSettings
function S.clamp(n,a,b) return math.max(a,math.min(b,tonumber(n) or a)) end
function S.ensure(root)
    root.settings=root.settings or {}
    local s=root.settings
    s.dimmer=S.clamp(s.dimmer or 1,0.25,1)
    s.uiScale=S.clamp(s.uiScale or 0.72,0.5,1)
    s.leadMinutes=S.clamp(s.leadMinutes or 30,10,120)
    if s.notificationsMuted==nil then s.notificationsMuted=s.dnd or false end
    s.dnd=s.notificationsMuted
    if s.learning==nil then s.learning=true end
    if s.travelTracking==nil then s.travelTracking=true end
    if s.showTrail==nil then s.showTrail=true end
    if s.watchEnabled==nil then s.watchEnabled=true end
    s.watchScale=S.clamp(s.watchScale or 1,0.65,1.4)
    s.watchOpacity=S.clamp(s.watchOpacity or math.max(0.65,s.dimmer*0.9),0.35,1)
    if s.sleepResetEnabled==nil then s.sleepResetEnabled=true end
    s.sleepTargetBedtime=S.clamp(s.sleepTargetBedtime or 1380,0,1439)
    s.sleepTargetWake=S.clamp(s.sleepTargetWake or 420,0,1439)
    s.sleepResetMinHours=S.clamp(s.sleepResetMinHours or 3,3,6)
    s.sleepResetMaxHours=S.clamp(s.sleepResetMaxHours or 6.5,4,9)
    s.version=6
    return s
end
return S
