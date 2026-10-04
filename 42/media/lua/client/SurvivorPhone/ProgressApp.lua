require 'SurvivorPhone/ActionRecognition'
require 'SurvivorPhone/XPTracker'
require 'SurvivorPhone/Widgets'
require 'SurvivorPhone/GameClock'

SurvivorWatchProgress=SurvivorWatchProgress or {}
local M=SurvivorWatchProgress
local D=SurvivorPhoneWidgets
local X=SurvivorPhoneXP
local R=SurvivorPhoneRecognition
local C=SurvivorPhoneClock
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
        local ae=a.estimate and 1 or 0;local be=b.estimate and 1 or 0
        if ae~=be then return ae>be end
        if a.today~=b.today then return a.today>b.today end
        if a.state.level~=b.state.level then return a.state.level>b.state.level end
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

local function drawSkillCard(panel,y,row)
    local x,w=panel.pad,panel.bodyW
    local skill,state,estimate=row.skill,row.state,row.estimate
    local estimateLines=estimate and 2 or 0
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

        if estimate then
            local rate='+'..number(estimate.rate or 0)..' XP'
            local actionLine=estimate.confidence..'  /  '..(estimate.actionLabel or 'Last action')..'  '..rate
            local actionColor=estimate.confidence=='Updating' and c.amber or estimate.confirmed and c.mint or c.muted
            D.text(panel,actionLine,x+14,y+91,actionColor,nil,w-28)
            local estimateText
            if estimate.confirmed and (estimate.rate or 0)<=0 then
                estimateText='This action currently grants no XP.'
            elseif estimate.repeats then
                estimateText=estimate.repeats..' more similar action'..(estimate.repeats==1 and '' or 's')..' estimated to reach Level '..(state.level+1)
            elseif estimate.confidence=='Updating' then
                estimateText='XP per action changed. Repeating the action will relearn the new rate.'
            elseif (estimate.rate or 0)<=0 then
                estimateText='Last attempt: 0 XP. Repeat it once more to confirm.'
            else
                estimateText='Learning this action. Repeat it once more before a level estimate is shown.'
            end
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

    y=panel:section('SKILL LEVELS',y)
    y=y+D.wrap(panel,'Current XP and level-end XP are cumulative totals. Repeat estimates use only recent matching actions from the current skill level and relearn whenever the XP rate changes.',x,y,w,c.muted)+12

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