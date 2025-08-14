--[[  
    Floxy Script - Fixed by luxx (v65 - New Loop System Integration)  

    UPDATES (v65):  
    - INTEGRATED: User-provided high-performance loop system is now the core of the combat logic.  
    - REPLACED: The old Heartbeat-based attack loop has been replaced.  
    - The new system uses `workspace:GetPartBoundsInBox` for efficient, modern hit detection.  
    - It is fully integrated with the existing command structure (.loop, .unloop, .aura).  
    - Hardcoded target has been replaced with the dynamic 'Targets' table.  
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
local Targets = {}  
local Whitelist = {}  
local ConnectedUsers = {}  
local DeathPositions = {}  
local FollowTarget = nil  
local MainConnector = nil  
local ForceEquipConnection = nil  
local SpammingEnabled = false  
local safePlatform = nil  
local safeZoneConnection = nil  
local safeZonePlatform = nil  
local spinConnection = nil  
local spinTarget = nil  
local AwaitingRejoinConfirmation = false  
local BangTarget = nil  
local BangConnection = nil  

-- Pre-loaded Instances  
local ChangeTimeEvent = nil  

-- Configuration  
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

--[[ v65: New Loop System Integration ]]  
local CombatLoopActive = false  
local AuraSize = Vector3.new(0, 0, 0)  

local function startCombatLoop()  
    if CombatLoopActive then return end  
    CombatLoopActive = true  
    
    -- Helper functions for the new loop  
    local function getCharacter(plr) return plr and plr.Character end  
    local function getHumanoid(char) return char and char:FindFirstChildWhichIsA("Humanoid") end  
    local function isAlive(humanoid) return humanoid and humanoid.Health > 0 end  
    
    task.spawn(function()  
        local overlapParams = OverlapParams.new()  
        overlapParams.FilterType = Enum.RaycastFilterType.Include  
        
        while CombatLoopActive do  
            local myChar = getCharacter(LP)  
            if not (myChar and isAlive(getHumanoid(myChar))) then  
                RunService.Heartbeat:Wait()  
                continue  
            end  
            
            local tool = myChar:FindFirstChildWhichIsA("Tool")  
            if not (tool and tool:IsDescendantOf(Workspace)) then  
                RunService.Heartbeat:Wait()  
                continue  
            end  
            
            local touchPart = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")  
            if not touchPart then  
                RunService.Heartbeat:Wait()  
                continue  
            end  
            
            -- Build the list of characters to attack  
            local charactersToAttack = {}  
            for _, targetName in ipairs(Targets) do  
                local player = Players:FindFirstChild(targetName)  
                if player and player.Character then table.insert(charactersToAttack, player.Character) end  
            end  
            
            -- If aura is on, add all valid players to the list  
            if AuraEnabled then  
                for _, player in ipairs(Players:GetPlayers()) do  
                    if player ~= LP and player.Character and not table.find(Whitelist, player.Name) then  
                        if not table.find(charactersToAttack, player.Character) then  
                           table.insert(charactersToAttack, player.Character)  
                        end  
                    end  
                end  
            end  
            
            if #charactersToAttack == 0 then  
                RunService.Heartbeat:Wait()  
                continue  
            end  
            
            overlapParams.FilterDescendantsInstances = charactersToAttack  
            
            local instancesInBox = Workspace:GetPartBoundsInBox(touchPart.CFrame, touchPart.Size + AuraSize, overlapParams)  
            
            for _, part in ipairs(instancesInBox) do  
                local char = part:FindFirstAncestorWhichIsA("Model")  
                if table.find(charactersToAttack, char) then  
                    if isAlive(getHumanoid(char)) then  
                        -- Attack logic  
                        tool:Activate()  
                        firetouchinterest(touchPart, part, 1)  
                        firetouchinterest(touchPart, part, 0)  
                    end  
                end  
            end  
            
            RunService.Heartbeat:Wait()  
        end  
    end)  
end  

local function stopCombatLoop()  
    if not CombatLoopActive then return end  
    if #Targets == 0 and not AuraEnabled then  
        CombatLoopActive = false  
    end  
end  
--[[ End of v65 New Loop System ]]  


-- ==================================  
-- ==      HELPER FUNCTIONS        ==  
-- ==================================  

local function sendMessage(message, channel)  
    pcall(function()  
        local targetChannel = channel or (TextChatService and TextChatService.ChatInputBarConfiguration and TextChatService.ChatInputBarConfiguration.TargetTextChannel)  
        if targetChannel then targetChannel:SendAsync(message) end  
    end)  
end  

local function findPlayer(partialName)  
    if not partialName then return nil end  
    local lowerName = tostring(partialName):lower()  
    for _, player in ipairs(Players:GetPlayers()) do  
        if player.Name:lower():find(lowerName, 1, true) then return player end  
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
-- ==      COMBAT & TOOL LOGIC     ==  
-- ==================================  
-- This section is now controlled by the new loop system above  

local function onHeartbeat() -- v65: Combat logic removed from here  
    if not LP.Character or not LP.Character.PrimaryPart then return end  

    local myPos = LP.Character.PrimaryPart.Position  
    local myHumanoid = LP.Character:FindFirstChildOfClass("Humanoid")  

    -- Follow logic remains  
    if FollowTarget and FollowTarget.Character and FollowTarget.Character.PrimaryPart and myHumanoid and not safeZoneConnection then  
        if (FollowTarget.Character.PrimaryPart.Position - myPos).Magnitude > 5 then  
            myHumanoid:MoveTo(FollowTarget.Character.PrimaryPart.Position)  
        end  
    end  
    
    -- Spam logic remains  
    if SpammingEnabled then  
        local tool = LP.Character:FindFirstChildOfClass("Tool")  
        if tool then pcall(function() tool:Activate() end) end  
    end  
end  


-- ==================================  
-- ==      COMMANDS & CONTROLS     ==  
-- ==================================  

local function stopBangLoop()  
    if BangConnection and BangConnection.Connected then  
        BangConnection:Disconnect()  
        BangConnection = nil  
        BangTarget = nil  
    end  
end  

local function startBangLoop(targetPlayer)  
    stopBangLoop()  
    BangTarget = targetPlayer  
    local bangState = 0  
    
    BangConnection = RunService.Heartbeat:Connect(function()  
        local myChar = LP.Character  
        local targetChar = BangTarget and BangTarget.Character  
        
        if not (myChar and myChar.PrimaryPart and targetChar and targetChar:FindFirstChild("HumanoidRootPart") and targetChar.Humanoid and targetChar.Humanoid.Health > 0) then  
            sendMessage("Bang target lost. Disabling.")  
            stopBangLoop()  
            return  
        end  
        
        local targetHrp = targetChar.HumanoidRootPart  
        local distance = (bangState % 2 == 0) and 3 or 3.5  
        bangState = bangState + 1  
        
        local newPos = (targetHrp.CFrame * CFrame.new(0, 0, distance)).Position  
        local lookAtPos = targetHrp.Position  
        teleportTo(myChar, CFrame.new(newPos, lookAtPos))  
    end)  
    sendMessage("Banging " .. targetPlayer.Name)  
end  

local function frogJump()  
    local myChar = LP.Character  
    if not (myChar and myChar.PrimaryPart) then return end  
    local startPos = myChar.PrimaryPart.Position  
    teleportTo(myChar, startPos - Vector3.new(0, FROG_JUMP_PREP_DIST, 0))  
    task.wait(0.05)  
    teleportTo(myChar, startPos + Vector3.new(0, FROG_JUMP_HEIGHT, 0))  
end  

local function stopSpinLoop()  
    if spinConnection and spinConnection.Connected then  
        spinConnection:Disconnect(); spinConnection = nil; spinTarget = nil  
    end  
end  

local function stopSafeZoneLoop()  
    if safeZoneConnection and safeZoneConnection.Connected then  
        safeZoneConnection:Disconnect(); safeZoneConnection = nil  
    end  
    if safeZonePlatform and safeZonePlatform.Parent then  
        safeZonePlatform:Destroy(); safeZonePlatform = nil  
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
            ForceEquipConnection:Disconnect(); ForceEquipConnection = nil  
        end  
    end  
end  

-- v65: Updated to control the new loop  
local function addTarget(playerName)  
    local player = findPlayer(playerName)  
    if player and player ~= LP and not table.find(Targets, player.Name) then  
        table.insert(Targets, player.Name)  
        forceEquip(true)  
        startCombatLoop()  
    end  
end  

-- v65: Updated to control the new loop  
local function removeTarget(playerName)  
    local player = findPlayer(playerName)  
    if player then  
        for i, name in ipairs(Targets) do  
            if name == player.Name then table.remove(Targets, i); break end  
        end  
        if #Targets == 0 and not AuraEnabled then forceEquip(false) end  
        stopCombatLoop()  
    end  
end  

local function killOnce(playerName)  
    local player = findPlayer(playerName)  
    if not player or not player.Character or not player.Character:FindFirstChild("Humanoid") then return end  
    addTarget(playerName)  
    local humanoid = player.Character.Humanoid  
    local connection  
    connection = humanoid.Died:Connect(function()  
        removeTarget(playerName)  
        if connection then connection:Disconnect() end  
    end)  
end  

local function spinLoop()  
    stopSpinLoop()  
    spinConnection = RunService.Heartbeat:Connect(function()  
        if not (spinTarget and spinTarget.Parent and spinTarget.Character and spinTarget.Character.PrimaryPart and LP.Character and LP.Character.PrimaryPart) then  
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

-- v65: Updated to control the new loop  
local function setAura(range)  
    local newRange = tonumber(range)  
    if newRange and newRange >= 0 then  
        AuraSize = Vector3.new(newRange, newRange, newRange)  
        AuraEnabled = newRange > 0  
        forceEquip(AuraEnabled or #Targets > 0)  
        
        if AuraEnabled then  
            startCombatLoop()  
        else  
            stopCombatLoop()  
        end  
    end  
end  

local function serverHop()  
    pcall(function()  
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
    end)  
end  

local function displayCommands()  
    local commandList_1 = ".kill [user], .loop [user|all], .unloop [user|all]\n.aura [range|off], .aura whitelist [user], .aura unwhitelist [user]\n.to [user], .follow [user], .unfollow, .spin [user], .unspin, .spinspeed [val]\n.bang [user], .unbang"  
    local commandList_2 = ".safe, .unsafe, .safezone [user], .unsafezone\n.refresh, .reset, .shop, .equip, .unequip, .fjump, .time [num]\n.spam, .unspam, .say [msg], .count, .ping, .test"  
    sendMessage(commandList_1)  
    task.wait(0.1)  
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

    if authorPlayer ~= LP and not table.find(ConnectedUsers, authorPlayer) then return end  

    if command == ".kill" and arg2 then killOnce(arg2)  
    elseif command == ".loop" and arg2 then  
        if arg2:lower() == "all" then  
            for _, player in ipairs(Players:GetPlayers()) do  
                if player ~= LP and not table.find(Whitelist, player.Name) then addTarget(player.Name) end  
            end  
        else addTarget(arg2) end  
    elseif command == ".unloop" and arg2 then  
        if arg2:lower() == "all" then  
            table.clear(Targets)  
            forceEquip(AuraEnabled)  
            stopCombatLoop()  
        else removeTarget(arg2) end  
    elseif command == ".aura" and arg2 then  
        if arg2:lower() == "off" then setAura(0)  
        elseif arg2:lower() == "whitelist" and arg3 then  
            local p = findPlayer(arg3); if p and not table.find(Whitelist, p.Name) then table.insert(Whitelist, p.Name) end  
        elseif arg2:lower() == "unwhitelist" and arg3 then  
            local p = findPlayer(arg3); if p then for i, n in ipairs(Whitelist) do if n == p.Name then table.remove(Whitelist, i); break end end end  
        else setAura(arg2) end  
    elseif command == ".spin" and arg2 then  
        local p = findPlayer(arg2); if p then spinTarget = p; spinLoop() end  
    elseif command == ".unspin" then stopSpinLoop()  
    elseif command == ".spinspeed" and arg2 then  
        local newSpeed = tonumber(arg2); if newSpeed and newSpeed > 0 then SPIN_SPEED = newSpeed; sendMessage("Spin speed set to " .. SPIN_SPEED) end  
    elseif command == ".reset" then  
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)  
    elseif command == ".shop" and authorPlayer == LP then serverHop()  
    elseif command == ".refresh" then  
        if LP.Character and LP.Character.PrimaryPart then  
            DeathPositions[LP.Name] = LP.Character.PrimaryPart.CFrame  
            if LP.Character.Humanoid then LP.Character.Humanoid.Health = 0 end  
        end  
    elseif command == ".to" and arg2 then  
        local targetPlayer = findPlayer(arg2)  
        if targetPlayer and targetPlayer.Character and targetPlayer.Character.PrimaryPart and LP.Character then teleportTo(LP.Character, targetPlayer.Character.PrimaryPart.Position) end  
    elseif command == ".follow" and arg2 then  
        stopSafeZoneLoop()  
        local targetPlayer = findPlayer(arg2)  
        if targetPlayer then FollowTarget = targetPlayer else FollowTarget = nil end  
    elseif command == ".unfollow" then  
        FollowTarget = nil; stopSafeZoneLoop()  
    elseif command == ".cmds" or command == ".help" then displayCommands()  
    elseif command == ".count" then sendMessage(#Players:GetPlayers() .. "/" .. Players.MaxPlayers .. " players")  
    elseif command == ".equip" then  
        if LP.Character and LP.Character.Humanoid then local tool = LP.Backpack:FindFirstChildWhichIsA("Tool"); if tool then LP.Character.Humanoid:EquipTool(tool) end end  
    elseif command == ".unequip" then  
        if LP.Character and LP.Character.Humanoid then local tool = LP.Character:FindFirstChildWhichIsA("Tool"); if tool then tool.Parent = LP.Backpack end end  
    elseif command == ".fjump" then frogJump()  
    elseif command == ".spam" then SpammingEnabled = true  
    elseif command == ".unspam" then SpammingEnabled = false  
    elseif command == ".say" and arg2 then  
        table.remove(args, 1); sendMessage(table.concat(args, " "))  
    elseif command == ".safe" then  
        if not safePlatform or not safePlatform.Parent then  
            safePlatform = Instance.new("Part", Workspace); safePlatform.Name = "SafePlatform"; safePlatform.Size = Vector3.new(50, 2, 50); safePlatform.Position = SAFE_PLATFORM_POS; safePlatform.Anchored = true; safePlatform.CanCollide = true  
        end; teleportTo(LP.Character, SAFE_PLATFORM_POS + Vector3.new(0, 5, 0))  
    elseif command == ".unsafe" then  
        if safePlatform and safePlatform.Parent then safePlatform:Destroy(); safePlatform = nil end  
        if LP.Character and LP.Character.Humanoid then LP.Character.Humanoid.Health = 0 end  
    elseif command == ".safezone" and arg2 then  
        local targetPlayer = findPlayer(arg2); if not (targetPlayer and LP.Character and LP.Character.PrimaryPart) then return end  
        stopSafeZoneLoop(); FollowTarget = targetPlayer  
        safeZonePlatform = Instance.new("Part", Workspace); safeZonePlatform.Name = "SafeZonePlatform"; safeZonePlatform.Size = Vector3.new(12, 2, 12); safeZonePlatform.Transparency = 0.5; safeZonePlatform.Anchored = true; safeZonePlatform.CanCollide = true  
        safeZoneConnection = RunService.Heartbeat:Connect(function()  
            if not (FollowTarget and FollowTarget.Character and FollowTarget.Character.PrimaryPart and LP.Character and LP.Character.PrimaryPart and safeZonePlatform and safeZonePlatform.Parent) then  
                sendMessage("Safezone target or self lost. Disabling."); stopSafeZoneLoop(); return  
            end  
            local targetPos = FollowTarget.Character.PrimaryPart.Position  
            local platformNewPos = targetPos + SAFE_ZONE_OFFSET; safeZonePlatform.Position = platformNewPos  
            local myHRP = LP.Character.PrimaryPart  
            local myNewPos = platformNewPos + Vector3.new(0, (safeZonePlatform.Size.Y / 2) + (myHRP.Size.Y / 2), 0)  
            teleportTo(LP.Character, CFrame.new(myNewPos) * (myHRP.CFrame - myHRP.CFrame.Position))  
        end)  
    elseif command == ".unsafezone" then stopSafeZoneLoop()  
    elseif command == ".bang" and arg2 then  
        local targetPlayer = findPlayer(arg2); if targetPlayer and targetPlayer ~= LP then startBangLoop(targetPlayer) else sendMessage("Player not found or you targeted yourself.") end  
    elseif command == ".unbang" then stopBangLoop(); sendMessage("Bang loop stopped.")  
    elseif command == ".test" then  
        pcall(function() loadstring(game:HttpGet('https://raw.githubusercontent.com/JarcoCZ/Control-Script/refs/heads/main/test.lua'))() end)  
    end  
end  

local function onCharacterAdded(char)  
    stopSafeZoneLoop()  
    stopBangLoop()  
    local humanoid = char:WaitForChild("Humanoid", 10)  

    if #Targets > 0 or AuraEnabled then  
        forceEquip(true)  
        startCombatLoop()  
    end  
    if DeathPositions[LP.Name] then  
        local hrp = char:WaitForChild("HumanoidRootPart", 10)  
        if hrp then task.wait(0.5); hrp.CFrame = DeathPositions[LP.Name]; DeathPositions[LP.Name] = nil end  
    end  
    if not (HeartbeatConnection and HeartbeatConnection.Connected) then  
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
    if spinTarget == p then stopSpinLoop() end  
    if BangTarget == p then stopBangLoop() end  
    removeTarget(p.Name)  
    for i, pl in ipairs(PlayerList) do if pl == p then table.remove(PlayerList, i); break end end  
    if FollowTarget == p then stopSafeZoneLoop() end  
end)  

TextChatService.MessageReceived:Connect(onMessageReceived)  
sendMessage("Script Executed - Floxy (Fixed by luxx v65 - New Loop System)")  
print("Floxy System Loaded. User Authorized.")
