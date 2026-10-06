require 'ISUI/ISPanel'
require 'SurvivorPhone/GameClock'

SurvivorWatchClockHotspot=ISPanel:derive('SurvivorWatchClockHotspot')
local H=SurvivorWatchClockHotspot
H.instance=nil

function H:new(player)
    local o=ISPanel.new(self,-1000,-1000,1,1)
    o.player=player
    o.watch=nil
    o.nextWatchSearch=0
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

local function clockTimeBounds()
    local x,y,w,h=clockBounds()
    if not x then return nil end
    -- The vanilla digital-watch face places the time in the upper-left portion,
    -- with the alarm control to its right and date/temperature below. Survivor
    -- Watch only owns the time digits; all other clock controls stay vanilla.
    local insetX=math.max(2,math.floor(w*0.02))
    local insetY=math.max(2,math.floor(h*0.05))
    local timeW=math.max(36,math.floor(w*0.64))
    local timeH=math.max(18,math.floor(h*0.52))
    return x+insetX,y+insetY,math.min(timeW,w-insetX),math.min(timeH,h-insetY)
end

local function validWatch(S,watch,player)
    if not S or not watch or not player then return false end
    local ok,value=pcall(function()
        local container=watch:getContainer()
        return container and container:isInCharacterInventory(player) and S.isDigitalWatch(watch)
    end)
    return ok and value==true
end

local function watchRinging(watch)
    if not watch or not watch.isRinging then return false end
    local ok,value=pcall(function() return watch:isRinging() end)
    return ok and value==true
end

function H:getWatch(S,force)
    if validWatch(S,self.watch,self.player) then return self.watch end
    self.watch=nil
    local seconds=SurvivorPhoneClock.realSeconds()
    if not force and seconds<(self.nextWatchSearch or 0) then return nil end
    self.nextWatchSearch=seconds+1
    local found=S and S.findTracker and S.findTracker(self.player:getInventory()) or nil
    if validWatch(S,found,self.player) then self.watch=found end
    return self.watch
end

function H:update()
    ISPanel.update(self)
    local player=self.player
    local S=SurvivorPhone
    if not player or not S or isClient() or isServer() or player:isDead() then
        self.enabled=false;self.watch=nil;self:setX(-1000);self:setY(-1000);return
    end
    local watch=self:getWatch(S,false)
    if watchRinging(watch) then
        -- The vanilla clock/watch HUD owns alarm dismissal. Move our transparent
        -- click target away until the alarm stops ringing.
        self.enabled=false;self.pressed=false
        self:setX(-1000);self:setY(-1000);self:setWidth(1);self:setHeight(1)
        return
    end
    local x,y,w,h=clockTimeBounds()
    if not watch or not x then
        self.enabled=false;self:setX(-1000);self:setY(-1000);self:setWidth(1);self:setHeight(1);return
    end
    self.enabled=true
    self:setX(x);self:setY(y);self:setWidth(w);self:setHeight(h)
end

function H:prerender()
    -- Intentionally transparent. Only the vanilla time digits are intercepted;
    -- alarm controls and the rest of the vanilla clock remain clickable.
end

function H:onMouseDown(x,y)
    if not self.enabled then return false end
    local S=SurvivorPhone
    local watch=S and self:getWatch(S,false) or nil
    if watchRinging(watch) then
        self.enabled=false;self.pressed=false
        self:setX(-1000);self:setY(-1000);self:setWidth(1);self:setHeight(1)
        return false
    end
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
    local watch=self:getWatch(S,true)
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