--[[  
    Floxy Script - Fully Corrected & Stabilized by luxx (v64 - Connection Fixes)  

    UPDATES (v64 - Connection Fixes):  
    - FIXED: The `@ [username]` command logic has been completely overhauled to work correctly and reliably.  
    - ADDED: Chat feedback messages are now sent to confirm when a user is successfully connected or disconnected.  
    - ADDED: A notification is now sent when the Main Connector leaves, resetting the connection for all users.  
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
local AwaitingRejoinConfirmation = false  

-- Pre-loaded Instances  
local ChangeTimeEvent = nil  

-- Configuration  
local Dist = 0  
local AuraEnabled = false  
local AuraVisible = false  
local DMG_TIMES = 2  
local FT_TIMES = 5  
local SPIN_RADIUS = 7  
local SPIN_SPEED = 10  
local SPIN_HEIGHT_OFFSET = 5  
local SAFE_PLATFORM_POS = Vector3.new(0, 10000, 0)  
local SAFE_ZONE_OFFSET = Vector3.new(0, 15, 0)  
local FROG_JUMP_HEIGHT = 10  
local FROG_JUMP_PREP_DIST = 3  
local WEBHOOK_URL = "https://discord.com/api/webhooks/1405285885678845963/KlBVzcpGVzyDygqUqghaSxJaL6OSj4IQ5ZIHQn8bbSu7a_O96DZUL2PynS47TAc0Pz22"  

-- Authorization  
local AuthorizedUsers = { 1588706905, 9167607498, 7569689472 }  

-- ==================================  
-- ==      HELPER FUNCTIONS        ==  
-- ==================================  

local function isAuthorized(userId)  
    for _, id in ipairs(AuthorizedUsers) do if userId == id then return true end end  
    return false  
end  

if not isAuthorized(LP.UserId) then  
    warn("Floxy Script: User not authorized. Halting execution.")  
    return  
end  

local function sendWebhook(payload)  
    pcall(function()  
        HttpService:PostAsync(WEBHOOK_URL, HttpService:JSONEncode(payload))  
    end)  
end  

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

local function teleportTo(character, destination)  
    if character and character.PrimaryPart then  
        if typeof(destination) == "CFrame" then  
            character:SetPrimaryPartCFrame(destination)  
        elseif typeof(destination) == "Vector3" then  
            character:SetPrimaryPartCFrame(CFrame.new(destination))  
        end  
    end  
end  

-- ==================================  
-- ==      TOOL & COMBAT LOGIC     ==  
-- ==================================  

local function createReachPart(tool)  
    if tool:IsA("Tool") and tool:FindFirstChild("Handle") then  
        local handle = tool.Handle  
        if not handle:FindFirstChild("BoxReachPart") then  
            local p = Instance.new("Part", handle)  
            p.Name = "BoxReachPart"; p.Size = Vector3.new(Dist, Dist, Dist)  
            p.Transparency = AuraVisible and 0.7 or 1  
            p.CanCollide = false; p.Massless = true  
            local w = Instance.new("WeldConstraint", p)  
            w.Part0, w.Part1 = handle, p  
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
            local targetChar = player.Character; local myChar = LP.Character  
            local tool = toolPart.Parent  
            if not (targetChar and targetChar:FindFirstChildOfClass("Humanoid") and targetChar.Humanoid.Health > 0 and myChar and tool and tool.Parent == myChar) then  
                break  
            end  
            for _, part in ipairs(targetChar:GetDescendants()) do  
                if part:IsA("BasePart") then fireTouch(toolPart, part) end  
            end  
            task.wait()  
        end  
        KillStates[player] = nil  
    end)  
end  

local function attackPlayer(toolPart, player)  
    local targetChar = player.Character  
    if not (targetChar and targetChar:FindFirstChildOfClass("Humanoid") and targetChar.Humanoid.Health > 0) then return end  
    pcall(function() toolPart.Parent:Activate() end)  
    for _ = 1, DMG_TIMES do  
        for _, part in ipairs(targetChar:GetDescendants()) do  
            if part:IsA("BasePart") then fireTouch(toolPart, part) end  
        end  
    end  
    killLoop(player, toolPart)  
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

    for _, tool in ipairs(LP.Character:GetDescendants()) do  
        if tool:IsA("Tool") then  
            local hitbox = tool:FindFirstChild("BoxReachPart") or tool:FindFirstChild("Handle")  
            if hitbox then  
                for _, player in ipairs(PlayerList) do  
                    if player ~= LP and player.Character and player.Character.PrimaryPart and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 then  
                        if not table.find(Whitelist, player.Name) then  
                            local isTargeted = table.find(Targets, player.Name)  
                            local inAuraRange = AuraEnabled and (player.Character.PrimaryPart.Position - myPos).Magnitude <= Dist  
                            if isTargeted or inAuraRange then  
                                attackPlayer(hitbox, player)  
                            end  
                        end  
                    end  
                end  
            end  
        end  
    end  
end  

-- ==================================  
-- ==      COMMANDS & CONTROLS     ==  
-- ==================================  

local function setAuraVisibility(visible)  
    AuraVisible = visible  
    local transparency = visible and 0.7 or 1  
    if LP.Character then  
        local tool = LP.Character:FindFirstChildOfClass("Tool")  
        if tool then  
            local hitbox = tool:FindFirstChild("BoxReachPart")  
            if hitbox then  
                hitbox.Transparency = transparency  
            end  
        end  
    end  
    sendMessage("Aura visibility set to " .. (visible and "ON" or "OFF"))  
end  

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
    task.wait(0.05)  
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
            ForceEquipConnection = RunService.RenderStepped:Connect(function()  
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
        table.insert(Targets, player.Name); forceEquip(true)  
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
            local tool = LP.Character:FindFirstWhichIsA("Tool")  
            if tool then  
                local reachPart = tool:FindFirstChild("BoxReachPart")  
                if reachPart then  
                    reachPart.Size = Vector3.new(Dist, Dist, Dist)  
                else  
                    createReachPart(tool)  
                end  
            end  
        end  
    end  
end  

local function serverHop()  
    local servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))  
    if servers and servers.data then  
        local serverList = {}  
        for _, server in ipairs(servers.data) do  
            if type(server) == "table" and server.id ~= game.JobId and server.playing < server.maxPlayers then  
                table.insert(serverList, server.id)  
            end  
        end  
        if #serverList > 0 then  
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverList[math.random(1, #serverList)], LP)  
        end  
    end  
end  

local function displayCommands()  
    local commandList_1 = [[  
@ [user], .unconnect [user]  
.kill [user], .loop [user|all], .unloop [user|all]  
.aura [range|off], .aura [see|unsee], .aura whitelist [user], .aura unwhitelist [user]  
.to [user], .follow [user], .unfollow, .spin [user], .unspin, .spinspeed [val]  
]]  
    local commandList_2 = [[  
.safe, .unsafe, .safezone [user], .unsafezone  
.refresh, .reset, .shop, .equip, .unequip, .fjump, .time [num]  
.spam, .unspam, .say [msg], .count, .ping, .test  
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
    sendWebhook(payload)  
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

    if AwaitingRejoinConfirmation and authorPlayer == LP then  
        if command == "y" then  
            AwaitingRejoinConfirmation = false  
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)  
            return  
        elseif command == "n" then  
            AwaitingRejoinConfirmation = false  
            sendMessage("Rejoin Rejected!")  
            return  
        end  
    end  

    if command:sub(1,1) == "@" then  
        local username = arg2 or command:sub(2)  
        if not MainConnector then MainConnector = authorPlayer end  
        
        if authorPlayer == MainConnector then  
            local targetPlayer = findPlayer(username)  
            if targetPlayer and not table.find(ConnectedUsers, targetPlayer) then  
                table.insert(ConnectedUsers, targetPlayer)  
                table.insert(Whitelist, targetPlayer.Name)  
                sendMessage("Connected with " .. targetPlayer.Name)  
            end  
        end  
        return  
    end  

    if authorPlayer ~= LP and not table.find(ConnectedUsers, authorPlayer) then return end  

    if command == ".unconnect" and arg2 and authorPlayer == MainConnector then  
        local targetPlayer = findPlayer(arg2)  
        if targetPlayer and targetPlayer ~= MainConnector then  
            for i, user in ipairs(ConnectedUsers) do if user == targetPlayer then table.remove(ConnectedUsers, i); break end end  
            for i, name in ipairs(Whitelist) do if name == targetPlayer.Name then table.remove(Whitelist, i); break end end  
            sendMessage("Unconnected: " .. targetPlayer.Name)  
        end  
    elseif command == ".kill" and arg2 then killOnce(arg2)  
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
    elseif command == ".aura" and arg2 then  
        if arg2:lower() == "off" then  
            setAura(0)  
        elseif arg2:lower() == "see" then  
            setAuraVisibility(true)  
        elseif arg2:lower() == "unsee" then  
            setAuraVisibility(false)  
        elseif arg2:lower() == "whitelist" and arg3 then  
            local p = findPlayer(arg3); if p and not table.find(Whitelist, p.Name) then table.insert(Whitelist, p.Name) end  
        elseif arg2:lower() == "unwhitelist" and arg3 then  
            local p = findPlayer(arg3); if p then for i, n in ipairs(Whitelist) do if n == p.Name then table.remove(Whitelist, i); break end end end  
        else setAura(arg2) end  
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
    elseif command == ".reset" then  
        if #Players:GetPlayers() >= Players.MaxPlayers then  
            sendMessage("Wanna rejoin? Y/N")  
            AwaitingRejoinConfirmation = true  
        else  
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)  
        end  
    elseif command == ".shop" and authorPlayer == LP then  
        serverHop()  
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
        if not safePlatform or not safePlatform.Parent then  
            safePlatform = Instance.new("Part", Workspace)  
            safePlatform.Name = "SafePlatform"  
            safePlatform.Size = Vector3.new(50, 2, 50)  
            safePlatform.Position = SAFE_PLATFORM_POS  
            safePlatform.Anchored = true  
            safePlatform.CanCollide = true  
        end  
        teleportTo(LP.Character, SAFE_PLATFORM_POS + Vector3.new(0, 5, 0))  
    elseif command == ".unsafe" then  
        if safePlatform and safePlatform.Parent then  
            safePlatform:Destroy()  
            safePlatform = nil  
        end  
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
    elseif command == ".test" then  
        pcall(function()  
            loadstring(game:HttpGet('https://raw.githubusercontent.com/JarcoCZ/Control-Script/refs/heads/main/test.lua'))()  
        end)  
    end  
end  

local function onCharacterAdded(char)  
    stopSafeZoneLoop()  
    local humanoid = char:WaitForChild("Humanoid", 10)  
    if humanoid then  
        humanoid.Died:Connect(function() onCharacterDied(humanoid) end)  
    end  
    
    for _, item in ipairs(char:GetChildren()) do createReachPart(item) end  
    char.ChildAdded:Connect(createReachPart)  
    
    if #Targets > 0 or AuraEnabled then forceEquip(true) end  
    
    if DeathPositions[LP.Name] then  
        local hrp = char:WaitForChild("HumanoidRootPart", 10)  
        if hrp then task.wait(0.5); hrp.CFrame = DeathPositions[LP.Name]; DeathPositions[LP.Name] = nil end  
    end  
    
    if not HeartbeatConnection or not HeartbeatConnection.Connected then  
        HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)  
    end  
end  

-- ==================================  
-- ==      INITIALIZATION          ==  
-- ==================================  

task.spawn(function()  
    ChangeTimeEvent = ReplicatedStorage:WaitForChild("ChangeTime", 30)  
    if ChangeTimeEvent then  
        print("Floxy System: ChangeTime event successfully located.")  
    else  
        warn("Floxy System: ChangeTime event could not be located after 30s.")  
    end  
end)  

for _, player in ipairs(Players:GetPlayers()) do table.insert(PlayerList, player) end  
table.insert(ConnectedUsers, LP); table.insert(Whitelist, LP.Name)  

LP.CharacterAdded:Connect(onCharacterAdded)  
if LP.Character then onCharacterAdded(LP.Character) end  

Players.PlayerAdded:Connect(function(p) table.insert(PlayerList, p) end)  
Players.PlayerRemoving:Connect(function(p)  
    if spinTarget and spinTarget == p then stopSpinLoop() end  
    removeTarget(p.Name)  
    for i, pl in ipairs(PlayerList) do if pl == p then table.remove(PlayerList, i); break end end  
    for i, u in ipairs(ConnectedUsers) do if u == p then table.remove(ConnectedUsers, i); break end end  
    if FollowTarget and p == FollowTarget then stopSafeZoneLoop() end  
    if MainConnector == p then  
        MainConnector = nil; table.clear(ConnectedUsers); table.clear(Whitelist)  
        table.insert(ConnectedUsers, LP); table.insert(Whitelist, LP.Name)  
        sendMessage("Main Connector has left. Connection reset.")  
    end  
    if safePlatform and #Players:GetPlayers() == 1 then  
        pcall(function() safePlatform:Destroy() end)  
    end  
end)  
TextChatService.MessageReceived:Connect(onMessageReceived)  

sendMessage("Script Executed - Floxy (Fixed by luxx v64)")  
print("Floxy System Loaded. User Authorized.")
