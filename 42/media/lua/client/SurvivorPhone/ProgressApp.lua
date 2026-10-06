require 'SurvivorPhone/ActionRecognition'
require 'SurvivorPhone/XPTracker'
require 'SurvivorPhone/Widgets'
require 'SurvivorPhone/GameClock'
require 'SurvivorPhone/ReadingAdvisor'
require 'SurvivorPhone/RunningTracker'

SurvivorWatchProgress=SurvivorWatchProgress or {}
local M=SurvivorWatchProgress
local D=SurvivorPhoneWidgets
local X=SurvivorPhoneXP
local R=SurvivorPhoneRecognition
local C=SurvivorPhoneClock
local Read=SurvivorPhoneReading
local Run=SurvivorPhoneRunning
local c=D.c

local function number(value)
    if value==nil then return '--' end
    if math.abs(value-math.floor(value+0.0001))<0.01 then return tostring(math.floor(value+0.0001)) end
    return string.format('%.1f',value)
end

local function signed(value)
    value=value or 0
    return (value>0 and '+' or '')..number(value)
end

local function trendLabel(state)
    if not state then return 'Unavailable' end
    if state.trend=='gaining' then return 'Gaining' end
    if state.trend=='losing' then return 'Losing' end
    return 'Stable'
end

local function buildRows(player,root,day,tracker)
    local rows={}
    for _,skill in ipairs(R.skillList()) do
        local state=X.skillState(player,skill)
        if state then
            local today=(tracker.totals or {})[skill.id] or 0
            local estimate=not state.maxed and X.estimate(root,day,skill.id,state.level,state.remaining) or nil
            table.insert(rows,{skill=skill,state=state,today=today,estimate=estimate})
        end
    end
    table.sort(rows,function(a,b)
        if a.state.maxed~=b.state.maxed then return not a.state.maxed end
        if not a.state.maxed then
            local aActive=(tonumber(a.today) or 0)>0
            local bActive=(tonumber(b.today) or 0)>0
            if aActive~=bActive then return aActive end
            local ar,br=tonumber(a.state.remaining),tonumber(b.state.remaining)
            if ar~=nil and br~=nil and ar~=br then return ar<br end
            if (ar~=nil)~=(br~=nil) then return ar~=nil end
            local ap,bp=tonumber(a.state.ratio) or 0,tonumber(b.state.ratio) or 0
            if ap~=bp then return ap>bp end
        end
        return a.skill.name<b.skill.name
    end)
    return rows
end

local function snapshot(panel,now,tracker)
    local revision=tonumber(tracker.revision) or 0
    local cache=panel._progressCache
    if cache and cache.day==now.day and cache.revision==revision then return cache end
    local previousDay=C.previousDay(now.day)
    local previous=tracker.history[previousDay]
    cache={
        day=now.day,
        revision=revision,
        total=X.total(tracker.totals),
        previousTotal=previous and X.total(previous) or nil,
        rows=buildRows(panel.player,panel.root,now.day,tracker)
    }
    panel._progressCache=cache
    return cache
end

local function drawWeight(panel,y,now,weight)
    local x,w=panel.pad,panel.bodyW
    local gap=8
    local cellW=(w-gap*2)/3
    local topH=68
    local cards={
        {'XP TODAY','+'..number(panel._progressSnapshot.total),c.purple},
        {'PREVIOUS DAY',panel._progressSnapshot.previousTotal and ('+'..number(panel._progressSnapshot.previousTotal)) or '--',c.mint},
        {'WEIGHT',weight and number(weight.weight) or '--',weight and (weight.trend=='gaining' and c.amber or weight.trend=='losing' and c.blue or c.text) or c.muted}
    }
    for i,row in ipairs(cards) do
        local bx=x+(i-1)*(cellW+gap)
        panel:card(bx,y,cellW,topH,c.glass,0.80)
        D.text(panel,row[1],bx+10,y+10,c.muted,nil,cellW-20)
        D.text(panel,row[2],bx+10,y+31,row[3],UIFont.Medium,cellW-20)
    end
    y=y+topH+8
    if weight then
        local detail='Weight trend: '..trendLabel(weight)..'  /  tracked change '..signed(weight.delta)
        y=y+D.wrap(panel,detail,x,y,w,c.muted)+12
    end
    return y
end

local function drawSuggestedReading(panel,y,tracker)
    local x,w=panel.pad,panel.bodyW
    local suggestions=Read.recommendations(panel.player,tracker,R.skillList())
    y=panel:section('SUGGESTED READING',y)
    if #suggestions==0 then
        return y+D.wrap(panel,'No missing skill-book bonus detected for skills earning XP today.',x,y,w,c.mint)+12
    end
    y=y+D.wrap(panel,'You earned XP in these skills today without the full book bonus for the current level range.',x,y,w,c.muted)+8
    for _,row in ipairs(suggestions) do
        local h=64
        panel:card(x,y,w,h,c.card,0.90)
        D.text(panel,row.book,x+12,y+9,c.text,UIFont.Medium,w-24)
        local range='Levels '..row.levelStart..'-'..row.levelEnd
        local status=row.status..'  /  '..range..'  /  Today +'..number(row.today)
        D.text(panel,status,x+12,y+31,row.status=='Not read' and c.amber or c.purple,nil,w-24)
        local bonus='Book bonus x'..number(row.current)..' of x'..number(row.full)
        D.text(panel,bonus,x+12,y+47,c.muted,nil,w-24)
        y=y+h+8
    end
    return y+4
end

local function fitnessLines(panel,state)
    local estimate=Run.estimate(panel.root,panel.player,state.level,state.remaining)
    local today=estimate.today or {}
    local runToday=(today.seconds or 0)>0 or (today.tiles or 0)>0
    if not estimate.learned then
        if not runToday then return nil end
        return {
            'Running tracker active  /  '..C.shortDuration(today.seconds or 0)..' running  /  '..number(today.tiles or 0)..' tiles',
            'Waiting for a Fitness XP gain before predicting time and distance.'
        },false
    end
    local confidence=estimate.confidence or 'Provisional'
    local rate='Running rate ('..confidence..')'
    if estimate.xpPerMinute then rate=rate..'  /  +'..number(estimate.xpPerMinute)..' XP/real min' end
    if estimate.xpPer100Tiles then rate=rate..'  /  +'..number(estimate.xpPer100Tiles)..' XP/100 tiles' end
    local remaining='Estimated to Level '..(state.level+1)..': '
    if estimate.secondsLeft then remaining=remaining..C.shortDuration(estimate.secondsLeft)..' running' else remaining=remaining..'-- running time' end
    if estimate.tilesLeft then remaining=remaining..'  /  '..number(math.floor(estimate.tilesLeft+0.5))..' tiles' end
    local basis='Based on '..estimate.sessions..' XP-producing run session'..(estimate.sessions==1 and '' or 's')
    if estimate.events and estimate.events>estimate.sessions then basis=basis..' / '..estimate.events..' Fitness XP gains' end
    return {rate,remaining,basis},true
end

local function drawSkillCard(panel,y,row)
    local x,w=panel.pad,panel.bodyW
    local skill,state,estimate=row.skill,row.state,row.estimate
    local runLines,runLearned
    if skill.id=='Fitness' and not state.maxed then runLines,runLearned=fitnessLines(panel,state) end
    local estimateLines=runLines and #runLines or estimate and 2 or 0
    local h=state.maxed and 72 or (96+estimateLines*panel.lh)
    panel:card(x,y,w,h,c.card,0.90)
    D.text(panel,skill.name,x+14,y+10,c.text,UIFont.Medium,w-130)
    local levelText=state.maxed and 'MAX LEVEL' or ('LEVEL '..state.level..' -> '..(state.level+1))
    D.text(panel,levelText,x+w-14-D.measure(levelText),y+12,state.maxed and c.mint or c.purple)

    if state.maxed then
        D.text(panel,'Current XP  '..number(state.total),x+14,y+39,c.muted,nil,w-28)
        D.text(panel,'Skill is maxed.',x+14,y+56,c.mint,nil,w-28)
    else
        local line='Current XP  '..number(state.total)..'    Level ends  '..number(state.endTotal)..'    Need  '..number(state.remaining)
        D.text(panel,line,x+14,y+36,c.muted,nil,w-28)
        local barY=y+59
        D.round(panel,x+14,barY,w-28,7,c.raised,1,4)
        if state.ratio and state.ratio>0 then D.round(panel,x+14,barY,(w-28)*state.ratio,7,c.purple,1,4) end
        local localLine='This level  '..number(state.current)..' / '..number(state.cost)
        if row.today>0 then localLine=localLine..'    Today +'..number(row.today) end
        D.text(panel,localLine,x+14,y+72,c.text,nil,w-28)

        if runLines then
            for i,line in ipairs(runLines) do
                D.text(panel,line,x+14,y+91+(i-1)*panel.lh,runLearned and (i==2 and c.text or c.mint) or c.muted,nil,w-28)
            end
        elseif estimate then
            local actionLabel=estimate.actionLabel or 'Last action'
            local actionLine,actionColor,estimateText
            if estimate.confirmed then
                actionLine='Average ('..tostring(estimate.count or 0)..' samples)  /  '..actionLabel..'  +'..number(estimate.rate or 0)..' XP/action'
                actionColor=(estimate.rate or 0)>0 and c.mint or c.muted
                if (estimate.rate or 0)<=0 then
                    estimateText='This action currently grants no XP.'
                elseif estimate.repeats then
                    estimateText=estimate.repeats..' more similar action'..(estimate.repeats==1 and '' or 's')..' estimated to reach Level '..(state.level+1)
                else
                    estimateText='Average updates after every matching action.'
                end
            else
                local sampleCount=estimate.sampleCount or estimate.count or 0
                actionLine='Learning '..sampleCount..'/3  /  '..actionLabel
                if estimate.lastXP~=nil then actionLine=actionLine..'  /  Last +'..number(estimate.lastXP)..' XP' end
                actionColor=c.muted
                estimateText=sampleCount==1 and 'Two more matching actions are needed before an average is shown.'
                    or 'One more matching action is needed before an average is shown.'
            end
            D.text(panel,actionLine,x+14,y+91,actionColor,nil,w-28)
            D.text(panel,estimateText,x+14,y+91+panel.lh,estimate.repeats and c.text or c.muted,nil,w-28)
        end
    end
    return y+h+10
end

function M.draw(panel,y,now)
    local x,w=panel.pad,panel.bodyW
    local tracker=X.ensure(panel.root,now.day)
    local state=snapshot(panel,now,tracker)
    panel._progressSnapshot=state
    local weight=X.weightState(panel.root,now.day,now.worldMinute,panel.player)

    y=panel:heading('Progress','Live skill XP, next-level targets, adaptive action estimates and body-weight trend.',y)
    y=drawWeight(panel,y,now,weight)
    y=drawSuggestedReading(panel,y,tracker)

    y=panel:section('SKILL LEVELS',y)
    y=y+D.wrap(panel,'Skills with XP gained today are listed first, then sorted by XP remaining to the next level. Zero-XP skills follow. Repeatable actions use recent matching samples; Fitness learns from continuous running time, distance and observed Fitness XP.',x,y,w,c.muted)+12

    local rows=state.rows
    if #rows==0 then
        return y+D.wrap(panel,'No skill information is available yet.',x,y,w,c.muted)+10
    end

    for _,row in ipairs(rows) do y=drawSkillCard(panel,y,row) end

    y=panel:section('RECENT XP',y)
    local gains=tracker.recentGains or {}
    if #gains==0 then
        y=y+D.wrap(panel,'No XP gains have been recorded in this session yet.',x,y,w,c.muted)+10
    else
        local shown=0
        for i=#gains,1,-1 do
            local gain=gains[i]
            local label=(gain.name or gain.skill)..'  +'..number(gain.xp)
            if gain.actionLabel then label=label..'  /  '..gain.actionLabel end
            y=y+D.wrap(panel,label,x,y,w,c.muted)+6
            shown=shown+1
            if shown>=8 then break end
        end
    end
    return y+8
end

return M