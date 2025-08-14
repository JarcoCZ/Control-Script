--[[  
    Floxy Script - v72 (v71 Base + Teleport Commands)  

    UPDATES (v72):  
    - NEW: Added the `.log` command to teleport the user to Place ID 86570022656177.  
    - NEW: Added the `.join` command to teleport the user to Place ID 6110766473.  
    - PRESERVED: All previous functionality, including the loop confirmation message and the modern combat loop, remains unchanged.  
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
-- KillStates is removed as the new loop doesn't use it.  
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
local AuraVisible = false -- Kept for command logic, though new loop has no visible part.  
-- DMG_TIMES and FT_TIMES are removed as new loop has its own attack mechanism.  
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
-- ==        COMBAT LOGIC          ==  
-- ==================================  

local AuraEnabled = false  
local CombatLoopConnection = nil  
local AURA_RANGE = 25 -- Default distance for aura. Adjust if needed.  

-- Function to find a usable weapon in the player's character or backpack.  
local function findWeapon()  
    if not LP.Character then return nil end  
    
    -- Priority 1: Check if a tool is already equipped.  
    local equippedTool = LP.Character:FindFirstChildOfClass("Tool")  
    if equippedTool and equippedTool:FindFirstChild("Handle") then  
        return equippedTool  
    end  

    -- Priority 2: Check the backpack for a suitable tool.  
    local backpack = LP:FindFirstChildOfClass("Backpack")  
    if backpack then  
        -- Prefer a tool named "ClassicSword", but fall back to any valid tool.  
        local sword = backpack:FindFirstChild("ClassicSword")  
        if sword and sword:IsA("Tool") and sword:FindFirstChild("Handle") then  
            return sword  
        end  
        for _, tool in ipairs(backpack:GetChildren()) do  
            if tool:IsA("Tool") and tool:FindFirstChild("Handle") then  
                return tool -- Return the first valid tool found.  
            end  
        end  
    end  
    
    return nil -- No weapon found  
end  

-- Equips or unequips the best available weapon.  
local function forceEquip(shouldEquip)  
    local weapon = findWeapon()  
    if not weapon then   
        warn("Floxy System: No weapon found to equip/unequip.")  
        return   
    end  

    local humanoid = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")  
    if not humanoid then return end  

    if shouldEquip and weapon.Parent ~= LP.Character then  
        humanoid:EquipTool(weapon)  
        task.wait(0.1) -- Give a small delay for the tool to equip.  
    elseif not shouldEquip and weapon.Parent == LP.Character then  
        humanoid:UnequipTools()  
    end  
end  

-- Main combat loop function, runs on every frame when active.  
local function runCombatTick()  
    -- Stop conditions for the loop  
    if not AuraEnabled and #Targets == 0 then  
        if CombatLoopConnection then  
            CombatLoopConnection:Disconnect()  
            CombatLoopConnection = nil  
            forceEquip(false) -- Unequip weapon when combat ends  
            sendMessage("Combat loop stopped.")  
            print("Floxy Debug: Loop stopped (no targets and aura is off).")  
        end  
        return  
    end  

    local myHRP = LP.Character and LP.Character.PrimaryPart  
    if not myHRP then return end -- Cannot fight without a character  

    local target = Targets[1]  
    if not (target and target.Character and target.Character.PrimaryPart and target.Character.Humanoid and target.Character.Humanoid.Health > 0) then  
        if target then  
            -- Target is invalid, remove them and move to the next.  
            print("Floxy Debug: Target invalid/dead, removing:", target.Name)  
            removeTarget(target.Name)  
        end  
        return -- Wait for the next tick to process the next target  
    end  

    local distance = (myHRP.Position - target.Character.PrimaryPart.Position).Magnitude  
    if distance > AURA_RANGE then  
        print("Floxy Debug: Target", target.Name, "is out of range ("..tostring(math.floor(distance)).."/"..tostring(AURA_RANGE)..").")  
        return -- Skip attack if target is too far  
    end  

    -- If we are here, we have a valid target in range. Time to attack.  
    forceEquip(true)  
    local weapon = LP.Character and LP.Character:FindFirstChildOfClass("Tool")  
    if not weapon then  
        warn("Floxy Debug: Failed to attack, weapon could not be equipped in time.")  
        return  
    end  
    
    -- Most common sword scripts use one of these two methods.  
    -- Method 1: Fire a remote event (preferred)  
    local attackRemote = weapon:FindFirstChild("Attack", true) -- Recursive find  
    if attackRemote and attackRemote:IsA("RemoteEvent") then  
        print("Floxy Debug: Firing 'Attack' remote on target:", target.Name)  
        pcall(function()  
            attackRemote:FireServer()  
        end)  
        return  
    end  
    
    -- Method 2: Use Tool:Activate() (common fallback)  
    print("Floxy Debug: No 'Attack' remote found. Trying weapon:Activate() on target:", target.Name)  
    pcall(function()  
        weapon:Activate()  
    end)  
end  

-- Starts the combat loop if it's not already running.  
local function startCombatLoop()  
    if CombatLoopConnection and CombatLoopConnection.Connected then  
        print("Floxy Debug: Attempted to start loop, but it is already running.")  
        return  
    end  
    
    if not LP.Character then   
        sendMessage("Cannot start combat without a character.")  
        return   
    end  
    
    sendMessage("Combat loop started.")  
    print("Floxy Debug: Combat loop successfully initiated.")  
    CombatLoopConnection = RunService.Heartbeat:Connect(runCombatTick)  
end  

-- Adds a player to the target list.  
local function addTarget(playerName)  
    local player = findPlayer(playerName)  
    if player and player ~= LP and not table.find(Targets, player) then  
        table.insert(Targets, 1, player) -- Add to the front of the list  
        sendMessage("Target added: " .. player.Name)  
        startCombatLoop() -- Automatically start the loop when a target is added  
    else  
        sendMessage("Could not find player or player is already a target: " .. playerName)  
    end  
end  

-- Removes a player from the target list.  
local function removeTarget(playerName)  
    local playerToRemove = findPlayer(playerName)  
    for i, target in ipairs(Targets) do  
        if target == playerToRemove then  
            table.remove(Targets, i)  
            sendMessage("Target removed: " .. playerName)  
            return  
        end  
    end  
end-- ==================================  
-- ==      COMMANDS & CONTROLS     ==  
-- ==================================  

local function setAuraVisibility(visible)  
    AuraVisible = visible  
    -- The new combat loop does not use a visible part, so this command is now for user feedback only.  
    -- We do not need to iterate through tools anymore.  
    sendMessage("Aura visibility set to " .. (visible and "ON" or "OFF") .. ". (Note: New loop has no visual part)")  
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
        table.insert(Targets, player.Name)  
        sendMessage(player.Name .. " has been looped.") -- ADDED THIS LINE FOR DEBUGGING  
        forceEquip(true)  
        startCombatLoop() -- Start the new combat loop  
    end  
end  

local function removeTarget(playerName)  
    local player = findPlayer(playerName)  
    if player then  
        for i, name in ipairs(Targets) do  
            if name == player.Name then   
                table.remove(Targets, i)  
                sendMessage(player.Name .. " has been unlooped.")  
                break   
            end  
        end  
        if #Targets == 0 and not AuraEnabled then forceEquip(false) end  
        stopCombatLoop() -- Check if the combat loop should stop  
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
        
        if AuraEnabled then  
            startCombatLoop()  
        else  
            stopCombatLoop()  
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
.kill [user], .loop [user|all], .unloop [user|all]  
.aura [range|off], .aura [see|unsee], .aura whitelist [user], .aura unwhitelist [user]  
.to [user], .follow [user], .unfollow, .spin [user], .unspin, .spinspeed [val]  
]]  
    local commandList_2 = [[  
.safe, .unsafe, .safezone [user], .unsafezone  
.refresh, .reset, .shop, .equip, .unequip, .fjump, .time [num]  
.spam, .unspam, .say [msg], .count, .ping, .test, .log, .join  
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

    if command == "connect" then  
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
    elseif command == ".loop" and arg2 then  
        if arg2:lower() == "all" then  
            sendMessage("Looping all valid players.")  
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
            sendMessage("Unlooping all players.")  
            table.clear(Targets)  
            forceEquip(AuraEnabled)  
            stopCombatLoop() -- Check if loop should stop  
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
            local p = findPlayer(arg3); if p and not table.find(Whitelist, p.Name) then table.insert(Whitelist, p.Name); sendMessage(p.Name .. " whitelisted.") end  
        elseif arg2:lower() == "unwhitelist" and arg3 then  
            local p = findPlayer(arg3); if p then for i, n in ipairs(Whitelist) do if n == p.Name then table.remove(Whitelist, i); sendMessage(p.Name .. " unwhitelisted."); break end end end  
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
    elseif command == ".log" then -- NEW COMMAND  
        sendMessage("Teleporting to log place...")  
        TeleportService:Teleport(86570022656177, LP)  
    elseif command == ".join" then -- NEW COMMAND  
        sendMessage("Teleporting to join place...")  
        TeleportService:Teleport(6110766473, LP)  
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
    
    -- The old `createReachPart` calls are no longer needed.  
    
    if #Targets > 0 or AuraEnabled then  
        forceEquip(true)  
        startCombatLoop()  
    end  
    
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
        sendMessage("Main Connector has left. Connection reset.")  
    end  
    if safePlatform and #Players:GetPlayers() == 1 then  
        pcall(function() safePlatform:Destroy() end)  
    end  
end)  
TextChatService.MessageReceived:Connect(onMessageReceived)  

sendMessage("Script Executed - Floxy (LOOP UPDATE V72")  
print("Floxy System Loaded. User Authorized.")
       
