require 'SurvivorPhone/PhoneUI'
local U,D,T,P=SurvivorPhoneUI,SurvivorPhoneWidgets,SurvivorPhoneTravel,SurvivorPhonePlanner
local c=D.c
function U:openPlaceName(place)
    self:clearEntries();self.travelNaming=true;self.travelRenameId=place and place.id or nil;self.scrollOffset=0
    local entry=ISTextEntryBox:new(place and place.name or '',0,0,self.bodyW,self.lh+16)
    entry:initialise();entry:instantiate();entry:setMaxTextLength(40)
    entry.backgroundColor={r=c.raised[1],g=c.raised[2],b=c.raised[3],a=self.opacity}
    entry.borderColor={r=c.line[1],g=c.line[2],b=c.line[3],a=self.opacity}
    entry.textColor={r=c.text[1],g=c.text[2],b=c.text[3],a=1}
    self:addChild(entry);table.insert(self.entries,entry)
end
function U:drawTravel(y,now)
    local x,w,h=self.pad,self.bodyW,self.lh+18
    local data=T.ensure(self.root);local pos=T.position(self.player)
    local task=self.travelTaskId and P.find(self.root.planner,self.travelTaskId)
    y=self:heading('Places & travel',task and 'Choose a place for '..task.name or 'A memory of where you have been.',y)
    if self.travelMessage then y=y+D.wrap(self,self.travelMessage,x,y,w,c.mint)+10 end
    if self.travelNaming then
        y=y+D.wrap(self,self.travelRenameId and 'Rename this place.' or 'Name your current spot. It will be saved when you choose Save.',x,y,w,c.muted)+8
        local entry=self.entries[1]
        entry:setX(x);entry:setY(y);entry:setWidth(w);entry:setHeight(h)
        entry.backgroundColor.a=self.opacity;entry.borderColor.a=self.opacity
        local visible=y>=self.bodyY and y+h<=self.bodyY+self.bodyH
        if not visible and entry.unfocus then entry:unfocus() end;entry:setVisible(visible)
        y=y+h+10
        self:button('place-save','Save place',x,y,w,h,function()
            local place,err
            if self.travelRenameId then
                place=T.find(self.root,self.travelRenameId)
                local name=entry:getText():match('^%s*(.-)%s*$')
                if name=='' or #name>40 then place=nil;err='Use a name of 1-40 characters.'
                elseif place then place.name=name else err='That place is no longer saved.' end
            else place,err=T.savePlace(self.player,entry:getText()) end
            if not place then self.travelMessage=err;return end
            self.travelMessage='Saved '..place.name..'.';self.travelNaming=false;self:clearEntries();self.scrollOffset=0
        end,'primary');y=y+h+8
        self:button('place-cancel','Cancel',x,y,w,h,function() self.travelNaming=false;self:clearEntries();self.scrollOffset=0 end)
        return y+h+12
    end
    if task then
        self:button('place-unlink','Remove location link',x,y,w,h,function() task.placeId=nil;self:showApp('planner');self.actionMenuId=task.id end)
        y=y+h+10
    else
        self:button('travel-record','Record travel / '..(self.root.settings.travelTracking and 'On' or 'Off'),x,y,w,h,function()
            self.root.settings.travelTracking=not self.root.settings.travelTracking;T.runtime[self.player]=nil
        end);y=y+h+8
        self:button('travel-trail','Recent trail / '..(self.root.settings.showTrail and 'Shown' or 'Hidden'),x,y,w,h,function() self.root.settings.showTrail=not self.root.settings.showTrail end);y=y+h+10
    end
    self:button('place-new','+ Save current location',x,y,w,h,function() self:openPlaceName(nil) end,'primary');y=y+h+16
    if not task and self.root.settings.showTrail then
        y=self:section('RECENT TRAIL',y)
        local ph=140;self:card(x,y,w,ph)
        local points={}
        for i=math.max(1,#data.points-119),#data.points do
            local point=data.points[i]
            if not pos or point.z==pos.z then table.insert(points,point) end
        end
        if #points<2 then D.text(self,'Walk a little to start your trail.',x+12,y+16,c.muted,nil,w-24)
        else
            local minX,maxX,minY,maxY=points[1].x,points[1].x,points[1].y,points[1].y
            for _,p in ipairs(points) do minX=math.min(minX,p.x);maxX=math.max(maxX,p.x);minY=math.min(minY,p.y);maxY=math.max(maxY,p.y) end
            local scale=math.min((w-32)/math.max(20,maxX-minX),(ph-32)/math.max(20,maxY-minY))
            local cx,cy=(minX+maxX)/2,(minY+maxY)/2
            for i,p in ipairs(points) do
                local px=x+w/2+(p.x-cx)*scale;local py=y+ph/2+(p.y-cy)*scale
                local size=i==#points and 7 or 3
                D.rect(self,px-size/2,py-size/2,size,size,i==#points and c.mint or c.blue,0.35+0.65*i/#points)
            end
        end
        y=y+ph+8
        y=y+D.wrap(self,'Dots are sampled positions on this floor; green is the latest. This is a trail sketch, with no terrain or unexplored map information.',x,y,w,c.muted)+16
    end
    y=self:section('SAVED PLACES',y)
    if #data.places==0 then y=y+D.wrap(self,'Save places while you visit them, then link planner activities to them through Actions.',x,y,w,c.muted)+12 end
    for _,value in ipairs(data.places) do
        local place=value
        y=y+D.wrap(self,T.describe(place,pos),x,y,w,c.text,UIFont.Medium)+6
        y=y+D.wrap(self,'Last visited '..place.lastDay..' at '..P.time(place.lastMinute)..' / '..place.visits..' visit'..(place.visits==1 and '' or 's'),x,y,w,c.muted)+8
        self:button('place-'..place.id,task and 'Link to this activity' or 'Rename place',x,y,w,h,function()
            if task then task.placeId=place.id;self:showApp('planner');self.actionMenuId=task.id
            else self:openPlaceName(place) end
        end,task and 'primary' or nil);y=y+h+18
    end
    y=y+D.wrap(self,'Travel is sampled every five real seconds while awake. Up to 360 movement samples are kept for seven game days; saved places stay with this survivor.',x,y,w,c.muted)+16
    return y
end
return U
