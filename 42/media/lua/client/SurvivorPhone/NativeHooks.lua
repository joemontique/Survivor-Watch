require 'SurvivorPhone/FishingTracker'
require 'SurvivorPhone/ActionRecognition'
SurvivorPhoneHooks={status={},errors={}}
local H=SurvivorPhoneHooks
local F=SurvivorPhoneFishing
function H.safe(label,fn,...)
    local ok,err=pcall(fn,...)
    if not ok and not H.errors[label] then H.errors[label]=tostring(err);print('[SurvivorPhone] '..label..': '..tostring(err)) end
end
local function localPlayer(p) return p and not isClient() and not isServer() and not p:isDead() end
local function plantBefore(action,name)
    if not SFarmingSystem or not SFarmingSystem.instance then return end
    local plant
    if action.sq then plant=SFarmingSystem.instance:getLuaObjectOnSquare(action.sq)
    elseif action.plant then plant=SFarmingSystem.instance:getLuaObjectAt(action.plant.x,action.plant.y,action.plant.z) end
    if plant then return {plant=plant,state=plant.state,water=plant.waterLvl,fertilizer=plant.fertilizer,compost=plant.compost,vegetable=plant.hasVegetable} end
end
local function plantChanged(action,name)
    local before=action._survivorPlantBefore;if not before then return false end
    local plant=before.plant
    if name=='ISSeedActionNew' then return before.state=='plow' and plant.state~='plow' end
    if name=='ISWaterPlantAction' then return (action.usesUsed or 0)>0 or (plant.waterLvl or 0)>(before.water or 0) end
    if name=='ISFertilizeAction' then return plant.fertilizer~=before.fertilizer or plant.compost~=before.compost end
    if name=='ISHarvestPlantAction' then return plant.state~=before.state or before.vegetable==true and plant.hasVegetable~=true end
    return false
end
local function wrap(class,method,label,before,after)
    if not class or not class[method] then H.status[label]='Unavailable';return end
    -- Timed-action classes inherit from the base class. Never share its hook flags.
    class._survivorDashboardHooks=rawget(class,'_survivorDashboardHooks') or {}
    if class._survivorDashboardHooks[method] then H.status[label]='Active';return end
    local original=class[method]
    class[method]=function(self,...)
        if before then H.safe(label..':before',before,self,...) end
        local result=original(self,...)
        if after then H.safe(label..':after',after,self,result,...) end
        return result
    end
    class._survivorDashboardHooks[method]=true;H.status[label]='Active'
end
function H.install()
    if isClient() or isServer() then return end
    pcall(require,'TimedActions/ISBaseTimedAction')
    pcall(require,'TimedActions/ISTimedActionQueue')
    wrap(ISBaseTimedAction,'perform','Completed activity observations',function(self)
        if localPlayer(self.character) then SurvivorPhoneLearning.completeAction(self) end
    end)
    pcall(require,'Fishing/FishingManager')
    pcall(require,'TimedActions/Fishing/TimedActions/ISPickupFishAction')
    wrap(Fishing and Fishing.FishingManager,'changeState','Fishing cast boundaries',function(self,name)
        local p=self.player;if not localPlayer(p) then return end
        local seconds,now=SurvivorPhoneClock.realSeconds(),SurvivorPhoneClock.now()
        if name=='Cast' then F.begin(p,seconds,now)
        elseif name=='PickupFish' then F.reeled(p,seconds)
        elseif name=='None' then
            local s=F.active[p]
            if s then F.finish(p,s.stop and not s.action and 'empty' or 'interrupted',seconds,now) end
        end
    end)
    wrap(ISPickupFishAction,'start','Catch XP',function(self)
        if not localPlayer(self.character) then return end
        self._survivorCast=F.active[self.character]
        if self._survivorCast then self._survivorCast.action=self end
        self._survivorXP=self.character:getXp():getXP(Perks.Fishing)
    end,function(self)
        if self._survivorXP then self._survivorXPGained=self.character:getXp():getXP(Perks.Fishing)>self._survivorXP end
    end)
    wrap(ISPickupFishAction,'PickupFishUpdate','Catch received',nil,function(self)
        if not self._survivorCast or self._survivorRecorded or not self.fishInInv then return end
        if F.active[self.character]~=self._survivorCast then return end
        local container=self.item and self.item:getContainer()
        if not container or not container:isInCharacterInventory(self.character) then return end
        -- fishInInv is set by the native action when this exact catch enters inventory.
        self._survivorRecorded=true
        F.finish(self.character,self._survivorXPGained and 'success' or 'empty',SurvivorPhoneClock.realSeconds(),SurvivorPhoneClock.now())
    end)
    local generators={{'ISGeneratorInfoAction','perform'},{'ISActivateGenerator','complete'},
        {'ISPlugGenerator','complete'},{'ISFixGenerator','complete'},{'ISAddFuel','complete'},{'ISTakeGenerator','complete'}}
    for _,entry in ipairs(generators) do
        local name,method=entry[1],entry[2]
        pcall(require,'TimedActions/'..name)
        wrap(_G[name],method,name,nil,function(self,result)
            if localPlayer(self.character) and (method=='perform' or result==true) then
                SurvivorPhoneRecognition.result(self.character,'Generator interaction','Generator interaction completed')
            end
        end)
    end
    local animalActions={
        {'TimedActions/Animals/ISPetAnimal','ISPetAnimal','complete','Petted animal'},
        {'TimedActions/Animals/ISFeedAnimalFromHand','ISFeedAnimalFromHand','complete','Hand-fed animal'},
        {'TimedActions/Animals/ISMilkAnimal','ISMilkAnimal','complete','Animal care completed'}
    }
    for _,entry in ipairs(animalActions) do
        local path,name,method,evidence=entry[1],entry[2],entry[3],entry[4]
        pcall(require,path)
        wrap(_G[name],method,name,nil,function(self,result)
            if result==true and localPlayer(self.character) and not self._survivorCompletion then
                self._survivorCompletion=true
                SurvivorPhoneRecognition.result(self.character,'Animal care XP',evidence)
            end
        end)
    end
    local activities={
        {'Farming/TimedActions/ISSeedActionNew','ISSeedActionNew','Farming interaction','Sowed seeds'},
        {'Farming/TimedActions/ISWaterPlantAction','ISWaterPlantAction','Farming interaction','Watered a plant'},
        {'Farming/TimedActions/ISHarvestPlantAction','ISHarvestPlantAction','Farming interaction','Harvested a plant'},
        {'Farming/TimedActions/ISFertilizeAction','ISFertilizeAction','Farming interaction','Fertilized a plant'},
        {'Foraging/ISForageAction','ISForageAction','Foraging collected','Collected forage'}
    }
    for _,entry in ipairs(activities) do
        local path,name,rule,evidence=entry[1],entry[2],entry[3],entry[4]
        pcall(require,path)
        wrap(_G[name],'complete',name,function(self)
            if not localPlayer(self.character) then return end
            if rule=='Farming interaction' then self._survivorPlantBefore=plantBefore(self,name)
            else local items=self.forageIcon and self.forageIcon.itemList;self._survivorForageCount=items and items:size() or 0 end
        end,function(self,result)
            if result==true and localPlayer(self.character) and not self._survivorCompletion and
                (rule=='Farming interaction' and plantChanged(self,name) or rule=='Foraging collected' and (self._survivorForageCount or 0)>0) then
                self._survivorCompletion=true
                local now=SurvivorPhoneClock.now()
                local start=self._survivorActivityStart or now.worldMinute
                SurvivorPhoneLearning.touch(self.character,rule,start,now.worldMinute,now,true)
                SurvivorPhoneRecognition.result(self.character,rule,evidence)
            end
        end)
    end
    pcall(require,'BuildingObjects/TimedActions/ISBuildAction')
    wrap(ISBuildAction,'perform','Building completed',function(self)
        if localPlayer(self.character) and self.square then self._survivorObjectCount=self.square:getObjects():size() end
    end,function(self)
        if localPlayer(self.character) and not self._survivorCompletion and self._survivorObjectCount and self.square:getObjects():size()>self._survivorObjectCount then
            self._survivorCompletion=true
            SurvivorPhoneRecognition.result(self.character,'Building completed','Build action completed')
        end
    end)
end
return H
