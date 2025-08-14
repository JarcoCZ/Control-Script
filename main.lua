local Players = game:GetService("Players")  
local RunService = game:GetService("RunService")  
local TextChatService = game:GetService("TextChatService")  
local LP = Players.LocalPlayer  
local Dist = 0 -- Default disabled  
local DistSq = Dist * Dist  
local DMG_TIMES = 2 -- How many times to firetouchinterest for damage  
local FT_TIMES = 5  -- How many times to firetouchinterest for general touch events  
local AllPlayers = {} -- Will store all players in the game  
local Targets = {} -- Stores names of players currently being targeted by .loop  
local AuraEnabled = false  
local Whitelist = {} -- Stores names of whitelisted players  
local ForceEquipConnection = nil -- Manages the sword equipping loop  

-- Connect System variables  
local ConnectedUsers = {} -- Store all connected users (Player objects)  
local MainConnector = nil -- Store the main connector (Player object)  

-- Function to send message to chat  
local function sendMessage(message)  
    -- This uses a task.spawn to avoid blocking and ensure chat service is ready.  
    task.spawn(function()  
        while not TextChatService.ChatInputBarConfiguration.TargetTextChannel do  
            task.wait(0.1) -- Wait for the chat channel to be available  
        end  
        TextChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)  
    end)  
end  

-- Utility: Find a player by partial name  
local function findPlayer(partialName)  
    partialName = partialName:lower()  
    for _, player in ipairs(Players:GetPlayers()) do  
        if player.Name:lower():find(partialName, 1, true) then  
            return player  
        end  
    end  
    return nil  
end  

-- Check if a player is connected  
local function isConnected(player)  
    return table.find(ConnectedUsers, player) ~= nil  
end  

-- Force equip sword to LocalPlayer  
local function forceEquip()  
    local char = LP.Character  
    if not char then return end  
    local humanoid = char:FindFirstChildWhichIsA("Humanoid")  
    if not humanoid then return end  
    local sword = LP.Backpack:FindFirstChild("Sword")  
    if sword and not char:FindFirstChild("Sword") then  
        humanoid:EquipTool(sword)  
    end  
end  

-- Unequip sword from LocalPlayer  
local function unequipSword()  
    local char = LP.Character  
    if not char then return end  
    local sword = char:FindFirstChild("Sword")  
    if sword then  
        local humanoid = char:FindFirstChildWhichIsA("Humanoid")  
        if humanoid then  
            humanoid:UnequipTool(sword)  
        end  
    end  
end  

-- Start the continuous force equip  
local function startForceEquip()  
    if ForceEquipConnection then  
        ForceEquipConnection:Disconnect()  
    end  
    ForceEquipConnection = RunService.RenderStepped:Connect(forceEquip)  
end  

-- Stop the continuous force equip  
local function stopForceEquip()  
    if ForceEquipConnection then  
        ForceEquipConnection:Disconnect()  
        ForceEquipConnection = nil  
    end  
end  

-- Command: .loop (target players for auto-hit)  
local function addTarget(playerName)  
    local player = findPlayer(playerName)  
    if player then  
        if not table.find(Targets, player.Name) then  
            table.insert(Targets, player.Name)  
            sendMessage("Added '" .. player.Name .. "' to loop targets.")  
            startForceEquip() -- Start equipping if there are targets  
            return true  
        else  
            sendMessage("'" .. player.Name .. "' is already a loop target.")  
        end  
    else  
        sendMessage("Player '" .. playerName .. "' not found.")  
    end  
    return false  
end  

local function removeTarget(playerName)  
    local player = findPlayer(playerName)  
    if player then  
        for i, targetName in ipairs(Targets) do  
            if targetName == player.Name then  
                table.remove(Targets, i)  
                sendMessage("Removed '" .. player.Name .. "' from loop targets.")  
                if #Targets == 0 then  
                    stopForceEquip() -- Stop equipping if no more targets  
                    unequipSword()  
                end  
                return true  
            end  
        end  
        sendMessage("'" .. player.Name .. "' is not currently a loop target.")  
    else  
        sendMessage("Player '" .. playerName .. "' not found.")  
    end  
    return false  
end  

-- Command: .aura (set range or manage whitelist)  
local function setAura(range)  
    local newRange = tonumber(range)  
    if newRange and newRange >= 0 then  
        Dist = newRange  
        DistSq = Dist * Dist  
        AuraEnabled = Dist > 0  
        sendMessage("Aura range set to " .. Dist .. ". Aura " .. (AuraEnabled and "enabled" or "disabled") .. ".")  
        
        -- Update existing BoxReachPart sizes dynamically  
        if LP.Character then  
            for _, tool in ipairs(LP.Character:GetDescendants()) do  
                if tool:IsA("Tool") and tool:FindFirstChild("Handle") then  
                    local boxPart = tool.Handle:FindFirstChild("BoxReachPart")  
                    if boxPart then  
                        boxPart.Size = Vector3.new(Dist, Dist, Dist)  
                    end  
                end  
            end  
        end  
        return true  
    else  
        sendMessage("Invalid aura range. Please provide a non-negative number.")  
    end  
    return false  
end  

local function addToWhitelist(playerName)  
    local player = findPlayer(playerName)  
    if player then  
        if not table.find(Whitelist, player.Name) then  
            table.insert(Whitelist, player.Name)  
            sendMessage("Added '" .. player.Name .. "' to whitelist.")  
            return true  
        else  
            sendMessage("'" .. player.Name .. "' is already whitelisted.")  
        end  
    else  
        sendMessage("Player '" .. playerName .. "' not found.")  
    end  
    return false  
end  

local function removeFromWhitelist(playerName)  
    local player = findPlayer(playerName)  
    if player then  
        for i, whitelistName in ipairs(Whitelist) do  
            if whitelistName == player.Name then  
                table.remove(Whitelist, i)  
                sendMessage("Removed '" .. player.Name .. "' from whitelist.")  
                return true  
            end  
        end  
        sendMessage("'" .. player.Name .. "' is not currently whitelisted.")  
    else  
        sendMessage("Player '" .. playerName .. "' not found.")  
    end  
    return false  
end  

-- === Core Hitbox Manipulation Functions ===  

-- Creates or updates the BoxReachPart for a tool handle  
local function createOrUpdateBoxReachPart(toolObject)  
    if toolObject:IsA("Tool") and toolObject:FindFirstChild("Handle") then  
        local h = toolObject.Handle  
        local p = h:FindFirstChild("BoxReachPart")  
        if not p then  
            p = Instance.new("Part")  
            p.Name = "BoxReachPart"  
            p.Parent = h  
            local w = Instance.new("WeldConstraint")  
            w.Part0 = h  
            w.Part1 = p  
            w.Parent = p  
            p.Transparency = 1  
            p.CanCollide = false  
            p.Massless = true  
        end  
        p.Size = Vector3.new(Dist, Dist, Dist) -- Always update size  
    end  
end  

-- Simulates a touch event (used for damaging)  
local function fireTouch(partA, partB)  
    for _ = 1, FT_TIMES do  
        firetouchinterest(partA, partB, 0) -- Touch began  
        firetouchinterest(partA, partB, 1) -- Touch ended  
    end  
end  

-- Handles attacking a player  
local function handleDamage(toolPart, targetPlayer)  
    local targetChar = targetPlayer.Character  
    if not targetChar then return end  
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")  
    if not (targetHumanoid and targetHumanoid.Health > 0) then return end  

    -- Activate the tool (e.g., for damage scripts)  
    pcall(function()  
        toolPart.Parent:Activate()  
    end)  

    -- Iterate through target's body parts and fire touch events  
    for _ = 1, DMG_TIMES do  
        for _, part in ipairs(targetChar:GetDescendants()) do  
            if part:IsA("BasePart") then  
                fireTouch(toolPart, part)  
            end  
        end  
    end  
end  

-- Main Heartbeat loop for hitbox and aura  
local mainHeartbeatConnection = nil  
local function setupHeartbeatLoop()  
    if mainHeartbeatConnection then mainHeartbeatConnection:Disconnect() end  

    mainHeartbeatConnection = RunService.Heartbeat:Connect(function()  
        local myChar = LP.Character  
        if not myChar then return end  
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")  
        if not myHRP then return end  
        local myPos = myHRP.Position  

        for _, tool in ipairs(myChar:GetDescendants()) do  
            if tool:IsA("Tool") then  
                local toolHandle = tool:FindFirstChild("Handle")  
                -- Prefer the BoxReachPart if it exists, otherwise use the Handle itself  
                local hitPart = toolHandle and (toolHandle:FindFirstChild("BoxReachPart") or toolHandle)  
                if hitPart then  
                    for _, player in ipairs(AllPlayers) do  
                        -- Skip self and whitelisted players  
                        if player == LP or table.find(Whitelist, player.Name) then continue end  

                        local targetChar = player.Character  
                        if not targetChar then continue end  
                        local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")  
                        local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")  

                        if targetHRP and targetHumanoid and targetHumanoid.Health > 0 then  
                            local shouldHit = false  

                            -- Check if player is a direct .loop target  
                            if table.find(Targets, player.Name) then  
                                shouldHit = true  
                            end  

                            -- Check if aura is enabled and player is within range  
                            if AuraEnabled and not shouldHit then -- Only check aura if not already targeted  
                                local distance = (targetHRP.Position - myPos).Magnitude  
                                if distance <= Dist then  
                                    shouldHit = true  
                                end  
                            end  

                            if shouldHit then  
                                handleDamage(hitPart, player)  
                            end  
                        end  
                    end  
                end  
            end  
        end  
    end)  
end  

-- Initialize AllPlayers list  
local function updateAllPlayers()  
    table.clear(AllPlayers)  
    for _, p in ipairs(Players:GetPlayers()) do  
        table.insert(AllPlayers, p)  
    end  
end  

-- PlayerAdded and PlayerRemoving events to keep AllPlayers list updated  
Players.PlayerAdded:Connect(function(player)  
    table.insert(AllPlayers, player)  
end)  

Players.PlayerRemoving:Connect(function(player)  
    for i, p in ipairs(AllPlayers) do  
        if p == player then  
            table.remove(AllPlayers, i)  
            break  
        end  
    end  
    -- Also remove from targets and whitelist if player leaves  
    removeTarget(player.Name) -- This also handles stopping force equip if no targets remain  
    removeFromWhitelist(player.Name)  

    -- Handle connection system if player leaves  
    if MainConnector == player then  
        MainConnector = nil  
        table.clear(ConnectedUsers)  
        sendMessage("Main connector left. Connect system reset.")  
    else  
        -- Remove from connected users if they leave  
        for i, connectedUser in ipairs(ConnectedUsers) do  
            if connectedUser == player then  
                table.remove(ConnectedUsers, i)  
                sendMessage("'" .. player.Name .. "' disconnected.")  
                break  
            end  
        end  
    end  
end)  

-- Initialize players list on script start  
updateAllPlayers()  

-- Handle LocalPlayer character loading/respawning  
LP.CharacterAdded:Connect(function(char)  
    char:WaitForChild("HumanoidRootPart", 10)  
    char:WaitForChild("Humanoid")  

    -- Ensure BoxReachParts are created/updated for all tools in character  
    for _, tool in ipairs(char:GetDescendants()) do  
        createOrUpdateBoxReachPart(tool)  
    end  
    char.ChildAdded:Connect(function(child)  
        if child:IsA("Tool") then  
            createOrUpdateBoxReachPart(child)  
        end  
    end)  

    setupHeartbeatLoop() -- Re-start the main loop when character spawns  

    -- Re-equip sword on respawn if still targeting someone  
    if #Targets > 0 then  
        forceEquip()  
    end  
end)  

-- Initial setup if character already exists when script starts (e.g., in Studio)  
if LP.Character then  
    for _, tool in ipairs(LP.Character:GetDescendants()) do  
        createOrUpdateBoxReachPart(tool)  
    end  
    LP.Character.ChildAdded:Connect(function(child)  
        if child:IsA("Tool") then  
            createOrUpdateBoxReachPart(child)  
        end  
    end)  
    setupHeartbeatLoop()  
end  

-- TextChatService message handler  
TextChatService.MessageReceived:Connect(function(message)  
    local speaker = message.TextSource  
    if not speaker then return end  
    
    local player = Players:GetPlayerByUserId(speaker.UserId)  
    if not player then return end  
    
    local text = message.Text  
    local args = text:split(" ")  
    local command = args[1]:lower()  
    
    -- === Connect System Commands (accessible by anyone initially) ===  
    if command == "connect" then  
        if not MainConnector then  
            MainConnector = player  
            table.insert(ConnectedUsers, player)  
            table.insert(Whitelist, player.Name) -- Auto-whitelist main connector  
            sendMessage("'" .. player.Name .. "' is now the Main Connector. Type 'connect <playername>' to add others.")  
        elseif player == MainConnector then  
            -- Main connector can connect other users  
            if args[2] then  
                local targetPlayer = findPlayer(args[2])  
                if targetPlayer then  
                    if not isConnected(targetPlayer) then  
                        table.insert(ConnectedUsers, targetPlayer)  
                        sendMessage("Connected '" .. targetPlayer.Name .. "'. They can now use commands.")  
                    else  
                        sendMessage("'" .. targetPlayer.Name .. "' is already connected.")  
                    end  
                else  
                    sendMessage("Player '" .. args[2] .. "' not found.")  
                end  
            else  
                sendMessage("Usage: connect <playername> (Main Connector only to add others)")  
            end  
        else  
            sendMessage("You are not the Main Connector. '" .. MainConnector.Name .. "' is currently the Main Connector.")  
        end  
        return -- Important: Don't let other commands process 'connect'  
    end  
    
    -- === .unconnect command (only MainConnector can use) ===  
    if command == ".unconnect" then  
        if player == MainConnector then  
            if args[2] then  
                local targetPlayer = findPlayer(args[2])  
                if targetPlayer then  
                    if targetPlayer == MainConnector then  
                        sendMessage("Cannot unconnect yourself (Main Connector). Use 'connect' again to reset.")  
                    else  
                        for i, connectedUser in ipairs(ConnectedUsers) do  
                            if connectedUser == targetPlayer then  
                                table.remove(ConnectedUsers, i)  
                                sendMessage("Disconnected '" .. targetPlayer.Name .. "'. They can no longer use commands.")  
                                return  
                            end  
                        end  
                        sendMessage("'" .. targetPlayer.Name .. "' is not currently connected.")  
                    end  
                else  
                    sendMessage("Player '" .. args[2] .. "' not found.")  
                end  
            else  
                sendMessage("Usage: .unconnect <playername>")  
            end  
        else  
            sendMessage("Only the Main Connector can use '.unconnect'.")  
        end  
        return -- Important: Don't let other commands process '.unconnect'  
    end  

    -- === Rest of the commands (only accessible by ConnectedUsers or MainConnector) ===  
    if not isConnected(player) then  
        sendMessage("You need to be connected to use commands. Type 'connect' to become the Main Connector.")  
        return -- Stop processing if not connected  
    end  
    
    if command == ".loop" then  
        if args[2] then  
            if args[2]:lower() == "clear" then  
                -- Clear all targets  
                table.clear(Targets)  
                sendMessage("All loop targets cleared.")  
                stopForceEquip()  
                unequipSword()  
            elseif args[2]:lower() == "list" then  
                -- List current targets  
                if #Targets > 0 then  
                    sendMessage("Current loop targets: " .. table.concat(Targets, ", "))  
                else  
                    sendMessage("No players currently in loop.")  
                end  
            else  
                addTarget(args[2])  
            end  
        else  
            sendMessage("Usage: .loop <playername> | .loop clear | .loop list")  
        end  
        
    elseif command == ".unloop" then  
        if args[2] then  
            removeTarget(args[2])  
        else  
            sendMessage("Usage: .unloop <playername>")  
        end  
        
    elseif command == ".aura" then  
        if args[2] then  
            local subCommand = args[2]:lower()  
            if subCommand == "whitelist" and args[3] then  
                addToWhitelist(args[3])  
            elseif subCommand == "unwhitelist" and args[3] then  
                removeFromWhitelist(args[3])  
            elseif subCommand == "list" then  
                if #Whitelist > 0 then  
                    sendMessage("Current whitelisted players: " .. table.concat(Whitelist, ", "))  
                else  
                    sendMessage("No players currently whitelisted.")  
                end  
            else  
                setAura(args[2]) -- Treat as range if not whitelist command  
            end  
        else  
            sendMessage("Usage: .aura <range> | .aura whitelist <playername> | .aura unwhitelist <playername> | .aura list")  
        end  
    end  
end)  

-- Initial message on script execution  
-- This will automatically make the first player to run it the Main Connector.  
task.spawn(function()  
    while not LP or not TextChatService.ChatInputBarConfiguration.TargetTextChannel do  
        task.wait(0.1) -- Wait for LocalPlayer and chat channel  
    end  
    -- Initial prompt for the user who loaded the script  
    sendMessage("Script Loaded! Type 'connect' to become the Main Connector and enable commands.")  
end)
