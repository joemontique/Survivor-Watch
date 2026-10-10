pcall(require,'XpSystem/XPSystem_SkillBook')

SurvivorPhoneReading={}
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

local function multiplier(player,perk)
    if not player or not player.getXp then return 0 end
    local xp=player:getXp()
    if not xp or not xp.getMultiplier then return 0 end
    local value=safe(function() return xp:getMultiplier(perk) end)
    value=tonumber(value)
    return value and value>0 and value or 0
end

local function expected(entry,volume)
    if not entry then return nil end
    return tonumber(entry['maxMultiplier'..tostring(volume)])
end

function R.recommendations(player,tracker,skills)
    local rows={}
    if not player or not tracker or not skills then return rows end
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
                        local bookLabel=skill.name..' Vol. '..(roman[volume] or tostring(volume))
                        table.insert(rows,{
                            skill=skill.name,skillId=skill.id,today=today,level=level,volume=volume,
                            book=bookLabel,
                            levelStart=start,levelEnd=volume*2,current=current,full=full,
                            status=current<=0.01 and 'Not read' or 'Partially read'
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

return R
