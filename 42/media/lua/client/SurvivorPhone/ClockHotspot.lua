require 'ISUI/ISPanel'

SurvivorWatchClockHotspot=ISPanel:derive('SurvivorWatchClockHotspot')
local H=SurvivorWatchClockHotspot
H.instance=nil

function H:new(player)
    local o=ISPanel.new(self,-1000,-1000,1,1)
    o.player=player
    o.background=false
    o.borderColor={r=0,g=0,b=0,a=0}
    o.backgroundColor={r=0,g=0,b=0,a=0}
    o.enabled=false
    return o
end

local function clockBounds()
    if not UIManager or not UIManager.getClock then return nil end
    local ok,clock=pcall(function() return UIManager.getClock() end)
    if not ok or not clock then return nil end
    local okVisible,visible=pcall(function() return clock:isVisible() end)
    if okVisible and not visible then return nil end
    local okX,x=pcall(function() return clock:getX() end)
    local okY,y=pcall(function() return clock:getY() end)
    local okW,w=pcall(function() return clock:getWidth() end)
    local okH,h=pcall(function() return clock:getHeight() end)
    if not (okX and okY and okW) then return nil end
    return tonumber(x) or 0,tonumber(y) or 0,math.max(1,tonumber(w) or 1),math.max(24,okH and tonumber(h) or 44)
end

function H:update()
    ISPanel.update(self)
    local player=self.player
    local S=SurvivorPhone
    if not player or not S or isClient() or isServer() or player:isDead() then
        self.enabled=false;self:setX(-1000);self:setY(-1000);return
    end
    local watch=S.findTracker and S.findTracker(player:getInventory()) or nil
    local x,y,w,h=clockBounds()
    if not watch or not x then
        self.enabled=false;self:setX(-1000);self:setY(-1000);self:setWidth(1);self:setHeight(1);return
    end
    self.enabled=true
    self:setX(x);self:setY(y);self:setWidth(w);self:setHeight(h)
end

function H:prerender()
    -- Intentionally transparent. This panel only makes the vanilla watch/time display clickable.
end

function H:onMouseDown(x,y)
    if not self.enabled then return false end
    self.pressed=true
    return true
end

function H:onMouseUp(x,y)
    if not self.enabled or not self.pressed then self.pressed=false;return false end
    self.pressed=false
    local S=SurvivorPhone
    local player=self.player
    if not S or not player then return true end
    local index=player:getPlayerNum()
    if S.windows and S.windows[index] then
        S.windows[index]:close()
        return true
    end
    local watch=S.findTracker(player:getInventory())
    if watch then S.openWatch(watch,player) end
    return true
end

function H:onMouseUpOutside(x,y)
    self.pressed=false
    return false
end

function H.install(player)
    if H.instance then
        H.instance:setVisible(false)
        H.instance:removeFromUIManager()
        H.instance=nil
    end
    if not player or isClient() or isServer() then return end
    local panel=H:new(player)
    panel:initialise()
    panel:addToUIManager()
    panel:setVisible(true)
    H.instance=panel
    return panel
end

return H
