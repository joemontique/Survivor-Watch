pcall(require,'XpSystem/XPSystem_SkillBook')

SurvivorPhoneReading={books=nil}
local R=SurvivorPhoneReading

local roman={'I','II','III','IV','V'}

local function safe(fn)
    local ok,value=pcall(fn)
    if ok then return value end
end

local function samePerk(a,b)
    return a~=nil and b~=nil and a==b
end

local function skillBookEntry(perk)
    if not SkillBook then return nil,nil end
    for name,entry in pairs(SkillBook) do
        if entry and samePerk(entry.perk,perk) then return name,entry end
    end
end

local function discoverBooks()
    if R.books then return R.books end
    R.books={}
    local manager=getScriptManager and getScriptManager()
    local items=manager and manager.getAllItems and manager:getAllItems()
    if not items or not items.size or not items.get then return R.books end
    for i=0,items:size()-1 do
        local item=items:get(i)
        local trained=safe(function() return item:getSkillTrained() end)
        local start=safe(function() return item:getLevelSkillTrained() end)
        if trained and start and SkillBook and SkillBook[trained] then
            R.books[trained]=R.books[trained] or {}
            R.books[trained][tonumber(start)]={
                name=safe(function() return item:getDisplayName() end),
                start=tonumber(start),
                finish=tonumber(safe(function() return item:getMaxLevelTrained() end))
            }
        end
    end
    return R.books
end

local function multiplier(player,perk)
    if not player or not player.getXp then return 1 end
    local xp=player:getXp()
    if not xp or not xp.getMultiplier then return 1 end
    local value=safe(function() return xp:getMultiplier(perk) end)
    value=tonumber(value)
    return value and value>0 and value or 1
end

local function expected(entry,volume)
    if not entry then return nil end
    return tonumber(entry['maxMultiplier'..tostring(volume)])
end

function R.recommendations(player,tracker,skills)
    local rows={}
    if not player or not tracker or not skills then return rows end
    local books=discoverBooks()
    for _,skill in ipairs(skills) do
        local today=tonumber((tracker.totals or {})[skill.id]) or 0
        if today>0 then
            local level=player:getPerkLevel(skill.perk)
            if level<10 then
                local bookSkill,entry=skillBookEntry(skill.perk)
                if bookSkill and entry then
                    local volume=math.floor(level/2)+1
                    local full=expected(entry,volume)
                    local current=multiplier(player,skill.perk)
                    if full and full>1 and current<full-0.01 then
                        local start=(volume-1)*2+1
                        local found=books[bookSkill] and books[bookSkill][start]
                        local fallback=skill.name..' '..(roman[volume] or tostring(volume))
                        table.insert(rows,{
                            skill=skill.name,skillId=skill.id,today=today,level=level,volume=volume,
                            book=found and found.name or fallback,
                            levelStart=start,levelEnd=volume*2,current=current,full=full,
                            status=current<=1.01 and 'Not read' or 'Partially read'
                        })
                    end
                end
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.today~=b.today then return a.today>b.today end
        return a.skill<b.skill
    end)
    return rows
end

function R.resetCache()
    R.books=nil
end

return R
