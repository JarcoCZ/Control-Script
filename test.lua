--[[  
    Floxy Script - Fully Corrected & Stabilized by luxx (v34)  

    UPDATES (v34):  
    - Added `.kill [user]` command. This command will loop-attack a player until they die, then automatically unloop them.  
    - Modified `.unsafe` to teleport the player to the MainConnector's position after removing the platform.  
    - Added `.unsafezone` command to stop the safezone loop.  
    - Modified `.safezone` to be a loop, continuously teleporting the player above the target.  
    - Modified `.safe` command to continuously teleport the player upwards.  
]]  

-- Services  
local Players = game:GetService("Players")  
local RunService = game:GetService("RunService")  
local TextChatService = game:GetService("TextChatService")  
local TeleportService = game:GetService("TeleportService")  
local HttpService = game:GetService("HttpService")  
local Workspace = game:GetService("Workspace")  

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
local safePlatform = nil -- Variable to hold our safe platform  
local safeTeleportConnection = nil -- Connection for the safe teleport loop  
local safeZoneConnection = nil -- Connection for the safe zone loop  

-- Configuration  
local Dist = 0  
local AuraEnabled = false  
local DMG_TIMES = 2  
local FT_TIMES = 5  
local SAFE_PLATFORM_POS = Vector3.new(0, 10000, 0) -- High up in the sky  
local SAFE_ZONE_OFFSET = Vector3.new(0, 20, 0) -- Offset for the safezone command  

-- Authorization  
local AuthorizedUsers = { 1588706905, 9167607498, 7569689472 }  

-- ==================================  
-- ==      HELPER FUNCTIONS        ==  
-- ==================================  

local function isAuthorized(userId)  
    for _, id in ipairs(AuthorizedUsers) do  
        if userId == id then  
            return true  
        end  
    end  
    return false  
end  

if not isAuthorized(LP.UserId) then  
    warn("Floxy Script: User not authorized. Halting execution.")  
    return  
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

local function teleportTo(character, position)  
    if character and character:FindFirstChild("HumanoidRootPart") then  
        character.HumanoidRootPart.CFrame = CFrame.new(position)  
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
            p.Transparency = 1; p.CanCollide = false; p.Massless = true  
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
    if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then return end  
    local myPos = LP.Character.HumanoidRootPart.Position  
    local myHumanoid = LP.Character:FindFirstChildOfClass("Humanoid")  

    if FollowTarget and FollowTarget.Character and FollowTarget.Character:FindFirstChild("HumanoidRootPart") and myHumanoid then  
        local targetPos = FollowTarget.Character.HumanoidRootPart.Position  
        if (targetPos - myPos).Magnitude > 5 then  
            myHumanoid:MoveTo(targetPos)  
        end  
    end  
    
    if SpammingEnabled then  
        local tool = LP.Character:FindFirstChildOfClass("Tool")  
        if tool then  
            pcall(function() tool:Activate() end)  
        end  
    end  

    for _, tool in ipairs(LP.Character:GetDescendants()) do  
        if tool:IsA("Tool") then  
            local hitbox = tool:FindFirstChild("BoxReachPart") or tool:FindFirstChild("Handle")  
            if hitbox then  
                for _, player in ipairs(PlayerList) do  
                    if player ~= LP and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 then  
                        if not table.find(Whitelist, player.Name) then  
                            local isTargeted = table.find(Targets, player.Name)  
                            local inAuraRange = AuraEnabled and (player.Character.HumanoidRootPart.Position - myPos).Magnitude <= Dist  
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

local function stopSafeZoneLoop()  
    if safeZoneConnection and safeZoneConnection.Connected then  
        safeZoneConnection:Disconnect()  
        safeZoneConnection = nil  
    end  
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
    if player and not table.find(Targets, player.Name) then  
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
        sendMessage("Target " .. playerName .. " eliminated. Unlooping.")  
        removeTarget(playerName)  
        if connection then connection:Disconnect() end  
    end)  
end  

local function setAura(range)  
    local newRange = tonumber(range)  
    if newRange and newRange >= 0 then  
        Dist = newRange  
        AuraEnabled = newRange > 0  
        forceEquip(AuraEnabled or #Targets > 0)  
        
        if LP.Character then  
            for _, tool in ipairs(LP.Character:GetDescendants()) do  
                if tool:IsA("Tool") and tool:FindFirstChild("BoxReachPart") then  
                    tool.BoxReachPart.Size = Vector3.new(Dist, Dist, Dist)  
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
.kill [user], .loop [user], .unloop [user]  
.aura [range], .aura whitelist [user], .aura unwhitelist [user]  
.to [user], .follow [user], .unfollow  
]]  
    local commandList_2 = [[  
.safe, .unsafe, .safezone [user], .unsafezone  
.refresh, .reset, .equip, .unequip  
.shop (hops server)  
.spam, .unspam, .say [msg]  
]]  
    sendMessage(commandList_1)  
    task.wait(0.5)  
    sendMessage(commandList_2)  
end  

-- ==================================  
-- ==      EVENT HANDLERS          ==  
-- ==================================  

local function onMessageReceived(messageData)  
    local text = messageData.Text  
    if not text or not messageData.TextSource then return end  
    
    local authorPlayer = Players:GetPlayerByUserId(messageData.TextSource.UserId)  
    if not authorPlayer then return end  

    local args = text:split(" ")  
    local command = args[1]:lower()  
    local arg2 = args[2] or nil  
    local arg3 = args[3] or nil  

    if command == "test" then  
        if not MainConnector then  
            MainConnector = authorPlayer  
            table.insert(ConnectedUsers, authorPlayer); table.insert(Whitelist, authorPlayer.Name)  
            sendMessage("Connected With " .. authorPlayer.Name)  
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

    if command == ".unconnect" and authorPlayer == MainConnector and arg2 then  
        local targetPlayer = findPlayer(arg2)  
        if targetPlayer and targetPlayer ~= MainConnector then  
            for i, user in ipairs(ConnectedUsers) do  
                if user == targetPlayer then table.remove(ConnectedUsers, i); break end  
            end  
            sendMessage("Unconnected: " .. targetPlayer.Name)  
        end  
    elseif command == ".kill" and arg2 then killOnce(arg2)  
    elseif command == ".loop" and arg2 then addTarget(arg2)  
    elseif command == ".unloop" and arg2 then removeTarget(arg2)  
    elseif command == ".aura" and arg2 then  
        if arg2:lower() == "whitelist" and arg3 then  
            local p = findPlayer(arg3); if p and not table.find(Whitelist, p.Name) then table.insert(Whitelist, p.Name) end  
        elseif arg2:lower() == "unwhitelist" and arg3 then  
            local p = findPlayer(arg3); if p then for i, n in ipairs(Whitelist) do if n == p.Name then table.remove(Whitelist, i); break end end end  
        else setAura(arg2) end  
    elseif command == ".reset" then  
        TeleportService:Teleport(game.PlaceId, LP)  
    elseif command == ".shop" and authorPlayer == LP then  
        serverHop()  
    elseif command == ".refresh" then  
        if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then  
            DeathPositions[LP.Name] = LP.Character.HumanoidRootPart.CFrame  
            LP.Character.Humanoid.Health = 0  
        end  
    elseif command == ".to" and arg2 then  
        local targetPlayer = findPlayer(arg2)  
        if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then  
            teleportTo(LP.Character, targetPlayer.Character.HumanoidRootPart.Position)  
        end  
    elseif command == ".follow" and arg2 then  
        local targetPlayer = findPlayer(arg2)  
        if targetPlayer then FollowTarget = targetPlayer else FollowTarget = nil end  
    elseif command == ".unfollow" then  
        FollowTarget = nil  
        stopSafeZoneLoop()  
    elseif command == ".cmds" then  
        displayCommands()  
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
        if not safeTeleportConnection or not safeTeleportConnection.Connected then  
            safeTeleportConnection = RunService.Heartbeat:Connect(function()  
                if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and safePlatform and safePlatform.Parent then  
                    teleportTo(LP.Character, LP.Character.HumanoidRootPart.Position + Vector3.new(0, 1, 0))  
                end  
            end)  
        end  
    elseif command == ".unsafe" then  
        if safeTeleportConnection and safeTeleportConnection.Connected then  
            safeTeleportConnection:Disconnect()  
            safeTeleportConnection = nil  
        end  
        if safePlatform and safePlatform.Parent then  
            safePlatform:Destroy()  
            safePlatform = nil  
        end  
        if MainConnector and MainConnector.Character and MainConnector.Character:FindFirstChild("HumanoidRootPart") and LP.Character then  
            teleportTo(LP.Character, MainConnector.Character.HumanoidRootPart.Position + Vector3.new(0, 5, 0))  
        else  
            local spawns = Workspace:FindFirstChild("Spawns") or Workspace:FindFirstChild("SpawnLocation")  
            if spawns and LP.Character then  
                local spawnPoint = spawns:IsA("SpawnLocation") and spawns or spawns:GetChildren()[1]  
                if spawnPoint then  
                    teleportTo(LP.Character, spawnPoint.Position + Vector3.new(0, 5, 0))  
                else   
                     LP.Character.Humanoid.Health = 0  
                end  
            else  
                if LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") then LP.Character.Humanoid.Health = 0 end  
            end  
        end  
    elseif command == ".safezone" and arg2 then  
        local targetPlayer = findPlayer(arg2)  
        if not targetPlayer then return end  

        stopSafeZoneLoop() -- Stop any previous loop  

        safeZoneConnection = RunService.Heartbeat:Connect(function()  
            if not LP.Character or not LP.Character:FindFirstChild("HumanoidRootPart") then stopSafeZoneLoop(); return end  
            if not targetPlayer or not targetPlayer.Parent or not targetPlayer.Character or not targetPlayer.Character:FindFirstChild("HumanoidRootPart") then  
                sendMessage("Safezone target lost. Disabling.")  
                stopSafeZoneLoop()  
                return  
            end  
            local targetPos = targetPlayer.Character.HumanoidRootPart.Position  
            teleportTo(LP.Character, targetPos + SAFE_ZONE_OFFSET)  
        end)  
    elseif command == ".unsafezone" then  
        stopSafeZoneLoop()  
    end  
end  

local function onCharacterAdded(char)  
    char:WaitForChild("Humanoid", 10)  
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

for _, player in ipairs(Players:GetPlayers()) do table.insert(PlayerList, player) end  

LP.CharacterAdded:Connect(onCharacterAdded)  
if LP.Character then onCharacterAdded(LP.Character) end  

Players.PlayerAdded:Connect(function(p) table.insert(PlayerList, p) end)  
Players.PlayerRemoving:Connect(function(p)  
    removeTarget(p.Name) -- Also remove them from targets if they leave  
    for i, pl in ipairs(PlayerList) do if pl == p then table.remove(PlayerList, i); break end end  
    for i, u in ipairs(ConnectedUsers) do if u == p then table.remove(ConnectedUsers, i); break end end  
    if p == FollowTarget then FollowTarget = nil; stopSafeZoneLoop() end  
    if MainConnector == p then  
        MainConnector = nil; table.clear(ConnectedUsers); table.clear(Whitelist)  
        sendMessage("Main Connector has left. Connection reset.")  
    end  
    if safePlatform and #Players:GetPlayers() == 1 then -- cleanup platform if server is empty  
        safePlatform:Destroy()  
    end  
end)  
TextChatService.MessageReceived:Connect(onMessageReceived)  

sendMessage("Script Executed - Floxy (Fixed by luxx v34)")  
print("Floxy System Loaded. User Authorized.")
