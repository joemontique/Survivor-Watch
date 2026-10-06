require 'SurvivorPhone/SaveData'
SurvivorPhoneNeeds={samples={}}
local N=SurvivorPhoneNeeds
local specs={
    {key='hunger',stat='HUNGER',moodle='HUNGRY',label='Hunger',threshold=0.15,zero=1,warning='Peckish'},
    {key='thirst',stat='THIRST',moodle='THIRST',label='Thirst',threshold=0.12,zero=1,warning='Thirsty'},
    {key='fatigue',stat='FATIGUE',moodle='TIRED',label='Rested',threshold=0.6,zero=0.6,warning='Drowsy'},
    {key='endurance',stat='ENDURANCE',moodle='ENDURANCE',label='Stamina',threshold=0.75,zero=0,warning='Exertion'}
}
N.specs=specs
local function clamp(v) return math.max(0,math.min(1,v)) end
function N.ensure(root)
    root.needsHistory=root.needsHistory or {version=1,onsets={},recoveries={},rates={}}
    return root.needsHistory
end
local function append(rows,row)
    table.insert(rows,row);while #rows>180 do table.remove(rows,1) end
end
local function nativeLabel(group,level,fallback)
    local key='Moodles_'..group..'_lvl'..level
    if getText then local value=getText(key);if value and value~=key then return value end end
    return fallback
end
function N.fullness(player,hunger,level)
    local moodles=player:getMoodles()
    local fed=MoodleType.FOOD_EATEN and moodles:getMoodleLevel(MoodleType.FOOD_EATEN) or 0
    fed=fed or 0
    local body=player.getBodyDamage and player:getBodyDamage()
    local timer=body and body:getHealthFromFoodTimer() or 0
    local standard=body and body:getStandardHealthFromFoodTime() or 1600
    -- CharacterStat.HUNGER has appeared on both normalized (0..1) and percentage
    -- (0..100) scales. Normalize it before drawing the reserve gauge so reaching
    -- Peckish warns the player without incorrectly looking empty.
    local raw=tonumber(hunger) or 0
    local normalized=raw>1 and raw/100 or raw
    -- The base hunger reserve uses 80% of the gauge; the top 20% is the temporary
    -- food/fullness bonus. Zero is reserved for the extreme end of starvation.
    local fill=0.8*(1-clamp(normalized))
    if level==0 then
        fill=fill+0.2*clamp(timer/math.max(1,standard*2))
        if fed>=3 then return 1,fed,timer end
    end
    return math.min(0.999,clamp(fill)),fed,timer
end
function N.percent(fill,canBeFull)
    local value=math.floor(clamp(fill)*1000+0.5)/10
    return canBeFull and value or math.min(99.9,value)
end
function N.threshold(spec)
    -- Build 42.20.4 MoodleStat defaults verified in the installed game.
    -- Respect the native registry when it is exposed to Lua.
    if MoodleStat and MoodleStat[spec.moodle] then
        if spec.key=='endurance' then return MoodleStat[spec.moodle]:getMinimumThreshold() end
        return MoodleStat[spec.moodle]:getLowestThreshold()
    end
    return spec.threshold
end
function N.measure(spec,value,level)
    local zero=spec.key=='fatigue' and N.threshold(spec) or spec.zero
    local fill=spec.key=='endurance' and clamp(value) or clamp(1-value/zero)
    if spec.key=='fatigue' and level>=1 then fill=0 end
    return fill
end
function N.rate(samples)
    if #samples<4 then return nil end
    local first,last=samples[1],samples[#samples]
    if last.t-first.t<5 then return nil end
    -- Linear regression over up to fifteen game minutes smooths individual ticks.
    local st,sv,stt,stv=0,0,0,0
    for _,s in ipairs(samples) do local t=s.t-first.t;st=st+t;sv=sv+s.v;stt=stt+t*t;stv=stv+t*s.v end
    local n=#samples;local denom=n*stt-st*st
    if denom<=0 then return nil end
    local rate=(n*stv-st*sv)/denom
    local mean=sv/n;local intercept=(sv-rate*st)/n;local residual,total=0,0
    for _,s in ipairs(samples) do local expected=intercept+rate*(s.t-first.t);residual=residual+(s.v-expected)^2;total=total+(s.v-mean)^2 end
    if total>0 and 1-residual/total<0.8 then return nil end
    return rate
end
function N.estimate(samples,threshold,value,inverse)
    local rate=N.rate(samples);if not rate then return nil end
    if inverse then if rate>=-0.00001 then return nil end else if rate<=0.00001 then return nil end end
    local eta=(threshold-value)/rate
    if eta<=0 or eta>720 then return nil end
    return math.max(1,math.floor(eta/5+0.5)*5)
end
function N.update(player)
    local root,_,now=SurvivorPhoneData.get(player)
    local state=N.samples[player] or {};N.samples[player]=state
    local history=N.ensure(root)
    local d={bars={},warnings={}};root.needs=d
    local stats,moodles=player:getStats(),player:getMoodles()
    local labels={hunger={'Not hungry','Peckish','Hungry','Very Hungry','Starving'},thirst={'Hydrated','Slightly Thirsty','Thirsty','Parched','Dying of Thirst'},fatigue={'Rested','Drowsy','Tired','Very Tired','Ridiculously Tired'},endurance={'Ready','Out of Breath','High Exertion','Excessive Exertion','Exhausted'}}
    local groups={hunger='Hungry',thirst='Thirst',fatigue='Tired',endurance='Endurance'}
    for _,spec in ipairs(specs) do
        local v=stats:get(CharacterStat[spec.stat]);local level=moodles:getMoodleLevel(MoodleType[spec.moodle]) or 0
        local fill=N.measure(spec,v,level);local fed,timer=0,0
        if spec.key=='hunger' then fill,fed,timer=N.fullness(player,v,level) end
        local mode=spec.key=='hunger' and (timer>0 and 'fed' or 'unfed') or 'normal'
        local status=labels[spec.key][level+1] or spec.warning
        if level>0 then status=nativeLabel(groups[spec.key],level,status)
        elseif spec.key=='hunger' and fed>0 then status=nativeLabel('FoodEaten',fed,({'Satiated','Well Fed','Stuffed','Full to Bursting'})[fed]) end
        local seq=state[spec.key] or {};state[spec.key]=seq
        local last=seq[#seq];local inverse=spec.key=='endurance'
        local improved=last and (inverse and v>last.v+0.00001 or not inverse and v<last.v-0.00001 or spec.key=='hunger' and timer>(last.food or 0)+1)
        local broken=last and (now.worldMinute<last.t or now.worldMinute-last.t>5)
        local previous=state[spec.key..'previous']
        if root.settings.learning and spec.key~='endurance' and previous and now.worldMinute>=previous.t and now.worldMinute-previous.t<=5 then
            local row={day=now.day,minute=now.minute,worldMinute=now.worldMinute,key=spec.key,state=status,level=level}
            if previous.level==0 and level>0 and not player:isAsleep() then append(history.onsets,row) end
            if previous.level>0 and level==0 then append(history.recoveries,row) end
        end
        state[spec.key..'previous']={t=now.worldMinute,level=level}
        if improved or broken or last and last.mode~=mode or player:isAsleep() then
            seq={};state[spec.key]=seq;last=nil
        end
        if not last or now.worldMinute-last.t>=1 then
            table.insert(seq,{t=now.worldMinute,v=v,mode=mode,food=timer})
            while #seq>1 and (now.worldMinute-seq[1].t>15 or #seq>16) do table.remove(seq,1) end
        end
        local eta,forecast,confidence=nil,'Learning your pace','calibrating'
        local rate=spec.key~='endurance' and N.rate(seq) or nil
        local rateKey=spec.key..':'..mode
        if rate and rate>0.00001 and not player:isAsleep() and root.settings.learning then
            local learned=history.rates[rateKey] or {days={},rate=rate}
            if learned.last~=math.floor(now.worldMinute) then
                learned.rate=learned.rate*0.8+rate*0.2;learned.last=math.floor(now.worldMinute)
                learned.days[now.day]=true
                local dates={};for day in pairs(learned.days) do table.insert(dates,day) end;table.sort(dates)
                while #dates>30 do learned.days[table.remove(dates,1)]=nil end
                history.rates[rateKey]=learned
            end
        end
        if player:isAsleep() then forecast='Sleeping / recalibrating'
        elseif level>0 then forecast=spec.warning..' threshold reached'
        elseif improved then forecast='Recovering / recalibrating'
        elseif spec.key~='endurance' then
            local predicted=rate and rate>0.00001 and (N.threshold(spec)-v)/rate or nil
            if spec.key=='hunger' and timer>0 and predicted then
                local first=seq[1];local decay=first and (first.food-timer)/math.max(0.001,now.worldMinute-first.t) or 0
                local remaining=decay>0 and timer/decay or nil
                if not remaining then predicted=nil
                elseif predicted>remaining then
                    local after=history.rates['hunger:unfed']
                    if after and after.rate>0.00001 then predicted=remaining+math.max(0,N.threshold(spec)-v-rate*remaining)/after.rate else predicted=nil end
                end
            end
            if predicted and predicted>0 and predicted<=720 then eta=math.max(1,math.floor(predicted/5+0.5)*5);confidence='recent';forecast='Based on your recent pace'
            elseif predicted and predicted>720 then forecast='More than 12 game hours'
            elseif rate and math.abs(rate)<=0.00001 then forecast='Stable / no countdown'
            elseif rate and rate<0 then forecast='Recovering / recalibrating' end
        end
        local full=spec.key=='hunger' and fed>=3 and level==0 or spec.key~='hunger' and fill>=1
        local bar={key=spec.key,label=spec.label,value=v,fill=fill,percent=N.percent(fill,full),level=level,status=status,eta=eta,warning=spec.warning,forecastStatus=forecast,confidence=confidence,foodLevel=fed}
        table.insert(d.bars,bar)
        if eta and eta<=root.settings.leadMinutes then table.insert(d.warnings,bar) end
        if improved or broken or state.day~=now.day then state[spec.key..'warned']=nil end
        if spec.key~='thirst' and eta and eta<=root.settings.leadMinutes and not state[spec.key..'warned'] then
            state[spec.key..'warned']=true
            if SurvivorPhoneNotifications then SurvivorPhoneNotifications.emit(player,'needs',spec.key..':'..now.worldMinute,spec.warning..' in '..SurvivorPhoneClock.irlEta(eta),'home') end
        end
    end
    state.day=now.day
    return d
end
return N
