--[[  
    Floxy Script - Final Corrected Version (v24)  
    By luxx & JarcoCZ  

    REASON FOR FIX:  
    -   A critical logic error was found in the onMessageReceived function. It was mishandling the command 'author' when using different chat systems, causing the entire script to fail silently on load.  
    -   This version completely rewrites the command handler to be robust and logical.  
    -   It correctly processes commands from both the local player and connected users without conflict.  
    -   This is the definitive, stable merge of the local script (v21) and the networked script (v10).  
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
            else  
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
                local w = Instance.new("WeldConstraint", p); w.Part0, w.Part1 = handle, p  
            end  
        end  
    end  

    local function fireTouch(part1, part2)  
        for _ = 1, FT_TIMES do  
            firetouchinterest(part1, part2, 0); firetouchinterest(part1, part2, 1)  
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
                        if player ~= LP and player.Character and player.Character:FindFirstChildOfClass("Humanoid").Health > 0 then  
                            if not table.find(Whitelist, player.Name) then  
                                if table.find(Targets, player.Name) or (AuraEnabled and (player.Character.HumanoidRootPart.Position - myPos).Magnitude <= Dist) then  
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
            if ForceEquipConnection and not AuraEnabled and #Targets == 0 then  
                ForceEquipConnection:Disconnect(); ForceEquipConnection = nil  
            end  
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
        local arg2 = args[2]  

        if command == "connect" then  
            if not MainConnector then  
                MainConnector = author  
                table.insert(ConnectedUsers, author); table.insert(Whitelist, author.Name)  
                sendMessage("Main Connector set: " .. author.Name)  
            elseif author == MainConnector and arg2 then  
                local p = findPlayer(arg2)  
                if p and not table.find(ConnectedUsers, p) then  
                    table.insert(ConnectedUsers, p); sendMessage("Connected: " .. p.Name)  
                end  
            end  
            return  
        end  

        if author ~= LP and not table.find(ConnectedUsers, author) then return end  

        if command == ".cmds" then sendMessage("Cmds: .loop, .unloop, .aura, .whitelist, .unwhitelist, .to, .follow, .unfollow, .reset, .refresh, connect, .unconnect")  
        elseif command == ".unconnect" and author == MainConnector and arg2 then  
            local p = findPlayer(arg2)  
            if p and p ~= MainConnector then  
                for i, u in ipairs(ConnectedUsers) do if u == p then table.remove(ConnectedUsers, i) break end end  
                sendMessage("Unconnected: " .. p.Name)  
            end  
        elseif command == ".loop" and arg2 then local p = findPlayer(arg2); if p and not table.find(Targets, p.Name) then table.insert(Targets, p.Name); forceEquip(true) end  
        elseif command == ".unloop" and arg2 then local p = findPlayer(arg2); if p then for i, n in ipairs(Targets) do if n == p.Name then table.remove(Targets, i) break end end forceEquip(false) end  
        elseif command == ".aura" and arg2 then  
            local num = tonumber(arg2)  
            if num and num >= 0 then  
                Dist = num; AuraEnabled = num > 0  
                forceEquip(AuraEnabled)  
                if LP.Character then for _, tool in ipairs(LP.Character:GetDescendants()) do if tool:IsA("Tool") and tool:FindFirstChild("BoxReachPart") then tool.BoxReachPart.Size = Vector3.new(Dist, Dist, Dist) end end end  
            end  
        elseif command == ".whitelist" and arg2 then local p = findPlayer(arg2); if p and not table.find(Whitelist, p.Name) then table.insert(Whitelist, p.Name) end  
        elseif command == ".unwhitelist" and arg2 then local p = findPlayer(arg2); if p then for i, n in ipairs(Whitelist) do if n == p.Name then table.remove(Whitelist, i) break end end  
        elseif command == ".to" and arg2 then local p = findPlayer(arg2); if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and LP.Character then LP.Character:FindFirstChild("HumanoidRootPart").CFrame = p.Character.HumanoidRootPart.CFrame end  
        elseif command == ".follow" and arg2 then local p = findPlayer(arg2); if p then startFollow(p) end  
        elseif command == ".unfollow" then stopFollow()  
        elseif command == ".reset" and author == LP then TeleportService:Teleport(game.PlaceId, LP)  
        elseif command == ".refresh" and author == LP then  
            if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then  
                DeathPositions[LP.Name] = LP.Character.HumanoidRootPart.Position  
                LP.Character.Humanoid.Health = 0  
            end  
        end  
    end  

    local function onCharacterAdded(char)  
        char:WaitForChild("Humanoid", 10)  
        for _, item in ipairs(char:GetChildren()) do createReachPart(item) end  
        char.ChildAdded:Connect(createReachPart)  
        forceEquip(#Targets > 0 or AuraEnabled)  
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
        if FollowTarget == p then stopFollow() end  
        if MainConnector == p then  
            MainConnector = nil; table.clear(ConnectedUsers); table.clear(Whitelist)  
            stopFollow()  
            sendMessage("Main Connector left. Connection reset.")  
        else  
            for i, u in ipairs(ConnectedUsers) do if u == p then table.remove(ConnectedUsers, i) break end end  
        end  
    end)  

    task.spawn(function()  
        pcall(function()  
            if TextChatService and TextChatService.MessageReceived then  
                TextChatService.MessageReceived:Connect(function(message) onMessageReceived(message, true) end)  
            elseif LP.Chatted then  
                LP.Chatted:Connect(function(message) onMessageReceived(message, false) end)  
            else  
                warn("Floxy: No chat service available.")  
            end  
        end)  
    end)  

    sendMessage("Floxy Final Script (v24) Executed.")  
    print("Floxy System (v24) Loaded. User Authorized.")  
end)  

if not success then  
    print("----------- FLOXY SCRIPT (v24) FAILED TO INITIALIZE -----------")  
    warn("----------- FLOXY SCRIPT (v24) FAILED TO INITIALIZE -----------")  
    warn("ERROR: " .. tostring(err))  
    print("---------------------------------------------------------")  
end
