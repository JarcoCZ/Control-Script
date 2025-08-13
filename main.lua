--[[  
    Floxy Script - Merged & Finalized (v22)  
    By luxx & JarcoCZ  

    This version merges the multi-user "connect" logic from v10 into the robust v21 framework.  
    
    FEATURES:  
    -   All commands from both versions are present.  
    -   Includes the robust chat handler to prevent silent errors.  
    -   Maintains the local-mode commands (.reset, .refresh).  
    -   Adds multi-user commands (connect, .unconnect).  
    -   Adds MainConnector-relative commands (.to, .follow, .unfollow).  
    -   Cleaned up and consolidated for stability.  
]]  

-- ==================================  
-- ==      PROTECTED LOADER        ==  
-- ==================================  
local success, err = pcall(function()  

    -- Services  
    local Players = game:GetService("Players")  
    local RunService = game:GetService("RunService")  
    local TextChatService = game:GetService("TextChatService")  
    local TeleportService = game:GetService("TeleportService")  
    local ReplicatedStorage = game:GetService("ReplicatedStorage")  

    -- Local Player & Script-Wide Variables  
    local LP = Players.LocalPlayer  
    local KillStates = {}  
    local Targets = {}  
    local Whitelist = {}  
    local DeathPositions = {}  
    local FollowTarget = nil  
    local ForceEquipConnection = nil  
    local HeartbeatConnection = nil  
    local FollowConnection = nil  

    -- Networking Variables  
    local MainConnector = nil  
    local ConnectedUsers = {}  

    -- Configuration  
    local Dist = 0  
    local AuraEnabled = false  
    local DMG_TIMES = 2  
    local FT_TIMES = 5  

    -- Authorization  
    local AuthorizedUsers = { 1588706905, 9167607498, 7569689472 }  

    -- ==================================  
    -- ==      HELPER FUNCTIONS        ==  
    -- ==================================  

    if not table.find(AuthorizedUsers, LP.UserId) then  
        warn("Floxy Script: User not authorized. Halting execution.")  
        return  
    end  

    local function sendMessage(message)  
        pcall(function()  
            if TextChatService and TextChatService.ChatInputBarConfiguration then  
                TextChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)  
            else -- Fallback for older chat systems  
                ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(message, "All")  
            end  
        end)  
    end  

    local function findPlayer(partialName)  
        if not partialName then return nil end  
        local lowerName = tostring(partialName):lower()  
        if lowerName == "me" then return LP end  
        for _, player in ipairs(Players:GetPlayers()) do  
            if player.Name:lower():find(lowerName, 1, true) then  
                return player  
            end  
        end  
        return nil  
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
                local tool = toolPart and toolPart.Parent  
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

        for _, tool in ipairs(LP.Character:GetDescendants()) do  
            if tool:IsA("Tool") then  
                local hitbox = tool:FindFirstChild("BoxReachPart") or tool:FindFirstChild("Handle")  
                if hitbox then  
                    for _, player in ipairs(Players:GetPlayers()) do  
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
            if ForceEquipConnection then ForceEquipConnection:Disconnect(); ForceEquipConnection = nil end  
        end  
    end  
    
    local function stopFollow()  
        if FollowConnection then FollowConnection:Disconnect(); FollowConnection = nil end  
        FollowTarget = nil  
    end  

    local function startFollow(targetPlayer)  
        stopFollow()  
        FollowTarget = targetPlayer  
        FollowConnection = RunService.RenderStepped:Connect(function()  
            if FollowTarget and FollowTarget.Character and FollowTarget.Character:FindFirstChild("HumanoidRootPart") and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then  
                LP.Character.HumanoidRootPart.CFrame = FollowTarget.Character.HumanoidRootPart.CFrame * CFrame.new(0,0,5)  
            else  
                stopFollow()  
            end  
        end)  
    end  

    -- ==================================  
    -- ==      EVENT HANDLERS          ==  
    -- ==================================  

    local function onMessageReceived(messageData, isNewChat)  
        local text = isNewChat and messageData.Text or messageData  
        local author = isNewChat and messageData.TextSource and Players:GetPlayerByUserId(messageData.TextSource.UserId) or LP  
        if not text or not author then return end  
        
        local args = text:split(" ")  
        local command = args[1]:lower()  
        local arg2 = args[2] or nil  
        
        -- Networking Commands  
        if command == "connect" then  
            if not MainConnector then  
                MainConnector = author  
                table.insert(ConnectedUsers, author)  
                table.insert(Whitelist, author.Name)  
                sendMessage("Main Connector set to: " .. author.Name)  
            elseif author == MainConnector and arg2 then  
                local p = findPlayer(arg2)  
                if p and not table.find(ConnectedUsers, p) then  
                    table.insert(ConnectedUsers, p)  
                    sendMessage("Connected user: " .. p.Name)  
                end  
            end  
            return -- End here for connect command  
        end  

        -- Check if user is authorized to run commands  
        if author ~= LP and not table.find(ConnectedUsers, author) then  
            return  
        end  

        -- Main Commands  
        if command == ".cmds" then sendMessage("Cmds: .loop, .unloop, .aura, .whitelist, .unwhitelist, .to, .follow, .unfollow, .reset, .refresh, connect, .unconnect") end  
        if command == ".unconnect" and author == MainConnector and arg2 then  
            local p = findPlayer(arg2)  
            if p and p ~= MainConnector then  
                for i, user in ipairs(ConnectedUsers) do if user == p then table.remove(ConnectedUsers, i); break end end  
                sendMessage("Unconnected: " .. p.Name)  
            end  
        end  
        if command == ".reset" and author == LP then TeleportService:Teleport(game.PlaceId, LP) end  
        if command == ".refresh" and author == LP then  
            if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then  
                DeathPositions[LP.Name] = LP.Character.HumanoidRootPart.Position  
                LP.Character.Humanoid.Health = 0  
            end  
        end  
        if command == ".loop" and arg2 then local p = findPlayer(arg2); if p and not table.find(Targets, p.Name) then table.insert(Targets, p.Name); forceEquip(true) end end  
        if command == ".unloop" and arg2 then local p = findPlayer(arg2); if p then for i, name in ipairs(Targets) do if name == p.Name then table.remove(Targets, i); break end end; if #Targets == 0 and not AuraEnabled then forceEquip(false) end end  
        if command == ".aura" and arg2 then  
            local newRange = tonumber(arg2)  
            if newRange and newRange >= 0 then  
                Dist = newRange; AuraEnabled = newRange > 0  
                if AuraEnabled then forceEquip(true) elseif #Targets == 0 then forceEquip(false) end  
                if LP.Character then for _, tool in ipairs(LP.Character:GetDescendants()) do if tool:IsA("Tool") and tool:FindFirstChild("BoxReachPart") then tool.BoxReachPart.Size = Vector3.new(Dist, Dist, Dist) end end end  
            end  
        end  
		if command == ".whitelist" and arg2 then local p = findPlayer(arg2); if p and not table.find(Whitelist, p.Name) then table.insert(Whitelist, p.Name) end end  
		if command == ".unwhitelist" and arg2 then local p = findPlayer(arg2); if p then for i, n in ipairs(Whitelist) do if n == p.Name then table.remove(Whitelist, i); break end end end  
        if command == ".to" and arg2 then -- Teleport to any specified player  
            local p = findPlayer(arg2); if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then LP.Character.HumanoidRootPart.CFrame = p.Character.HumanoidRootPart.CFrame end  
        end  
        if command == ".follow" and arg2 then -- Follow any specified player  
            local p = findPlayer(arg2); if p then startFollow(p) end  
        end  
        if command == ".unfollow" then  
            stopFollow()  
        end  
    end  

    local function onCharacterAdded(char)  
        char:WaitForChild("Humanoid", 10)  
        for _, item in ipairs(char:GetChildren()) do createReachPart(item) end  
        char.ChildAdded:Connect(createReachPart)  
        if #Targets > 0 or AuraEnabled then forceEquip(true) end  
        if DeathPositions[LP.Name] then  
            local hrp = char:WaitForChild("HumanoidRootPart", 10)  
            if hrp then task.wait(0.5); hrp.CFrame = CFrame.new(DeathPositions[LP.Name]); DeathPositions[LP.Name] = nil end  
        end  
        if not HeartbeatConnection or not HeartbeatConnection.Connected then  
            HeartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)  
        end  
    end  

    -- ==================================  
    -- ==      INITIALIZATION          ==  
    -- ==================================  

    LP.CharacterAdded:Connect(onCharacterAdded)  
    if LP.Character then onCharacterAdded(LP.Character) end  
    
    Players.PlayerRemoving:Connect(function(p)  
        for i, user in ipairs(ConnectedUsers) do if user == p then table.remove(ConnectedUsers, i); break end end  
        if MainConnector == p then  
            MainConnector = nil; table.clear(ConnectedUsers); table.clear(Whitelist)  
            stopFollow()  
            sendMessage("Main Connector has left. Connection reset.")  
        end  
        if FollowTarget == p then stopFollow() end  
    end)  

    -- ROBUST CHAT INITIALIZER  
    task.spawn(function()  
        local chatSuccess, _ = pcall(function()  
            if TextChatService and TextChatService.MessageReceived then  
                TextChatService.MessageReceived:Connect(function(message) onMessageREDDIT SUX(message, true) end)  
            elseif LP.Chatted then  
                LP.Chatted:Connect(function(message) onMessageReceived(message, false) end)  
            else  
                 warn("Floxy: No chat service found.")  
            end  
        end)  
        if not chatSuccess then warn("Floxy: Could not connect to any chat service.") end  
    end)  

    sendMessage("Floxy Merged Script (v22) Executed.")  
    print("Floxy System (v22) Loaded. User Authorized.")  
end)  

if not success then  
    print("----------- FLOXY SCRIPT (v22) FAILED TO INITIALIZE -----------")  
    warn("----------- FLOXY SCRIPT (v22) FAILED TO INITIALIZE -----------")  
    warn("ERROR: " .. tostring(err))  
    print("---------------------------------------------------------")  
end
