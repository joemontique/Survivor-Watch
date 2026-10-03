require 'SurvivorPhone/PhoneUI'
local U,D,P,L,W=SurvivorPhoneUI,SurvivorPhoneWidgets,SurvivorPhonePlanner,SurvivorPhoneLearning,SurvivorPhoneWhatNow
local c=D.c
function U:scheduleSuggestions(now)
    local seconds=SurvivorPhoneClock.realSeconds()
    if not self.suggestionCache or self.suggestionCacheDay~=now.day or seconds-(self.suggestionCacheTime or 0)>=1 or seconds<(self.suggestionCacheTime or 0) then
        self.suggestionCache=L.suggestions(self.root,now);self.suggestionCacheTime=seconds;self.suggestionCacheDay=now.day
    end
    return self.suggestionCache
end
function U:drawWhatNow(y,now)
    local x,w=self.pad,self.bodyW;local h=self.lh+18
    local item=W.choose(self.root,now,self.player)
    local headingY=y
    y=self:section('WHAT NOW?',y)
    if self.compact then
        D.text(self,self.guideDetails and 'Less' or 'Details',x+w-54,headingY,c.mint,nil,54)
        self:region('guide-details',x+w-66,headingY-4,66,self.lh+8,function() self.guideDetails=not self.guideDetails end)
    end
    y=y+D.wrap(self,item.title,x,y,w,item.urgent and c.amber or c.mint,UIFont.Medium)+7
    if self.compact and not self.guideDetails then return y+10 end
    y=y+D.wrap(self,item.reason,x,y,w,c.muted)+12
    local bw=self.compact and w or (w-20)/3
    local openLabel=item.sleepAction=='arm' and 'Arm sleep alarm' or item.sleepAction=='cancel' and 'Cancel alarm' or 'Open '..(item.app=='skills' and 'Progress' or 'Planner')
    self:button('guide-open',openLabel,x,y,bw,h,function()
        if item.sleepAction then SurvivorPhoneSleepCoach.perform(self.player,item.sleepAction)
        else self:showApp(item.app=='home' and 'planner' or item.app);self.actionMenuId=item.taskId end
    end,'primary')
    if self.compact then
        y=y+h+8;bw=(w-10)/2
        self:button('guide-later','Snooze 30m',x,y,bw,h,function() W.decide(self.root,item,'snooze',now) end)
        self:button('guide-dismiss','Dismiss today',x+bw+10,y,bw,h,function() W.decide(self.root,item,'dismiss',now) end)
    else
        self:button('guide-later','Snooze 30m',x+bw+10,y,bw,h,function() W.decide(self.root,item,'snooze',now) end)
        self:button('guide-dismiss','Dismiss today',x+2*(bw+10),y,bw,h,function() W.decide(self.root,item,'dismiss',now) end)
    end
    y=y+h+12
    local count=#self:scheduleSuggestions(now)
    if count>0 then
        self:button('guide-review','Review '..count..' schedule suggestion'..(count==1 and '' or 's'),x,y,w,h,function() self:showApp('suggestions') end)
        y=y+h+12
    end
    return y+8
end
local function description(task)
    if not task then return 'Not currently scheduled' end
    return task.name..' / '..P.time(task.start)..(task.finish and ' - '..P.time(task.finish) or '')
end
function U:drawSuggestions(y,now)
    local x,w=self.pad,self.bodyW;local h=self.lh+18;local half=(w-10)/2
    y=self:heading('A routine that fits you','Review each change. Your current plan stays in place until you choose Apply.',y)
    if self.suggestionMessage then y=y+D.wrap(self,self.suggestionMessage,x,y,w,c.mint)+14 end
    local rows=self:scheduleSuggestions(now)
    if #rows==0 then
        y=y+D.wrap(self,self.root.settings.learning and 'No changes to review. Keep playing your usual routine: suggestions need at least three separate days of comparable observations.' or 'Routine learning is off. Enable it in Settings to collect observations and suggest changes.',x,y,w,c.muted)+18
    end
    for _,suggestion in ipairs(rows) do
        local s=suggestion
        local verb=s.kind=='add' and 'ADD' or s.kind=='remove' and 'REMOVE' or 'ADJUST'
        y=self:section(verb..' / '..s.confidence..' / '..s.count..' days',y)
        y=y+D.wrap(self,s.name,x,y,w,c.text,UIFont.Medium)+8
        y=y+D.wrap(self,s.reason,x,y,w,c.purple)+10
        y=y+D.wrap(self,'Current: '..description(s.current),x,y,w,c.muted)+5
        y=y+D.wrap(self,'Proposed: '..(s.kind=='remove' and 'Archive this activity; keep its history.' or description(s.proposed)),x,y,w,c.text)+10
        for _,evidence in ipairs(s.evidence) do y=y+D.wrap(self,evidence,x,y,w,c.muted)+5 end
        if #s.overlaps>0 then
            y=y+D.wrap(self,'Overlaps to consider: '..table.concat(s.overlaps,'; ')..'. Applying changes only this activity.',x,y,w,c.amber)+12
        end
        local function choose(action)
            local ok,err=L.decide(self.root,s,action,now)
            self.suggestionMessage=ok and (action=='apply' and 'Change applied. Your other activities and records are kept.' or action=='keep' and 'Current schedule kept. This proposal stays quiet until you edit the activity.' or action=='snooze' and 'Hidden until the next game day.' or 'Dismissed. It can return when the proposed change is materially different.') or err
            self.scrollOffset=0
            self.suggestionCache=nil
        end
        self:button('suggest-'..s.key..'-apply',s.kind=='remove' and 'Apply removal' or 'Apply change',x,y,half,h,function() choose('apply') end,s.kind=='remove' and 'danger' or 'primary')
        self:button('suggest-'..s.key..'-snooze','Snooze until tomorrow',x+half+10,y,half,h,function() choose('snooze') end);y=y+h+10
        self:button('suggest-'..s.key..'-dismiss','Dismiss suggestion',x,y,half,h,function() choose('dismiss') end)
        self:button('suggest-'..s.key..'-keep','Keep current schedule',x+half+10,y,half,h,function() choose('keep') end);y=y+h+22
        D.rect(self,x,y,w,1,c.line);y=y+20
    end
    local audit=L.ensure(self.root).audit
    if #audit>0 then
        y=self:section('RECENT APPLIED CHANGES',y)
        for i=#audit,math.max(1,#audit-4),-1 do local r=audit[i];y=y+D.wrap(self,r.day..' / '..r.kind..' / '..r.name,x,y,w,c.muted)+8 end
    end
    return y+8
end
return U
