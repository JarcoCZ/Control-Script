local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TeleportService = game:GetService("TeleportService")
local LP = Players.LocalPlayer
local Dist = 0 -- Default disabled
local DistSq = Dist * Dist
local DMG_TIMES = 2
local FT_TIMES = 5
local A = {}
local K = {}
local Targets = {} -- Will store targeted players
local AuraEnabled = false
local ConnectedUsers = {} -- Store all connected users
local MainConnector = nil -- Store the main connector
local ForceEquipConnection = nil -- Store the force equip connection
local Whitelist = {} -- Store whitelisted players
local DeathPositions = {} -- Store death positions for refresh command

-- Authorized user IDs
local AuthorizedUsers = {
    1588706905,
    9167607498,
    7569689472
}

-- Function to send message to chat
local function sendMessage(message)
    if TextChatService.ChatInputBarConfiguration.TargetTextChannel then
        TextChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)
    end
end

-- Function to force equip sword
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

-- Function to unequip sword
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

-- Function to start force equip
local function startForceEquip()
    if ForceEquipConnection then
        ForceEquipConnection:Disconnect()
    end
    ForceEquipConnection = RunService.RenderStepped:Connect(forceEquip)
end

-- Function to stop force equip
local function stopForceEquip()
    if ForceEquipConnection then
        ForceEquipConnection:Disconnect()
        ForceEquipConnection = nil
    end
end

-- Check if user is authorized
local function isAuthorized(userId)
    for _, id in ipairs(AuthorizedUsers) do
        if userId == id then
            return true
        end
    end
    return false
end

-- Check if user is connected
local function isConnected(player)
    return table.find(ConnectedUsers, player) ~= nil
end

-- Add user to whitelist
local function addToWhitelist(playerName)
    local player = findPlayer(playerName)
    if player then
        if not table.find(Whitelist, player.Name) then
            table.insert(Whitelist, player.Name)
            return true
        end
    end
    return false
end

-- Remove user from whitelist
local function removeFromWhitelist(playerName)
    local player = findPlayer(playerName)
    if player then
        for i, whitelistName in ipairs(Whitelist) do
            if whitelistName == player.Name then
                table.remove(Whitelist, i)
                return true
            end
        end
    end
    return false
end

-- Command system
local function findPlayer(partialName)
    partialName = partialName:lower()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower():find(partialName, 1, true) then
            return player
        end
    end
    return nil
end

local function addTarget(playerName)
    local player = findPlayer(playerName)
    if player then
        if not table.find(Targets, player.Name) then
            table.insert(Targets, player.Name)
            -- Start force equip when targeting someone
            startForceEquip()
            return true
        end
    end
    return false
end

local function removeTarget(playerName)
    local player = findPlayer(playerName)
    if player then
        for i, targetName in ipairs(Targets) do
            if targetName == player.Name then
                table.remove(Targets, i)
                -- If no more targets, stop force equip and unequip sword
                if #Targets == 0 then
                    stopForceEquip()
                    unequipSword()
                end
                return true
            end
        end
    end
    return false
end

local function setAura(range)
    local newRange = tonumber(range)
    if newRange and newRange >= 0 then
        Dist = newRange
        DistSq = Dist * Dist
        AuraEnabled = Dist > 0
        
        -- Update existing box reach parts
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
    end
    return false
end

-- TextChatService message handler
local function onMessageReceived(message)
    local speaker = message.TextSource
    if not speaker then return end
    
    local player = Players:GetPlayerByUserId(speaker.UserId)
    if not player then return end
    
    local text = message.Text
    local args = text:split(" ")
    local command = args[1]:lower()
    
    -- Handle connection system
    if command == "connect" then
        if not MainConnector then
            MainConnector = player
            table.insert(ConnectedUsers, player)
            -- Automatically whitelist the main connector
            table.insert(Whitelist, player.Name)
            sendMessage("Connected With " .. player.Name)
        elseif player == MainConnector and args[2] then
            -- Main connector can connect other users
            local targetPlayer = findPlayer(args[2])
            if targetPlayer and not isConnected(targetPlayer) then
                table.insert(ConnectedUsers, targetPlayer)
                sendMessage("Connected With " .. targetPlayer.Name)
            end
        end
        return
    end
    
    -- Handle unconnect command (only main connector can use it)
    if command == ".unconnect" and player == MainConnector and args[2] then
        local targetPlayer = findPlayer(args[2])
        if targetPlayer and targetPlayer ~= MainConnector then
            for i, connectedUser in ipairs(ConnectedUsers) do
                if connectedUser == targetPlayer then
                    table.remove(ConnectedUsers, i)
                    break
                end
            end
        end
        return
    end
    
    -- Only allow commands if user is connected or is the script runner
    if player ~= LP and not isConnected(player) then return end
    
    -- Check if user is authorized (for script runner only)
    if player == LP and not isAuthorized(LP.UserId) then return end
    
    if command == ".loop" then
        if args[2] then
            addTarget(args[2])
        end
        
    elseif command == ".unloop" then
        if args[2] then
            removeTarget(args[2])
        end
        
    elseif command == ".aura" then
        if args[2] then
            if args[2]:lower() == "whitelist" and args[3] then
                addToWhitelist(args[3])
            elseif args[2]:lower() == "unwhitelist" and args[3] then
                removeFromWhitelist(args[3])
            else
                setAura(args[2])
            end
        end
        
    elseif command == ".reset" then
        -- Rejoin the game
        TeleportService:Teleport(game.PlaceId, LP)
        
    elseif command == ".refresh" then
        -- Kill the script runner and store death position
        local char = LP.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if hrp and humanoid then
                -- Store death position
                DeathPositions[LP.Name] = hrp.Position
                -- Kill the character
                humanoid.Health = 0
            end
        end
    end
end

-- Connect to TextChatService
TextChatService.MessageReceived:Connect(onMessageReceived)

local function CRB(x)
    if x:IsA("Tool") and x:FindFirstChild("Handle") then
        local h = x.Handle
        if not h:FindFirstChild("BoxReachPart") then
            local p = Instance.new("Part")
            p.Name = "BoxReachPart"
            p.Size = Vector3.new(Dist, Dist, Dist)
            p.Transparency = 1
            p.CanCollide = false
            p.Massless = true
            p.Parent = h
            local w = Instance.new("WeldConstraint")
            w.Part0 = h
            w.Part1 = p
            w.Parent = p
        end
    end
end

local function FT(a, b)
    for _ = 1, FT_TIMES do
        firetouchinterest(a, b, 0)
        firetouchinterest(a, b, 1)
    end
end

local function KL(p, t)
    if K[p] then return end
    K[p] = true
    while true do
        local lc = LP.Character
        local tc = p.Character
        if not (lc and tc) then break end
        local tw = lc:FindFirstChildWhichIsA("Tool")
        local th = tc:FindFirstChildOfClass("Humanoid")
        if not (tw and tw.Parent == lc and t.Parent and th and th.Health > 0) then break end
        for _, v in ipairs(tc:GetDescendants()) do
            if v:IsA("BasePart") then
                firetouchinterest(t, v, 0)
                firetouchinterest(t, v, 1)
            end
        end
        task.wait()
    end
    K[p] = nil
end

local function PC(c)
    for _, v in ipairs(c:GetDescendants()) do
        CRB(v)
    end
    c.ChildAdded:Connect(CRB)
end

local function MH(toolPart, plr)
    local c = plr.Character
    if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not (h and r and h.Health > 0) then return end
    pcall(function() 
        toolPart.Parent:Activate() 
    end)
    for _ = 1, DMG_TIMES do
        for _, v in ipairs(c:GetDescendants()) do
            if v:IsA("BasePart") then
                FT(toolPart, v)
            end
        end
    end
    task.spawn(function()
        KL(plr, toolPart)
    end)
end

local function HB()
    local c = LP.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = hrp.Position
    
    for _, t in ipairs(c:GetDescendants()) do
        if t:IsA("Tool") then
            local b = t:FindFirstChild("BoxReachPart") or t:FindFirstChild("Handle")
            if b then
                for _, p in ipairs(A) do
                    if p ~= LP and p.Character then
                        local rp = p.Character:FindFirstChild("HumanoidRootPart")
                        local hm = p.Character:FindFirstChildOfClass("Humanoid")
                        if rp and hm and hm.Health > 0 then
                            -- Check if player is whitelisted
                            local isWhitelisted = table.find(Whitelist, p.Name)
                            if isWhitelisted then
                                goto continue
                            end
                            
                            -- Check if player is targeted OR if aura is enabled and in range
                            local shouldTarget = table.find(Targets, p.Name)
                            
                            if not shouldTarget and AuraEnabled then
                                local d = rp.Position - pos
                                if d:Dot(d) <= DistSq then
                                    shouldTarget = true
                                end
                            end
                            
                            if shouldTarget then
                                MH(b, p)
                            end
                        end
                        ::continue::
                    end
                end
            end
        end
    end
end

local CN
local function SK()
    if CN then CN:Disconnect() end
    CN = RunService.Heartbeat:Connect(HB)
end

LP.CharacterAdded:Connect(function(c)
    c:WaitForChild("HumanoidRootPart", 10)
    c:WaitForChild("Humanoid")
    PC(c)
    SK()
    -- Re-equip sword on respawn if targeting someone
    if #Targets > 0 then
        forceEquip()
    end
    -- Teleport to death position if refresh was used
    if DeathPositions[LP.Name] then
        local hrp = c:WaitForChild("HumanoidRootPart", 10)
        if hrp then
            hrp.CFrame = CFrame.new(DeathPositions[LP.Name])
            DeathPositions[LP.Name] = nil -- Clear the stored position
        end
    end
end)

if LP.Character then
    PC(LP.Character)
    SK()
end

local function UP()
    table.clear(A)
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(A, p)
    end
end

Players.PlayerAdded:Connect(function(p)
    table.insert(A, p)
end)

Players.PlayerRemoving:Connect(function(p)
    -- Remove from connected users if they leave
    for i, connectedUser in ipairs(ConnectedUsers) do
        if connectedUser == p then
            table.remove(ConnectedUsers, i)
            break
        end
    end
    
    -- Reset main connector if they leave
    if MainConnector == p then
        MainConnector = nil
        table.clear(ConnectedUsers)
        table.clear(Whitelist)
    end
    
    -- Do not remove from whitelist if they leave (keep them whitelisted)
    
    -- Do not remove from targets if they leave (keep them targeted)
    
    -- Remove from player list
    for i, v in ipairs(A) do
        if v == p then
            table.remove(A, i)
            break
        end
    end
end)

UP()

-- Show initial message
sendMessage("Script Executed - Floxy")

-- Only show load message if user is authorized
if isAuthorized(LP.UserId) then
    print("System loaded")
end
