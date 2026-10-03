require 'SurvivorPhone/Learning'
local L=SurvivorPhoneLearning
local P=SurvivorPhonePlanner
SurvivorPhoneSuggestions={}
local S=SurvivorPhoneSuggestions
local function median(values)
    table.sort(values);local n=#values
    if n==0 then return nil end
    return n%2==1 and values[(n+1)/2] or (values[n/2]+values[n/2+1])/2
end
local function round(v) return math.floor(v/5+0.5)*5 end
local function snapshot(t)
    if not t then return nil end
    local s={};for _,k in ipairs({'id','name','start','finish','category','kind','priority','recognition','notes','needKey'}) do s[k]=t[k] end;return s
end
local function fingerprint(t)
    if not t then return '-' end
    local parts={};for _,k in ipairs({'id','name','start','finish','category','kind','priority','recognition','notes','needKey'}) do table.insert(parts,tostring(t[k] or '')) end
    return table.concat(parts,'|')
end
local function analyze(rows,day)
    local starts,durations,used,needDays={},{},{},{}
    for i=#rows,1,-1 do
        local r=rows[i]
        if r.day~=day and not used[r.day] and r.arrivalVerified~=false and r.minute and r.minute>=0 and r.minute<1440 then
            used[r.day]=true;table.insert(starts,r.minute)
            if r.duration and r.duration>=5 then table.insert(durations,r.duration) end
            for key,need in pairs(r.needs or {}) do if (need.level or 0)>0 or need.eta and need.eta<=30 then needDays[key]=(needDays[key] or 0)+1 end end
            if #starts>=7 then break end
        end
    end
    local mid=median(starts);local duration=median(durations)
    if #starts<3 or starts[#starts]-starts[1]>120 then return nil end
    return {start=round(mid),duration=#durations>=3 and round(duration) or nil,count=#starts,needs=needDays,spread=starts[#starts]-starts[1]}
end
local function conflicts(data,proposal,excluded)
    local result={};if not proposal or not proposal.start then return result end
    local finish=proposal.finish or proposal.start+15
    for _,task in ipairs(data.tasks) do
        if task.id~=excluded and task.start and proposal.start<(task.finish or task.start+15) and task.start<finish then table.insert(result,task.name..' / '..P.time(task.start)..' - '..P.time(task.finish or task.start+15)) end
    end
    return result
end
local function needPattern(events,key,anchor,day)
    local days={}
    for _,e in ipairs(events) do
        if e.key==key and e.day~=day then
            local delta=(e.minute-anchor+720)%1440-720
            if math.abs(delta)<=60 and (not days[e.day] or math.abs(delta)<math.abs(days[e.day])) then days[e.day]=delta end
        end
    end
    local dates={};for d in pairs(days) do table.insert(dates,d) end;table.sort(dates)
    local offsets={};for i=#dates,math.max(1,#dates-6),-1 do table.insert(offsets,days[dates[i]]) end
    if #offsets<3 then return nil end
    return {start=round((anchor+median(offsets))%1440)%1440,count=#offsets}
end
function S.suggestions(root,now)
    local result={};local data=L.ensure(root)
    if not root.settings.learning then return result end
    local function add(kind,task,proposed,key,stats,reason,evidence)
        local current=snapshot(task)
        local signature=kind..':'..fingerprint(current)..'>'..fingerprint(proposed)
        local decision=data.decisions[key]
        if decision and decision.action=='dismiss' and decision.baseline==fingerprint(current) and decision.proposed and proposed then
            local sameTime=math.abs((decision.proposed.start or 0)-(proposed.start or 0))<15
            local sameEnd=math.abs((decision.proposed.finish or 0)-(proposed.finish or 0))<15
            if decision.proposed.name==proposed.name and sameTime and sameEnd then return end
        end
        if decision and (decision.action=='keep' and decision.baseline==fingerprint(current) or decision.action=='snooze' and decision.day==now.day or decision.signature==signature and decision.action~='snooze') then return end
        local old=task and data.ignored[tostring(task.id)]
        if old==now.day then return end
        local item={key=key,kind=kind,id=task and task.id,taskId=task and task.id,name=(proposed or task).name,start=proposed and proposed.start,finish=proposed and proposed.finish,
            count=stats.count,confidence=stats.count>=5 and 'Strong pattern' or 'Emerging pattern',reason=reason,evidence=evidence or {},current=current,proposed=proposed,
            signature=signature,baseline=fingerprint(current),overlaps=conflicts(root.planner,proposed,task and task.id)}
        for need,count in pairs(stats.needs or {}) do if count>=2 then table.insert(item.evidence,need..' was active or near its threshold on '..count..' observed days.') end end
        table.insert(result,item)
    end
    local linked={}
    for _,task in ipairs(P.sorted(root.planner)) do
        if task.recognition~='Manual' then linked[task.recognition]=true end
        local key=tostring(task.id)
        local rows=data.activityDays[key] or {}
        local stats=analyze(rows,now.day) or analyze(data.tasks[key] or {},now.day)
        if stats and task.start then
            local start=math.abs(stats.start-task.start)>=15 and stats.start or task.start
            local duration=stats.duration
            local finish=duration and start+math.max(5,duration) or task.finish and start+(task.finish-task.start) or nil
            if (not finish or finish<1440) and (start~=task.start or finish and (not task.finish or math.abs(finish-task.finish)>=15)) then
                local proposal=snapshot(task);proposal.start=start;proposal.finish=finish
                add('adjust',task,proposal,'task:'..key,stats,'Match this activity to the time you actually spend on it.',{'Median arrival '..P.time(stats.start)..' across '..stats.count..' separate days.',duration and 'Median verified activity time: '..duration..' game min.' or 'Duration is unchanged until more complete sessions are observed.'})
            end
        end
        local skips=0
        for day in pairs(data.skips[key] or {}) do if day~=now.day then skips=skips+1 end end
        if skips>=3 then add('remove',task,nil,'remove:'..key,{count=skips},'You have explicitly skipped this activity repeatedly.',{'Skipped on '..skips..' separate days. Missing detections never count as skips.','Removing it archives this activity and keeps its history.'}) end
    end
    local groupNames={['Fishing catch']={'Fishing','Fishing'},['Animal care XP']={'Animal care','Animals'},['Mechanics XP']={'Mechanics practice','Mechanics'},['Carving XP']={'Carving practice','Skills'},['Generator interaction']={'Generator check','Generator'}}
    local groupKeys={};for group in pairs(data.groups) do table.insert(groupKeys,group) end;table.sort(groupKeys)
    for _,group in ipairs(groupKeys) do
        local value=data.groups[group];local stats=analyze(value.rows or {},now.day)
        if stats and not linked[group] then
            local meta=groupNames[group];local name=meta and meta[1] or tostring(value.name or group):sub(1,31)..' practice'
            local duplicate=false
            for _,task in ipairs(root.planner.tasks) do if task.name:lower()==name:lower() then duplicate=true end end
            local finish=stats.duration and stats.start+math.max(5,stats.duration) or nil
            if not duplicate and (not finish or finish<1440) then
                local proposal={name=name,category=meta and meta[2] or 'Skills',kind='Scheduled',priority='Normal',start=stats.start,finish=finish,recognition=group,notes='Suggested from observed activity.'}
                add('add',nil,proposal,'group:'..group,stats,'Make room for an activity you already return to.',{'Observed on '..stats.count..' separate days. Median arrival '..P.time(stats.start)..'.',stats.duration and 'Median verified duration: '..stats.duration..' game min.' or 'A single XP event establishes arrival, not duration.'})
            end
        end
    end
    local pendingNeeds={}
    local function proposeNeed(task,proposal,key,stats,reason,evidence)
        if not task then add('add',nil,proposal,key,stats,reason,evidence);return end
        local old=pendingNeeds[task.id]
        if not old then pendingNeeds[task.id]={task=task,proposal=proposal,stats=stats,reason=reason,evidence=evidence};return end
        -- A combined food-and-water entry gets one coherent proposal, using the
        -- earlier need, rather than competing edits for the same activity.
        local earlier=(proposal.start-task.start+720)%1440-720<(old.proposal.start-task.start+720)%1440-720
        if earlier then old.proposal=proposal end
        old.reason='Prepare before your recurring needs usually begin.'
        old.stats.count=math.min(old.stats.count,stats.count)
        for _,line in ipairs(evidence) do table.insert(old.evidence,line) end
    end
    local needMeta={hunger={'Eat and refuel','Food','Peckish'},thirst={'Drink water','Food','Thirsty'},fatigue={'Wind down for sleep','General','Drowsy'}}
    for _,key in ipairs({'hunger','thirst','fatigue'}) do
        local meta=needMeta[key];local used={}
        for anchor=0,1380,60 do
            local stats=needPattern((root.needsHistory or {}).onsets or {},key,anchor,now.day)
            local duplicate=false
            if stats then for _,minute in ipairs(used) do if math.abs((stats.start-minute+720)%1440-720)<120 then duplicate=true end end end
            if stats and not duplicate then
                table.insert(used,stats.start)
                local start=(stats.start-(root.settings.leadMinutes or 30))%1440
                local task,distance=nil,nil
                for _,candidate in ipairs(root.planner.tasks) do
                    local name=candidate.name:lower()
                    local matches=candidate.needKey==key or key=='hunger' and (name:find('food',1,true) or name:find('eat',1,true) or name:find('meal',1,true))
                        or key=='thirst' and (name:find('water',1,true) or name:find('drink',1,true)) or key=='fatigue' and (name:find('sleep',1,true) or name:find('bed',1,true) or name:find('wind down',1,true))
                    local delta=candidate.start and math.abs(candidate.start-start) or 1440;delta=math.min(delta,1440-delta)
                    if matches and candidate.start and delta<=120 and (not distance or delta<distance) then task,distance=candidate,delta end
                end
                if not task or math.abs(start-task.start)>=15 then
                    local proposal=snapshot(task) or {name=meta[1],category=meta[2],kind='Scheduled',priority='High',recognition='Manual',notes='Suggested from your observed '..meta[3]..' times.',needKey=key}
                    proposal.start=start;local duration=task and task.finish and task.finish-task.start or 15
                    proposal.finish=start+duration<1440 and start+duration or nil
                    proposeNeed(task,proposal,'need:'..key..':'..math.floor((stats.start+60)%1440/120),stats,'Prepare before '..meta[3]..' usually begins.',{'Native '..meta[3]..' onset near '..P.time(stats.start)..' across '..stats.count..' separate days.',(root.settings.leadMinutes or 30)..' game min of lead time. Eating, drinking and sleep remain manual.',start>stats.start and 'This preparation time is on the evening before the observed onset.' or 'The current bar forecast can change with activity and recovery.'})
                end
            end
        end
    end
    for _,task in ipairs(P.sorted(root.planner)) do
        local proposal=pendingNeeds[task.id]
        if proposal then add('adjust',task,proposal.proposal,'need-task:'..task.id,proposal.stats,proposal.reason,proposal.evidence) end
    end
    return result
end
function S.decide(root,suggestion,action,now)
    now=now or SurvivorPhoneClock.now()
    local data=L.ensure(root);local task=suggestion.id and P.find(root.planner,suggestion.id)
    if suggestion.id and (not task or fingerprint(task)~=suggestion.baseline) then return false,'The activity changed. Review a fresh suggestion.' end
    if action=='apply' then
        local fresh
        for _,item in ipairs(S.suggestions(root,now)) do if item.key==suggestion.key and item.signature==suggestion.signature then fresh=item;break end end
        if not fresh then return false,'This suggestion is no longer current. Review the updated observations.' end
        if suggestion.kind=='remove' then
            root.planner.archived=root.planner.archived or {}
            table.insert(root.planner.archived,{task=snapshot(task),state=snapshot(P.state(root.planner,task)),day=now.day,reason=suggestion.reason})
            -- Keep the full current state, including evidence, alongside archived task.
            local archived=root.planner.archived[#root.planner.archived];archived.state={}
            for k,v in pairs(P.state(root.planner,task)) do archived.state[k]=v end
            while #root.planner.archived>100 do table.remove(root.planner.archived,1) end
            if task.recognition~='Manual' then data.decisions['group:'..task.recognition]={action='keep',baseline='-',day=now.day} end
            if task.needKey then for bucket=0,11 do data.decisions['need:'..task.needKey..':'..bucket]={action='keep',baseline='-',day=now.day} end end
            P.delete(root.planner,task.id)
        else
            local p=suggestion.proposed
            local fields={name=p.name,category=p.category,kind=p.kind,priority=p.priority,notes=p.notes or '',recognition=p.recognition,start=p.start and P.time(p.start) or '',finish=p.finish and P.time(p.finish) or ''}
            local saved,err=P.save(root.planner,suggestion.id,fields)
            if not saved then return false,err end
            saved.needKey=p.needKey
        end
        table.insert(data.audit,{day=now.day,minute=now.minute,kind=suggestion.kind,name=suggestion.name,before=suggestion.current,after=suggestion.proposed})
        while #data.audit>60 do table.remove(data.audit,1) end
    elseif action~='snooze' and action~='dismiss' and action~='keep' then return false,'Unknown choice.' end
    data.decisions[suggestion.key]={action=action,day=now.day,signature=suggestion.signature,baseline=suggestion.baseline,proposed=suggestion.proposed}
    return true
end
L.suggestions=S.suggestions
L.decide=S.decide
L.apply=function(root,suggestion,now) return S.decide(root,suggestion,'apply',now) end
L.dismiss=function(root,suggestion,snooze,day) return S.decide(root,suggestion,snooze and 'snooze' or 'dismiss',{day=day or SurvivorPhoneClock.now().day}) end
return S
