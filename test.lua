-- =========================================================================================  
-- ||                                                                                     ||  
-- ||                             COMPLETE CONTROL SCRIPT                                 ||  
-- ||                                                                                     ||  
-- =========================================================================================  
-- This script provides a comprehensive suite of commands for controlling a player,  
-- including movement, combat, server utilities, and automated actions via event handlers.  

-- // Services and Core Components  
local Players = game:GetService("Players")  
local RunService = game:GetService("RunService")  
local TeleportService = game:GetService("TeleportService")  
local Stats = game:GetService("Stats")  
local Workspace = game:GetService("Workspace")  
local LP = Players.LocalPlayer  

-- // Configuration & State Management  
local Targets = {}  
local Whitelist = {}  
local ConnectedUsers = {}  
local DeathPositions = {}  
local MainConnector = nil  
local FollowTarget = nil  
local SpinTarget = nil  
local safePlatform = nil  
local safeZonePlatform = nil  

local AURA_RANGE = 70  
local SPIN_SPEED = 20  
local SAFE_ZONE_OFFSET = Vector3.new(0, 15, 0)  
local SAFE_PLATFORM_POS = Vector3.new(0, 100, 0)  

local AuraEnabled = false  
local SpammingEnabled = false  
local AwaitingRejoinConfirmation = false  

local CombatLoopConnection = nil  
local HeartbeatConnection = nil  
local safeZoneConnection = nil  
local spinConnection = nil  

-- ==================================  
-- ==     UTILITY FUNCTIONS        ==  
-- ==================================  
-- Helper functions used by various commands and systems.  

local function sendMessage(message)  
    -- This is a placeholder for your chat/notification system.  
    -- Example: game.ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(message, "All")  
    print("SCRIPT MESSAGE: " .. tostring(message))  
end  

local function findPlayer(playerName)  
    if not playerName then return nil end  
    local lowerPlayerName = playerName:lower()  
    if lowerPlayerName == "me" then return LP end  
    for _, player in ipairs(Players:GetPlayers()) do  
        if player.Name:lower():match("^" .. lowerPlayerName) then  
            return player  
        end  
    end  
    return nil  
end  

local function teleportTo(character, destination)  
    if character and character:FindFirstChild("HumanoidRootPart") then  
        character.HumanoidRootPart.CFrame = CFrame.new(destination)  
    end  
end  

-- ==================================  
-- ==     EVENT HANDLERS           ==  
-- ==================================  
-- This section handles all game events, like players spawning, dying, or chatting.  

-- A utility function to perform a single, direct attack on a target.  
local function manualAttack(targetPlayer)  
    local character = LP.Character  
    local targetCharacter = targetPlayer.Character  
    if not (character and targetCharacter) then return end  

    local tool = character:FindFirstChildWhichIsA("Tool")  
    if not (tool and tool:FindFirstChild("Handle")) then  
        local backpackTool = LP.Backpack:FindFirstChildWhichIsA("Tool")  
        if backpackTool then  
            backpackTool.Parent = character  
            task.wait(0.2)  
            tool = backpackTool  
        else  
            sendMessage("Auto-attack failed: No tool to equip.")  
            return  
        end  
    end  
    
    local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")  
    if not (targetHumanoid and targetHumanoid.Health > 0) then return end  
    if typeof(firetouchinterest) ~= "function" then return end  

    pcall(function() tool:Activate() end)  
    for _ = 1, 5 do  
        for _, part in ipairs(targetCharacter:GetDescendants()) do  
            if part:IsA("BasePart") then  
                firetouchinterest(tool.Handle, part, 0)  
                firetouchinterest(tool.Handle, part, 1)  
            end  
        end  
    end  
    sendMessage("Auto-attacked " .. targetPlayer.Name .. " on spawn.")  
end  

-- Handles what happens when any player's character dies.  
local function onCharacterDied(humanoid)  
    local killerTag = humanoid:FindFirstChild("creator")  
    local killerName = "Unknown"  
    if killerTag and killerTag.Value then  
        killerName = killerTag.Value.Name  
    end  
    -- sendMessage("Player " .. LP.Name .. " died. Killed by: " .. killerName)  
end  

-- Handles what happens when any player's character is added (spawns/respawns).  
local function onCharacterAdded(character)  
    if safeZoneConnection then stopSafeZoneLoop() end  
    
    local humanoid = character:WaitForChild("Humanoid", 10)  
    if humanoid then  
        humanoid.Died:Connect(function() onCharacterDied(humanoid) end)  
    end  

    local player = Players:GetPlayerFromCharacter(character)  
    if player and table.find(Targets, player) then  
        sendMessage(player.Name .. " has spawned. Preparing to attack...")  
        task.wait(0.5)   
        manualAttack(player)  
    end  

    if player == LP then  
        if DeathPositions[LP.Name] then  
            local hrp = character:WaitForChild("HumanoidRootPart", 10)  
            if hrp then   
                task.wait(0.5)  
                hrp.CFrame = DeathPositions[LP.Name]  
                DeathPositions[LP.Name] = nil   
            end  
        end  
        if not HeartbeatConnection or not HeartbeatConnection.Connected then  
            HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)  
        end  
    end  
end  

-- ==================================  
-- ==   COMMAND HANDLER & LOGIC    ==  
-- ==================================  
-- This is the main engine that processes chat commands and executes actions.  

-- Dummy functions to prevent errors if the full combat loop is not present.  
local function forceEquip() end  
local function startCombatLoop() end  
local function stopCombatLoop() end  
local function setAura() end  
local function setAuraVisibility() end  
local function killOnce() end  
local function addTarget(playerName)  
    local p = findPlayer(playerName)  
    if p and not table.find(Targets, p) then  
        table.insert(Targets, p)  
        sendMessage("Target added: "..p.Name..". Will auto-attack on spawn.")  
    end  
end  
local function removeTarget(playerName)  
    local p = findPlayer(playerName)  
    if p then  
        for i, target in ipairs(Targets) do  
            if target == p then  
                table.remove(Targets, i)  
                sendMessage("Target removed: "..p.Name)  
                break  
            end  
        end  
    end  
end  

-- Loops for continuous actions  
local function stopSpinLoop()  
    if spinConnection then spinConnection:Disconnect(); spinConnection = nil; SpinTarget = nil; sendMessage("Spin stopped.") end  
end  
local function spinLoop()  
    if spinConnection then stopSpinLoop() end  
    sendMessage("Spinning " .. (SpinTarget and SpinTarget.Name or "air") .. ".")  
    spinConnection = RunService.Heartbeat:Connect(function()  
        if not (LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")) then stopSpinLoop(); return end  
        local targetPos = SpinTarget and SpinTarget.Character and SpinTarget.Character.PrimaryPart and SpinTarget.Character.PrimaryPart.Position or LP.Character.HumanoidRootPart.Position + LP.Character.HumanoidRootPart.CFrame.LookVector * 10  
        local newCFrame = CFrame.new(LP.Character.HumanoidRootPart.Position, targetPos) * CFrame.Angles(0, math.rad(RunService:GetRunTime() * SPIN_SPEED % 360), 0)  
        LP.Character.HumanoidRootPart.CFrame = newCFrame  
    end)  
end  
local function stopSafeZoneLoop()  
    if safeZoneConnection then safeZoneConnection:Disconnect(); safeZoneConnection = nil end  
    if safeZonePlatform then safeZonePlatform:Destroy(); safeZonePlatform = nil end  
    FollowTarget = nil  
    sendMessage("Safezone disabled.")  
end  
local function frogJump()  
    if LP.Character and LP.Character:FindFirstChild("Humanoid") then  
        LP.Character.Humanoid.JumpPower = 100  
        LP.Character.Humanoid.Jump = true  
        task.wait(0.5)  
        LP.Character.Humanoid.JumpPower = 50 -- Reset to default  
    end  
end  
local function serverHop()  
    local servers = TeleportService:GetServerInstancesAsync(game.PlaceId)  
    local validServers = {}  
    for _, server in ipairs(servers) do  
        if server.JobId ~= game.JobId and server.Players < server.MaxPlayers then  
            table.insert(validServers, server)  
        end  
    end  
    if #validServers > 0 then  
        local randomServer = validServers[math.random(1, #validServers)]  
        TeleportService:TeleportToPlaceInstance(game.PlaceId, randomServer.JobId, LP)  
    else  
        sendMessage("No other servers found to hop to.")  
    end  
end  

-- Main heartbeat function for periodic checks  
function onHeartbeat()  
    if FollowTarget and FollowTarget.Character and FollowTarget.Character.PrimaryPart and LP.Character and LP.Character.PrimaryPart then  
        local offset = Vector3.new(5, 5, 5)  
        teleportTo(LP.Character, FollowTarget.Character.PrimaryPart.Position + offset)  
    end  
    if SpammingEnabled then  
        sendMessage("Spamming message!") -- Customize the message here  
    end  
end  

-- The main function that parses and executes commands from chat.  
local function onMessageReceived(messageData)  
    local text = messageData.Text  
    if not text or not messageData.TextSource then return end  
    
    local authorPlayer = Players:GetPlayerByUserId(messageData.TextSource.UserId)  
    if not authorPlayer then return end  

    if authorPlayer ~= LP and not table.find(ConnectedUsers, authorPlayer) then return end  

    local args = text:split(" ")  
    local command = args[1]:lower()  
    table.remove(args, 1)  

    -- Command routing  
    if command == ".kill" and args[1] then manualAttack(findPlayer(args[1]))  
    elseif command == ".target" and args[1] then addTarget(args[1])  
    elseif command == ".untarget" and args[1] then removeTarget(args[1])  
    elseif command == ".loop" and args[1] then addTarget(args[1]) -- Alias for .target  
    elseif command == ".unloop" and args[1] then removeTarget(args[1]) -- Alias for .untarget  
    elseif command == ".to" and args[1] then local p = findPlayer(args[1]); if p and p.Character then teleportTo(LP.Character, p.Character.PrimaryPart.Position) end  
    elseif command == ".follow" and args[1] then FollowTarget = findPlayer(args[1])  
    elseif command == ".unfollow" then FollowTarget = nil  
    elseif command == ".spin" and args[1] then SpinTarget = findPlayer(args[1]); spinLoop()  
    elseif command == ".unspin" then stopSpinLoop()  
    elseif command == ".spinspeed" and args[1] then SPIN_SPEED = tonumber(args[1]) or 20  
    elseif command == ".reset" then if LP.Character then LP.Character.Humanoid.Health = 0 end  
    elseif command == ".refresh" then if LP.Character then DeathPositions[LP.Name] = LP.Character.PrimaryPart.CFrame; LP.Character.Humanoid.Health = 0 end  
    elseif command == ".shop" then serverHop()  
    elseif command == ".fjump" then frogJump()  
    elseif command == ".spam" then SpammingEnabled = true  
    elseif command == ".unspam" then SpammingEnabled = false  
    elseif command == ".safezone" and args[1] then  
        stopSafeZoneLoop()  
        local target = findPlayer(args[1])  
        if not target then return end  
        FollowTarget = target  
        safeZonePlatform = Instance.new("Part", Workspace); safeZonePlatform.Name = "SafeZone"; safeZonePlatform.Anchored = true; safeZonePlatform.Size = Vector3.new(12, 2, 12); safeZonePlatform.Transparency = 0.5  
        safeZoneConnection = RunService.Heartbeat:Connect(function()  
            if not (FollowTarget and FollowTarget.Character and FollowTarget.Character.PrimaryPart and safeZonePlatform) then stopSafeZoneLoop(); return end  
            local pos = FollowTarget.Character.PrimaryPart.Position + SAFE_ZONE_OFFSET  
            safeZonePlatform.Position = pos  
            teleportTo(LP.Character, pos + Vector3.new(0, 3, 0))  
        end)  
    elseif command == ".unsafezone" then stopSafeZoneLoop()  
    elseif command == ".equip" then  
        local tool = LP.Backpack:FindFirstChildWhichIsA("Tool")  
        if tool and LP.Character then tool.Parent = LP.Character end  
    elseif command == ".unequip" then  
        local tool = LP.Character:FindFirstChildWhichIsA("Tool")  
        if tool then tool.Parent = LP.Backpack end  
    elseif command == ".ping" then  
        local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()  
        sendMessage("Ping: " .. math.floor(ping) .. "ms")  
    end  
end  

-- ==================================  
-- ==     INITIALIZATION           ==  
-- ==================================  
-- Connects the handlers and starts the script's core loops.  

-- Connect handlers for all players currently in the game  
for _, player in ipairs(Players:GetPlayers()) do  
    player.CharacterAdded:Connect(onCharacterAdded)  
    if player.Character then  
        pcall(onCharacterAdded, player.Character)  
    end  
end  

-- Connect handlers for players who join in the future  
Players.PlayerAdded:Connect(function(player)  
    player.CharacterAdded:Connect(onCharacterAdded)  
end)  

-- Connect the chat message handler to the local player  
LP.Chatted:Connect(function(text)  
    local messageData = { Text = text, TextSource = LP }  
    onMessageReceived(messageData)  
end)  

-- Start the main heartbeat loop  
HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)  

sendMessage("Control Script Initialized.")
       
