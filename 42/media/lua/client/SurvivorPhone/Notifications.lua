require 'ISUI/ISPanel'
require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/Widgets'
SurvivorPhoneNotifications={windows={},queues={}}
local N=SurvivorPhoneNotifications
local D=SurvivorPhoneWidgets
local Toast=ISPanel:derive('SurvivorDashboardToast')
function N.dismiss(index)
    local w=N.windows[index]
    if w then w:setVisible(false);w:removeFromUIManager();N.windows[index]=nil end
end
function N.ensure(root)
    root.notifications=root.notifications or {history={},seen={}}
    return root.notifications
end
function N.isMuted(root)
    local s=root and root.settings or {}
    return s.notificationsMuted==true or s.dnd==true
end
function N.emit(player,kind,key,message,app)
    local root,planner,now=SurvivorPhoneData.get(player);local d=N.ensure(root)
    if d.seen[key] then return false end
    local entry={key=key,day=now.day,minute=now.minute,kind=kind,message=message,app=app or 'home'}
    d.seen[key]=true;table.insert(d.history,entry)
    while #d.history>100 do local old=table.remove(d.history,1);d.seen[old.key]=nil end
    if N.isMuted(root) or kind=='routine' and planner.freeRoam or player:isAsleep() then return true end
    local queue=N.queues[player] or {};N.queues[player]=queue
    table.insert(queue,{entry=entry,expires=SurvivorPhoneClock.realSeconds()+30})
    while #queue>4 do table.remove(queue,1) end
    return true
end
function Toast:prerender()
    D.round(self,0,0,self.width,self.height,D.c.bg,1,12)
    D.round(self,0,12,4,self.height-24,D.c.mint,1,2)
    D.text(self,self.entry.kind=='wake' and 'MORNING REPORT' or 'SURVIVOR',16,12,D.c.mint,nil,self.width-66)
    D.text(self,'x',self.width-28,12,D.c.muted)
    D.wrap(self,self.entry.message,16,38,self.width-32,D.c.text)
    D.text(self,'Click to open / '..SurvivorPhonePlanner.time(self.entry.minute),16,self.height-D.fontHeight()-12,D.c.muted,nil,self.width-32)
end
function Toast:onMouseDown() return true end
function Toast:onMouseUp(x,y)
    if not (x>self.width-48 and y<34) then
        local item=SurvivorPhone.findTracker(self.player:getInventory())
        if item then SurvivorPhone.open(item,self.player);local w=SurvivorPhone.windows[self.player:getPlayerNum()];if w then w:showApp(self.entry.app) end end
    end
    N.dismiss(self.player:getPlayerNum());return true
end
function Toast:update()
    local root=SurvivorPhoneData.get(self.player)
    if self.player:isDead() or self.player:isAsleep() or N.isMuted(root) or root.planner.freeRoam and self.entry.kind=='routine' or SurvivorPhoneClock.realSeconds()>=self.expires then N.dismiss(self.player:getPlayerNum()) end
end
function N.deliver(player)
    if N.windows[player:getPlayerNum()] then return end
    local queue=N.queues[player];if not queue or #queue==0 then return end
    local root=SurvivorPhoneData.get(player)
    local pending=table.remove(queue,1);local e=pending.entry
    if pending.expires<SurvivorPhoneClock.realSeconds() or N.isMuted(root) or player:isAsleep() or e.kind=='routine' and root.planner.freeRoam then return end
    if not SurvivorPhone.findTracker(player:getInventory()) then return end
    local width=math.min(400,getCore():getScreenWidth()-40)
    local lines=math.ceil(D.measure(e.message)/(width-32))+1
    local height=72+lines*(D.fontHeight()+4)
    local x,y=getCore():getScreenWidth()-width-24,80
    local dashboard=SurvivorPhone.windows[player:getPlayerNum()]
    if dashboard and dashboard.x>=width+12 then x=dashboard.x-width-12;y=math.min(dashboard.y,getCore():getScreenHeight()-height-12) end
    local w=ISPanel.new(Toast,x,y,width,height)
    w.player=player;w.entry=e;w.expires=SurvivorPhoneClock.realSeconds()+12;w.opacity=root.settings.dimmer
    w:initialise();w:addToUIManager();w:setVisible(true);N.windows[player:getPlayerNum()]=w
end
return N
