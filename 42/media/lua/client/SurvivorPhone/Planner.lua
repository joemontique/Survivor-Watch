-- Pure planner rules. No UI or engine calls; all times are minutes within a day.
SurvivorPhonePlanner = {}
local P = SurvivorPhonePlanner
P.categories = {"General", "Fishing", "Animals", "Food", "Mechanics", "Skills", "Base", "Generator", "Farming"}
P.kinds = {"Scheduled", "Daily", "Optional"}
P.priorities = {"Low", "Normal", "High"}

local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
local function member(value, values)
    for _, candidate in ipairs(values) do if value == candidate then return true end end
    return false
end

function P.parseTime(value)
    value = trim(value)
    if value == "" then return nil end
    local h, m = value:match("^(%d%d?):(%d%d)$")
    h, m = tonumber(h), tonumber(m)
    if not h or not m or h > 23 or m > 59 then return nil, "Use a time from 00:00 to 23:59." end
    return h * 60 + m
end

function P.time(value)
    if value == nil then return "Anytime" end
    value = value % 1440
    return string.format("%02d:%02d", math.floor(value / 60), value % 60)
end

function P.state(data, task)
    local s = data.states[tostring(task.id)]
    if not s then s = {status="pending"}; data.states[tostring(task.id)] = s end
    return s
end

function P.rollDay(data, day)
    
if data.day ~= day then
        data.history=data.history or {}
        if data.day then data.history[data.day]=data.states end
        local days={};for d in pairs(data.history) do table.insert(days,d) end;table.sort(days)
        while #days>30 do data.history[table.remove(days,1)]=nil end
        data.day=day;data.states={};data.sequence=0;return true
    end
    return false
end

function P.init(root, day)
    if not root.planner then
        root.planner = {tasks={}, states={}, day=day, nextId=1, freeRoam=false}
        local routine = {
            {"Fishing", "Fishing", "Scheduled", 300, 480, "Normal"},
            {"Chicken care", "Animals", "Scheduled", 480, nil, "High"},
            {"Food and water", "Food", "Scheduled", 510, nil, "Normal"},
            {"Mechanics practice", "Mechanics", "Scheduled", 540, nil, "Normal"},
            {"Carving / skill training", "Skills", "Optional", 660, nil, "Low"},
            {"Base projects", "Base", "Daily", nil, nil, "Normal"},
            {"Generator check", "Generator", "Scheduled", 1080, nil, "High"},
            {"Crops and traps", "Farming", "Daily", nil, nil, "Normal"},
        }
        for _, row in ipairs(routine) do
            local data = root.planner
            table.insert(data.tasks, {id=data.nextId, name=row[1], category=row[2], kind=row[3], start=row[4], finish=row[5], priority=row[6], notes=""})
            data.nextId = data.nextId + 1
        end
    end
    
local data=root.planner
    data.states=data.states or {};data.sequence=data.sequence or 0
    -- Only migrate the original named activities; custom entries stay manual.
    local defaults={Fishing='Fishing catch',['Chicken care']='Animal care XP',
        ['Mechanics practice']='Mechanics XP',['Carving / skill training']='Carving XP',
        ['Generator check']='Generator interaction'}
    for _,task in ipairs(data.tasks) do
        if not task.recognition then task.recognition=defaults[task.name] or 'Manual' end
        data.nextId=math.max(data.nextId or 1,task.id+1)
        data.sequence=math.max(data.sequence,P.state(data,task).completionOrder or 0)
    end
    if not data.orderVersion then
        local completed={}
        for _,task in ipairs(data.tasks) do if P.state(data,task).status=='done' then table.insert(completed,task) end end
        table.sort(completed,function(a,b)
            local sa,sb=P.state(data,a),P.state(data,b)
            if (sa.completedAt or -1)~=(sb.completedAt or -1) then return (sa.completedAt or -1)<(sb.completedAt or -1) end
            return a.id<b.id
        end)
        for _,task in ipairs(completed) do data.sequence=data.sequence+1;P.state(data,task).completionOrder=data.sequence end
        data.orderVersion=1
    end
    root.schemaVersion=math.max(root.schemaVersion or 1,5)
    root.lastApp = root.lastApp or "home"
    P.rollDay(root.planner, day)
    return root.planner
end

function P.find(data, id)
    for _, task in ipairs(data.tasks) do if task.id == id then return task end end
end

function P.save(data, id, fields)
    local name = trim(fields.name)
    if name == "" or #name > 40 then return nil, "Name must be 1-40 characters." end
    local notes = trim(fields.notes)
    if #notes > 240 then return nil, "Notes must be 240 characters or fewer." end
    if not member(fields.category, P.categories) or not member(fields.kind, P.kinds) or not member(fields.priority, P.priorities) then
        return nil, "Choose a category, type, and priority."
    end
    local start, err = P.parseTime(fields.start)
    if err then return nil, err end
    local finish, endErr = P.parseTime(fields.finish)
    if endErr then return nil, endErr end
    if fields.kind == "Scheduled" and start == nil then return nil, "Scheduled tasks need a start time." end
    if finish and (not start or finish <= start) then return nil, "End must be after start on the same day." end
    local old = id and P.find(data, id)
    if id and not old then return nil, "This activity no longer exists." end
    if not old and #data.tasks >= 100 then return nil, "The planner supports up to 100 activities." end
    local task = old or {id=data.nextId}
    -- Preserve today's completion when editing; a changed time starts a fresh reminder.
    local changedTime = old and (old.start ~= start or old.finish ~= finish)
    task.name, task.notes = name, notes
    task.category, task.kind, task.priority = fields.category, fields.kind, fields.priority
    task.start, task.finish = start, finish
    task.recognition=fields.recognition or task.recognition or "Manual"
    if not old then data.nextId=data.nextId+1; table.insert(data.tasks,task) end
    if changedTime then
        local s = P.state(data, task)
        s.notified, s.snoozeUntil = nil, nil
        if s.status == "snoozed" then s.status = "pending" end
    end
    return task
end

function P.delete(data, id)
    for i, task in ipairs(data.tasks) do
        if task.id == id then table.remove(data.tasks, i); data.states[tostring(id)] = nil; return true end
    end
    return false
end

function P.action(data, id, action, minute)
    local task = P.find(data, id)
    if not task then return false end
    local s = P.state(data, task)
    if action=='done' and s.status=='done' then return false end
    if action == "done" or action == "skipped" or action == "pending" then
        s.status=action; s.snoozeUntil=nil
        
if action == "done" then
            data.sequence=(data.sequence or 0)+1;s.completedAt=minute;s.completionOrder=data.sequence
        else s.completedAt=nil;s.completionOrder=nil;s.evidence=nil;s.startedAt=nil end
        -- Undo is explicit; make a due reminder eligible again.
        if action == "pending" then s.notified=nil end
    elseif action == "start" then
        for _, other in ipairs(data.tasks) do
            local state = P.state(data, other)
            if state.status == "active" then state.status = "pending";state.startedAt=nil end
        end
        s.status="active";s.snoozeUntil=nil;s.notified=true;s.startedAt=minute
    elseif action == "snooze" then
        s.status="snoozed"; s.snoozeUntil=minute+30; s.notified=nil
    else return false end
    return true
end

function P.status(data, task, minute)
    local s = P.state(data, task)
    if s.status == "done" then return "Done" end
    if s.status == "skipped" then return "Skipped today" end
    if s.status == "active" then return "In progress" end
    if s.snoozeUntil and minute < s.snoozeUntil then
        if s.snoozeUntil >= 1440 then return "Snoozed for today" end
        return "Snoozed to " .. P.time(s.snoozeUntil)
    end
    if s.snoozeUntil then return "Due now" end
    if task.finish and minute >= task.finish then return "Window passed" end
    if task.start and minute >= task.start then return "Due now" end
    return task.start and "Upcoming" or "Anytime today"
end

function P.sorted(data)
    local tasks = {}
    for _, task in ipairs(data.tasks) do table.insert(tasks, task) end
    local rank={High=1, Normal=2, Low=3}
    table.sort(tasks, function(a,b)
        local at,bt=a.start or 1440,b.start or 1440
        if at ~= bt then return at < bt end
        if a.priority ~= b.priority then return rank[a.priority] < rank[b.priority] end
        return a.id < b.id
    end)
    return tasks
end

function P.nextTask(data, minute)
    local best, bestRank, bestDue, bestPriority
    local priorities={High=1, Normal=2, Low=3}
    for _, task in ipairs(data.tasks) do
        local status=P.status(data,task,minute)
        if status ~= "Done" and status ~= "Skipped today" and status ~= "Window passed" then
            local state=P.state(data,task)
            local due=state.snoozeUntil or task.start
            local rank=status=="In progress" and 0 or status=="Due now" and 1 or due and 2 or 3
            local priority=priorities[task.priority]
            due=due or 1440
            if not best or rank<bestRank or (rank==bestRank and (due<bestDue or due==bestDue and priority<bestPriority)) then
                best,bestRank,bestDue,bestPriority=task,rank,due,priority
            end
        end
    end
    return best
end

function P.nextAfter(data, minute, excluded)
    local candidates={}
    for _,task in ipairs(P.sorted(data)) do
        if task.id~=excluded then
            local status=P.status(data,task,minute)
            if status~="Done" and status~="Skipped today" and status~="Window passed" then table.insert(candidates,task) end
        end
    end
    return candidates[1]
end

function P.progress(data)
    local count=0
    for _, task in ipairs(data.tasks) do if P.state(data,task).status=="done" then count=count+1 end end
    return count,#data.tasks
end

function P.notifications(data, minute)
    local due={}
    -- Quiet modes suppress delivery, not tracking or history.
    for _, task in ipairs(P.sorted(data)) do
        local s=P.state(data,task)
        if not s.notified and P.status(data,task,minute)=="Due now" then
            s.notified=true
            table.insert(due,task)
        end
    end
    return due
end


P.recognitions={'Manual','Fishing catch','Animal care XP','Mechanics XP','Carving XP','Generator interaction','Skill:Woodwork','Skill:PlantScavenging','Skill:Farming','Farming interaction','Foraging collected','Building completed','Sleep completed'}
function P.latestDone(data)
    local latest,best
    for _,task in ipairs(data.tasks) do
        local s=P.state(data,task);local order=s.completionOrder or s.completedAt or -1
        if s.status=='done' and (not best or order>best or order==best and task.id>latest.id) then latest,best=task,order end
    end
    return latest
end
function P.visible(data,history)
    local last=P.latestDone(data);local rows={}
    for _,task in ipairs(P.sorted(data)) do
        local status=P.state(data,task).status
        if history or (status~='done' and status~='skipped') or last and last.id==task.id then table.insert(rows,task) end
    end
    return rows
end
function P.radar(data,minute)
    local active,recent,future;local ordered=P.sorted(data)
    for _,task in ipairs(ordered) do
        local s=P.state(data,task)
        if s.status=='active' then active=task end
        if s.status~='skipped' and task.start then
            if task.start<=minute then recent=task elseif s.status~='done' and not future then future=task end
        end
    end
    local current=active or recent or P.latestDone(data) or future or P.nextTask(data,minute)
    local passed=false
    for _,task in ipairs(ordered) do
        local s=P.state(data,task)
        if passed and s.status~='done' and s.status~='skipped' then return current,task end
        if current and task.id==current.id then passed=true end
    end
    return current,nil
end
function P.recognize(data,rule,minute,evidence)
    local best,active,count,activeCount=nil,nil,0,0
    for _,task in ipairs(P.sorted(data)) do
        local s=P.state(data,task)
        if task.recognition==rule and s.status~='done' and s.status~='skipped' then
            count=count+1;best=task
            if s.status=='active' then active=task;activeCount=activeCount+1 end
        end
    end
    best=activeCount==1 and active or count==1 and best or nil
    if best then
        local s=P.state(data,best)
        P.action(data,best.id,'done',minute);s.evidence=evidence;return best
    end
end
return P
