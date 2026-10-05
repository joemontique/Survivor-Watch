require 'SurvivorPhone/SaveData'

SurvivorPhoneNotifications={windows={},queues={}}
local N=SurvivorPhoneNotifications

function N.dismiss(index)
    local w=N.windows[index]
    if w then
        w:setVisible(false)
        w:removeFromUIManager()
        N.windows[index]=nil
    end
end

function N.ensure(root)
    root.notifications=root.notifications or {history={},seen={}}
    return root.notifications
end

-- Kept for save/UI compatibility. Survivor Watch no longer creates popup notifications.
function N.isMuted(root)
    local s=root and root.settings or {}
    return s.notificationsMuted==true or s.dnd==true
end

function N.emit(player,kind,key,message,app)
    local root,_,now=SurvivorPhoneData.get(player)
    local d=N.ensure(root)
    if d.seen[key] then return false end
    local entry={key=key,day=now.day,minute=now.minute,kind=kind,message=message,app=app or 'home'}
    d.seen[key]=true
    table.insert(d.history,entry)
    while #d.history>100 do
        local old=table.remove(d.history,1)
        d.seen[old.key]=nil
    end
    return true
end

function N.deliver(player)
    -- History is retained, but popup delivery is intentionally disabled.
    local index=player and player:getPlayerNum()
    if index~=nil then N.dismiss(index) end
    if player then N.queues[player]=nil end
end

return N
