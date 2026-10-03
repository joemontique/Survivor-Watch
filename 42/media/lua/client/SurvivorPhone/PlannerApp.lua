require 'SurvivorPhone/PhoneUI'
-- Extends the dashboard. Planner tasks use compact rows with one action menu.
local U=SurvivorPhoneUI
local D=SurvivorPhoneWidgets
local P=SurvivorPhonePlanner
local L=SurvivorPhoneLearning
local c=D.c
function U:taskAction(id,action)
    local _,data,now=SurvivorPhoneData.get(self.player)
    local task=P.find(data,id);if not task then return end
    local state=P.state(data,task)
    local start=state.startedAt
    if P.action(data,id,action,now.minute) then
        L.recordPlannerAction(self.root,task,action,now)
        if action=='done' then
            local duration=start and now.minute>=start and now.minute-start or nil
            L.observe(self.root,task,now,start,duration,'Manually confirmed')
        end
    end
    self.deleteId=nil
end
function U:drawPlanner(y,now)
    if self.editing then return self:drawEditor(y) end
    local x,w=self.pad,self.bodyW;local data=self.root.planner
    if self.expandedId and not self.actionMenuId then self.actionMenuId=self.expandedId;self.expandedId=nil end
    local done,total=P.progress(data)
    y=self:heading('Your day',now.day..' / '..done..' of '..total..' complete',y)
    local h=self.lh+18;local gap=10;local half=(w-gap)/2
    self:button('add','+ Add activity',x,y,half,h,function() self:openEditor(nil) end,'primary')
    self:button('completed',self.showCompleted and 'Hide history' or 'Today\'s history',x+half+gap,y,half,h,function() self.showCompleted=not self.showCompleted end)
    y=y+h+12
    y=y+D.wrap(self,'Use Actions on a task when you want to change it.',x,y,w,c.muted)+12
    local suggestions=self:scheduleSuggestions(now)
    self:button('learn-review',#suggestions>0 and 'Review '..#suggestions..' schedule suggestions' or 'Schedule insights / learning',x,y,w,h,function() self:showApp('suggestions') end)
    y=y+h+16
    local rows=P.visible(data,self.showCompleted)
    for _,row in ipairs(rows) do
        local task=row;local id=task.id;local state=P.state(data,task)
        local open=self.actionMenuId==id
        local titleHeight=self.compact and D.wrap(nil,task.name,0,0,w-32,c.text,UIFont.Medium) or D.fontHeight(UIFont.Medium)
        local collapsed=self.compact and titleHeight+h+32 or self.lh*2+30
        local cardStart=y
        local notes=open and task.notes~='' and D.wrap(nil,task.notes,0,0,w-32)+6 or 0
        local place=SurvivorPhoneTravel.find(self.root,task.placeId)
        local locationText=place and SurvivorPhoneTravel.describe(place,SurvivorPhoneTravel.position(self.player))
        local placeHeight=locationText and D.wrap(nil,locationText,0,0,w-32)+8 or 0
        local height=collapsed+(open and self.lh+19+notes+placeHeight+5*(h+8)+4 or 0)
        self:card(x,y,w,height)
        local tone=state.status=='done' and c.mint or state.status=='active' and c.purple or c.muted
        if not self.compact then
            if state.status=='done' then D.icon(self,'check',x+12,y+17,tone)
            else D.round(self,x+17,y+22,10,10,tone,1,5) end
        end
        local actionW=math.max(86,math.min(112,w*.28))
        local actionY=y+18
        if self.compact then
            D.wrap(self,task.name,x+16,y+12,w-32,c.text,UIFont.Medium)
            actionY=y+titleHeight+18
            D.text(self,P.time(task.start)..' / '..P.status(data,task,now.minute),x+16,actionY+9,tone,nil,w-actionW-44)
        else
            D.text(self,task.name,x+44,y+12,c.text,UIFont.Medium,w-64-actionW)
            D.text(self,P.time(task.start)..' / '..P.status(data,task,now.minute),x+44,y+14+D.fontHeight(UIFont.Medium),tone,nil,w-64-actionW)
        end
        self:button('task-'..id..'-actions',open and 'Close' or 'Actions',x+w-actionW-14,actionY,actionW,h,function()
            self.actionMenuId=open and nil or id;self.deleteId=nil
        end,open and 'primary' or nil)
        self:region('task-'..id,x,y,w-actionW-20,collapsed,function()
            self.actionMenuId=self.actionMenuId==id and nil or id;self.deleteId=nil
        end,{taskId=id})
        local cy=y+collapsed
        if open then
            D.rect(self,x+16,cy-2,w-32,1,c.line)
            D.text(self,task.category..' / '..task.priority..' / '..task.kind,x+16,cy+6,c.muted,nil,w-32);cy=cy+self.lh+9
            if task.notes~='' then cy=cy+D.wrap(self,task.notes,x+16,cy,w-32,c.text)+6 end
            if locationText then cy=cy+D.wrap(self,locationText,x+16,cy,w-32,c.mint)+8 end
            local bw=(w-42)/2
            local opts={{'Done','done'},{'Start now','start'},{'Snooze 30m','snooze'},{'Skip today','skipped'},{'Undo','pending'},{'Edit',nil}}
            for i,opt in ipairs(opts) do
                local label,action=opt[1],opt[2];local bx=x+16+(i-1)%2*(bw+10);local by=cy+math.floor((i-1)/2)*(h+8)
                self:button('task-'..id..'-'..label,label,bx,by,bw,h,function()
                    if action then self:taskAction(id,action) else self:openEditor(task) end
                end,label=='Done' and 'primary' or nil)
            end
            cy=cy+3*(h+8)
            self:button('task-'..id..'-delete',self.deleteId==id and 'Confirm delete activity' or 'Delete activity',x+16,cy,w-32,h,function()
                if self.deleteId==id then P.delete(data,id);self.deleteId=nil;self.actionMenuId=nil else self.deleteId=id end
            end,self.deleteId==id and 'danger' or nil)
            cy=cy+h+8
            self:button('task-'..id..'-place',place and 'Change linked place' or 'Link a saved place',x+16,cy,w-32,h,function()
                self:showApp('travel');self.travelTaskId=id
            end);cy=cy+h+8
        end
        y=math.max(cardStart+height,cy)+12
    end
    if #rows==0 then y=y+D.wrap(self,'No visible activities. Add one, or open today\'s history.',x,y,w,c.muted)+12 end
    y=y+8
    y=y+D.wrap(self,'Older completions are hidden. The newest stays visible, and every daily activity returns at midnight.',x,y,w,c.muted)+12
    y=y+D.wrap(self,'Learning observes fishing, animal care, mechanics and generator activity, including after a task is done. Start now / Done also measures a session. Suggestions need three comparable days.',x,y,w,c.muted)+16
    local recent=L.ensure(self.root).recent
    if #recent>0 then
        y=self:section('RECENT ACTIVITY OBSERVATIONS',y)
        for i=#recent,math.max(1,#recent-4),-1 do
            local r=recent[i]
            y=y+D.wrap(self,r.group..' / '..P.time(r.minute)..' / '..math.max(1,math.floor(r.duration+0.5))..' game min',x,y,w,c.muted)+6
        end
    end
    return y
end
function U:openEditor(task)
    self:clearEntries();self.editing=true;self.editTask=task and task.id or nil;self.error=nil;self.scrollOffset=0;self.actionMenuId=nil;self.deleteId=nil
    local values=task or {name='',notes='',category='General',kind='Daily',priority='Normal',recognition='Manual'}
    local function field(key,text,options)
        local entry
        if options then
            entry=ISComboBox:new(0,0,100,self.lh+16)
            for i,value in ipairs(options) do entry:addOption(value);if value==text then entry.selected=i end end
        else
            entry=ISTextEntryBox:new(text or '',0,0,100,self.lh+16)
        end
        entry:initialise();entry:instantiate();entry.spField=key;entry.spOptions=options
        if not options then entry:setMaxTextLength(key=='notes' and 240 or key=='name' and 40 or 5) end
        entry.backgroundColor={r=c.raised[1],g=c.raised[2],b=c.raised[3],a=self.opacity}
        entry.borderColor={r=c.line[1],g=c.line[2],b=c.line[3],a=self.opacity}
        entry.textColor={r=c.text[1],g=c.text[2],b=c.text[3],a=1}
        self:addChild(entry);table.insert(self.entries,entry)
    end
    field('name',values.name);field('category',values.category,P.categories);field('kind',values.kind,P.kinds)
    field('start',values.start and P.time(values.start) or '');field('finish',values.finish and P.time(values.finish) or '')
    field('priority',values.priority,P.priorities);field('recognition',values.recognition,P.recognitions);field('notes',values.notes)
end
function U:drawEditor(y)
    local x,w=self.pad,self.bodyW;local h=self.lh+16;local half=(w-12)/2
    y=self:heading(self.editTask and 'Edit activity' or 'New activity','Daily routines repeat at midnight. Leave times empty for an anytime task.',y)
    local locations={name={x,y,w,'Activity name'},category={x,y+h+self.lh+18,half,'Category'},kind={x+half+12,y+h+self.lh+18,half,'Type'}}
    local row=h+self.lh+18
    locations.start={x,y+row*2,half,'Start / HH:MM'};locations.finish={x+half+12,y+row*2,half,'End / HH:MM'}
    locations.priority={x,y+row*3,half,'Priority'};locations.recognition={x+half+12,y+row*3,half,'Auto-complete with'}
    locations.notes={x,y+row*4,w,'Notes'}
    if self.compact then
        local labels={name='Activity name',category='Category',kind='Type',start='Start / HH:MM',finish='End / HH:MM',priority='Priority',recognition='Auto-complete with',notes='Notes'}
        for i,e in ipairs(self.entries) do locations[e.spField]={x,y+row*(i-1),w,labels[e.spField]} end
    end
    for _,e in ipairs(self.entries) do
        local pos=locations[e.spField];D.text(self,pos[4],pos[1],pos[2],c.muted,nil,pos[3])
        e:setX(pos[1]);e:setY(pos[2]+self.lh+5);e:setWidth(pos[3]);e:setHeight(h)
        e.backgroundColor.a=self.opacity;e.borderColor.a=self.opacity
        -- Native input controls are visible only inside the scroll viewport.
        local visible=e.y>=self.bodyY and e.y+e.height<=self.bodyY+self.bodyH
        if not visible then if e.unfocus then e:unfocus() end;if e.hidePopup then e:hidePopup() end end
        e:setVisible(visible)
    end
    y=y+row*(self.compact and #self.entries or 5)
    if self.error then y=y+D.wrap(self,self.error,x,y,w,c.red)+10 end
    self:button('save-edit','Save activity',x,y,half,h,function() self:saveEditor() end,'primary')
    self:button('cancel-edit','Cancel',x+half+12,y,half,h,function() self:showApp('planner') end);y=y+h+12
    if self.editTask then
        self:button('delete-edit',self.deleteId and 'Confirm delete activity' or 'Delete activity',x,y,w,h,function()
            if self.deleteId==self.editTask then P.delete(self.root.planner,self.editTask);self:showApp('planner') else self.deleteId=self.editTask end
        end,self.deleteId and 'danger' or nil);y=y+h+12
    end
    return y+10
end
function U:saveEditor()
    local fields={}
    for _,e in ipairs(self.entries) do fields[e.spField]=e.spOptions and e:getOptionText(e.selected) or e:getText() end
    local task,err=P.save(self.root.planner,self.editTask,fields)
    if not task then self.error=err;return end
    self:showApp('planner');self.actionMenuId=task.id
end
return U
