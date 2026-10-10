require 'ISUI/ISPanel'
require 'ISUI/ISTextEntryBox'
require 'ISUI/ISComboBox'
require 'SurvivorPhone/Widgets'
require 'SurvivorPhone/SaveData'
require 'SurvivorPhone/XPTracker'
require 'SurvivorPhone/FishingTracker'
require 'SurvivorPhone/NeedsForecast'
require 'SurvivorPhone/Learning'
require 'SurvivorPhone/SleepCoach'
require 'SurvivorPhone/ScheduleSuggestions'
require 'SurvivorPhone/WhatNow'
require 'SurvivorPhone/Travel'
require 'SurvivorPhone/DebugGate'
SurvivorPhoneUI=ISPanel:derive('SurvivorPhoneUI')
local U=SurvivorPhoneUI
local D=SurvivorPhoneWidgets
local P=SurvivorPhonePlanner
local C=SurvivorPhoneClock
local c=D.c
function U:new(player,item)
    local root=SurvivorPhoneData.get(player)
    local o=ISPanel.new(self,0,0,500,600)
    o.player=player;o.item=item;o.root=root;o.app='home';o.scrollOffset=0;o.regions={};o.entries={}
    o.background=false;o.opacity=root.settings.dimmer;o.lh=D.fontHeight(UIFont.Small)+4
    o:resizeDashboard()
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    o:setX(math.max(0,math.min(sw-o.width,root.settings.posX or sw-o.width-36)))
    o:setY(math.max(0,math.min(sh-o.height,root.settings.posY or 70)))
    return o
end
function U:resizeDashboard()
    local s=math.max(0,math.min(1,(self.root.settings.uiScale-0.5)/0.5))
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    self:setWidth(math.min(sw-24,math.floor(276+146*s)))
    self:setHeight(math.min(sh-36,math.floor(318+202*s)))
    self.compact=self.width<420
    self.pad=self.compact and 12 or 20
    self.header=self.compact and math.max(38,self.lh+12) or math.max(54,self.lh+28)
    self.navHeight=self.compact and self.lh+12 or self.lh+22
    self.bodyY=self.header+self.navHeight+(self.compact and 10 or 16);self.footer=self.compact and 34 or 44
    self.bodyH=self.height-self.bodyY-self.footer-12;self.bodyW=self.width-self.pad*2-8
    self:setX(math.max(0,math.min(sw-self.width,self.x)));self:setY(math.max(0,math.min(sh-self.height,self.y)))
end
function U:close()
    self:clearEntries();self:setCapture(false);self:setVisible(false);self:removeFromUIManager()
    self.root.settings.posX,self.root.settings.posY=self.x,self.y
    if SurvivorPhone then
        local index=self.player:getPlayerNum()
        SurvivorPhone.windows[index]=nil
        if self.root.settings.watchEnabled and SurvivorPhone.isDigitalWatch(self.item) and self.item:getContainer() and self.item:getContainer():isInCharacterInventory(self.player) then
            SurvivorPhone.openWatch(self.item,self.player)
        end
    end
end
function U:clearEntries()
    for _,e in ipairs(self.entries or {}) do if e.unfocus then e:unfocus() end;if e.hidePopup then e:hidePopup() end;self:removeChild(e) end
    self.entries={}
end
function U:showApp(app)
    self:clearEntries();self.editTask=nil;self.editing=false;self.error=nil
    self.app=app;self.root.lastApp=app;self.scrollOffset=0;self.expandedId=nil;self.actionMenuId=nil;self.deleteId=nil
    self.suggestionCache=nil;self.suggestionMessage=nil
    self.travelTaskId=nil;self.travelMessage=nil;self.travelNaming=false
end
function U:region(id,x,y,w,h,action,meta)
    if self.inBody then
        if y<self.bodyY or y+h>self.bodyY+self.bodyH then return end
        local bottom=math.min(y+h,self.bodyY+self.bodyH);y=math.max(y,self.bodyY);h=bottom-y
    end
    if h>0 and w>0 then table.insert(self.regions,{id=id,x=x,y=y,w=w,h=h,action=action,meta=meta}) end
end
function U:hit(x,y)
    for i=#self.regions,1,-1 do local r=self.regions[i];if x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h then return r end end
end
function U:button(id,label,x,y,w,h,fn,style,meta)
    if self.inBody and (y<self.bodyY or y+h>self.bodyY+self.bodyH) then return end
    local hot=self.hoverId==id
    local color=style=='primary' and c.mint or style=='danger' and c.red or style=='ghost' and c.card or hot and c.soft or c.raised
    D.round(self,x,y,w,h,c.line,style=='ghost' and 0.42 or 0.75,9)
    D.round(self,x+1,y+1,w-2,h-2,color,style=='primary' and 0.92 or style=='danger' and 0.90 or 0.82,8)
    if style=='primary' then D.round(self,x+4,y+4,w-8,math.max(2,h*.28),c.text,0.08,6) end
    local fg=(style=='primary' or style=='danger') and c.bg or c.text
    D.text(self,label,x+math.max(8,(w-D.measure(label))/2),y+(h-D.fontHeight())/2,fg,nil,w-16)
    self:region(id,x,y,w,h,fn,meta)
end
function U:heading(title,caption,y)
    local x=self.pad;D.text(self,title,x,y,c.text,UIFont.Medium,self.bodyW)
    y=y+D.fontHeight(UIFont.Medium)+8
    if caption then y=y+D.wrap(self,caption,x,y,self.bodyW,c.muted)+6 end
    return y+8
end
function U:section(title,y)
    D.text(self,title,self.pad,y,c.muted,nil,self.bodyW);return y+self.lh+10
end
function U:card(x,y,w,h,color,alpha)
    D.round(self,x,y,w,h,c.line,0.45,14)
    D.round(self,x+1,y+1,w-2,h-2,color or c.card,alpha or 0.92,13)
end
local function clamp01(value) return math.max(0,math.min(1,value or 0)) end
local function firstNeed(root,key)
    for _,bar in ipairs(((root.needs or {}).bars or {})) do
        if bar.key==key then return bar end
    end
end
local function bodyBattery(root)
    local total,count=0,0
    for _,bar in ipairs(((root.needs or {}).bars or {})) do
        total=total+clamp01(bar.fill);count=count+1
    end
    if count==0 then return nil end
    return total/count
end
function U:trackerRing(label,value,color,x,y,w)
    value=clamp01(value)
    D.text(self,label,x,y,c.text,nil,w)
    local percent=math.floor(value*100+0.5)..'%'
    D.text(self,percent,x+w-D.measure(percent),y,color,nil,w)
    local by=y+self.lh+3
    D.round(self,x,by,w,9,c.raised,1,5)
    if value>0 then D.round(self,x,by,w*value,9,color,1,5) end
    return y+self.lh+18
end
function U:statPill(label,value,x,y,w,color)
    self:card(x,y,w,self.lh*2+26,c.raised,0.80)
    D.text(self,label,x+12,y+10,c.muted,nil,w-24)
    D.text(self,value,x+12,y+self.lh+17,color or c.text,UIFont.Medium,w-24)
end
function U:appTile(id,label,caption,icon,x,y,w,h,color,action)
    self:card(x,y,w,h,c.raised,0.78)
    D.round(self,x+12,y+12,34,34,color or c.mint,0.22,12)
    D.icon(self,icon,x+18,y+18,color or c.mint)
    D.text(self,label,x+56,y+12,c.text,UIFont.Medium,w-68)
    if caption then D.text(self,caption,x+56,y+15+D.fontHeight(UIFont.Medium),c.muted,nil,w-68) end
    self:region(id,x,y,w,h,action)
end
function U:drawTrackerSummary(y,now)
    local x,w=self.pad,self.bodyW
    local done,total=P.progress(self.root.planner)
    local xp=SurvivorPhoneXP.ensure(self.root,now.day)
    local xpTotal=SurvivorPhoneXP.total(xp.totals)
    local battery=bodyBattery(self.root)
    local ringH=self.compact and 166 or 188
    self:card(x,y,w,ringH,c.glass,0.90)
    D.round(self,x+10,y+10,w-20,ringH-20,c.bg,0.28,12)
    D.text(self,'TODAY',x+18,y+16,c.muted,nil,w-36)
    local dateText=now.dateText or now.day
    D.text(self,dateText,x+w-18-D.measure(dateText),y+16,c.muted)
    local time=P.time(now.minute)
    D.text(self,time,x+18,y+42,c.text,UIFont.Large,w-36)
    local bodyText=battery and math.floor(battery*100+0.5)..'%' or '--'
    D.text(self,'BODY',x+w-108,y+48,c.muted,nil,90)
    D.text(self,bodyText,x+w-108,y+48+self.lh,c.mint,UIFont.Medium,90)
    local tileY=y+(self.compact and 96 or 108)
    local gap=8
    local cols=self.compact and 2 or 3
    local tileW=(w-36-gap*(cols-1))/cols
    local sleepAlarm=self.root.sleepCoach and self.root.sleepCoach.alarm or {}
    local resetText=sleepAlarm.armed and (sleepAlarm.targetLabel or P.time(sleepAlarm.targetMinute)) or 'Ready'
    local values={{'Routine',done..' / '..total,c.mint},{'XP','+'..string.format('%.1f',xpTotal),c.purple},{'Reset',resetText,c.blue}}
    for i,row in ipairs(values) do
        local tx=x+18+((i-1)%cols)*(tileW+gap)
        local ty=tileY+math.floor((i-1)/cols)*(self.lh*2+34)
        if not self.compact or i<3 then self:statPill(row[1],row[2],tx,ty,tileW,row[3]) end
    end
    self:region('today-summary',x,y,w,ringH,function() self:showApp('skills') end)
    return y+ringH+14
end
function U:drawHome(y,now)
    local x,w=self.pad,self.bodyW
    y=self:drawTrackerSummary(y,now)
    y=self:drawWhatNow(y,now)
    local current,nextTask=P.radar(self.root.planner,now.minute)
    y=self:section('NEXT SET',y)
    local planH=self.lh*3+34
    self:card(x,y,w,planH,c.card,0.88)
    D.text(self,current and current.name or 'Free roam',x+14,y+12,c.text,UIFont.Medium,w-28)
    y=y+self.lh+18
    y=y+D.wrap(self,current and P.time(current.start)..' / '..P.status(self.root.planner,current,now.minute) or 'A little structure. Room to roam.',x+14,y,w-28,c.muted)+2
    y=y+D.wrap(self,nextTask and 'Next: '..P.time(nextTask.start)..' / '..nextTask.name or 'Next: no later scheduled task',x+14,y,w-28,c.mint)+16
    y=y+10
    y=self:section('TRACKER APPS',y)
    local gap=10;local tileH=self.compact and self.lh*2+42 or self.lh*2+48
    local cols=self.compact and 1 or 2
    local tileW=(w-gap*(cols-1))/cols
    local apps={{'home-plan','Plan','Checklist','planner',c.mint,'planner'},{'home-vitals','Vitals','Health bars','skills',c.blue,'vitals'},{'home-xp','Training','XP and casts','skills',c.purple,'skills'},{'home-gear','Gear','Settings','settings',c.amber,'settings'}}
    for i,a in ipairs(apps) do
        local tx=x+((i-1)%cols)*(tileW+gap)
        local ty=y+math.floor((i-1)/cols)*(tileH+gap)
        self:appTile(a[1],a[2],a[3],a[4],tx,ty,tileW,tileH,a[5],function() self:showApp(a[6]) end)
    end
    return y+math.ceil(#apps/cols)*(tileH+gap)+18
end
function U:drawVitals(y,now)
    local x,w=self.pad,self.bodyW
    y=self:heading('Vitals','Hydration, hunger, rest and stamina stay separate from the rest of the tracker.',y)
    local bars=(self.root.needs or {}).bars or {}
    if #bars==0 then return y+D.wrap(self,'Waiting for the survivor\'s current condition...',x,y,w,c.muted)+12 end
    local columns=self.compact and 1 or 2
    local cellW=(w-(columns-1)*20)/columns
    local gridY=y;local rowHeight=0
    for i,bar in ipairs(bars) do
        if i>1 and (i-1)%columns==0 then gridY=gridY+rowHeight+16;rowHeight=0 end
        local bx=x+(i-1)%columns*(cellW+20);local by=gridY
        local color=(bar.key=='hunger' or bar.key=='fatigue') and bar.level>=1 and c.red or bar.level>=3 and c.red or bar.level>=1 and c.amber or c.mint
        local track=c.raised
        if bar.key=='fatigue' and bar.level>=2 then
            local period=bar.level>=4 and 0.55 or bar.level>=3 and 1.25 or 3
            if C.realSeconds()%period<period*0.45 then track=c.red end
        end
        local fitnessLabel=bar.key=='thirst' and 'Hydration' or bar.key=='hunger' and 'Hunger' or bar.key=='fatigue' and 'Rest' or bar.key=='endurance' and 'Stamina' or bar.label
        local forecast=bar.forecastStatus or 'Learning your pace'
        if bar.key~='endurance' and bar.eta then forecast=bar.warning..' in '..C.irlEta(bar.eta) end
        local forecastHeight=bar.key~='endurance' and D.wrap(nil,forecast,bx,by,cellW-24) or 0
        local tileH=self.lh*3+58+forecastHeight
        self:card(bx,by,cellW,tileH,c.card,0.88)
        D.round(self,bx+12,by+12,30,30,color,0.20,11)
        D.text(self,fitnessLabel,bx+52,by+10,c.text,UIFont.Medium,cellW-64)
        local label=string.format('%.1f%%',bar.percent or math.min(99.9,bar.fill*100))
        D.text(self,label,bx+52,by+14+D.fontHeight(UIFont.Medium),bar.level>0 and color or c.muted,nil,cellW-64)
        D.text(self,bar.status,bx+12,by+self.lh*2+24,c.muted,nil,cellW-24)
        local barY=by+self.lh*3+30
        D.round(self,bx+12,barY,cellW-24,9,track,1,5)
        if bar.fill>0 then D.round(self,bx+12,barY,(cellW-24)*bar.fill,9,color,1,5) end
        if bar.key~='endurance' then
            D.wrap(self,forecast,bx+12,barY+18,cellW-24,bar.eta and bar.eta<=(self.root.settings.leadMinutes or 30) and c.amber or c.muted)
        end
        rowHeight=math.max(rowHeight,tileH)
    end
    y=gridY+rowHeight
    y=y+18
    y=y+D.wrap(self,'These are normalized tracker reserves, not raw Zomboid values. Hunger and Rest keep reserve through their warning moodles and only approach zero at their extreme states; Stamina follows endurance.',x,y,w,c.muted)+12
    return y
end
function U:drawSkills(y,now)
    local x,w=self.pad,self.bodyW;local X=SurvivorPhoneXP;local t=X.ensure(self.root,now.day)
    y=self:heading('Training','Every skill. Today\'s gains and yesterday\'s story.',y)
    self:card(x,y,w,self.lh*2+40)
    D.text(self,'TODAY  /  '..(now.dateText or now.day),x+16,y+12,c.muted)
    D.text(self,'+'..string.format('%.1f',X.total(t.totals))..' XP',x+16,y+self.lh+18,c.purple,UIFont.Large)
    y=y+self.lh*2+58
    local rows=X.rows(t.totals,t.names)
    if #rows==0 then y=y+D.wrap(self,'No gains yet. XP appears here as you earn it, including animal care and passive skills.',x,y,w,c.muted)+12 end
    for _,row in ipairs(rows) do
        D.text(self,row.name,x,y,c.text,nil,w-112)
        local value='+'..string.format('%.1f',row.xp)..' XP';D.text(self,value,x+w-D.measure(value),y,c.purple)
        D.rect(self,x,y+self.lh+6,w,1,c.line);y=y+self.lh+18
    end
    y=y+12;y=self:section('PREVIOUS DAY  /  '..C.previousDay(now.day),y)
    local previous=t.history[C.previousDay(now.day)]
    if previous then
        y=y+D.wrap(self,string.format('%.1f',X.total(previous))..' XP earned. This is the report shown after your first wake today.',x,y,w,c.muted)+8
        for _,row in ipairs(X.rows(previous,t.names)) do D.text(self,row.name,x,y,c.text,nil,w-112);local v='+'..string.format('%.1f',row.xp)..' XP';D.text(self,v,x+w-D.measure(v),y,c.purple);y=y+self.lh+8 end
    else y=y+D.wrap(self,'No record for that date. Tracking starts when this version is loaded.',x,y,w,c.muted)+8 end
    y=y+18;y=self:section('FISHING  /  REAL ELAPSED TIME',y)
    local f=SurvivorPhoneFishing.ensure(self.root,now.day)
    local active=SurvivorPhoneFishing.active[self.player]
    if active then
        local seconds=(active.stop or C.realSeconds())-active.start
        y=y+D.wrap(self,(active.stop and 'Reeled in / verifying catch  ' or 'Cast in progress  ')..C.duration(seconds),x,y,w,c.mint)+10
    end
    D.text(self,'Today: '..f.today.casts..' casts / '..f.today.successful..' catches',x,y,c.text,nil,w);y=y+self.lh+10
    D.text(self,'Lifetime: '..f.casts..' casts / '..f.successful..' catches',x,y,c.muted,nil,w);y=y+self.lh+10
    local avg,count=SurvivorPhoneFishing.recentAverage(f,true)
    local all=SurvivorPhoneFishing.recentAverage(f,false)
    y=y+D.wrap(self,'Recent successful average: '..C.duration(avg)..' ('..count..' samples)',x,y,w,c.text)+6
    y=y+D.wrap(self,'Recent all-cast average: '..C.duration(all)..' / Last 20 casts',x,y,w,c.muted)+6
    y=y+D.wrap(self,'Lifetime successful average: '..C.duration(f.successTimed>0 and f.successSeconds/f.successTimed or nil),x,y,w,c.muted)+6
    y=y+D.wrap(self,f.empty..' empty / '..f.interrupted..' interrupted. Success requires the catch and its XP. The old mixed-unit statistics were reset once.',x,y,w,c.muted)+22
    y=self:section('RECENT CONFIRMED ACTIVITY',y)
    local recent=((self.root.activity or {}).recent or {})
    if #recent==0 then y=y+D.wrap(self,'Confirmed actions and skill gains will appear here.',x,y,w,c.muted)+10 end
    for i=#recent,math.max(1,#recent-7),-1 do
        local r=recent[i]
        y=y+D.wrap(self,r.day..' / '..P.time(r.minute)..' / '..r.name,x,y,w,c.text)+4
        y=y+D.wrap(self,r.evidence..((r.count or 1)>1 and ' ('..r.count..' observations)' or ''),x,y,w,c.muted)+12
    end
    return y
end
function U:slider(id,label,value,min,max,x,y,w,callback,format)
    D.text(self,label,x,y,c.text)
    local text=format or tostring(value);D.text(self,text,x+w-D.measure(text),y,c.mint)
    local ty=y+self.lh+16
    D.round(self,x,ty,w,6,c.raised,1,3)
    local ratio=(value-min)/(max-min)
    D.round(self,x,ty,w*ratio,6,c.mint,1,3)
    D.round(self,x+math.max(0,math.min(w-14,w*ratio-7)),ty-4,14,14,c.text,1,7)
    self:region(id,x,ty-10,w,26,nil,{slider=true,min=min,max=max,callback=callback})
    return ty+32
end
function U:drawSettings(y,now)
    local x,w=self.pad,self.bodyW;local s=self.root.settings
    y=self:heading('Gear','Quiet, size and readability controls for the tracker.',y)
    y=self:slider('dimmer','Dimmer / opacity',s.dimmer,0.25,1,x,y,w,function(v) s.dimmer=v;self.opacity=v end,math.floor(s.dimmer*100+0.5)..'%')
    y=y+8;y=self:slider('size','Dashboard size',s.uiScale,0.5,1,x,y,w,function(v) s.uiScale=v;self:resizeDashboard() end,math.floor(s.uiScale*100+0.5)..'%')
    y=y+D.wrap(self,'Drag the header to move. Dashboard size and opacity update as you slide and stay saved for this survivor.',x,y,w,c.muted)+18
    local h=self.lh+24
    self:button('mute','Mute all notifications  /  '..((s.notificationsMuted or s.dnd) and 'On' or 'Off'),x,y,w,h,function()
        local value=not (s.notificationsMuted or s.dnd)
        s.notificationsMuted=value;s.dnd=value
    end,(s.notificationsMuted or s.dnd) and 'primary' or nil);y=y+h+10
    y=y+D.wrap(self,'Mute blocks popups only. Tracking, XP, What Now, history and task recognition continue. Thirst never sends popups; it stays in Vitals.',x,y,w,c.muted)+18
    self:button('learning','Routine learning  /  '..(s.learning and 'On' or 'Off'),x,y,w,h,function()
        s.learning=not s.learning;SurvivorPhoneLearning.sessions[self.player]=nil
    end);y=y+h+16
    self:button('sleep-reset','Sleep Reset coach  /  '..(s.sleepResetEnabled and 'On' or 'Off'),x,y,w,h,function()
        s.sleepResetEnabled=not s.sleepResetEnabled
        if not s.sleepResetEnabled then SurvivorPhoneSleepCoach.cancel(self.root) end
    end,s.sleepResetEnabled and 'primary' or nil);y=y+h+10
    y=y+D.wrap(self,'Sleep Reset learns your routine, then uses a short corrective 3-4 game-hour sleep when fatigue would otherwise push your schedule off course.',x,y,w,c.muted)+16
    y=self:slider('lead','Need popup lead time',s.leadMinutes,10,120,x,y,w,function(v) s.leadMinutes=math.floor(v/5+0.5)*5 end,s.leadMinutes..' game min')
    self:button('history','Notification history',x,y,w,h,function() self:showApp('history') end);y=y+h+10
    self:button('travel','Places & travel history',x,y,w,h,function() self:showApp('travel') end);y=y+h+10
    self:button('store','Coming soon',x,y,w,h,function() self:showApp('store') end);y=y+h+20
    y=self:section('DIGITAL WATCH',y)
    self:button('watch-toggle','Watch overlay  /  '..(s.watchEnabled and 'On' or 'Off'),x,y,w,h,function()
        s.watchEnabled=not s.watchEnabled
        if SurvivorPhone then
            if s.watchEnabled then SurvivorPhone.openWatch(self.item,self.player) else SurvivorPhone.closeWatch(self.player:getPlayerNum(),false) end
        end
    end,s.watchEnabled and 'primary' or nil);y=y+h+10
    y=self:slider('watch-size','Watch size',s.watchScale,0.65,1.4,x,y,w,function(v)
        s.watchScale=v
        local watch=SurvivorPhone and SurvivorPhone.watchWindows and SurvivorPhone.watchWindows[self.player:getPlayerNum()]
        if watch then watch:resizeWatch() end
    end,math.floor(s.watchScale*100+0.5)..'%')
    y=y+8;y=self:slider('watch-opacity','Watch opacity',s.watchOpacity,0.35,1,x,y,w,function(v)
        s.watchOpacity=v
        local watch=SurvivorPhone and SurvivorPhone.watchWindows and SurvivorPhone.watchWindows[self.player:getPlayerNum()]
        if watch then watch.opacity=v end
    end,math.floor(s.watchOpacity*100+0.5)..'%')
    y=y+D.wrap(self,'The watch face now puts Vitals first, then one recommendation and the next plan item. Details stays available when you want the full drawer.',x,y,w,c.muted)+18
    local label=self.resetLearning and 'Confirm: clear learned observations' or 'Clear learned observations'
    self:button('clear-learning',label,x,y,w,h,function()
        if self.resetLearning then self.root.learning=nil;self.root.needsHistory=nil;self.root.guidance=nil;SurvivorPhoneLearning.sessions[self.player]=nil;SurvivorPhoneNeeds.samples[self.player]=nil;self.resetLearning=false else self.resetLearning=true end
    end,self.resetLearning and 'danger' or nil);y=y+h+12
    y=y+D.wrap(self,'Clears activity and need patterns, including suggestion choices. Your schedule, XP and fishing records are kept.',x,y,w,c.muted)+12
    if SurvivorPhoneDebug.isEnabled() then
        self:button('debug','Debug diagnostics',x,y,w,h,function() self:showApp('debug') end);y=y+h+12
    end
    y=y+D.wrap(self,'Survivor Watch 1.6.6 / Build 42.20\nVitals-first watch face. Mute all notifications silences popups without stopping tracking. Thirst is manual-only for popups and remains visible in Vitals and What Now. The details drawer is scaled down for readability. Battery cosmetic. Terrain map integration is paused.',x,y,w,c.muted)+10
    return y
end
function U:drawStore(y)
    y=self:heading('Labs','Ideas for the tracker later.',y)
    local items={{'Notes & goals','A place for plans, project notes and longer ambitions.'},{'Explored map','Known places and your markers, with unexplored areas protected.'},{'Watch faces','More compact faces and alerts built around the digital watch.'},{'Battery & charging','A later addition. Battery is decorative for now.'}}
    for _,item in ipairs(items) do
        D.icon(self,'store',self.pad+14,y+16,c.purple)
        D.text(self,item[1],self.pad+50,y+12,c.text,UIFont.Medium,self.bodyW-66)
        y=y+14+D.fontHeight(UIFont.Medium)+6
        y=y+D.wrap(self,item[2],self.pad+50,y,self.bodyW-66,c.muted)+24
    end
    return y
end
function U:drawHistory(y)
    y=self:heading('Notification history','Reminders are kept here even while you are in a quiet mode.',y)
    local rows=(self.root.notifications or {}).history or {}
    if #rows==0 then y=y+D.wrap(self,'Nothing yet. Your day is just getting started.',self.pad,y,self.bodyW,c.muted) end
    for i=#rows,1,-1 do
        local r=rows[i];D.text(self,r.day..'  '..P.time(r.minute),self.pad,y,c.muted);y=y+self.lh+4
        y=y+D.wrap(self,r.message,self.pad,y,self.bodyW,c.text)+18
    end
    return y+10
end
function U:drawDebug(y)
    if not SurvivorPhoneDebug.isEnabled() then return self:heading('Debug mode is off',nil,y) end
    y=self:heading('Survivor diagnostics','Read-only diagnostics owned by this mod.',y)
    local h=SurvivorPhoneHooks or {status={},errors={}}
    local names={};for name in pairs(h.status) do table.insert(names,name) end;table.sort(names)
    for _,name in ipairs(names) do y=y+D.wrap(self,name..': '..h.status[name],self.pad,y,self.bodyW,c.muted)+8 end
    for name,err in pairs(h.errors) do y=y+D.wrap(self,name..': '..err,self.pad,y,self.bodyW,c.red)+8 end
    y=y+12;y=self:section('CONDITION OBSERVATIONS',y)
    for _,bar in ipairs((self.root.needs or {}).bars or {}) do
        y=y+D.wrap(self,bar.label..': '..string.format('%.4f',bar.value)..' raw / '..string.format('%.1f%%',bar.percent or 0)..' reserve / '..bar.status..' / '..(bar.eta and bar.eta..' game min' or bar.forecastStatus),self.pad,y,self.bodyW,c.muted)+8
    end
    y=y+D.wrap(self,'Observed need onsets: '..#((self.root.needsHistory or {}).onsets or {})..'. Schedule suggestions: '..#self:scheduleSuggestions(SurvivorPhoneClock.now())..'.',self.pad,y,self.bodyW,c.muted)+8
    return y
end
function U:prerender()
    self.opacity=self.root.settings.dimmer;self.regions={};self.inBody=false
    D.round(self,0,0,self.width,self.height,c.bg,1,18)
    D.round(self,7,7,self.width-14,self.height-14,c.card,0.64,16)
    D.round(self,14,14,self.width-28,self.header-18,c.glass,0.86,14)
    D.round(self,22,self.compact and 18 or 22,34,8,c.mint,1,4)
    D.text(self,'SURVIVOR WATCH',64,self.compact and 12 or 17,c.text,UIFont.Medium,self.width-142)
    if not self.compact then D.text(self,'digital watch tracker',65,20+D.fontHeight(UIFont.Medium),c.muted,nil,self.width-142) end
    self:button('close','x',self.width-48,self.compact and 10 or 18,30,30,function() self:close() end,'ghost')
    local tabs=self.compact and {{'home','Today'},{'planner','Plan'},{'vitals','Vitals'},{'skills','XP'},{'settings','Gear'}} or {{'home','Today'},{'planner','Plan'},{'vitals','Vitals'},{'skills','Training'},{'settings','Gear'}}
    local tw=(self.width-32)/#tabs
    for i,tab in ipairs(tabs) do
        local app,label=tab[1],tab[2];local tx=16+(i-1)*tw;local active=self.app==app or app=='planner' and self.app=='suggestions' or (app=='settings' and (self.app=='store' or self.app=='history' or self.app=='debug' or self.app=='travel'))
        local ty=self.header
        D.round(self,tx,ty,tw-5,self.navHeight,active and c.soft or c.bg,active and 0.92 or 0.42,10)
        if active then D.round(self,tx+4,ty+4,tw-13,self.navHeight-8,c.mint,0.13,8) end
        D.text(self,label,tx+math.max(2,(tw-5-D.measure(label))/2),ty+(self.navHeight-D.fontHeight())/2,active and c.text or c.muted,nil,tw-8)
        self:region('nav-'..app,tx,ty,tw-5,self.navHeight,function() self:showApp(app) end)
    end
    local _,_,now=SurvivorPhoneData.get(self.player)
    self.inBody=true;self:setStencilRect(self.pad,self.bodyY,self.bodyW,self.bodyH)
    local first=self.bodyY-self.scrollOffset;local last=first
    if self.app=='home' then last=self:drawHome(first,now)
    elseif self.app=='vitals' then last=self:drawVitals(first,now)
    elseif self.app=='planner' then last=self:drawPlanner(first,now)
    elseif self.app=='suggestions' then last=self:drawSuggestions(first,now)
    elseif self.app=='skills' then last=self:drawSkills(first,now)
    elseif self.app=='settings' then last=self:drawSettings(first,now)
    elseif self.app=='store' then last=self:drawStore(first)
    elseif self.app=='history' then last=self:drawHistory(first)
    elseif self.app=='travel' then last=self:drawTravel(first,now)
    elseif self.app=='debug' then last=self:drawDebug(first) end
    self:clearStencilRect();self.inBody=false
    self.contentHeight=last-first
    self.scrollOffset=math.max(0,math.min(self.scrollOffset,math.max(0,self.contentHeight-self.bodyH)))
    if self.contentHeight>self.bodyH then
        local trackH=self.bodyH;local handle=math.max(26,trackH*trackH/self.contentHeight)
        D.round(self,self.width-12,self.bodyY,4,trackH,c.card,1,2)
        local sy=self.bodyY+self.scrollOffset/(self.contentHeight-self.bodyH)*(trackH-handle)
        D.round(self,self.width-12,sy,4,handle,c.muted,1,2)
        self:region('scrollbar',self.width-19,self.bodyY,18,trackH,nil,{scrollbar=true})
    end
    local fy=self.height-self.footer
    D.rect(self,16,fy-6,self.width-32,1,c.line)
    local free=self.root.planner.freeRoam
    self:button('free-roam','Free Roam  '..(free and 'On' or 'Off'),16,fy+2,self.compact and 128 or 150,self.lh+10,function() self.root.planner.freeRoam=not free end)
    local muted=self.root.settings.notificationsMuted or self.root.settings.dnd
    local mw=self.compact and 92 or 128
    self:button('mute-footer',muted and 'Muted' or 'Alerts On',self.width-mw-16,fy+2,mw,self.lh+10,function()
        local value=not (self.root.settings.notificationsMuted or self.root.settings.dnd)
        self.root.settings.notificationsMuted=value;self.root.settings.dnd=value
    end,muted and 'primary' or nil)
end
function U:applySlider(region,x)
    local m=region.meta;local ratio=math.max(0,math.min(1,(x-region.x)/region.w))
    m.callback(m.min+ratio*(m.max-m.min))
end
function U:moveScroll(y)
    self.scrollOffset=math.max(0,math.min(1,(y-self.bodyY)/self.bodyH))*math.max(0,(self.contentHeight or 0)-self.bodyH)
end
function U:onMouseDown(x,y)
    self:bringToTop();local r=self:hit(x,y)
    if r then
        self.pressedId=r.id
        if r.meta and r.meta.slider then self.dragSlider=r;self.sliderOriginX=self.x;self:setCapture(true);self:applySlider(r,x)
        elseif r.meta and r.meta.scrollbar then self.dragScroll=true;self:setCapture(true);self:moveScroll(y) end
        return true
    end
    if y<self.header then self.dragging=true;self.dragX=getMouseX()-self.x;self.dragY=getMouseY()-self.y;self:setCapture(true) end
    return true
end
function U:onMouseMove(dx,dy)
    local x,y=self:getMouseX(),self:getMouseY();local r=self:hit(x,y);self.hoverId=r and r.id or nil
    if self.dragging then
        self:setX(math.max(0,math.min(getCore():getScreenWidth()-self.width,getMouseX()-self.dragX)))
        self:setY(math.max(0,math.min(getCore():getScreenHeight()-self.height,getMouseY()-self.dragY)))
    elseif self.dragSlider then self:applySlider(self.dragSlider,getMouseX()-self.sliderOriginX)
    elseif self.dragScroll then self:moveScroll(y) end
    return true
end
function U:onMouseMoveOutside(dx,dy) if self.dragging or self.dragSlider or self.dragScroll then return self:onMouseMove(dx,dy) end;self.hoverId=nil;self.hoverTask=nil end
function U:onMouseUp(x,y)
    local r=self:hit(x,y)
    if not self.dragging and not self.dragSlider and not self.dragScroll and r and r.id==self.pressedId and r.action then r.action() end
    self.dragging=false;self.dragSlider=nil;self.dragScroll=false;self.pressedId=nil;self:setCapture(false)
    self.root.settings.posX,self.root.settings.posY=self.x,self.y
    return true
end
function U:onMouseUpOutside(x,y) return self:onMouseUp(x,y) end
function U:onMouseWheel(delta)
    self.scrollOffset=math.max(0,math.min(math.max(0,(self.contentHeight or 0)-self.bodyH),self.scrollOffset+delta*self.lh*3))
    self.hoverTask=nil;return true
end
function U:update()
    ISPanel.update(self)
    if self.player:isDead() or not self.item:getContainer() or not self.item:getContainer():isInCharacterInventory(self.player) then self:close();return end
    if self.lastScreenW~=getCore():getScreenWidth() or self.lastScreenH~=getCore():getScreenHeight() then
        self.lastScreenW=getCore():getScreenWidth();self.lastScreenH=getCore():getScreenHeight();self:resizeDashboard()
    end
end
return U



