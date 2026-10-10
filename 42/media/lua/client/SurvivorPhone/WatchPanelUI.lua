require 'SurvivorPhone/PhoneUI'
require 'SurvivorPhone/ProgressApp'

SurvivorWatchPanelUI=SurvivorPhoneUI:derive('SurvivorWatchPanelUI')
local U=SurvivorWatchPanelUI
local B=SurvivorPhoneUI
local D=SurvivorPhoneWidgets
local P=SurvivorPhonePlanner
local X=SurvivorPhoneXP
local c=D.c

local needNames={thirst='Hydration',hunger='Hunger',fatigue='Rest',endurance='Stamina'}
local needColors={thirst=c.blue,hunger=c.mint,fatigue=c.purple,endurance=c.amber}

local function clamp01(v) return math.max(0,math.min(1,v or 0)) end
function U:new(player,item)
    local o=B.new(self,player,item)
    o.app='home'
    o.root.lastApp='home'
    o.scrollOffset=0
    o:resizeDashboard()
    return o
end

function U:resizeDashboard()
    local s=self.root and self.root.settings or {uiScale=0.72}
    local t=math.max(0,math.min(1,((s.uiScale or 0.72)-0.5)/0.5))
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    self:setWidth(math.min(sw-24,math.floor(540+180*t)))
    self:setHeight(math.min(sh-36,math.floor(470+160*t)))
    self.compact=self.width<590
    self.pad=self.compact and 14 or 18
    self.header=68
    self.navHeight=38
    self.bodyY=self.header+self.navHeight+8
    self.footer=40
    self.bodyH=self.height-self.bodyY-self.footer-10
    self.bodyW=self.width-self.pad*2-8
    self:setX(math.max(0,math.min(sw-self.width,self.x or 0)))
    self:setY(math.max(0,math.min(sh-self.height,self.y or 0)))
end

function U:drawVitalsStrip(y)
    local bars=((self.root.needs or {}).bars or {})
    local x,w=self.pad,self.bodyW
    y=self:section('VITALS',y)
    if #bars==0 then return y+D.wrap(self,'Learning your current condition...',x,y,w,c.muted)+12 end
    local gap=8
    local cols=self.compact and 2 or 4
    local cellW=(w-gap*(cols-1))/cols
    local cellH=58
    local rows=math.ceil(#bars/cols)
    for i,bar in ipairs(bars) do
        local col=(i-1)%cols
        local row=math.floor((i-1)/cols)
        local bx=x+col*(cellW+gap)
        local by=y+row*(cellH+gap)
        local level=tonumber(bar.level) or 0
        local color=(bar.key=='hunger' or bar.key=='fatigue') and level>=1 and c.red or level>=3 and c.red or level>=1 and c.amber or needColors[bar.key] or c.mint
        local value=clamp01(bar.fill)
        local pct=math.floor((bar.percent or math.min(99.9,value*100))+0.5)..'%'
        local reading=pct
        if (bar.key=='hunger' or bar.key=='fatigue') and level>0 and bar.status then reading=bar.status..' / '..pct end
        self:card(bx,by,cellW,cellH,c.raised,0.72)
        D.text(self,needNames[bar.key] or bar.label,bx+10,by+8,c.muted,nil,cellW-20)
        D.text(self,reading,bx+10,by+25,color,UIFont.Medium,cellW-20)
        D.round(self,bx+10,by+46,cellW-20,5,c.card,1,3)
        if value>0 then D.round(self,bx+10,by+46,(cellW-20)*value,5,color,1,3) end
    end
    return y+rows*(cellH+gap)+8
end

function U:drawPlanSnapshot(y,now)
    local x,w=self.pad,self.bodyW
    local current,nextTask=P.radar(self.root.planner,now.minute)
    y=self:section('SCHEDULE',y)
    local gap=10
    local cardW=(w-gap)/2
    local h=self.lh*3+38
    self:card(x,y,cardW,h,c.card,0.88)
    D.text(self,'NOW',x+12,y+10,c.muted,nil,cardW-24)
    D.text(self,current and current.name or 'Free roam',x+12,y+30,c.text,UIFont.Medium,cardW-24)
    local currentSub=current and ((current.start and P.time(current.start)..' / ' or '')..P.status(self.root.planner,current,now.minute)) or 'Nothing needs you right now.'
    D.wrap(self,currentSub,x+12,y+34+D.fontHeight(UIFont.Medium),cardW-24,c.muted)

    local nx=x+cardW+gap
    self:card(nx,y,cardW,h,c.card,0.88)
    D.text(self,'NEXT',nx+12,y+10,c.muted,nil,cardW-24)
    D.text(self,nextTask and nextTask.name or 'Open schedule',nx+12,y+30,nextTask and c.mint or c.text,UIFont.Medium,cardW-24)
    local nextSub=nextTask and ((nextTask.start and P.time(nextTask.start)..' / ' or '')..P.status(self.root.planner,nextTask,now.minute)) or 'No later scheduled task.'
    D.wrap(self,nextSub,nx+12,y+34+D.fontHeight(UIFont.Medium),cardW-24,c.muted)
    self:region('today-plan',x,y,w,h,function() self:showApp('planner') end)
    return y+h+12
end

function U:drawDailySnapshot(y,now)
    local x,w=self.pad,self.bodyW
    local done,total=P.progress(self.root.planner)
    local tracker=X.ensure(self.root,now.day)
    local xpTotal=X.total(tracker.totals)
    local alarm=self.root.sleepCoach and self.root.sleepCoach.alarm or {}
    local gap=8
    local cellW=(w-gap*2)/3
    local h=58
    local resetText=alarm.armed and (alarm.targetLabel or P.time(alarm.targetMinute)) or 'Ready'
    local rows={{'Tasks',done..' / '..total,c.mint},{'XP today','+'..string.format('%.1f',xpTotal),c.purple},{'Sleep Reset',resetText,c.blue}}
    for i,row in ipairs(rows) do
        local bx=x+(i-1)*(cellW+gap)
        self:card(bx,y,cellW,h,c.raised,0.70)
        D.text(self,row[1],bx+10,y+9,c.muted,nil,cellW-20)
        D.text(self,row[2],bx+10,y+28,row[3],UIFont.Medium,cellW-20)
    end
    return y+h+10
end

function U:drawHome(y,now)
    y=self:heading('Today','One clear recommendation, your condition and what is coming next.',y)
    y=self:drawWhatNow(y,now)
    y=self:drawVitalsStrip(y)
    y=self:drawPlanSnapshot(y,now)
    y=self:section('TODAY AT A GLANCE',y)
    y=self:drawDailySnapshot(y,now)
    return y+8
end

function U:drawSkills(y,now)
    return SurvivorWatchProgress.draw(self,y,now)
end

function U:drawSettings(y,now)
    local x,w=self.pad,self.bodyW
    local s=self.root.settings
    local h=self.lh+22
    y=self:heading('Settings','Display, watch behavior, notifications and smart features in one place.',y)

    y=self:section('DISPLAY',y)
    y=self:slider('panel-opacity','Panel opacity',s.dimmer,0.25,1,x,y,w,function(v) s.dimmer=v;self.opacity=v end,math.floor(s.dimmer*100+0.5)..'%')
    y=y+8
    y=self:slider('panel-size','Expanded panel size',s.uiScale,0.5,1,x,y,w,function(v) s.uiScale=v;self:resizeDashboard() end,math.floor(s.uiScale*100+0.5)..'%')
    y=y+8
    y=y+D.wrap(self,'Drag the top header to move the expanded panel. Size and opacity stay saved for this survivor.',x,y,w,c.muted)+18

    y=self:section('WATCH FACE',y)
    self:button('watch-toggle','Small watch face  /  '..(s.watchEnabled and 'On' or 'Off'),x,y,w,h,function() s.watchEnabled=not s.watchEnabled end,s.watchEnabled and 'primary' or nil)
    y=y+h+10
    y=self:slider('watch-size','Watch size',s.watchScale,0.65,1.4,x,y,w,function(v) s.watchScale=v end,math.floor(s.watchScale*100+0.5)..'%')
    y=y+8
    y=self:slider('watch-opacity','Watch opacity',s.watchOpacity,0.35,1,x,y,w,function(v) s.watchOpacity=v end,math.floor(s.watchOpacity*100+0.5)..'%')
    y=y+10

    y=self:section('NEEDS FORECAST',y)
    y=y+D.wrap(self,'Controls how early Survivor Watch starts treating predicted hunger, thirst and fatigue as upcoming needs.',x,y,w,c.muted)+10
    y=self:slider('lead','Forecast lead time',s.leadMinutes,10,120,x,y,w,function(v) s.leadMinutes=math.floor(v/5+0.5)*5 end,s.leadMinutes..' game min')
    y=y+12

    y=self:section('HISTORY',y)
    y=y+D.wrap(self,'Popup notifications are disabled. Planner, needs, sleep and XP-related events are still recorded here.',x,y,w,c.muted)+8
    self:button('history','Notification history',x,y,w,h,function() self:showApp('history') end)
    y=y+h+18

    y=self:section('SMART FEATURES',y)
    self:button('learning','Routine learning  /  '..(s.learning and 'On' or 'Off'),x,y,w,h,function()
        s.learning=not s.learning;SurvivorPhoneLearning.sessions[self.player]=nil
    end,s.learning and 'primary' or nil)
    y=y+h+10
    self:button('sleep-reset','Sleep Reset coach  /  '..(s.sleepResetEnabled and 'On' or 'Off'),x,y,w,h,function()
        s.sleepResetEnabled=not s.sleepResetEnabled
        if not s.sleepResetEnabled then SurvivorPhoneSleepCoach.cancel(self.root,self.player,'disabled') end
    end,s.sleepResetEnabled and 'primary' or nil)
    y=y+h+10
    self:button('travel-tracking','Travel tracking  /  '..(s.travelTracking and 'On' or 'Off'),x,y,w,h,function() s.travelTracking=not s.travelTracking end,s.travelTracking and 'primary' or nil)
    y=y+h+18

    y=self:section('ADVANCED',y)
    local clearLabel=self.resetLearning and 'Confirm: clear learned observations' or 'Clear learned observations'
    self:button('clear-learning',clearLabel,x,y,w,h,function()
        if self.resetLearning then
            self.root.learning=nil;self.root.needsHistory=nil;self.root.guidance=nil
            SurvivorPhoneLearning.sessions[self.player]=nil;SurvivorPhoneNeeds.samples[self.player]=nil
            self.resetLearning=false
        else self.resetLearning=true end
    end,self.resetLearning and 'danger' or nil)
    y=y+h+10
    if SurvivorPhoneDebug.isEnabled() then
        self:button('debug','Debug diagnostics',x,y,w,h,function() self:showApp('debug') end)
        y=y+h+10
    end
    y=y+D.wrap(self,'Internal save compatibility remains SurvivorPhone. Battery and terrain-map work stay separate from this UI redesign.',x,y,w,c.muted)+10
    return y
end

local function tabActive(app,id)
    if id=='planner' then return app=='planner' or app=='suggestions' end
    if id=='settings' then return app=='settings' or app=='history' or app=='debug' end
    return app==id
end

function U:prerender()
    self.opacity=self.root.settings.dimmer or self.opacity
    self.regions={}
    D.round(self,0,0,self.width,self.height,c.bg,1,18)
    D.round(self,7,7,self.width-14,self.height-14,c.card,0.97,14)

    local now=SurvivorPhoneData.now()
    local x=self.pad
    D.text(self,'SURVIVOR WATCH',x,16,c.muted,UIFont.Small,self.width-260)
    D.text(self,P.time(now.minute),x,34,c.text,UIFont.Large,150)
    local dateText=now.dateText or now.day
    D.text(self,dateText,self.width-54-D.measure(dateText),20,c.muted)
    D.text(self,'x',self.width-28,18,c.muted)
    self:region('close',self.width-38,8,32,32,function() self:close() end)

    local tabs={{'home','Today'},{'planner','Planner'},{'skills','Progress'},{'travel','Travel'},{'settings','Settings'}}
    local tx=self.pad
    local gap=6
    local tw=(self.width-self.pad*2-gap*(#tabs-1))/#tabs
    local ty=self.header
    for _,tab in ipairs(tabs) do
        local app,label=tab[1],tab[2]
        local active=tabActive(self.app,app)
        D.round(self,tx,ty,tw,self.navHeight-4,active and c.soft or c.raised,active and 0.92 or 0.64,9)
        D.text(self,label,tx+math.max(6,(tw-D.measure(label))/2),ty+8,active and c.mint or c.muted,nil,tw-12)
        self:region('tab-'..app,tx,ty,tw,self.navHeight-4,function() self:showApp(app) end)
        tx=tx+tw+gap
    end

    D.rect(self,self.pad,self.bodyY-5,self.bodyW,1,c.line,0.65)
    self:setStencilRect(self.pad,self.bodyY,self.bodyW+8,self.bodyH)
    local y=self.bodyY-(self.scrollOffset or 0)
    self.inBody=true
    if self.app=='home' then y=self:drawHome(y,now)
    elseif self.app=='planner' then y=self:drawPlanner(y,now)
    elseif self.app=='suggestions' then y=self:drawSuggestions(y,now)
    elseif self.app=='skills' then y=self:drawSkills(y,now)
    elseif self.app=='travel' then y=self:drawTravel(y,now)
    elseif self.app=='settings' then y=self:drawSettings(y,now)
    elseif self.app=='history' then y=self:drawHistory(y,now)
    elseif self.app=='debug' then y=self:drawDebug(y,now)
    elseif self.app=='vitals' then y=self:drawVitals(y,now)
    else self.app='home';y=self:drawHome(y,now) end
    self.inBody=false
    self:clearStencilRect()
    self.contentHeight=math.max(0,y-(self.bodyY-(self.scrollOffset or 0)))
    local maxScroll=math.max(0,self.contentHeight-self.bodyH)
    if self.scrollOffset>maxScroll then self.scrollOffset=maxScroll end
    if maxScroll>0 then
        local trackX=self.width-self.pad+1
        local thumbH=math.max(30,self.bodyH*(self.bodyH/self.contentHeight))
        local thumbY=self.bodyY+(self.scrollOffset/maxScroll)*(self.bodyH-thumbH)
        D.round(self,trackX,self.bodyY,4,self.bodyH,c.raised,0.65,2)
        D.round(self,trackX,thumbY,4,thumbH,c.mint,0.85,2)
        self:region('scrollbar',trackX-7,self.bodyY,18,self.bodyH,nil,{scrollbar=true})
    end

    local fy=self.height-self.footer+4
    local free=self.root.planner.freeRoam==true
    self:button('free-roam','Free Roam  /  '..(free and 'On' or 'Off'),self.pad,fy,150,28,function() self.root.planner.freeRoam=not self.root.planner.freeRoam end,free and 'primary' or nil)
end

return U