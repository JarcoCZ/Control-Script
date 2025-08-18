--[[  
    Floxy Script - Fully Corrected & Stabilized by luxx (v60 - Optimized & Pre-Respawn Attack - Silent)  
    ... (comments unchanged)  
]]  

-- Services  
local Players = game:GetService("Players")  
local RunService = game:GetService("RunService")  
local TextChatService = game:GetService("TextChatService")  
local TeleportService = game:GetService("TeleportService")  
local HttpService = game:GetService("HttpService")  
local Workspace = game:GetService("Workspace")  
local ReplicatedStorage = game:GetService("ReplicatedStorage")  

-- Local Player & Script-Wide Variables  
local LP = Players.LocalPlayer  
local PlayerList = {}  
local KillStates = {}  
local Targets = {}  
local Whitelist = {}  
local ConnectedUsers = {}  
local DeathPositions = {}  
local PlayersAboutToRespawn = {} -- Track players who are about to respawn  
local FollowTarget = nil  
local MainConnector = nil  
local ForceEquipConnection = nil  
local HeartbeatConnection = nil  
local SpammingEnabled = false  
local safePlatform = nil  
local safeZoneConnection = nil  
local safeZonePlatform = nil  
local spinConnection = nil  
local spinTarget = nil  

-- NEW: From first script  
local TargetList = {} -- userId => true  
local AutoEquipConnection = nil  
local AutoEquipEnabled = false  
local SimpleAuraConnection = nil  
local SimpleAuraEnabled = false  
local SimpleAuraRange = 20  

-- Bot specific variables  
getgenv().HowFastDanSchneiderCatchesYou = 1.1  
getgenv().HowMuchDanSchneiderTouchesYou = 15  
getgenv().HowMuchDanSchneiderTouchedYou = 10000  
getgenv().Daddy_Catches_You = false  

-- Pre-loaded Instances  
local ChangeTimeEvent = nil  

-- Configuration  
local Dist = 0  
local AuraEnabled = false  
local DMG_TIMES = 1  
local FT_TIMES = 3  
local SPIN_RADIUS = 7  
local SPIN_SPEED = 10  
local SPIN_HEIGHT_OFFSET = 5  
local SAFE_PLATFORM_POS = Vector3.new(0, 10000, 0)  
local FIGHT_PLATFORM_POS = Vector3.new(0, 125, 125)  
local SAFE_ZONE_OFFSET = Vector3.new(0, 15, 0)  
local FROG_JUMP_HEIGHT = 10  
local FROG_JUMP_PREP_DIST = 3  
local WEBHOOK_URL = "https://discord.com/api/webhooks/1405285885678845963/KlBVzcpGVzyDygUqghaSxJaL6OSj4IQ5ZIHQn8bbSu7a_O96DZUL2PynS47TAc0P22"  

-- Authorization  
local AuthorizedUsers = { 1588706905, 3495579817, 7569689472, 8334959064, 7569689472, 8163394412, 4773801116 }  
local AutoWhitelistUsers = {  
    "cubot_nova4","Cub0t_01","Cubot_Nova3","FlexFightPro68","FlexFightPro69","defnotluxs","e5c4qe"  
}  

-- ==================================  
-- ==      HELPER FUNCTIONS        ==  
-- ==================================  

local function isAuthorized(userId)  
    for _, id in ipairs(AuthorizedUsers) do if userId == id then return true end end  
    return false  
end  

if not isAuthorized(LP.UserId) then  
    return  
end  

local function sendWebhook(payload) end -- removed  

local function sendMessage(message)  
    pcall(function()  
        TextChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)  
    end)  
end  

local function findPlayer(partialName)  
    if not partialName then return nil end  
    local lowerName = tostring(partialName):lower()  
    for _, player in ipairs(Players:GetPlayers()) do  
        if player.Name:lower():find(lowerName, 1, true) then  
            return player  
        end  
    end  
    return nil  
end  

-- NEW: From first script - flexible partial matches for name or display  
local function FindPlayers(partialName)  
    if not partialName then return {} end  
    local lowerName = tostring(partialName):lower()  
    local found = {}  
    for _, p in ipairs(Players:GetPlayers()) do  
        if p ~= LP then  
            local pn = p.Name:lower()  
            local pd = p.DisplayName:lower()  
            if pn:find(lowerName, 1, true) or pd:find(lowerName, 1, true) then  
                table.insert(found, p)  
            end  
        end  
    end  
    return found  
end  

-- NEW: From first script - TargetList helpers  
local function AddMultipleTargets(players)  
    local count = 0  
    for _, player in ipairs(players) do  
        if not TargetList[player.UserId] then  
            TargetList[player.UserId] = true  
            count = count + 1  
        end  
    end  
    return count  
end  

local function RemoveMultipleTargets(players)  
    local count = 0  
    for _, player in ipairs(players) do  
        if TargetList[player.UserId] then  
            TargetList[player.UserId] = nil  
            count = count + 1  
        end  
    end  
    return count  
end  

local function teleportTo(character, destination)  
    if character and character.PrimaryPart then  
        if typeof(destination) == "CFrame" then  
            character:SetPrimaryPartCFrame(destination)  
        elseif typeof(destination) == "Vector3" then  
            character:SetPrimaryPartCFrame(CFrame.new(destination))  
        end  
    end  
end  

local function getClosestPlayer()  
    local closestPlayer = nil  
    local shortestDistance = getgenv().HowMuchDanSchneiderTouchedYou  
    if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then return nil end  
    local localRootPart = LP.Character.HumanoidRootPart  
    for _, v in pairs(Players:GetPlayers()) do  
        if v.Name ~= LP.Name then  
            if v.Character and v.Character:FindFirstChild("Humanoid") and v.Character.Humanoid.Health > 0 and v.Character:FindFirstChild("HumanoidRootPart") and v.Character:FindFirstChild("Head") then  
                if not v.Character:FindFirstChildOfClass("ForceField") then  
                    local ray = Ray.new(v.Character.HumanoidRootPart.Position, Vector3.new(0,-100000,0))  
                    local hitPart = Workspace:FindPartOnRay(ray, v.Character)  
                    if hitPart then  
                        local magnitude = (v.Character.HumanoidRootPart.Position - localRootPart.Position).Magnitude  
                        if magnitude < shortestDistance then  
                            closestPlayer = v  
                            shortestDistance = magnitude  
                        end  
                    end  
                end  
            end  
        end  
    end  
    return closestPlayer  
end  

-- ==================================  
-- ==      TOOL & COMBAT LOGIC     ==  
-- ==================================  

local function createReachPart(tool)  
    if tool:IsA("Tool") and tool:FindFirstChild("Handle") then  
        local handle = tool.Handle  
        if not handle:FindFirstChild("BoxReachPart") then  
            local p = Instance.new("Part")  
            p.Name = "BoxReachPart"; p.Size = Vector3.new(Dist, Dist, Dist)  
            p.Transparency = 1; p.CanCollide = false; p.Massless = true  
            p.Parent = handle  
            local w = Instance.new("WeldConstraint")  
            w.Part0, w.Part1 = handle, p  
            w.Parent = p  
        end  
    end  
end  

local function fireTouch(part1, part2)  
    for _ = 1, FT_TIMES do  
        firetouchinterest(part1, part2, 0)  
        firetouchinterest(part1, part2, 1)  
    end  
end  

local function killLoop(player, toolPart)  
    if KillStates[player] then return end  
    KillStates[player] = true  
    task.spawn(function()  
        while KillStates[player] and player.Parent and LP.Character do  
            local targetChar = player.Character;  
            local myChar = LP.Character  
            local tool = toolPart.Parent  
            if not (targetChar and targetChar:FindFirstChildOfClass("Humanoid") and targetChar.Humanoid.Health > 0 and myChar and tool and tool.Parent == myChar) then  
                break  
            end  
            local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")  
            if not targetHumanoid or targetHumanoid.Health <= 0 then break end  
            for _, part in ipairs(targetChar:GetChildren()) do  
                if part:IsA("BasePart") then fireTouch(toolPart, part) end  
            end  
            task.wait()  
        end  
        KillStates[player] = nil  
    end)  
end  

local function attackPlayer(toolPart, player)  
    local targetChar = player.Character  
    local targetHumanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")  
    if not (targetHumanoid and targetHumanoid.Health > 0) then return end  
    pcall(function() toolPart.Parent:Activate() end)  
    for _ = 1, DMG_TIMES do  
        for _, part in ipairs(targetChar:GetChildren()) do  
            if part:IsA("BasePart") then fireTouch(toolPart, part) end  
        end  
    end  
    killLoop(player, toolPart)  
end  

local function manualAttack(targetPlayer)  
    local character = LP.Character  
    local targetCharacter = targetPlayer.Character  
    if not (character and targetCharacter) then return end  
    local tool = character:FindFirstChildWhichIsA("Tool")  
    if not (tool and tool:FindFirstChild("Handle")) then  
        local backpackTool = LP.Backpack:FindFirstChildWhichIsA("Tool")  
        if backpackTool then  
            backpackTool.Parent = character  
            task.wait(0.1)  
            tool = backpackTool  
        else  
            return  
        end  
    end  
    local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")  
    if not (targetHumanoid and targetHumanoid.Health > 0) then return end  
    pcall(function() tool:Activate() end)  
    for _ = 1, DMG_TIMES do  
        for _, part in ipairs(targetCharacter:GetChildren()) do  
            if part:IsA("BasePart") then  
                fireTouch(tool.Handle, part)  
            end  
        end  
    end  
end  

local function onHeartbeat()  
    if not LP.Character or not LP.Character.PrimaryPart then return end  
    local myPos = LP.Character.PrimaryPart.Position  
    local myHumanoid = LP.Character:FindFirstChildOfClass("Humanoid")  

    if FollowTarget and FollowTarget.Character and FollowTarget.Character.PrimaryPart and myHumanoid and not safeZoneConnection then  
        local targetPos = FollowTarget.Character.PrimaryPart.Position  
        if (targetPos - myPos).Magnitude > 5 then  
            myHumanoid:MoveTo(targetPos)  
        end  
    end  

    if SpammingEnabled then  
        local tool = LP.Character:FindFirstChildOfClass("Tool")  
        if tool then pcall(function() tool:Activate() end) end  
    end  

    if getgenv().Daddy_Catches_You == true then  
        local targetPlayer = getClosestPlayer()  
        if LP.Character and LP.Character.PrimaryPart and targetPlayer ~= nil then  
            local TargetPart = targetPlayer.Character.HumanoidRootPart  
            local Part = LP.Character.HumanoidRootPart  
            LP.Character:FindFirstChildOfClass('Humanoid').AutoRotate = false  
            Part.CFrame = Part.CFrame:Lerp(CFrame.new(Part.Position, TargetPart.Position) * CFrame.Angles(math.rad(0), math.rad(25), math.rad(0)), getgenv().HowFastDanSchneiderCatchesYou)  
            LP.Character.Humanoid:MoveTo(targetPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(-3, 0, 0).p)  
            if targetPlayer.Character.Humanoid:GetState() == Enum.HumanoidStateType.Freefall then  
                LP.Character.Humanoid.Jump = true  
            end  
        else  
            if LP.Character and LP.Character:FindFirstChildOfClass('Humanoid') then  
                LP.Character:FindFirstChildOfClass('Humanoid').AutoRotate = true  
            end  
        end  
    else  
        if LP.Character and LP.Character:FindFirstChildOfClass('Humanoid') then  
            LP.Character:FindFirstChildOfClass('Humanoid').AutoRotate = true  
        end  
    end  

    for _, tool in ipairs(LP.Character:GetChildren()) do  
        if tool:IsA("Tool") then  
            local hitbox = tool:FindFirstChild("BoxReachPart") or tool:FindFirstChild("Handle")  
            if hitbox then  
                for _, player in ipairs(PlayerList) do  
                    if player ~= LP and player.Character then  
                        local targetHumanoid = player.Character:FindFirstChildOfClass("Humanoid")  
                        if targetHumanoid and targetHumanoid.Health > 0 then  
                            if not table.find(Whitelist, player.Name) then  
                                local isTargeted = table.find(Targets, player.Name) -- old list  
                                -- NEW: respect TargetList too (userId keyed)  
                                local isTargetedById = TargetList[player.UserId] == true  
                                local distToPlayer = AuraEnabled and (player.Character.PrimaryPart.Position - myPos).Magnitude or math.huge  
                                local inAuraRange = AuraEnabled and distToPlayer <= Dist  
                                if isTargeted or isTargetedById or inAuraRange then  
                                    attackPlayer(hitbox, player)  
                                end  
                            end  
                        end  
                    end  
                end  
            end  
        end  
    end  
end  

-- ==================================  
-- ==   AUT0EQUIP / SIMPLE AURA    ==  
-- ==================================  

local function StartAutoEquip()  
    if AutoEquipConnection then AutoEquipConnection:Disconnect() end  
    AutoEquipConnection = RunService.Stepped:Connect(function()  
        pcall(function()  
            for _, tool in ipairs(LP.Backpack:GetChildren()) do  
                if tool.Name == "Punch" or tool.Name == "Ground Slam" or tool.Name == "Stomp" then  
                    tool:Destroy()  
                elseif tool:IsA("Tool") then  
                    tool.Parent = LP.Character  
                end  
            end  
            local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")  
            if tool then tool:Activate() end  
        end)  
    end)  
    AutoEquipEnabled = true  
end  

local function StopAutoEquip()  
    if AutoEquipConnection then AutoEquipConnection:Disconnect() AutoEquipConnection = nil end  
    AutoEquipEnabled = false  
end  

local function StartSimpleAura()  
    if SimpleAuraConnection then SimpleAuraConnection:Disconnect() end  
    local function onRenderStep()  
        local character = LP.Character  
        if not character then return end  
        local hrp = character:FindFirstChild("HumanoidRootPart")  
        if not hrp then return end  
        local tool = character:FindFirstChildOfClass("Tool")  
        if not (tool and tool:FindFirstChild("Handle")) then return end  
        local handle = tool.Handle  
        local lpPos = hrp.Position  
        local activated = false  
        local rangeSq = SimpleAuraRange * SimpleAuraRange  
        for _, otherPlayer in ipairs(Players:GetPlayers()) do  
            if otherPlayer ~= LP and otherPlayer.Character then  
                local targetChar = otherPlayer.Character  
                local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")  
                local humanoid = targetChar:FindFirstChildWhichIsA("Humanoid")  
                if targetHrp and humanoid and humanoid.Health > 0 then  
                    local delta = targetHrp.Position - lpPos  
                    if delta:Dot(delta) <= rangeSq then  
                        if not activated then  
                            pcall(function() tool:Activate() end)  
                            activated = true  
                        end  
                        for _, part in ipairs(targetChar:GetDescendants()) do  
                            if part:IsA("BasePart") then  
                                pcall(function()  
                                    firetouchinterest(handle, part, 0)  
                                    firetouchinterest(handle, part, 1)  
                                end)  
                            end  
                        end  
                    end  
                end  
            end  
        end  
    end  
    SimpleAuraConnection = RunService.RenderStepped:Connect(onRenderStep)  
    SimpleAuraEnabled = true  
end  

local function StopSimpleAura()  
    if SimpleAuraConnection then SimpleAuraConnection:Disconnect() SimpleAuraConnection = nil end  
    SimpleAuraEnabled = false  
end  

-- ==================================  
-- ==      COMMANDS & CONTROLS     ==  
-- ==================================  

local function changeTime(count)  
    local num = tonumber(count)  
    if not num or num <= 0 then return end  
    if not ChangeTimeEvent then  
        sendMessage("Error: Time event not loaded yet. Please wait a moment and try again.")  
        return  
    end  
    for i = 1, num do  
        ChangeTimeEvent:FireServer("Anti333Exploitz123FF45324", 433, 429)  
    end  
    sendMessage("Time command executed " .. num .. " times.")  
end  

local function frogJump()  
    local myChar = LP.Character  
    if not (myChar and myChar.PrimaryPart) then return end  

    local startPos = myChar.PrimaryPart.Position  
    local prepPos = startPos - Vector3.new(0, FROG_JUMP_PREP_DIST, 0)  
    local finalPos = startPos + Vector3.new(0, FROG_JUMP_HEIGHT, 0)  

    teleportTo(myChar, prepPos)  
    task.wait(0.01)  
    teleportTo(myChar, finalPos)  
end  

local function stopSpinLoop()  
    if spinConnection and spinConnection.Connected then  
        spinConnection:Disconnect()  
        spinConnection = nil  
        spinTarget = nil  
    end  
end  

local function stopSafeZoneLoop()  
    if safeZoneConnection and safeZoneConnection.Connected then  
        safeZoneConnection:Disconnect()  
        safeZoneConnection = nil  
    end  
    if safeZonePlatform and safeZonePlatform.Parent then  
        safeZonePlatform:Destroy()  
        safeZonePlatform = nil  
    end  
    FollowTarget = nil  
end  

local function forceEquip(shouldEquip)  
    if shouldEquip then  
        if not ForceEquipConnection then  
            ForceEquipConnection = RunService.Heartbeat:Connect(function()  
                if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then  
                    local sword = LP.Backpack:FindFirstChildWhichIsA("Tool") or LP.Character:FindFirstChildWhichIsA("Tool")  
                    if sword and not LP.Character:FindFirstChild(sword.Name) then  
                        LP.Character.Humanoid:EquipTool(sword)  
                    end  
                end  
            end)  
        end  
    else  
        if ForceEquipConnection then  
            ForceEquipConnection:Disconnect()  
            ForceEquipConnection = nil  
        end  
    end  
end  

local function addTarget(playerName)  
    local player = findPlayer(playerName)  
    if player and player ~= LP and not table.find(Targets, player.Name) then  
        table.insert(Targets, player.Name)  
        if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then  
            local tool = LP.Backpack:FindFirstChildWhichIsA("Tool") or LP.Character:FindFirstChildWhichIsA("Tool")  
            if tool and not LP.Character:FindFirstChild(tool.Name) then  
                LP.Character.Humanoid:EquipTool(tool)  
            end  
        end  
    end  
end  

local function removeTarget(playerName)  
    local player = findPlayer(playerName)  
    if player then  
        for i, name in ipairs(Targets) do  
            if name == player.Name then table.remove(Targets, i); break end  
        end  
        if #Targets == 0 and not AuraEnabled then forceEquip(false) end  
    end  
end  

local function killOnce(playerName)  
    local player = findPlayer(playerName)  
    if not player or not player.Character or not player.Character:FindFirstChild("Humanoid") then return end  
    addTarget(playerName)  
    local humanoid = player.Character:FindFirstChild("Humanoid")  
    local connection  
    connection = humanoid.Died:Connect(function()  
        removeTarget(playerName)  
        if connection then connection:Disconnect() end  
    end)  
    manualAttack(player)  
end  

local function spinLoop()  
    stopSpinLoop()  
    spinConnection = RunService.Heartbeat:Connect(function()  
        if not (spinTarget and spinTarget.Parent and spinTarget.Character and spinTarget.Character.PrimaryPart) then  
            stopSpinLoop()  
            return  
        end  
        if not (LP.Character and LP.Character.PrimaryPart) then  
            stopSpinLoop()  
            return  
        end  

        local targetPos = spinTarget.Character.PrimaryPart.Position  
        local angle = tick() * SPIN_SPEED  
        local x = targetPos.X + SPIN_RADIUS * math.cos(angle)  
        local z = targetPos.Z + SPIN_RADIUS * math.sin(angle)  

        local myNewPos = Vector3.new(x, targetPos.Y + SPIN_HEIGHT_OFFSET, z)  
        local lookAtPos = Vector3.new(targetPos.X, myNewPos.Y, targetPos.Z)  

        teleportTo(LP.Character, CFrame.new(myNewPos, lookAtPos))  
    end)  
end  

local function setAura(range)  
    local newRange = tonumber(range)  
    if newRange and newRange >= 0 then  
        Dist = newRange  
        AuraEnabled = newRange > 0  
        forceEquip(AuraEnabled or #Targets > 0)  

        if LP.Character then  
            for _, tool in ipairs(LP.Character:GetChildren()) do  
                if tool:IsA("Tool") and tool:FindFirstChild("BoxReachPart") then  
                    tool.BoxReachPart.Size = Vector3.new(Dist, Dist, Dist)  
                end  
            end  
        end  
    end  
end  

local function serverHop()  
    local servers = {}  
    local success, err = pcall(function()  
        local raw = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")  
        servers = HttpService:JSONDecode(raw)  
    end)  

    if not success then  
        sendMessage("Failed to retrieve server list: " .. err)  
        return  
    end  

    if servers and servers.data then  
        local serverList = {}  
        for _, server in ipairs(servers.data) do  
            if type(server) == "table" and server.id ~= game.JobId and server.playing < server.maxPlayers then  
                table.insert(serverList, server.id)  
            end  
        end  

        if #serverList > 0 then  
            local targetServerId = serverList[math.random(1, #serverList)]  
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServerId, LP)  
        else  
            sendMessage("No other available servers found to hop to.")  
        end  
    else  
        sendMessage("Failed to retrieve server list (empty data).")  
    end  
end  

local function displayCommands()  
    local commandList_1 = [[  
.kill [user], .loop [user|all], .unloop [user|all]  
.aura [range], .aura whitelist [user], .aura unwhitelist [user]  
.to [user], .follow [user], .unfollow, .spin [user], .unspin, .spinspeed [val]  
]]  
    local commandList_2 = [[  
.safe, .unsafe, .safezone [user], .unsafezone  
.refresh, .reset, .shop, .join, .equip, .unequip, .fjump, .time [num]  
.spam, .unspam, .say [msg], .count, .ping, .test  
.play, .stop (for sword fight bot)  
.aura lp <name>, .aura unlp <name>, .aura listtargets, .aura clearall  
.aura autoequip, .aura simple [range]  
]]  
    sendMessage(commandList_1)  
    task.wait(0.5)  
    sendMessage(commandList_2)  
end  

-- ==================================  
-- ==      EVENT HANDLERS          ==  
-- ==================================  

local function onCharacterDied(humanoid)  
    local killerTag = humanoid:FindFirstChild("creator")  
    local killerName = "Unknown"  
    if killerTag and killerTag.Value then  
        killerName = killerTag.Value.Name  
    end  
    local payload = {  
        content = "Player " .. LP.Name .. " died. Killed by: " .. killerName,  
        username = "Death Notifier"  
    }  
    -- sendWebhook(payload)  
end  

local function onMessageReceived(messageData)  
    local text = messageData.Text  
    if not text or not messageData.TextSource then return end  
    local authorPlayer = Players:GetPlayerByUserId(messageData.TextSource.UserId)  
    if not authorPlayer then return end  

    local args = text:split(" ")  
    local command = args[1]:lower()  
    local arg2 = args[2] or nil  
    local arg3 = args[3] or nil  

    if command == "$" then  
        if not MainConnector then  
            MainConnector = authorPlayer  
            table.insert(ConnectedUsers, authorPlayer); table.insert(Whitelist, authorPlayer.Name)  
            sendMessage("!")  
        elseif authorPlayer == MainConnector and arg2 then  
            local targetPlayer = findPlayer(arg2)  
            if targetPlayer and not table.find(ConnectedUsers, targetPlayer) then  
                table.insert(ConnectedUsers, targetPlayer)  
                sendMessage("Connected With " .. targetPlayer.Name)  
            end  
        end  
        return  
    end  

    if authorPlayer ~= LP and not table.find(ConnectedUsers, authorPlayer) then return end  

    if command:sub(1,1) == "." then  
        if command == ".unconnect" and arg2 and authorPlayer == MainConnector then  
            local targetPlayer = findPlayer(arg2)  
            if targetPlayer and targetPlayer ~= MainConnector then  
                for i, user in ipairs(ConnectedUsers) do  
                    if user == targetPlayer then table.remove(ConnectedUsers, i); break end  
                end  
                sendMessage("Unconnected: " .. targetPlayer.Name)  
            end  
        elseif command == ".kill" and arg2 then  
            killOnce(arg2)  

        elseif command == ".loop" and arg2 then  
            if arg2:lower() == "all" then  
                for _, player in ipairs(PlayerList) do  
                    if player ~= LP and not table.find(Whitelist, player.Name) then  
                        addTarget(player.Name)  
                    end  
                end  
            else  
                addTarget(arg2)  
            end  

        elseif command == ".unloop" and arg2 then  
            if arg2:lower() == "all" then  
                table.clear(Targets)  
                forceEquip(AuraEnabled)  
            else  
                removeTarget(arg2)  
            end  

        elseif command == ".aura" then  
            -- Subcommands:  
            -- .aura [range]  
            -- .aura whitelist [user]  
            -- .aura unwhitelist [user]  
            -- .aura lp <name>  
            -- .aura unlp <name>  
            -- .aura listtargets  
            -- .aura clearall  
            -- .aura autoequip  
            -- .aura simple [range]  
            if arg2 == nil then  
                sendMessage("Usage: .aura [range] | .aura whitelist <user> | .aura unwhitelist <user> | .aura lp <name> | .aura unlp <name> | .aura listtargets | .aura clearall | .aura autoequip | .aura simple [range]")  
            else  
                local sub = arg2:lower()  
                if sub == "whitelist" and arg3 then  
                    local p = findPlayer(arg3); if p and not table.find(Whitelist, p.Name) then table.insert(Whitelist, p.Name); sendMessage("Whitelisted: "..p.Name) end  
                elseif sub == "unwhitelist" and arg3 then  
                    local p = findPlayer(arg3); if p then for i, n in ipairs(Whitelist) do if n == p.Name then table.remove(Whitelist, i); sendMessage("Unwhitelisted: "..p.Name); break end end end  

                elseif sub == "lp" and arg3 then  
                    local found = FindPlayers(arg3)  
                    local added = AddMultipleTargets(found)  
                    sendMessage("Added "..tostring(added).." target(s) to LP TargetList.")  
                elseif sub == "unlp" and arg3 then  
                    local found = FindPlayers(arg3)  
                    local removed = RemoveMultipleTargets(found)  
                    sendMessage("Removed "..tostring(removed).." target(s) from LP TargetList.")  
                elseif sub == "listtargets" then  
                    local names = {}  
                    for uid, _ in pairs(TargetList) do  
                        local plr = Players:GetPlayerByUserId(uid)  
                        if plr then table.insert(names, plr.Name) end  
                    end  
                    if #names == 0 then  
                        sendMessage("TargetList is empty.")  
                    else  
                        sendMessage("TargetList: " .. table.concat(names, ", "))  
                    end  
                elseif sub == "clearall" then  
                    TargetList = {}  
                    sendMessage("Cleared all LP targets.")  
                elseif sub == "autoequip" then  
                    if AutoEquipEnabled then  
                        StopAutoEquip()  
                        sendMessage("AutoEquip disabled.")  
                    else  
                        StartAutoEquip()  
                        sendMessage("AutoEquip enabled.")  
                    end  
                elseif sub == "simple" then  
                    local r = tonumber(arg3)  
                    if r and r > 0 then  
                        SimpleAuraRange = r  
                    end  
                    if SimpleAuraEnabled then  
                        StopSimpleAura()  
                        sendMessage("Simple Aura disabled.")  
                    else  
                        StartSimpleAura()  
                        sendMessage("Simple Aura enabled. Range = "..tostring(SimpleAuraRange))  
                    end  
                else  
                    -- default .aura [range] behavior  
                    setAura(arg2)  
                    sendMessage("Aura range set to "..tostring(Dist)..(AuraEnabled and " (enabled)" or " (disabled)"))  
                end  
            end  

        elseif command == ".spin" and arg2 then  
            local p = findPlayer(arg2)  
            if p then spinTarget = p; spinLoop() end  
        elseif command == ".unspin" then  
            stopSpinLoop()  
        elseif command == ".spinspeed" and arg2 then  
            local newSpeed = tonumber(arg2)  
            if newSpeed and newSpeed > 0 then  
                SPIN_SPEED = newSpeed  
                sendMessage("Spin speed set to " .. SPIN_SPEED)  
            end  
        elseif command == ".time" and arg2 then  
            changeTime(arg2)  
        elseif command == ".ping" then  
            local ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())  
            sendMessage("ping: " .. ping .. "ms")  
        elseif command == ".fps" then  
            local renderSteppedConnection = nil  
            local frameCount = 0  
            local startTime = tick()  
            local duration = 1  
            renderSteppedConnection = RunService.RenderStepped:Connect(function()  
                frameCount = frameCount + 1  
                if tick() - startTime >= duration then  
                    local fps = frameCount / duration  
                    sendMessage("FPS: " .. math.floor(fps))  
                    renderSteppedConnection:Disconnect()  
                    renderSteppedConnection = nil  
                end  
            end)  
        elseif command == ".reset" then  
            if #Players:GetPlayers() >= Players.MaxPlayers then  
                sendMessage("Won't rejoin, server is full.")  
            else  
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)  
            end  
        elseif command == ".shop" then  
            serverHop()  
        elseif command == ".join" then  
            local targetPlaceId = 6110766473  
            pcall(function()  
                TeleportService:Teleport(targetPlaceId, LP)  
            end)  
            sendMessage("Joining ⚔️ Flex Fight ⚔️")  
        elseif command == ".refresh" then  
            if LP.Character and LP.Character.PrimaryPart then  
                DeathPositions[LP.Name] = LP.Character.PrimaryPart.CFrame  
                if LP.Character.Humanoid then LP.Character.Humanoid.Health = 0 end  
            end  
        elseif command == ".to" and arg2 then  
            local targetPlayer = findPlayer(arg2)  
            if targetPlayer and targetPlayer.Character and targetPlayer.Character.PrimaryPart and LP.Character then  
                teleportTo(LP.Character, targetPlayer.Character.PrimaryPart.Position)  
            end  
        elseif command == ".follow" and arg2 then  
            stopSafeZoneLoop()  
            local targetPlayer = findPlayer(arg2)  
            if targetPlayer then FollowTarget = targetPlayer else FollowTarget = nil end  
        elseif command == ".unfollow" then  
            FollowTarget = nil  
            stopSafeZoneLoop()  
        elseif command == ".cmds" then  
            displayCommands()  
        elseif command == ".count" then  
            local playerCount = #Players:GetPlayers()  
            local maxPlayers = Players.MaxPlayers  
            sendMessage(playerCount .. "/" .. maxPlayers .. " players")  
        elseif command == ".equip" then  
            if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then  
                local tool = LP.Backpack:FindFirstChildWhichIsA("Tool")  
                if tool then LP.Character.Humanoid:EquipTool(tool) end  
            end  
        elseif command == ".unequip" then  
            if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then  
                local tool = LP.Character:FindFirstChildWhichIsA("Tool")  
                if tool then tool.Parent = LP.Backpack end  
            end  
        elseif command == ".fjump" then  
            frogJump()  
        elseif command == ".spam" then  
            SpammingEnabled = true  
        elseif command == ".unspam" then  
            SpammingEnabled = false  
        elseif command == ".say" and arg2 then  
            table.remove(args, 1)  
            local message = table.concat(args, " ")  
            sendMessage(message)  
        elseif command == ".safe" then  
            teleportTo(LP.Character, SAFE_PLATFORM_POS + Vector3.new(0, 5, 0))  
        elseif command == ".unsafe" then  
            if MainConnector and MainConnector.Character and MainConnector.Character.PrimaryPart and LP.Character then  
                teleportTo(LP.Character, MainConnector.Character.PrimaryPart.Position + Vector3.new(0, 5, 0))  
            else  
                local spawns = Workspace:FindFirstChild("Spawns") or Workspace:FindFirstChild("SpawnLocation")  
                if spawns and LP.Character then  
                    local spawnPoint = spawns:IsA("SpawnLocation") and spawns or spawns:GetChildren()[1]  
                    if spawnPoint then  
                        teleportTo(LP.Character, spawnPoint.Position + Vector3.new(0, 5, 0))  
                    else  
                        if LP.Character.Humanoid then LP.Character.Humanoid.Health = 0 end  
                    end  
                else  
                    if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then LP.Character.Humanoid.Health = 0 end  
                end  
            end  
        elseif command == ".fight" then  
            teleportTo(LP.Character, FIGHT_PLATFORM_POS + Vector3.new(0, 5, 0))  
        elseif command == ".safezone" and arg2 then  
            local targetPlayer = findPlayer(arg2)  
            if not (targetPlayer and LP.Character and LP.Character.PrimaryPart) then return end  
            stopSafeZoneLoop()  
            FollowTarget = targetPlayer  

            safeZonePlatform = Instance.new("Part", Workspace)  
            safeZonePlatform.Name = "SafeZonePlatform"  
            safeZonePlatform.Size = Vector3.new(12, 2, 12)  
            safeZonePlatform.Transparency = 0.5  
            safeZonePlatform.Anchored = true  
            safeZonePlatform.CanCollide = true  

            safeZoneConnection = RunService.Heartbeat:Connect(function()  
                if not (FollowTarget and FollowTarget.Character and FollowTarget.Character.PrimaryPart and LP.Character and LP.Character.PrimaryPart and safeZonePlatform and safeZonePlatform.Parent) then  
                    sendMessage("Safezone target or self lost. Disabling.")  
                    stopSafeZoneLoop()  
                    return  
                end  

                local targetPos = FollowTarget.Character.PrimaryPart.Position  
                local platformNewPos = targetPos + SAFE_ZONE_OFFSET  
                safeZonePlatform.Position = platformNewPos  

                local myHRP = LP.Character.PrimaryPart  
                local myNewPos = platformNewPos + Vector3.new(0, (safeZonePlatform.Size.Y / 2) + (myHRP.Size.Y / 2), 0)  
                teleportTo(LP.Character, CFrame.new(myNewPos) * (myHRP.CFrame - myHRP.CFrame.Position))  
            end)  
        elseif command == ".unsafezone" then  
            stopSafeZoneLoop()  
        elseif command == ".log" then  
            if LP.Character then  
                sendMessage("Attempting to force disconnect...")  
                game:GetService("TeleportService"):Teleport(0)  
            else  
                sendMessage("Cannot force disconnect: Character not found.")  
            end  
        elseif command == ".test" then  
            pcall(function()  
                loadstring(game:HttpGet('https://raw.githubusercontent.com/JarcoCZ/Control-Script/refs/heads/main/test.lua'))()  
            end)  
        elseif command == ".play" then  
            getgenv().Daddy_Catches_You = true  
            sendMessage("Sword fight bot enabled!")  
        elseif command == ".stop" then  
            getgenv().Daddy_Catches_You = false  
            sendMessage("Sword fight bot disabled.")  
        else  
            sendMessage("Command " .. command .. " doesn't exist!")  
        end  
    end  
end  

local function onCharacterAdded(char)  
    stopSafeZoneLoop()  
    local humanoid = char:WaitForChild("Humanoid", 10)  
    if humanoid then  
        humanoid.Died:Connect(function()  
            onCharacterDied(humanoid)  
        end)  
    end  

    local player = Players:GetPlayerFromCharacter(char)  

    for _, item in ipairs(char:GetChildren()) do createReachPart(item) end  
    char.ChildAdded:Connect(createReachPart)  

    if #Targets > 0 or AuraEnabled then forceEquip(true) end  

    if not HeartbeatConnection or not HeartbeatConnection.Connected then  
        HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)  
    end  
end  

-- ==================================  
-- ==      INITIALIZATION          ==  
-- ==================================  

-- Add auto-whitelisted users to the Whitelist table  
for _, username in ipairs(AutoWhitelistUsers) do  
    if not table.find(Whitelist, username) then  
        table.insert(Whitelist, username)  
    end  
end  

-- Create the safe platform at initialization  
safePlatform = Instance.new("Part", Workspace)  
safePlatform.Name = "SafePlatform"  
safePlatform.Size = Vector3.new(50, 2, 50)  
safePlatform.Position = SAFE_PLATFORM_POS  
safePlatform.Anchored = true  
safePlatform.CanCollide = true  

-- Create the fight platform at initialization  
fightPlatform = Instance.new("Part", Workspace)  
fightPlatform.Name = "FightPlatform"  
fightPlatform.Size = Vector3.new(15, 2, 15)  
fightPlatform.Position = FIGHT_PLATFORM_POS  
fightPlatform.Anchored = true  
fightPlatform.CanCollide = true  

task.spawn(function()  
    ChangeTimeEvent = ReplicatedStorage:WaitForChild("ChangeTime", 30)  
end)  

for _, player in ipairs(Players:GetPlayers()) do table.insert(PlayerList, player) end  

Players.PlayerAdded:Connect(function(player)  
    table.insert(PlayerList, player)  
    player.CharacterAdded:Connect(onCharacterAdded)  
end)  

Players.PlayerRemoving:Connect(function(p)  
    if p.Character and p.Character:FindFirstChildOfClass("Humanoid") then  
        PlayersAboutToRespawn[p.Name] = true  
    end  

    if spinTarget and spinTarget == p then stopSpinLoop() end  
    removeTarget(p.Name)  
    for i, pl in ipairs(PlayerList) do if pl == p then table.remove(PlayerList, i); break end end  
    for i, u in ipairs(ConnectedUsers) do if u == p then table.remove(ConnectedUsers, i); break end end  
    if FollowTarget and p == FollowTarget then stopSafeZoneLoop() end  
    if MainConnector == p then  
        MainConnector = nil; table.clear(ConnectedUsers); table.clear(Whitelist)  
        sendMessage("Main Connector has left. Connection reset.")  
    end  
end)  

TextChatService.MessageReceived:Connect(onMessageReceived)  

if LP.Character then  
    onCharacterAdded(LP.Character)  
end  
LP.CharacterAdded:Connect(onCharacterAdded)  

-- Initial teleport to safe platform on script execution  
task.spawn(function()  
    if LP.Character then  
        teleportTo(LP.Character, SAFE_PLATFORM_POS + Vector3.new(0, 5, 0))  
    else  
        LP.CharacterAdded:Wait()  
        teleportTo(LP.Character, SAFE_PLATFORM_POS + Vector3.new(0, 5, 0))  
    end  
end)  

sendMessage("FLOXY SCRIPT ADDED")
