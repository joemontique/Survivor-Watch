require 'ISUI/ISPanel'
require 'SurvivorPhone/Widgets'
require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/Planner'
require 'SurvivorPhone/WhatNow'
require 'SurvivorPhone/XPTracker'

SurvivorWatchUI=ISPanel:derive('SurvivorWatchUI')
local W=SurvivorWatchUI
local D=SurvivorPhoneWidgets
local P=SurvivorPhonePlanner
local C=SurvivorPhoneClock
local c=D.c

local needNames={thirst='Hydration',hunger='Fuel',fatigue='Recovery',endurance='Stamina'}
local needColors={thirst=c.blue,hunger=c.mint,fatigue=c.purple,endurance=c.amber}
local needPriority={fatigue=3,thirst=2,hunger=1}

function W:new(player,item)
    local root=SurvivorPhoneData.get(player)
    local o=ISPanel.new(self,0,0,214,236)
    o.player=player
    o.item=item
    o.root=root
    o.background=false
    o.opacity=root.settings.watchOpacity or math.max(0.65,(root.settings.dimmer or 1)*0.9)
    o.lh=D.fontHeight(UIFont.Small)+4
    o.regions={}
    o:resizeWatch()
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    o:setX(math.max(0,math.min(sw-o.width,root.settings.watchX or sw-o.width-28)))
    o:setY(math.max(0,math.min(sh-o.height,root.settings.watchY or sh-o.height-96)))
    return o
end

function W:resizeWatch()
    local s=self.root.settings.watchScale or 1
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    self:setWidth(math.min(sw-18,math.floor(184+62*s)))
    self:setHeight(math.min(sh-18,math.floor(166+82*s)))
    self.pad=10
    self:setX(math.max(0,math.min(sw-self.width,self.x)))
    self:setY(math.max(0,math.min(sh-self.height,self.y)))
end

function W:close(disable)
    self:setCapture(false)
    self:setVisible(false)
    self:removeFromUIManager()
    self.root.settings.watchX,self.root.settings.watchY=self.x,self.y
    if disable then self.root.settings.watchEnabled=false end
    if SurvivorPhone then SurvivorPhone.watchWindows[self.player:getPlayerNum()]=nil end
end

function W:region(id,x,y,w,h,action)
    table.insert(self.regions,{id=id,x=x,y=y,w=w,h=h,action=action})
end

function W:hit(x,y)
    for i=#self.regions,1,-1 do
        local r=self.regions[i]
        if x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h then return r end
    end
end

function W:button(id,label,x,y,w,h,action,style)
    local hot=self.hoverId==id
    local color=style=='primary' and c.mint or style=='mute' and c.amber or hot and c.line or c.raised
    D.round(self,x,y,w,h,color,1,7)
    local fg=style=='primary' and c.bg or c.text
    D.text(self,label,x+math.max(6,(w-D.measure(label))/2),y+(h-D.fontHeight())/2,fg,nil,w-12)
    self:region(id,x,y,w,h,action)
end

function W:chip(id,label,x,y,w,h,action,active)
    D.round(self,x,y,w,h,active and c.amber or c.raised,active and 0.92 or 0.82,8)
    D.text(self,label,x+math.max(5,(w-D.measure(label))/2),y+(h-D.fontHeight())/2,active and c.bg or c.text,nil,w-10)
    self:region(id,x,y,w,h,action)
end

local function urgentNeed(root)
    local active,activeScore,soon
    for _,bar in ipairs(((root.needs or {}).bars or {})) do
        if bar.key~='endurance' then
            local level=tonumber(bar.level) or 0
            if level>0 then
                local score=level*100+(needPriority[bar.key] or 0)
                if not active or score>activeScore or score==activeScore and (bar.eta or math.huge)<(active.eta or math.huge) then
                    active,activeScore=bar,score
                end
            elseif bar.eta and (not soon or bar.eta<soon.eta) then
                soon=bar
            end
        end
    end
    if active then return active,(needNames[active.key] or active.label)..' / '..active.status end
    if soon then return soon,(needNames[soon.key] or soon.label)..' in '..C.irlEta(soon.eta) end
end

function W:bodyBattery()
    local total,count=0,0
    for _,bar in ipairs(((self.root.needs or {}).bars or {})) do
        total=total+math.max(0,math.min(1,bar.fill or 0));count=count+1
    end
    return count>0 and total/count or nil
end

function W:drawVitals(x,y,w)
    local bars=((self.root.needs or {}).bars or {})
    if #bars==0 then
        D.text(self,'Vitals learning',x,y,c.muted,nil,w)
        return y+self.lh+2
    end
    local rowH=14
    for _,bar in ipairs(bars) do
        local name=needNames[bar.key] or bar.label
        local color=bar.level and bar.level>=3 and c.red or bar.level and bar.level>=1 and c.amber or needColors[bar.key] or c.mint
        local pct=math.floor((bar.percent or math.min(99.9,(bar.fill or 0)*100))+0.5)..'%'
        D.text(self,name,x,y,c.text,nil,74)
        D.round(self,x+76,y+4,w-116,6,c.raised,1,3)
        if (bar.fill or 0)>0 then D.round(self,x+76,y+4,(w-116)*math.max(0,math.min(1,bar.fill or 0)),6,color,1,3) end
        D.text(self,pct,x+w-36,y,c.muted,nil,36)
        y=y+rowH
    end
    return y+2
end

function W:prerender()
    self.opacity=self.root.settings.watchOpacity or self.opacity
    self.regions={}
    D.round(self,0,0,self.width,self.height,c.bg,1,18)
    D.round(self,7,7,self.width-14,self.height-14,c.card,0.96,14)
    local x,y,w=self.pad,10,self.width-self.pad*2
    local _,planner,now=SurvivorPhoneData.get(self.player)
    D.text(self,'SURVIVOR WATCH',x,y,c.muted,nil,w-42)
    D.text(self,'x',self.width-24,y,c.muted)
    self:region('close',self.width-31,4,28,28,function() self:close(true) end)
    y=y+self.lh+1
    D.text(self,P.time(now.minute),x,y,c.text,UIFont.Large,w)
    y=y+D.fontHeight(UIFont.Large)+4
    y=self:drawVitals(x,y,w)
    local _,needText=urgentNeed(self.root)
    y=y+D.wrap(self,needText or 'Vitals steady',x,y,w,needText and c.amber or c.mint)+3
    D.rect(self,x,y,w,1,c.line)
    y=y+7
    local what=SurvivorPhoneWhatNow.choose(self.root,now,self.player)
    y=y+D.wrap(self,what and what.title or 'Free roam',x,y,w,c.text,UIFont.Medium)+1
    if what and what.subtitle and y<self.height-68 then y=y+D.wrap(self,what.subtitle,x,y,w,c.muted)+2 end
    local current,nextTask=P.radar(planner,now.minute)
    local nextText=nextTask and ('Next '..P.time(nextTask.start)..' / '..nextTask.name) or current and ((current.start and P.time(current.start)..' / ' or '')..current.name) or 'No later task'
    if y<self.height-58 then y=y+D.wrap(self,nextText,x,y,w,c.muted)+2 end
    self:button('open','Details',x,self.height-38,w,28,function()
        if SurvivorPhone then SurvivorPhone.open(self.item,self.player) end
    end,'primary')
end

function W:onMouseDown(x,y)
    self:bringToTop()
    local r=self:hit(x,y)
    if r then
        self.pressedId=r.id
        return true
    end
    self.watchPress=true
    self.pressScreenX=getMouseX()
    self.pressScreenY=getMouseY()
    self.dragX=getMouseX()-self.x
    self.dragY=getMouseY()-self.y
    self:setCapture(true)
    return true
end

function W:onMouseMove(dx,dy)
    local x,y=self:getMouseX(),self:getMouseY()
    local r=self:hit(x,y)
    self.hoverId=r and r.id or nil
    if self.watchPress and not self.dragging then
        local mx,my=getMouseX(),getMouseY()
        if math.abs(mx-(self.pressScreenX or mx))>4 or math.abs(my-(self.pressScreenY or my))>4 then self.dragging=true end
    end
    if self.dragging then
        self:setX(math.max(0,math.min(getCore():getScreenWidth()-self.width,getMouseX()-self.dragX)))
        self:setY(math.max(0,math.min(getCore():getScreenHeight()-self.height,getMouseY()-self.dragY)))
    end
    return true
end

function W:onMouseMoveOutside(dx,dy)
    if self.watchPress or self.dragging then return self:onMouseMove(dx,dy) end
    self.hoverId=nil
end

function W:onMouseUp(x,y)
    local r=self:hit(x,y)
    local wasWatchPress=self.watchPress==true
    local wasDragging=self.dragging==true
    if not wasWatchPress and not wasDragging and r and r.id==self.pressedId and r.action then
        r.action()
    elseif wasWatchPress and not wasDragging and SurvivorPhone then
        SurvivorPhone.open(self.item,self.player)
    end
    self.dragging=false
    self.watchPress=false
    self.pressedId=nil
    self:setCapture(false)
    self.root.settings.watchX,self.root.settings.watchY=self.x,self.y
    return true
end

function W:onMouseUpOutside(x,y)
    self.dragging=false
    self.watchPress=false
    self.pressedId=nil
    self:setCapture(false)
    self.root.settings.watchX,self.root.settings.watchY=self.x,self.y
    return true
end

function W:update()
    ISPanel.update(self)
    if self.lastScreenW~=getCore():getScreenWidth() or self.lastScreenH~=getCore():getScreenHeight() then
        self.lastScreenW=getCore():getScreenWidth()
        self.lastScreenH=getCore():getScreenHeight()
        self:resizeWatch()
    end
    if self.player:isDead() or not self.item:getContainer() or not self.item:getContainer():isInCharacterInventory(self.player) then
        self:close(false)
    end
end

return W
