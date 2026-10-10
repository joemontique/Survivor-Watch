require 'SurvivorPhone/PhoneUI'
require 'SurvivorPhone/WatchUI'
require 'SurvivorPhone/PlannerApp'
require 'SurvivorPhone/GuidanceApp'
require 'SurvivorPhone/TravelApp'
require 'SurvivorPhone/WatchPanelUI'
require 'SurvivorPhone/ProgressApp'
require 'SurvivorPhone/MechanicsXP'
require 'SurvivorPhone/ClockHotspot'
require 'SurvivorPhone/Notifications'
require 'SurvivorPhone/NativeHooks'
require 'SurvivorPhone/SleepCoach'
require 'SurvivorPhone/RunningTracker'
SurvivorPhone=SurvivorPhone or {}
local S=SurvivorPhone
S.windows=S.windows or {};S.watchWindows=S.watchWindows or {};S.nextPoll={};S.lastMinute={};S.legacyItemType='SurvivorPhone.CellPhone';S.version='1.6.6'
local function ownedBy(item,player)
    local container=item and item:getContainer();return container and container:isInCharacterInventory(player)
end
function S.isDigitalWatch(item)
    if not item then return false end
    local okKind,kind=pcall(function() return instanceof(item,'AlarmClockClothing') end)
    if not okKind or not kind then return false end
    if item.isDigital then
        local ok,value=pcall(function() return item:isDigital() end)
        if ok and value==false then return false end
    end
    return true
end
function S.open(item,player)
    if not player or isClient() or isServer() or player:isDead() or not ownedBy(item,player) or not S.isDigitalWatch(item) then return end
    local index=player:getPlayerNum();local current=S.windows[index]
    if current then current:bringToTop();return end
    if S.watchWindows[index] then S.closeWatch(index,false) end
    local window=SurvivorWatchPanelUI:new(player,item)
    window:initialise();window:addToUIManager();window:setVisible(true);S.windows[index]=window
end
function S.openWatch(item,player)
    if not player or isClient() or isServer() or player:isDead() or not ownedBy(item,player) or not S.isDigitalWatch(item) then return end
    local index=player:getPlayerNum();local current=S.watchWindows[index]
    if S.windows[index] then S.windows[index]:bringToTop();return end
    if current then current:bringToTop();return end
    local root=SurvivorPhoneData.get(player)
    root.settings.watchEnabled=true
    local watch=SurvivorWatchUI:new(player,item)
    watch:initialise();watch:addToUIManager();watch:setVisible(true);S.watchWindows[index]=watch
end
function S.closeWatch(index,disable)
    local watch=S.watchWindows[index]
    if watch then watch:close(disable) end
end
function S.ensureWatch(player,item)
    local index=player:getPlayerNum()
    local root=SurvivorPhoneData.get(player)
    if S.windows[index] then
        if S.watchWindows[index] then S.closeWatch(index,false) end
        return
    end
    if root.settings.watchEnabled then
        if not S.watchWindows[index] then S.openWatch(item,player) end
    elseif S.watchWindows[index] then S.closeWatch(index,false) end
end
function S.contextMenu(index,context,items)
    local player=getSpecificPlayer(index);if not player or isClient() or isServer() then return end
    for _,entry in ipairs(items) do
        local item=entry
        if not instanceof(entry,'InventoryItem') then item=entry.items and entry.items[1] end
        if S.isDigitalWatch(item) and ownedBy(item,player) then
            context:addOption('Open Survivor Watch',item,S.openWatch,player)
            return
        end
    end
end
function S.findTracker(container)
    local items=container:getItems()
    for i=0,items:size()-1 do
        local item=items:get(i)
        if S.isDigitalWatch(item) then return item end
        if instanceof(item,'InventoryContainer') then local found=S.findTracker(item:getInventory());if found then return found end end
    end
end
function S.findPhone(container)
    local items=container:getItems()
    for i=0,items:size()-1 do
        local item=items:get(i)
        if item:getFullType()==S.legacyItemType then return item end
        if instanceof(item,'InventoryContainer') then local found=S.findPhone(item:getInventory());if found then return found end end
    end
end
function S.removeLegacyPhone(player)
    local item=S.findPhone(player:getInventory())
    if not item then return end
    local container=item:getContainer()
    if container and container.Remove then pcall(function() container:Remove(item) end) end
end
function S.onCreatePlayer(index,player)
    if S.windows[index] then S.windows[index]:close() end
    if S.watchWindows[index] then S.watchWindows[index]:close(false) end
    SurvivorPhoneNotifications.dismiss(index)
    S.nextPoll={};S.lastMinute={}
    if not player or isClient() or isServer() then return end
    local root=SurvivorPhoneData.get(player)
    S.removeLegacyPhone(player)
    root.receivedPhone=nil
    SurvivorPhoneRecognition.snapshots[player]=nil;SurvivorPhoneRecognition.levels[player]=nil;SurvivorPhoneRecognition.sleeping[player]=nil
    SurvivorPhoneActivity.current[player]=nil;SurvivorPhoneTravel.runtime[player]=nil;SurvivorPhoneRunning.runtime[player]=nil
    SurvivorPhoneRecognition.scan(player)
    SurvivorPhoneHooks.install()
    SurvivorPhoneMechanicsXP.install()
    if SurvivorWatchClockHotspot then SurvivorWatchClockHotspot.install(player) end
    local watch=S.findTracker(player:getInventory())
    if watch then S.ensureWatch(player,watch) end
end
function S.poll(player)
    if not player or isClient() or isServer() or player:isDead() or getSpecificPlayer(player:getPlayerNum())~=player then return end
    local seconds=SurvivorPhoneClock.realSeconds()
    if seconds<(S.nextPoll[player] or 0) then return end
    S.nextPoll[player]=seconds+0.25
    SurvivorPhoneHooks.safe('Activity detection',SurvivorPhoneActivity.poll,player)
    SurvivorPhoneHooks.safe('Travel observations',SurvivorPhoneTravel.poll,player)
    SurvivorPhoneHooks.safe('Activity observations',SurvivorPhoneLearning.poll,player)
    SurvivorPhoneHooks.safe('XP tracking',SurvivorPhoneRecognition.scan,player)
    SurvivorPhoneHooks.safe('Running fitness tracking',SurvivorPhoneRunning.poll,player)
    SurvivorPhoneHooks.safe('Fishing maintenance',SurvivorPhoneFishing.update,player)
    SurvivorPhoneHooks.safe('Needs tracking',SurvivorPhoneNeeds.update,player)
    SurvivorPhoneHooks.safe('Sleep reset coach',SurvivorPhoneSleepCoach.poll,player)
    local root,planner,now=SurvivorPhoneData.get(player)
    local hotspot=SurvivorWatchClockHotspot and SurvivorWatchClockHotspot.instance
    local watch
    if hotspot and hotspot.player==player then watch=hotspot:getWatch(S,false)
    else watch=S.findTracker(player:getInventory()) end
    if watch then SurvivorPhoneHooks.safe('Watch overlay',S.ensureWatch,player,watch) end
    if S.lastMinute[player]~=math.floor(now.worldMinute) then
        S.lastMinute[player]=math.floor(now.worldMinute)
        local due=SurvivorPhonePlanner.notifications(planner,now.minute)
        if #due>0 then
            local message=#due==1 and due[1].name..' is ready when you are.' or #due..' planned activities are ready.'
            SurvivorPhoneNotifications.emit(player,'routine','due:'..now.day..':'..now.minute,message,'planner')
        end
    end
    SurvivorPhoneNotifications.deliver(player)
end
local function onXP(player)
    if player and instanceof(player,'IsoPlayer') and not isClient() and not isServer() and getSpecificPlayer(player:getPlayerNum())==player then
        SurvivorPhoneHooks.safe('XP event',SurvivorPhoneRecognition.scan,player)
    end
end
Events.OnFillInventoryObjectContextMenu.Add(S.contextMenu)
Events.OnCreatePlayer.Add(S.onCreatePlayer)
Events.OnPlayerUpdate.Add(S.poll)
Events.OnGameStart.Add(SurvivorPhoneHooks.install)
Events.OnGameStart.Add(SurvivorPhoneMechanicsXP.install)
Events.AddXP.Add(onXP)
print('[SurvivorPhone] Survivor Watch 1.6.6 loaded (Build 42.20).')
return S