-- // Services Setup
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- ZHM HUB - SHARED UI / COMPATIBILITY HELPERS
--------------------------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G
local controller = { CancelGeneration = 0 }
ENV.ZHM_Controller = controller
ENV.ZHM_AutoWalk = true
ENV.ZHM_AutoFarm = false
ENV.ZHM_AutoBuy = false
ENV.ZHM_AutoUpgrade = false
local TP_DELAY = 1 -- 1 second between movement teleports.
if ENV.ZHM_AutoNearestPrompt == nil then ENV.ZHM_AutoNearestPrompt = false end -- Day default; night controller enables it automatically.
-- Combined side-job modules. Defaults preserve the two standalone scripts.
if ENV.ZHM_AutoSweep == nil then ENV.ZHM_AutoSweep = true end
ENV.ZHM_NPCAutoTP = false -- Auto TP removed; scanner is used only for Rolling Pin swing.
if ENV.ZHM_NPCAutoSwing == nil then ENV.ZHM_NPCAutoSwing = true end
ENV.ZHM_SweepActive = false
ENV.ZHM_NPCBusy = false
ENV.ZHM_NPCStatus = "Swing scanner idle"
ENV.ZHM_SweepStatus = "Waiting"
if type(ENV.CashierAutoAccept) == "table" then
    ENV.CashierAutoAccept.Enabled = false
    ENV.CashierAutoAccept = nil
end

local THEME = {
    Background  = Color3.fromRGB(13, 14, 22),
    Surface     = Color3.fromRGB(20, 22, 34),
    Surface2    = Color3.fromRGB(28, 30, 46),
    Surface3    = Color3.fromRGB(38, 41, 61),
    Accent      = Color3.fromRGB(124, 58, 237),  -- Vibrant Violet
    Accent2     = Color3.fromRGB(6, 182, 212),    -- Electric Cyan
    Success     = Color3.fromRGB(16, 185, 129),
    Danger      = Color3.fromRGB(239, 68, 68),
    Warning     = Color3.fromRGB(245, 158, 11),
    Text        = Color3.fromRGB(248, 250, 252),
    Muted       = Color3.fromRGB(148, 163, 184),
    Stroke      = Color3.fromRGB(51, 65, 85)
}


local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 10)
    corner.Parent = parent
    return corner
end

local function addStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or THEME.Stroke
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

local function addGradient(parent, colorA, colorB, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, colorA),
        ColorSequenceKeypoint.new(1, colorB)
    })
    gradient.Rotation = rotation or 0
    gradient.Parent = parent
    return gradient
end

local function getGuiParents()
    local parents = {}
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then
            table.insert(parents, hui)
        end
    end
    table.insert(parents, CoreGui)
    table.insert(parents, playerGui)
    return parents
end

local function destroyNamedGui(name)
    for _, parent in ipairs(getGuiParents()) do
        pcall(function()
            local existing = parent:FindFirstChild(name)
            if existing then
                existing:Destroy()
            end
        end)
    end
end

local function mountGui(gui)
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then
            local mounted = pcall(function() gui.Parent = hui end)
            if mounted and gui.Parent then return gui.Parent end
        end
    end

    local mounted = pcall(function() gui.Parent = CoreGui end)
    if not mounted or not gui.Parent then
        gui.Parent = playerGui
    end

    return gui.Parent
end

local function bindPressAnimation(button, hoverColor)
    if not button or not button:IsA("GuiButton") then return end

    button.AutoButtonColor = false
    local pressScale = Instance.new("UIScale")
    pressScale.Name = "PressScale"
    pressScale.Scale = 1
    pressScale.Parent = button

    local baseColor = button.BackgroundColor3

    button.MouseEnter:Connect(function()
        if hoverColor then button.BackgroundColor3 = hoverColor end
    end)

    button.MouseLeave:Connect(function()
        if hoverColor then button.BackgroundColor3 = baseColor end
        pressScale.Scale = 1
    end)

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressScale.Scale = 0.95
        end
    end)

    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressScale.Scale = 1
        end
    end)
end

local function makeDraggable(handle, target)
    target = target or handle
    local dragging = false
    local dragInput, dragStart, startPosition

    handle.Active = true

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = target.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart and startPosition then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

local function applyResponsiveScale(scaleObject, baseWidth, baseHeight)
    local function update()
        local camera = Workspace.CurrentCamera
        if not camera then return end

        local viewport = camera.ViewportSize
        local widthScale = viewport.X / (baseWidth or 420)
        local heightScale = viewport.Y / (baseHeight or 520)
        local scale = math.clamp(math.min(widthScale, heightScale, 1), 0.55, 1)

        scaleObject.Scale = scale
        scaleObject:SetAttribute("ResponsiveScale", scale)
    end

    update()

    if Workspace.CurrentCamera then
        Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
    end

    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        task.wait()
        update()
    end)

    return update
end

--------------------------------------------------------------------------------
-- 0. KEYLESS START
-- Key UI / validation removed. Script continues immediately on execute.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STATIONARY AUTOMATION (OPTIMIZED FOR NO DELAY)
--------------------------------------------------------------------------------
ENV.ZHM_AutoFarm = ENV.ZHM_AutoFarm == true
ENV.ZHM_AutoBuy = ENV.ZHM_AutoBuy == true
ENV.ZHM_AutoUpgrade = ENV.ZHM_AutoUpgrade == true
for _, key in ipairs({ "ZHM_AutoAccept", "ZHM_AutoPrepareDough", "ZHM_AutoBake", "ZHM_AutoCollect", "ZHM_AutoCollectTip", "ZHM_AutoGiveOrder", "ZHM_AutoEnableBreads", "ZHM_HidePopups" }) do
    if ENV[key] == nil then ENV[key] = true end
end
ENV.ZHM_PlotName = ENV.ZHM_PlotName or "Plot4"
ENV.ZHM_FeatureStatus = {}

local function isCurrent()
    return ENV.ZHM_Controller == controller
end

local function running(key)
    if not isCurrent() or ENV[key] ~= true then
        return false
    end

    -- Trash sweeping owns movement/interaction while an actionable sweep prompt exists.
    -- Toggle values are NOT changed; jobs simply pause and automatically resume afterward.
    if ENV.ZHM_SweepActive == true then
        return false
    end

    -- NPC scanner never owns movement in swing-only mode.
    -- Rack movement remains independent because NPC teleporting has been removed.

    return true
end

local function farming(key)
    return running("ZHM_AutoFarm") and ENV[key] == true
end

local notices = {}
local function report(feature, message)
    if not isCurrent() then return end
    ENV.ZHM_FeatureStatus[feature] = message
    local last = notices[feature]
    if not last or os.clock() - last >= 20 then
        notices[feature] = os.clock()
        warn("[ZHM/" .. feature .. "] " .. message)
    end
end

local function resolve(root, names)
    for _, name in ipairs(names) do
        root = root and root:FindFirstChild(name)
        if not root then return nil end
    end
    return root
end

local function ui(names)
    return resolve(player:FindFirstChildOfClass("PlayerGui"), names)
end

local function findMyPlot()
    local shops = resolve(Workspace, { "Game", "Shops" })
    if not shops then return nil end

    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    local closestPlot = nil
    local shortestDist = math.huge

    for _, plot in ipairs(shops:GetChildren()) do
        local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")
        if owner and owner:IsA("ValueBase") then
            if owner.Value == player or owner.Value == player.Name or owner.Value == player.UserId then
                return plot
            end
        end

        if plot:GetAttribute("OwnerUserId") == player.UserId then
            return plot
        end

        if rootPart then
            local anyPart = plot:FindFirstChildWhichIsA("BasePart", true)
            if anyPart then
                local dist = (rootPart.Position - anyPart.Position).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    closestPlot = plot
                end
            end
        end
    end

    return shops:FindFirstChild(ENV.ZHM_PlotName) or closestPlot
end

--------------------------------------------------------------------------------
-- INSTANT TP / RACK MOVEMENT
-- All rack-route tween/Lerp movement has been replaced with direct CFrame TP.
--------------------------------------------------------------------------------
local function getPartFromContainer(container)
    if not container then return nil end
    if container:IsA("BasePart") then return container end
    if container:IsA("Model") and container.PrimaryPart then return container.PrimaryPart end
    return container:FindFirstChildWhichIsA("BasePart", true)
end

local function getDisplayRackPos(plot)
    if not plot then return nil end
    local equipment = plot:FindFirstChild("Equipment") or plot

    for _, desc in ipairs(equipment:GetDescendants()) do
        local lowerName = desc.Name:lower()
        if lowerName:find("displayrack", 1, true) or lowerName:find("display", 1, true) then
            local part = getPartFromContainer(desc)
            if part then return part.Position end
        end
    end

    return nil
end

-- Dough PrepTable destination used at the end of every rack route.
local function getPrepTablePos(plot)
    if not plot then return nil end

    -- Known game path first.
    local position = plot:FindFirstChild("Position")
    local prepTable = position and position:FindFirstChild("PrepTable")
    if prepTable then
        local part = getPartFromContainer(prepTable)
        if part then return part.Position end
    end

    -- Compatibility fallback for renamed/nested PrepTable objects.
    for _, desc in ipairs(plot:GetDescendants()) do
        local lowerName = string.lower(desc.Name or "")
        if lowerName == "preptable"
            or lowerName:find("preptable", 1, true)
            or lowerName:find("doughprep", 1, true) then
            local part = getPartFromContainer(desc)
            if part then return part.Position end
        end
    end

    -- Final fallback: use the PrepTablePrompt's parent part/model.
    local prompt = plot:FindFirstChild("PrepTablePrompt", true)
    if prompt then
        local part = getPartFromContainer(prompt.Parent)
        if part then return part.Position end
    end

    return nil
end

local function getAllBakingRacks(plot)
    if not plot then return {} end
    local equipment = plot:FindFirstChild("Equipment") or plot
    local racks = {}
    local seenParts = {}

    for _, desc in ipairs(equipment:GetDescendants()) do
        local lowerName = desc.Name:lower()
        if (lowerName:find("bakingrack", 1, true) or lowerName:find("normalbakingrack", 1, true))
            and not lowerName:find("prompt", 1, true) then
            local part = getPartFromContainer(desc)
            if part and not seenParts[part] then
                seenParts[part] = true
                table.insert(racks, { instance = desc, part = part, position = part.Position })
            end
        end
    end

    return racks
end

local function teleportToPosition(targetPos)
    if not running("ZHM_AutoWalk") then return false end

    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    rootPart.CFrame = CFrame.new(targetPos) * rootPart.CFrame.Rotation
    return true
end

local function startAutoWalk()
    task.spawn(function()
        local visitedRacks = {}

        while isCurrent() do
            if running("ZHM_AutoWalk") then
                local myPlot = findMyPlot()

                if myPlot then
                    local allRacks = getAllBakingRacks(myPlot)
                    local unvisitedRacks = {}

                    for _, rack in ipairs(allRacks) do
                        if not visitedRacks[rack.instance] then
                            table.insert(unvisitedRacks, rack)
                        end
                    end

                    if #unvisitedRacks > 0 then
                        local char = player.Character
                        local rootPart = char and char:FindFirstChild("HumanoidRootPart")

                        if rootPart then
                            table.sort(unvisitedRacks, function(a, b)
                                return (rootPart.Position - a.position).Magnitude < (rootPart.Position - b.position).Magnitude
                            end)
                        end

                        local nextRack = unvisitedRacks[1]
                        visitedRacks[nextRack.instance] = true

                        report("AutoWalk", "TP to BakingRack: " .. nextRack.instance.Name)
                        if teleportToPosition(nextRack.position + Vector3.new(0, 2.5, 0))
                            and running("ZHM_AutoWalk") then
                            task.wait(TP_DELAY)
                        end
                    else
                        local displayPos = getDisplayRackPos(myPlot)

                        if displayPos then
                            report("AutoWalk", "TP to DisplayRack...")
                            if teleportToPosition(displayPos + Vector3.new(0, 2.5, 0))
                                and running("ZHM_AutoWalk") then
                                -- Stay at the DisplayRack for exactly 10 seconds.
                                task.wait(10)

                                -- After DisplayRack, TP to the Dough PrepTable before
                                -- resetting the rack route and starting the next loop.
                                if running("ZHM_AutoWalk") then
                                    local prepPos = getPrepTablePos(myPlot)
                                    if prepPos then
                                        report("AutoWalk", "DisplayRack complete • TP to Dough PrepTable...")
                                        if teleportToPosition(prepPos + Vector3.new(0, 2.5, 0))
                                            and running("ZHM_AutoWalk") then
                                            task.wait(TP_DELAY)
                                        end
                                    else
                                        report("AutoWalk", "Dough PrepTable not found; restarting rack route.")
                                        task.wait(0.25)
                                    end
                                end
                            end
                        else
                            task.wait(0.5)
                        end

                        -- Full route repeats:
                        -- BakingRacks -> DisplayRack (10s) -> Dough PrepTable -> BakingRacks...
                        visitedRacks = {}
                    end
                else
                    task.wait(0.5)
                end
            else
                visitedRacks = {}
                task.wait(0.5)
            end

            task.wait(0.05)
        end
    end)
end

startAutoWalk()

--------------------------------------------------------------------------------
-- AUTOMATION HELPERS
--------------------------------------------------------------------------------
local function binding(container)
    if not container then return nil end
    assert(type(getconnections) == "function", "getconnections unavailable")
    local buttons = {}
    if container:IsA("GuiButton") then buttons[#buttons + 1] = container end
    for _, child in ipairs(container:GetDescendants()) do
        if child:IsA("GuiButton") then buttons[#buttons + 1] = child end
    end
    for _, button in ipairs(buttons) do
        for _, event in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Up", "MouseButton1Down" }) do
            local active = {}
            for _, connection in ipairs(getconnections(button[event])) do
                if connection.Enabled ~= false and connection.ForeignState ~= true
                    and connection.LuaConnection ~= false then
                    active[#active + 1] = connection
                end
            end
            if #active > 0 then return { Button = button, Event = event, Connections = active } end
        end
    end
end

local function triggerButton(container, feature)
    if not isCurrent() then return false end
    local target = binding(container)
    if not target then
        report(feature, "Button missing or no supported active handler exposed.")
        return false
    end
    local args = table.pack()
    if target.Event == "Activated" then
        args = table.pack(nil, 1)
    elseif target.Event == "MouseButton1Down" or target.Event == "MouseButton1Up" then
        local center = target.Button.AbsolutePosition + target.Button.AbsoluteSize / 2
        args = table.pack(center.X, center.Y)
    end
    local canFire = true
    for _, connection in ipairs(target.Connections) do
        if type(connection.Fire) ~= "function" then canFire = false end
    end
    if canFire then
        for _, connection in ipairs(target.Connections) do
            if not isCurrent() then return false end
            connection:Fire(table.unpack(args, 1, args.n))
        end
    elseif type(firesignal) == "function" then
        firesignal(target.Button[target.Event], table.unpack(args, 1, args.n))
    else
        error("Neither Connection:Fire nor firesignal is available")
    end
    return true
end

local function firePromptSafe(prompt, feature)
    if not isCurrent() then return false end
    if not prompt or not prompt:IsA("ProximityPrompt") then
        report(feature, "Prompt missing on the configured plot.")
        return false
    end
    if not prompt.Enabled then return false end
    if type(fireproximityprompt) ~= "function" then
        report(feature, "fireproximityprompt unavailable.")
        return false
    end
    fireproximityprompt(prompt)
    return true
end

--------------------------------------------------------------------------------
-- AUTO PRESS NEAREST CLICKABLE PROMPT
-- Supports both ProximityPrompt and ClickDetector and only fires the nearest
-- usable interaction anywhere in Workspace, choosing the closest to the player.
--------------------------------------------------------------------------------
local AUTO_NEAREST_ACTIVATION_DISTANCE = 1000000000 -- practical unlimited range
local AUTO_NEAREST_SCAN_DELAY = 0.08
local AUTO_NEAREST_COOLDOWN = 0.35

local nearestInteractions = setmetatable({}, { __mode = "k" })
local nearestLastFire = setmetatable({}, { __mode = "k" })

local function registerNearestInteraction(obj)
    if obj and (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")) then
        nearestInteractions[obj] = true
    end
end

for _, obj in ipairs(Workspace:GetDescendants()) do
    registerNearestInteraction(obj)
end

Workspace.DescendantAdded:Connect(registerNearestInteraction)
Workspace.DescendantRemoving:Connect(function(obj)
    nearestInteractions[obj] = nil
    nearestLastFire[obj] = nil
end)

local function getNearestInteractionPart(interaction)
    if not interaction then return nil end

    local current = interaction.Parent
    while current and current ~= Workspace do
        if current:IsA("Attachment") then
            local parent = current.Parent
            if parent and parent:IsA("BasePart") then return parent end
        elseif current:IsA("BasePart") then
            return current
        elseif current:IsA("Model") then
            local part = current.PrimaryPart
                or current:FindFirstChild("HumanoidRootPart")
                or current:FindFirstChildWhichIsA("BasePart", true)
            if part then return part end
        end
        current = current.Parent
    end

    return nil
end

local function nearestInteractionAllowed(interaction, distance)
    if not interaction or not interaction.Parent then return false end
    -- No distance cap: the nearest valid interaction can be anywhere in Workspace.

    if interaction:IsA("ProximityPrompt") then
        return interaction.Enabled == true
    end

    if interaction:IsA("ClickDetector") then
        return true
    end

    return false
end

local function getNearestClickableInteraction()
    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    local closest = nil
    local closestDistance = math.huge

    for interaction in pairs(nearestInteractions) do
        if interaction and interaction.Parent then
            local part = getNearestInteractionPart(interaction)
            if part then
                local distance = (rootPart.Position - part.Position).Magnitude
                if distance < closestDistance
                    and nearestInteractionAllowed(interaction, distance) then
                    closest = interaction
                    closestDistance = distance
                end
            end
        else
            nearestInteractions[interaction] = nil
            nearestLastFire[interaction] = nil
        end
    end

    return closest, closestDistance
end

local function pressNearestClickableInteraction(interaction)
    if not interaction or not interaction.Parent then return false end

    local now = os.clock()
    if now - (nearestLastFire[interaction] or 0) < AUTO_NEAREST_COOLDOWN then
        return false
    end

    if interaction:IsA("ProximityPrompt") then
        if not interaction.Enabled or type(fireproximityprompt) ~= "function" then
            return false
        end

        pcall(function() interaction.HoldDuration = 0 end)
        pcall(function() interaction.RequiresLineOfSight = false end)
        pcall(function()
            interaction.MaxActivationDistance = math.max(interaction.MaxActivationDistance, AUTO_NEAREST_ACTIVATION_DISTANCE)
        end)

        -- Try the most aggressive instant form first, then executor-compatible fallbacks.
        local ok = pcall(function() fireproximityprompt(interaction, 0, true) end)
        if not ok then
            ok = pcall(function() fireproximityprompt(interaction, 0) end)
        end
        if not ok then
            ok = pcall(function() fireproximityprompt(interaction) end)
        end

        if ok then
            nearestLastFire[interaction] = now
            return true
        end
    elseif interaction:IsA("ClickDetector") then
        if type(fireclickdetector) ~= "function" then return false end

        pcall(function()
            interaction.MaxActivationDistance = math.max(interaction.MaxActivationDistance, AUTO_NEAREST_ACTIVATION_DISTANCE)
        end)

        local ok = pcall(function() fireclickdetector(interaction) end)
        if ok then
            nearestLastFire[interaction] = now
            return true
        end
    end

    return false
end

local function autoNearestPromptEnabled()
    -- IMPORTANT: do not use running() here. running() intentionally pauses jobs
    -- while ZHM_SweepActive is true, but nearest prompt pressing must stay alive
    -- during night sweeping so sweep/nearby prompts can still fire instantly.
    return isCurrent() and ENV.ZHM_AutoNearestPrompt == true
end

local function startAutoNearestPrompt()
    task.spawn(function()
        while isCurrent() do
            if autoNearestPromptEnabled() then
                local interaction = getNearestClickableInteraction()
                if interaction then
                    pressNearestClickableInteraction(interaction)
                end
            end
            task.wait(AUTO_NEAREST_SCAN_DELAY)
        end
    end)
end

startAutoNearestPrompt()

local function sortedChildren(container)
    local children = container:GetChildren()
    table.sort(children, function(a, b) return a.Name < b.Name end)
    return children
end

local customerIndex = 0
local function autoAccept()
    local body = ui({ "MainUI", "Cashier", "Frame", "Body" })
    local accept = resolve(body, { "Actions", "AcceptButton" })
    if not binding(accept) then report("Accept", "Cashier Accept handler unavailable."); return end
    local rows = body:FindFirstChild("OrdersRow")
    local candidates = {}
    if rows then
        for _, row in ipairs(sortedChildren(rows)) do
            if row.Name:match("^Customer%d+$") then candidates[#candidates + 1] = row end
        end
    end
    if #candidates > 0 then
        customerIndex = customerIndex % #candidates + 1
        if not triggerButton(candidates[customerIndex], "Accept") then return end
        task.wait()
        if not farming("ZHM_AutoAccept") then return end
    end
    accept = ui({ "MainUI", "Cashier", "Frame", "Body", "Actions", "AcceptButton" })
    if triggerButton(accept, "Accept") then report("Accept", "Accept handler dispatched.") end
end

local function autoPrepareDough()
    local plot = findMyPlot()
    local prompt = resolve(plot, { "Position", "PrepTable", "PrepTablePrompt" })
        or (plot and plot:FindFirstChild("PrepTablePrompt", true))
    if firePromptSafe(prompt, "Dough") then report("Dough", "Prepare Dough prompt dispatched.") end
end

local bakeIndex = 0
local function bakeAllBreads()
    local list = ui({ "MainUI", "BakeSelect", "Frame", "ScrollingFrame" })
    if not list then report("Bake", "BakeSelect handlers unavailable; waiting for game initialization."); return end
    local candidates = {}
    for _, row in ipairs(sortedChildren(list)) do
        local button = resolve(row, { "Main_Frame", "Buttons", "Bake" })
        if button then candidates[#candidates + 1] = button end
    end
    for _ = 1, #candidates do
        bakeIndex = bakeIndex % #candidates + 1
        local button = candidates[bakeIndex]
        if binding(button) and triggerButton(button, "Bake") then
            report("Bake", "Bake handler dispatched.")
            return
        end
    end
    report("Bake", "No supported Bake handlers found.")
end

local enabledBreadButtons = setmetatable({}, { __mode = "k" })
local function autoEnableBreads()
    local list = ui({ "MainUI", "Breads", "Frame", "ScrollingFrame" })
    if not list then report("Breads", "Bread Enable controls unavailable."); return end
    for _, row in ipairs(sortedChildren(list)) do
        if not farming("ZHM_AutoEnableBreads") then return end
        local button = resolve(row, { "Main_Frame", "Buttons", "Enable" })
        if button and not enabledBreadButtons[button] and (not button:IsA("GuiObject") or button.Visible) then
            if triggerButton(button, "Breads") then enabledBreadButtons[button] = true end
            task.wait()
        end
    end
end

-- AUTO GIVE ORDER: separate delivery logic from Auto Collect.
-- This catches prompts whose ActionText changes dynamically to "Give Order",
-- plus common delivery prompt names such as RackDeliverPrompt / DeliverPrompt.
local function isGiveOrderPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then
        return false
    end

    local name = string.lower(prompt.Name or "")
    local action = string.lower(tostring(prompt.ActionText or ""))
    local objectText = string.lower(tostring(prompt.ObjectText or ""))

    return action == "give order"
        or action:find("give order", 1, true) ~= nil
        or action == "deliver"
        or action:find("deliver order", 1, true) ~= nil
        or name == "rackdeliverprompt"
        or name == "deliverprompt"
        or name == "giveorderprompt"
        or name:find("giveorder", 1, true) ~= nil
        or name:find("deliver", 1, true) ~= nil
        or objectText:find("give order", 1, true) ~= nil
end

local function fireGiveOrderPrompt(prompt)
    if not farming("ZHM_AutoGiveOrder") then return false end
    if not prompt or not prompt.Parent or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end
    if not isGiveOrderPrompt(prompt) then return false end
    if type(fireproximityprompt) ~= "function" then
        report("GiveOrder", "fireproximityprompt unavailable.")
        return false
    end

    -- Make the delivery prompt easy to trigger when the rack route reaches it.
    pcall(function() prompt.HoldDuration = 0 end)
    pcall(function() prompt.RequiresLineOfSight = false end)
    pcall(function() prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 35) end)

    local ok = pcall(function()
        fireproximityprompt(prompt, 0)
    end)
    if not ok then
        ok = pcall(function()
            fireproximityprompt(prompt)
        end)
    end
    return ok
end

local giveOrderCache = {}
local giveOrderCachePlot = nil
local giveOrderNextScan = 0

local function getGiveOrderPrompts(plot)
    local now = os.clock()
    local needScan = plot ~= giveOrderCachePlot or now >= giveOrderNextScan

    if not needScan then
        for _, prompt in ipairs(giveOrderCache) do
            if not prompt or not prompt.Parent then
                needScan = true
                break
            end
        end
    end

    if needScan then
        giveOrderCachePlot = plot
        giveOrderNextScan = now + 0.20
        giveOrderCache = {}

        if plot then
            for _, obj in ipairs(plot:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and isGiveOrderPrompt(obj) then
                    giveOrderCache[#giveOrderCache + 1] = obj
                end
            end
        end
    end

    return giveOrderCache
end

local function autoGiveOrder()
    if not farming("ZHM_AutoGiveOrder") then return end

    local plot = findMyPlot()
    if not plot then
        report("GiveOrder", "Waiting for your plot.")
        return
    end

    local prompts = getGiveOrderPrompts(plot)
    local fired = 0

    for _, prompt in ipairs(prompts) do
        if not farming("ZHM_AutoGiveOrder") then return end
        if prompt and prompt.Parent and prompt.Enabled and isGiveOrderPrompt(prompt) then
            if fireGiveOrderPrompt(prompt) then
                fired += 1
            end
            task.wait(0.02)
        end
    end

    if fired > 0 then
        report("GiveOrder", "Give Order dispatched on " .. tostring(fired) .. " prompt(s).")
    end
end

-- AUTO COLLECT TIP: dedicated Tip Jar collection logic.
-- This is separate from BakingRack Auto Collect because Tip Jar prompts/clicks
-- are a different interaction and may only become enabled when tips are ready.
local function normalizedCompactText(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-]+", "")
end

local function objectLooksLikeTipJar(obj, stopAt)
    local current = obj
    while current and current ~= stopAt do
        local compact = normalizedCompactText(current.Name)
        if compact == "tip"
            or compact == "tips"
            or compact:find("tipjar", 1, true)
            or compact:find("tipbox", 1, true)
            or compact:find("tipmoney", 1, true) then
            return true
        end
        current = current.Parent
    end
    return false
end

local function isTipPrompt(prompt, plot)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end

    local name = normalizedCompactText(prompt.Name)
    local action = normalizedCompactText(prompt.ActionText)
    local objectText = normalizedCompactText(prompt.ObjectText)
    local ancestryLooksLikeTip = objectLooksLikeTipJar(prompt.Parent, plot and plot.Parent)

    local mentionsTip = name:find("tip", 1, true) ~= nil
        or action:find("tip", 1, true) ~= nil
        or objectText:find("tip", 1, true) ~= nil
        or ancestryLooksLikeTip

    if not mentionsTip then return false end

    -- If it lives under a TipJar object, allow the prompt even when the game uses a
    -- generic ActionText such as "Collect". Otherwise require tip/collect semantics.
    return ancestryLooksLikeTip
        or action:find("collect", 1, true) ~= nil
        or action:find("claim", 1, true) ~= nil
        or action:find("take", 1, true) ~= nil
        or action:find("empty", 1, true) ~= nil
        or action:find("tip", 1, true) ~= nil
        or name:find("tip", 1, true) ~= nil
end

local function isTipClickDetector(detector, plot)
    if not detector or not detector:IsA("ClickDetector") then return false end
    return objectLooksLikeTipJar(detector.Parent, plot and plot.Parent)
end

local tipInteractionCache = {}
local tipInteractionCachePlot = nil
local tipInteractionNextScan = 0

local function getTipInteractions(plot)
    local now = os.clock()
    local needScan = plot ~= tipInteractionCachePlot or now >= tipInteractionNextScan

    if not needScan then
        for _, item in ipairs(tipInteractionCache) do
            if not item or not item.Parent then
                needScan = true
                break
            end
        end
    end

    if needScan then
        tipInteractionCachePlot = plot
        tipInteractionNextScan = now + 0.15
        tipInteractionCache = {}

        if plot then
            for _, obj in ipairs(plot:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and isTipPrompt(obj, plot) then
                    tipInteractionCache[#tipInteractionCache + 1] = obj
                elseif obj:IsA("ClickDetector") and isTipClickDetector(obj, plot) then
                    tipInteractionCache[#tipInteractionCache + 1] = obj
                end
            end
        end
    end

    return tipInteractionCache
end

local function fireTipInteraction(item, plot)
    if not farming("ZHM_AutoCollectTip") then return false end
    if not item or not item.Parent then return false end

    if item:IsA("ProximityPrompt") then
        if not item.Enabled or not isTipPrompt(item, plot) then return false end

        pcall(function() item.HoldDuration = 0 end)
        pcall(function() item.RequiresLineOfSight = false end)
        pcall(function() item.MaxActivationDistance = math.max(item.MaxActivationDistance, 35) end)

        if type(fireproximityprompt) ~= "function" then
            report("Tip", "fireproximityprompt unavailable.")
            return false
        end

        local ok = pcall(function() fireproximityprompt(item, 0) end)
        if not ok then
            ok = pcall(function() fireproximityprompt(item) end)
        end
        return ok
    end

    if item:IsA("ClickDetector") then
        if not isTipClickDetector(item, plot) then return false end
        if type(fireclickdetector) ~= "function" then
            report("Tip", "fireclickdetector unavailable for this Tip Jar.")
            return false
        end
        return pcall(function() fireclickdetector(item) end)
    end

    return false
end

local function autoCollectTip()
    if not farming("ZHM_AutoCollectTip") then return end

    local plot = findMyPlot()
    if not plot then
        report("Tip", "Waiting for your plot.")
        return
    end

    local interactions = getTipInteractions(plot)
    local fired = 0

    for _, item in ipairs(interactions) do
        if not farming("ZHM_AutoCollectTip") then return end
        if fireTipInteraction(item, plot) then
            fired += 1
        end
        task.wait(0.02)
    end

    if fired > 0 then
        report("Tip", "Collected Tip Jar interaction(s): " .. tostring(fired))
    end
end

-- AUTO COLLECT: process every DIFFERENT BakingRack on the player's plot.
-- Prompts are grouped by their nearest BakingRack ancestor so duplicate descendants
-- from the same rack do not cause that rack to be counted more than once.
local function isRackCollectPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end

    local name = string.lower(prompt.Name or "")
    local action = string.lower(tostring(prompt.ActionText or ""))

    if name == "bakeprompt" or name == "cashierprompt" or isGiveOrderPrompt(prompt) then
        return false
    end

    return name == "pickupllaneraprompt"
        or name == "displayrackprompt"
        or name:find("collect", 1, true) ~= nil
        or name:find("pickup", 1, true) ~= nil
        or action == "collect"
        or action:find("collect", 1, true) ~= nil
        or action:find("pickup", 1, true) ~= nil
end

local function isBakingRackObject(obj)
    if not obj then return false end
    local name = string.lower(obj.Name or "")
    return (name:find("bakingrack", 1, true) ~= nil
        or name:find("normalbakingrack", 1, true) ~= nil)
        and not name:find("prompt", 1, true)
end

local function nearestBakingRackAncestor(obj, stopAt)
    local current = obj and obj.Parent
    while current and current ~= stopAt do
        if isBakingRackObject(current) then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function collectEquipmentPrompts()
    local plot = findMyPlot()
    if not plot then
        report("Collect", "Plot unavailable; check ZHM_PlotName.")
        return
    end

    local equipment = plot:FindFirstChild("Equipment") or plot
    local rackGroups = {}
    local rackOrder = {}
    local seenPrompts = {}
    local otherPrompts = {}

    -- First pass: group every valid collect prompt under its own BakingRack.
    -- Non-rack collect prompts are kept too so the old Auto Collect behavior
    -- (DisplayRack / other equipment collection) still works.
    for _, obj in ipairs(equipment:GetDescendants()) do
        if not farming("ZHM_AutoCollect") then return end

        if obj:IsA("ProximityPrompt") and isRackCollectPrompt(obj) then
            local rack = nearestBakingRackAncestor(obj, equipment.Parent)

            if rack then
                if not rackGroups[rack] then
                    rackGroups[rack] = {}
                    rackOrder[#rackOrder + 1] = rack
                end

                if not seenPrompts[obj] then
                    seenPrompts[obj] = true
                    rackGroups[rack][#rackGroups[rack] + 1] = obj
                end
            elseif not seenPrompts[obj] then
                seenPrompts[obj] = true
                otherPrompts[#otherPrompts + 1] = obj
            end
        end
    end

    -- Some game builds place the prompt beside the named BakingRack model instead
    -- of inside it. Use getAllBakingRacks() as a fallback and inspect each rack's
    -- local container without double-firing prompts already grouped above.
    for _, rackInfo in ipairs(getAllBakingRacks(plot)) do
        if not farming("ZHM_AutoCollect") then return end

        local rack = rackInfo.instance
        if rack and rack.Parent and not rackGroups[rack] then
            local prompts = {}

            if rack:IsA("ProximityPrompt") and isRackCollectPrompt(rack) then
                prompts[#prompts + 1] = rack
            end

            for _, obj in ipairs(rack:GetDescendants()) do
                if obj:IsA("ProximityPrompt")
                    and isRackCollectPrompt(obj)
                    and not seenPrompts[obj] then
                    seenPrompts[obj] = true
                    prompts[#prompts + 1] = obj
                end
            end

            if #prompts > 0 then
                rackGroups[rack] = prompts
                rackOrder[#rackOrder + 1] = rack
            end
        end
    end

    -- Stable rack order prevents random skipping/reordering between scans.
    table.sort(rackOrder, function(a, b)
        local okA, fullA = pcall(function() return a:GetFullName() end)
        local okB, fullB = pcall(function() return b:GetFullName() end)
        return (okA and fullA or a.Name) < (okB and fullB or b.Name)
    end)

    local racksProcessed = 0
    local promptsFired = 0

    for _, rack in ipairs(rackOrder) do
        if not farming("ZHM_AutoCollect") then return end

        local prompts = rackGroups[rack]
        local firedThisRack = false

        if prompts then
            for _, prompt in ipairs(prompts) do
                if not farming("ZHM_AutoCollect") then return end

                if prompt and prompt.Parent and prompt.Enabled and isRackCollectPrompt(prompt) then
                    if firePromptSafe(prompt, "Collect") then
                        promptsFired += 1
                        firedThisRack = true
                    end
                    task.wait()
                end
            end
        end

        if firedThisRack then
            racksProcessed += 1
        end
    end

    -- Preserve collection from DisplayRack / other supported equipment prompts.
    local extraPromptsFired = 0
    for _, prompt in ipairs(otherPrompts) do
        if not farming("ZHM_AutoCollect") then return end
        if prompt and prompt.Parent and prompt.Enabled and isRackCollectPrompt(prompt) then
            if firePromptSafe(prompt, "Collect") then
                extraPromptsFired += 1
            end
            task.wait()
        end
    end

    if racksProcessed > 0 or extraPromptsFired > 0 then
        report(
            "Collect",
            "Collected from "
                .. tostring(racksProcessed)
                .. " BakingRack(s), "
                .. tostring(promptsFired)
                .. " rack prompt(s), "
                .. tostring(extraPromptsFired)
                .. " other prompt(s)."
        )
    end
end

-- AUTO BUY ALL MARKET V2
-- Robust Market GUI discovery + category cycling + scrolling + world Buy fallback.
local MARKET_OPEN_WAIT = 0.12
local MARKET_CATEGORY_WAIT = 0.10
local MARKET_SCROLL_WAIT = 0.035
local MARKET_BUY_WAIT = 0.01
local MARKET_PASS_WAIT = 0.15
local MARKET_MAX_REBUILDS = 24
local WORLD_BUY_RADIUS = 160
local WORLD_BUY_COOLDOWN = 0.30

local worldBuyLastFire = setmetatable({}, { __mode = "k" })

local function compactMarketText(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%./%(%)%[%]:]+", "")
end

local function buttonTextBlob(obj, depth)
    if not obj then return "" end
    depth = depth or 3

    local values = { obj.Name or "" }

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        values[#values + 1] = obj.Text or ""
    elseif obj:IsA("StringValue") then
        values[#values + 1] = tostring(obj.Value or "")
    end

    local queue = { { object = obj, level = 0 } }
    local head = 1

    while head <= #queue do
        local entry = queue[head]
        head += 1

        if entry.level < depth then
            for _, child in ipairs(entry.object:GetChildren()) do
                values[#values + 1] = child.Name or ""

                if child:IsA("TextLabel")
                    or child:IsA("TextButton")
                    or child:IsA("TextBox") then
                    values[#values + 1] = child.Text or ""
                elseif child:IsA("StringValue") then
                    values[#values + 1] = tostring(child.Value or "")
                end

                queue[#queue + 1] = {
                    object = child,
                    level = entry.level + 1,
                }
            end
        end
    end

    return string.lower(table.concat(values, " "))
end

local function getMarketRoot()
    local mainUI = playerGui:FindFirstChild("MainUI")

    -- Known path first.
    if mainUI then
        local market = mainUI:FindFirstChild("Market")
            or mainUI:FindFirstChild("Market", true)
        if market then return market end
    end

    -- Compatibility fallback for renamed Market / Shop / Store containers.
    for _, obj in ipairs(playerGui:GetDescendants()) do
        local name = compactMarketText(obj.Name)
        if (name == "market"
            or name == "shop"
            or name == "store"
            or name:find("marketui", 1, true)
            or name:find("shopui", 1, true))
            and (obj:IsA("GuiObject") or obj:IsA("ScreenGui")) then
            return obj
        end
    end

    return nil
end

local function guiIsActuallyVisible(obj)
    if not obj then return false end

    local current = obj
    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        elseif current:IsA("ScreenGui") and not current.Enabled then
            return false
        end
        current = current.Parent
    end

    return true
end

local function getMarketFrame()
    local market = getMarketRoot()
    if not market then return nil end

    if market:IsA("GuiObject") and market.Name == "Frame" then
        return market
    end

    return market:FindFirstChild("Frame")
        or market:FindFirstChild("Frame", true)
        or market
end

local function getClickable(container)
    if not container then return nil end
    if container:IsA("GuiButton") then return container end
    return container:FindFirstChildWhichIsA("GuiButton", true)
end

local function fireGuiControl(container)
    local button = getClickable(container)
    if not button then return false end

    -- Direct callback path. Works even if the Market panel itself is hidden.
    if type(getconnections) == "function" then
        for _, eventName in ipairs({
            "Activated",
            "MouseButton1Click",
            "MouseButton1Up",
            "MouseButton1Down",
        }) do
            local signal = button[eventName]
            if signal then
                local ok, connections = pcall(getconnections, signal)
                if ok and connections then
                    local fired = false

                    for _, connection in ipairs(connections) do
                        if connection.Enabled ~= false
                            and connection.ForeignState ~= true
                            and connection.LuaConnection ~= false
                            and type(connection.Fire) == "function" then

                            local success = pcall(function()
                                if eventName == "Activated" then
                                    connection:Fire(nil, 1)
                                elseif eventName == "MouseButton1Down"
                                    or eventName == "MouseButton1Up" then
                                    local center =
                                        button.AbsolutePosition + button.AbsoluteSize / 2
                                    connection:Fire(center.X, center.Y)
                                else
                                    connection:Fire()
                                end
                            end)

                            fired = fired or success
                        end
                    end

                    if fired then return true end
                end
            end
        end
    end

    if type(firesignal) == "function" then
        for _, eventName in ipairs({ "Activated", "MouseButton1Click" }) do
            local signal = button[eventName]
            if signal then
                local ok = pcall(function()
                    if eventName == "Activated" then
                        firesignal(signal, nil, 1)
                    else
                        firesignal(signal)
                    end
                end)
                if ok then return true end
            end
        end
    end

    -- Executor-independent fallback: actual mouse click if visible on screen.
    if guiIsActuallyVisible(button)
        and button.AbsoluteSize.X > 1
        and button.AbsoluteSize.Y > 1 then

        local center = button.AbsolutePosition + button.AbsoluteSize / 2
        local x = math.floor(center.X)
        local y = math.floor(center.Y)

        local ok = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            RunService.Heartbeat:Wait()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)

        if ok then return true end
    end

    return false
end

local function looksLikeMarketLauncher(button, marketRoot)
    if not button or not button:IsA("GuiButton") then return false end
    if marketRoot and button:IsDescendantOf(marketRoot) then return false end

    local compact = compactMarketText(buttonTextBlob(button, 2))
    return compact == "market"
        or compact == "shop"
        or compact == "store"
        or compact:find("openmarket", 1, true) ~= nil
        or compact:find("marketbutton", 1, true) ~= nil
        or compact:find("shopbutton", 1, true) ~= nil
end

local function tryOpenMarket()
    local market = getMarketRoot()

    if market and guiIsActuallyVisible(market) then
        return market
    end

    -- Try the game's actual Market launcher first.
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("GuiButton") and looksLikeMarketLauncher(obj, market) then
            fireGuiControl(obj)
            task.wait(MARKET_OPEN_WAIT)

            market = getMarketRoot()
            if market then return market end
        end
    end

    -- Last fallback: locally expose the Market tree so real click fallback can work.
    market = getMarketRoot()
    if market then
        local current = market
        while current and current ~= playerGui do
            pcall(function()
                if current:IsA("GuiObject") then
                    current.Visible = true
                elseif current:IsA("ScreenGui") then
                    current.Enabled = true
                end
            end)
            current = current.Parent
        end
    end

    return market
end

local function getCategoryRoot(frame)
    if not frame then return nil end

    for _, wanted in ipairs({
        "Category", "Categories", "Tabs", "Tab", "Buttons",
    }) do
        local found = frame:FindFirstChild(wanted)
            or frame:FindFirstChild(wanted, true)
        if found then
            local compact = compactMarketText(found.Name)
            if compact:find("categor", 1, true)
                or compact:find("tab", 1, true)
                or wanted == "Category"
                or wanted == "Categories" then
                return found
            end
        end
    end

    return nil
end

local function isLikelyCategoryButton(button, categoryRoot)
    if not button or not button:IsA("GuiButton") then return false end

    if categoryRoot and button:IsDescendantOf(categoryRoot) then
        return true
    end

    local compact = compactMarketText(buttonTextBlob(button, 2))

    return compact:find("equipment", 1, true) ~= nil
        or compact:find("furniture", 1, true) ~= nil
        or compact:find("decor", 1, true) ~= nil
        or compact:find("decoration", 1, true) ~= nil
        or compact:find("bakery", 1, true) ~= nil
        or compact:find("other", 1, true) ~= nil
        or compact:find("misc", 1, true) ~= nil
end

local function collectMarketCategories(frame)
    local result = {}
    local seen = {}
    if not frame then return result end

    local categoryRoot = getCategoryRoot(frame)

    if categoryRoot then
        if categoryRoot:IsA("GuiButton") then
            seen[categoryRoot] = true
            result[#result + 1] = categoryRoot
        end

        for _, obj in ipairs(categoryRoot:GetDescendants()) do
            if obj:IsA("GuiButton") and not seen[obj] then
                seen[obj] = true
                result[#result + 1] = obj
            end
        end
    else
        for _, obj in ipairs(frame:GetDescendants()) do
            if obj:IsA("GuiButton")
                and not seen[obj]
                and isLikelyCategoryButton(obj, nil) then
                seen[obj] = true
                result[#result + 1] = obj
            end
        end
    end

    table.sort(result, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    return result
end

local function hasPurchaseAncestor(button, frame)
    local current = button

    for _ = 1, 8 do
        if not current or current == frame then break end

        local compact = compactMarketText(current.Name)
        if compact == "buy"
            or compact == "money"
            or compact == "purchase"
            or compact == "cash"
            or compact:find("buybutton", 1, true)
            or compact:find("purchasebutton", 1, true)
            or compact:find("moneybutton", 1, true) then
            return true
        end

        current = current.Parent
    end

    return false
end

local function looksLikePurchaseButton(button, frame, categoryRoot)
    if not button or not button:IsA("GuiButton") then return false end
    if categoryRoot and button:IsDescendantOf(categoryRoot) then return false end

    local ownName = compactMarketText(button.Name)
    local ownText = button:IsA("TextButton")
        and compactMarketText(button.Text)
        or ""
    local blob = compactMarketText(buttonTextBlob(button, 3))

    if ownName == "buy"
        or ownName == "money"
        or ownName == "purchase"
        or ownName == "cash"
        or ownText == "buy"
        or ownText == "purchase"
        or ownName:find("buybutton", 1, true)
        or ownName:find("purchasebutton", 1, true)
        or ownName:find("moneybutton", 1, true)
        or blob:find("buynow", 1, true)
        or hasPurchaseAncestor(button, frame) then
        return true
    end

    -- Common structure: generic ImageButton inside a row/Frame containing
    -- Money / Price / Cost text or a peso sign.
    local parent = button.Parent
    for _ = 1, 4 do
        if not parent or parent == frame then break end

        local parentBlob = string.lower(buttonTextBlob(parent, 2))
        local compactParent = compactMarketText(parentBlob)

        local hasMoney =
            compactParent:find("money", 1, true) ~= nil
            or compactParent:find("price", 1, true) ~= nil
            or compactParent:find("cost", 1, true) ~= nil
            or parentBlob:find("₱", 1, true) ~= nil
            or parentBlob:find("$", 1, true) ~= nil

        if hasMoney then
            return true
        end

        parent = parent.Parent
    end

    return false
end

local function collectPurchaseButtons(frame)
    local result = {}
    local seen = {}
    if not frame then return result end

    local categoryRoot = getCategoryRoot(frame)

    for _, obj in ipairs(frame:GetDescendants()) do
        if obj:IsA("GuiButton")
            and not seen[obj]
            and looksLikePurchaseButton(obj, frame, categoryRoot) then
            seen[obj] = true
            result[#result + 1] = obj
        end
    end

    table.sort(result, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    return result
end

local function getMarketScrollFrames(frame)
    local result = {}
    if not frame then return result end

    for _, obj in ipairs(frame:GetDescendants()) do
        if obj:IsA("ScrollingFrame") then
            result[#result + 1] = obj
        end
    end

    return result
end

local function buyVisibleMaterializedRows(frame)
    local total = 0
    local rebuilds = 0
    local attempted = setmetatable({}, { __mode = "k" })

    while running("ZHM_AutoBuy") and rebuilds < MARKET_MAX_REBUILDS do
        rebuilds += 1
        frame = getMarketFrame() or frame
        if not frame then break end

        local buttons = collectPurchaseButtons(frame)
        local foundNew = false

        for _, button in ipairs(buttons) do
            if not running("ZHM_AutoBuy") then break end

            if button
                and button.Parent
                and not attempted[button] then
                attempted[button] = true
                foundNew = true

                if fireGuiControl(button) then
                    total += 1
                end

                task.wait(MARKET_BUY_WAIT)
            end
        end

        if not foundNew then break end
        RunService.Heartbeat:Wait()
    end

    return total
end

local function scanAllMarketScrollPositions(frame)
    local total = 0
    if not frame then return total end

    local scrollFrames = getMarketScrollFrames(frame)

    -- Buy currently materialized rows first.
    total += buyVisibleMaterializedRows(frame)

    for _, scrolling in ipairs(scrollFrames) do
        if not running("ZHM_AutoBuy") then break end
        if scrolling and scrolling.Parent then
            local original = scrolling.CanvasPosition
            local maxY = math.max(
                0,
                scrolling.AbsoluteCanvasSize.Y - scrolling.AbsoluteWindowSize.Y
            )

            local stepY = math.max(
                scrolling.AbsoluteWindowSize.Y * 0.75,
                120
            )

            local y = 0
            while running("ZHM_AutoBuy") and y <= maxY + 1 do
                pcall(function()
                    scrolling.CanvasPosition = Vector2.new(original.X, y)
                end)

                RunService.Heartbeat:Wait()
                task.wait(MARKET_SCROLL_WAIT)

                frame = getMarketFrame() or frame
                total += buyVisibleMaterializedRows(frame)

                y += stepY
            end

            pcall(function()
                scrolling.CanvasPosition = original
            end)
        end
    end

    return total
end

local function buyAllMarketGui()
    if not running("ZHM_AutoBuy") then return 0 end

    tryOpenMarket()
    task.wait(MARKET_OPEN_WAIT)

    local frame = getMarketFrame()
    if not frame then
        report("Market", "Market UI not found yet; waiting for it to load.")
        return 0
    end

    local total = 0

    -- Current category/page.
    total += scanAllMarketScrollPositions(frame)

    -- Every category/tab.
    local initialCategories = collectMarketCategories(frame)
    local count = #initialCategories

    for index = 1, count do
        if not running("ZHM_AutoBuy") then break end

        frame = getMarketFrame() or frame
        local liveCategories = collectMarketCategories(frame)
        local category = liveCategories[index] or initialCategories[index]

        if category and category.Parent then
            fireGuiControl(category)
            task.wait(MARKET_CATEGORY_WAIT)
            RunService.Heartbeat:Wait()

            frame = getMarketFrame() or frame
            total += scanAllMarketScrollPositions(frame)
        end
    end

    return total
end

-- Generic world Buy/Purchase fallback. This catches Market items implemented as
-- ProximityPrompts instead of GUI buttons.
local function getPromptPart(prompt)
    if not prompt then return nil end

    local current = prompt.Parent
    while current and current ~= Workspace do
        if current:IsA("Attachment") then
            local parent = current.Parent
            if parent and parent:IsA("BasePart") then
                return parent
            end
        elseif current:IsA("BasePart") then
            return current
        elseif current:IsA("Model") then
            local part = current.PrimaryPart
                or current:FindFirstChild("HumanoidRootPart")
                or current:FindFirstChildWhichIsA("BasePart", true)
            if part then return part end
        end

        current = current.Parent
    end

    return nil
end

local function isWorldBuyPrompt(prompt)
    if not prompt
        or not prompt:IsA("ProximityPrompt")
        or not prompt.Enabled then
        return false
    end

    local action = compactMarketText(prompt.ActionText)
    local name = compactMarketText(prompt.Name)

    return action == "buy"
        or action:find("buy", 1, true) ~= nil
        or action:find("purchase", 1, true) ~= nil
        or name:find("buyprompt", 1, true) ~= nil
        or name:find("purchaseprompt", 1, true) ~= nil
end

local function fireAllNearbyWorldBuyPrompts()
    if not running("ZHM_AutoBuy") then return 0 end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return 0 end

    local candidates = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and isWorldBuyPrompt(obj) then
            local part = getPromptPart(obj)
            if part then
                local distance = (root.Position - part.Position).Magnitude
                if distance <= WORLD_BUY_RADIUS then
                    candidates[#candidates + 1] = {
                        prompt = obj,
                        distance = distance,
                    }
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return a.distance < b.distance
    end)

    local total = 0

    for _, entry in ipairs(candidates) do
        if not running("ZHM_AutoBuy") then break end

        local prompt = entry.prompt
        local now = os.clock()
        local last = worldBuyLastFire[prompt] or 0

        if now - last >= WORLD_BUY_COOLDOWN then
            worldBuyLastFire[prompt] = now

            pcall(function() prompt.HoldDuration = 0 end)
            pcall(function() prompt.RequiresLineOfSight = false end)
            pcall(function()
                prompt.MaxActivationDistance =
                    math.max(prompt.MaxActivationDistance, 60)
            end)

            if type(fireproximityprompt) == "function" then
                local ok = pcall(function()
                    fireproximityprompt(prompt, 0)
                end)

                if not ok then
                    ok = pcall(function()
                        fireproximityprompt(prompt)
                    end)
                end

                if ok then total += 1 end
            end
        end
    end

    return total
end

local function autoBuyMarket()
    if not running("ZHM_AutoBuy") then return end

    local guiBought = buyAllMarketGui()

    if not running("ZHM_AutoBuy") then return end

    local worldBought = fireAllNearbyWorldBuyPrompts()

    if guiBought > 0 or worldBought > 0 then
        report(
            "Market",
            "Auto Buy All • GUI "
                .. tostring(guiBought)
                .. " • World "
                .. tostring(worldBought)
        )
    else
        report(
            "Market",
            "Scanning all Market categories, scroll rows, and nearby Buy prompts."
        )
    end

    task.wait(MARKET_PASS_WAIT)
end

local function autoUpgradeBakery()
    local items = ui({ "MainUI", "Bakery", "Frame", "ScrollingFrame", "Upgrade", "Items" })
    if not items then report("Upgrade", "Upgrade Money controls unavailable."); return end
    for _, item in ipairs(sortedChildren(items)) do
        if not running("ZHM_AutoUpgrade") then return end
        local button = resolve(item, { "Main_Frame", "Buttons", "Money" })
        if button then triggerButton(button, "Upgrade"); task.wait() end
    end
end

local farmJobs = {
    { Key = "ZHM_AutoAccept", Name = "Accept", Interval = 0.05, Run = autoAccept },
    { Key = "ZHM_AutoPrepareDough", Name = "Dough", Interval = 0.1, Run = autoPrepareDough },
    { Key = "ZHM_AutoBake", Name = "Bake", Interval = 0.1, Run = bakeAllBreads },
    { Key = "ZHM_AutoCollect", Name = "Collect", Interval = 0.05, Run = collectEquipmentPrompts },
    { Key = "ZHM_AutoCollectTip", Name = "Tip", Interval = 0.08, Run = autoCollectTip },
    { Key = "ZHM_AutoGiveOrder", Name = "GiveOrder", Interval = 0.05, Run = autoGiveOrder },
    { Key = "ZHM_AutoEnableBreads", Name = "Breads", Interval = 0.2, Run = autoEnableBreads },
}

local function startAutomation()
    task.spawn(function()
        local nextRun = {}
        while isCurrent() do
            for _, job in ipairs(farmJobs) do
                if farming(job.Key) and os.clock() >= (nextRun[job.Key] or 0) then
                    local ok, err = pcall(job.Run)
                    if not ok then report(job.Name, tostring(err)) end
                    nextRun[job.Key] = os.clock() + job.Interval
                end
            end
            task.wait()
        end
    end)
    for _, definition in ipairs({
        { Key = "ZHM_AutoBuy", Name = "Market", Run = autoBuyMarket },
        { Key = "ZHM_AutoUpgrade", Name = "Upgrade", Run = autoUpgradeBakery },
    }) do
        local job = definition
        task.spawn(function()
            while isCurrent() do
                if running(job.Key) then
                    local ok, err = pcall(job.Run)
                    if not ok then report(job.Name, tostring(err)) end
                end
                task.wait()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- 6A. NIGHT TRASH AUTO SWEEP (MERGED FROM STANDALONE)
-- Priority owner while active: pauses farm/buy/upgrade/rack/NPC loops without
-- changing the user's toggle values. Everything resumes when trash is gone.
--------------------------------------------------------------------------------
do
    local SWEEP_SCAN_INTERVAL = 0.15
    local SWEEP_TP_HEIGHT_OFFSET = 2.5
    local SWEEP_TP_BACK_OFFSET = 1.5
    local SWEEP_PROMPT_FIRE_DELAY = 0 -- fire immediately after each sweep TP
    local SWEEP_LOOP_DELAY = TP_DELAY

    local function guiObjectActive(obj)
        if not obj or not obj:IsA("GuiObject") or not obj.Visible then
            return false
        end

        local current = obj.Parent
        while current and current ~= playerGui do
            if current:IsA("GuiObject") and not current.Visible then
                return false
            end
            current = current.Parent
        end

        return true
    end

    local function getWeatherFrame()
        local weatherUI = playerGui:FindFirstChild("WeatherUI")
        return weatherUI and weatherUI:FindFirstChild("Frame") or nil
    end

    local function isNight()
        local frame = getWeatherFrame()
        if not frame then return false end

        local night = frame:FindFirstChild("Night")
        local day = frame:FindFirstChild("Day")

        if night and guiObjectActive(night) then return true end
        if day and guiObjectActive(day) then return false end

        for _, obj in ipairs(frame:GetDescendants()) do
            local lower = obj.Name:lower()
            if lower == "night" and guiObjectActive(obj) then
                return true
            elseif lower == "day" and guiObjectActive(obj) then
                return false
            end
        end

        return false
    end

    local function getCharacter()
        return player.Character or player.CharacterAdded:Wait()
    end

    local function getRoot()
        local character = getCharacter()
        return character and character:FindFirstChild("HumanoidRootPart") or nil
    end

    local function getPromptPart(prompt)
        if not prompt then return nil end
        local parent = prompt.Parent

        if parent and parent:IsA("BasePart") then
            return parent
        end

        if parent and parent:IsA("Model") then
            return parent.PrimaryPart
                or parent:FindFirstChild("HumanoidRootPart")
                or parent:FindFirstChildWhichIsA("BasePart", true)
        end

        local current = parent
        while current and current ~= Workspace do
            if current:IsA("BasePart") then
                return current
            elseif current:IsA("Model") then
                local part = current.PrimaryPart or current:FindFirstChildWhichIsA("BasePart", true)
                if part then return part end
            end
            current = current.Parent
        end

        return nil
    end

    local function getSweepPrompts()
        local root = Workspace:FindFirstChild("SideJobTrash")
        if not root then return {} end

        local prompts = {}
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.Enabled then
                local name = obj.Name:lower()
                local action = tostring(obj.ActionText or ""):lower()

                if name == "sweep"
                    or name == "sweepprompt"
                    or name:find("sweep", 1, true)
                    or action:find("sweep", 1, true) then
                    table.insert(prompts, obj)
                end
            end
        end
        return prompts
    end

    local function sortPromptsByDistance(prompts)
        local root = getRoot()
        if not root then return prompts end

        table.sort(prompts, function(a, b)
            local partA = getPromptPart(a)
            local partB = getPromptPart(b)
            local distA = partA and (root.Position - partA.Position).Magnitude or math.huge
            local distB = partB and (root.Position - partB.Position).Magnitude or math.huge
            return distA < distB
        end)

        return prompts
    end

    local function teleportToPrompt(prompt)
        local root = getRoot()
        local part = getPromptPart(prompt)
        if not root or not part then return false end

        root.CFrame = part.CFrame * CFrame.new(0, SWEEP_TP_HEIGHT_OFFSET, SWEEP_TP_BACK_OFFSET)
        return true
    end

    local function makePromptInstant(prompt)
        if not prompt then return end
        pcall(function() prompt.HoldDuration = 0 end)
        pcall(function() prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 15) end)
        pcall(function() prompt.RequiresLineOfSight = false end)
    end

    local function fireSweepPrompt(prompt)
        if not prompt or not prompt.Parent or not prompt.Enabled then return false end
        makePromptInstant(prompt)

        if type(fireproximityprompt) == "function" then
            -- Force an instant prompt during sweeping. Different executors support
            -- different fireproximityprompt signatures, so try all common forms.
            local ok = pcall(function() fireproximityprompt(prompt, 0, true) end)
            if not ok then
                ok = pcall(function() fireproximityprompt(prompt, 0) end)
            end
            if not ok then
                ok = pcall(function() fireproximityprompt(prompt) end)
            end
            return ok
        end

        return false
    end

    task.spawn(function()
        while isCurrent() do
            if ENV.ZHM_AutoSweep ~= true then
                ENV.ZHM_SweepActive = false
                ENV.ZHM_SweepStatus = "OFF"
                task.wait(0.2)
            elseif isNight() then
                local prompts = sortPromptsByDistance(getSweepPrompts())

                if #prompts > 0 then
                    ENV.ZHM_SweepActive = true
                    ENV.ZHM_NPCBusy = false
                    ENV.ZHM_SweepStatus = "Sweeping " .. tostring(#prompts) .. " target(s)"

                    for _, prompt in ipairs(prompts) do
                        if not isCurrent() or ENV.ZHM_AutoSweep ~= true or not isNight() then
                            break
                        end

                        if prompt and prompt.Parent and prompt.Enabled and teleportToPrompt(prompt) then
                            -- Fire immediately on arrival, then enforce the requested
                            -- 1-second delay before the next sweep teleport.
                            if SWEEP_PROMPT_FIRE_DELAY > 0 then
                                task.wait(SWEEP_PROMPT_FIRE_DELAY)
                            end
                            if not isNight() then break end
                            fireSweepPrompt(prompt)
                            task.wait(SWEEP_LOOP_DELAY)
                        end
                    end
                else
                    ENV.ZHM_SweepActive = false
                    ENV.ZHM_SweepStatus = "Night • no trash"
                end

                task.wait(SWEEP_SCAN_INTERVAL)
            else
                ENV.ZHM_SweepActive = false
                ENV.ZHM_SweepStatus = "Waiting for night"
                task.wait(0.25)
            end
        end

        ENV.ZHM_SweepActive = false
        ENV.ZHM_SweepStatus = "Stopped"
    end)
end

--------------------------------------------------------------------------------
-- 6B. STRICT MOVING-NPC SCANNER (12-16 STUDS/S) + ROLLING PIN AUTO SWING (NO TP)
--------------------------------------------------------------------------------
do
    local ROLLING_PIN_SLOT = "1"
    local rollingPinEquippedThisCharacter = false
    local equipInProgress = false

    -- STRICT swing-target rules:
    --   1) NPC only; never a player character.
    --   2) NPC must be alive.
    --   3) CURRENT horizontal AssemblyLinearVelocity must be 12-16 studs/s inclusive.
    --   4) NPC must satisfy the existing local scan-area rule.
    -- No teleporting is performed; the scanner only supplies targets to Rolling Pin swing.
    local MIN_TARGET_SPEED = 12
    local MAX_TARGET_SPEED = 16
    local NPC_PLOT_SCAN_RADIUS = 20
    local NPC_SCAN_INTERVAL = 0.08
    local NPC_SWING_INTERVAL = 0.08
    local NPC_CLICK_HOLD_TIME = 0.025
    local NPC_SWING_MAX_DISTANCE = 30

    local cachedPlot = nil
    local cachedPlotParts = nil
    local cachedPlotPartsFor = nil
    local currentTarget = nil

    local function getHotbarSlot1()
        local pg = player:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local backpackGui = pg:FindFirstChild("BackpackGui")
        local backpack = backpackGui and backpackGui:FindFirstChild("Backpack")
        local hotbar = backpack and backpack:FindFirstChild("Hotbar")
        return hotbar and hotbar:FindFirstChild(ROLLING_PIN_SLOT) or nil
    end

    local function findClickableGui(slot)
        if not slot then return nil end
        if slot:IsA("GuiButton") then return slot end
        return slot:FindFirstChildWhichIsA("GuiButton", true)
    end

    local function fireGuiButtonOnce(button)
        if not button or not button:IsA("GuiButton") then return false end

        if type(getconnections) == "function" then
            local fired = false
            for _, eventName in ipairs({"Activated", "MouseButton1Click", "MouseButton1Up"}) do
                local signal = button[eventName]
                if signal then
                    local ok, connections = pcall(getconnections, signal)
                    if ok and connections then
                        for _, connection in ipairs(connections) do
                            if type(connection.Fire) == "function" then
                                local success = pcall(function() connection:Fire() end)
                                if success then fired = true end
                            end
                        end
                    end
                end
            end
            if fired then return true end
        end

        if type(firesignal) == "function" then
            local ok = pcall(function() firesignal(button.Activated) end)
            if ok then return true end
        end

        return false
    end

    local function virtualClickGuiOnce(guiObject)
        if not guiObject or not guiObject:IsA("GuiObject") then return false end
        local size = guiObject.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then return false end

        local pos = guiObject.AbsolutePosition
        local x = math.floor(pos.X + size.X / 2)
        local y = math.floor(pos.Y + size.Y / 2)

        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    local function equipRollingPinOnce()
        if rollingPinEquippedThisCharacter or equipInProgress then return end
        if ENV.ZHM_NPCAutoSwing ~= true then return end

        equipInProgress = true
        for _ = 1, 150 do
            if rollingPinEquippedThisCharacter or not isCurrent() then break end
            if ENV.ZHM_NPCAutoSwing ~= true then break end

            local slot = getHotbarSlot1()
            if slot and slot:IsA("GuiObject") and slot.Visible
                and slot.AbsoluteSize.X > 0 and slot.AbsoluteSize.Y > 0 then

                local clicked = false
                local button = findClickableGui(slot)
                if button then clicked = fireGuiButtonOnce(button) end
                if not clicked then clicked = virtualClickGuiOnce(button or slot) end

                if clicked then
                    rollingPinEquippedThisCharacter = true
                    break
                end
            end
            task.wait(0.1)
        end
        equipInProgress = false
    end

    if ENV.ZHM_NPCAutoSwing == true then
        task.spawn(equipRollingPinOnce)
    end

    player.CharacterAdded:Connect(function()
        rollingPinEquippedThisCharacter = false
        equipInProgress = false
        cachedPlot = nil
        cachedPlotParts = nil
        cachedPlotPartsFor = nil
        currentTarget = nil
        ENV.ZHM_NPCBusy = false
        if ENV.ZHM_NPCAutoSwing == true then
            task.spawn(equipRollingPinOnce)
        end
    end)

    local function getPlayerRoot()
        local character = player.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local function isPlayerCharacter(model)
        return model and Players:GetPlayerFromCharacter(model) ~= nil
    end

    local function getHorizontalSpeed(part)
        if not part or not part:IsA("BasePart") then return 0 end
        local velocity = part.AssemblyLinearVelocity
        return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    end

    local function isTargetSpeed(speed)
        return type(speed) == "number"
            and speed == speed
            and speed >= MIN_TARGET_SPEED
            and speed <= MAX_TARGET_SPEED
    end

    local function getPlotPositionFolder(plot)
        if not plot then return nil end
        return plot:FindFirstChild("Position") or plot:FindFirstChild("Positions") or plot
    end

    local function getModelRoot(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChild("HumanoidRootPart", true)
            or model.PrimaryPart
            or model:FindFirstChild("UpperTorso", true)
            or model:FindFirstChild("Torso", true)
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getPlotParts(plot)
        if not plot then return {} end

        if cachedPlotPartsFor == plot and cachedPlotParts then
            local live = false
            for _, part in ipairs(cachedPlotParts) do
                if part and part.Parent then
                    live = true
                    break
                end
            end
            if live then return cachedPlotParts end
        end

        local root = getPlotPositionFolder(plot)
        local parts = {}
        local seen = {}

        local function addPart(part)
            if part and part:IsA("BasePart") and not seen[part] then
                seen[part] = true
                parts[#parts + 1] = part
            end
        end

        if root then
            if root:IsA("BasePart") then addPart(root) end
            for _, obj in ipairs(root:GetDescendants()) do
                addPart(obj)
            end
        end

        -- Fallback only if the Position folder has no physical parts.
        if #parts == 0 then
            if plot:IsA("BasePart") then addPart(plot) end
            for _, obj in ipairs(plot:GetDescendants()) do
                addPart(obj)
            end
        end

        cachedPlotPartsFor = plot
        cachedPlotParts = parts
        return parts
    end

    local function distancePointToPart(position, part)
        if not position or not part or not part.Parent then return math.huge end

        local localPoint = part.CFrame:PointToObjectSpace(position)
        local half = part.Size * 0.5
        local closest = Vector3.new(
            math.clamp(localPoint.X, -half.X, half.X),
            math.clamp(localPoint.Y, -half.Y, half.Y),
            math.clamp(localPoint.Z, -half.Z, half.Z)
        )

        return (localPoint - closest).Magnitude
    end

    local function distanceToMyPlot(position, plot)
        if not position or not plot then return math.huge end

        local nearest = math.huge
        for _, part in ipairs(getPlotParts(plot)) do
            if part and part.Parent then
                local d = distancePointToPart(position, part)
                if d < nearest then
                    nearest = d
                    if nearest <= 0.05 then break end
                end
            end
        end
        return nearest
    end

    local function plotDistanceFromPlayer(plot)
        local myRoot = getPlayerRoot()
        if not myRoot or not plot then return math.huge end
        return distanceToMyPlot(myRoot.Position, plot)
    end

    local function findNPCPlot()
        if cachedPlot and cachedPlot.Parent then return cachedPlot end

        local gameFolder = Workspace:FindFirstChild("Game")
        local shops = gameFolder and gameFolder:FindFirstChild("Shops")
        if not shops then return nil end

        -- Prefer explicit ownership so the scanner always starts from YOUR plot.
        for _, plot in ipairs(shops:GetChildren()) do
            local owner = plot:FindFirstChild("Owner")
                or plot:FindFirstChild("Player")
                or plot:FindFirstChild("OwnerPlayer")
                or plot:FindFirstChild("PlotOwner")

            if owner and owner:IsA("ValueBase") then
                local value = owner.Value
                if value == player or value == player.Name or value == player.UserId then
                    cachedPlot = plot
                    cachedPlotParts = nil
                    cachedPlotPartsFor = nil
                    return plot
                end
            end

            local ownerUserId = plot:GetAttribute("OwnerUserId")
            local ownerName = plot:GetAttribute("Owner")
                or plot:GetAttribute("OwnerName")
                or plot:GetAttribute("PlayerName")

            if ownerUserId == player.UserId or ownerName == player.Name then
                cachedPlot = plot
                cachedPlotParts = nil
                cachedPlotPartsFor = nil
                return plot
            end
        end

        -- Fallback: nearest plot to the player.
        local closestPlot = nil
        local closestDistance = math.huge
        for _, plot in ipairs(shops:GetChildren()) do
            local d = plotDistanceFromPlayer(plot)
            if d < closestDistance then
                closestDistance = d
                closestPlot = plot
            end
        end

        cachedPlot = closestPlot
        cachedPlotParts = nil
        cachedPlotPartsFor = nil
        return closestPlot
    end

    local function getExpandedPlotScanBox(plot)
        local parts = getPlotParts(plot)
        if #parts == 0 then return nil, nil end

        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

        -- Build a world-space AABB around the plot parts, accounting for rotation.
        for _, part in ipairs(parts) do
            if part and part.Parent then
                local half = part.Size * 0.5
                local cf = part.CFrame
                local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
                local extX = math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z
                local extY = math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z
                local extZ = math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
                local p = part.Position

                minX = math.min(minX, p.X - extX)
                minY = math.min(minY, p.Y - extY)
                minZ = math.min(minZ, p.Z - extZ)
                maxX = math.max(maxX, p.X + extX)
                maxY = math.max(maxY, p.Y + extY)
                maxZ = math.max(maxZ, p.Z + extZ)
            end
        end

        if minX == math.huge then return nil, nil end

        local expand = NPC_PLOT_SCAN_RADIUS * 2
        local minV = Vector3.new(minX, minY, minZ)
        local maxV = Vector3.new(maxX, maxY, maxZ)
        local center = (minV + maxV) * 0.5
        local size = (maxV - minV) + Vector3.new(expand, expand, expand)

        return CFrame.new(center), size
    end

    local function getHumanoidModelFromPart(part)
        if not part then return nil, nil end

        local current = part.Parent
        while current and current ~= Workspace do
            if current:IsA("Model") then
                local humanoid = current:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    return current, humanoid
                end
            end
            current = current.Parent
        end

        return nil, nil
    end

    local function getPlotLocalParts(plot)
        local boxCFrame, boxSize = getExpandedPlotScanBox(plot)
        if not boxCFrame or not boxSize then return {} end

        local overlap = OverlapParams.new()
        overlap.FilterType = Enum.RaycastFilterType.Exclude
        overlap.FilterDescendantsInstances = player.Character and { player.Character } or {}
        overlap.MaxParts = 0

        local ok, parts = pcall(function()
            return Workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlap)
        end)

        return ok and parts or {}
    end

    local function isStillValidRunningTarget(target)
        if not target or not target.model or not target.model.Parent then return false end
        if isPlayerCharacter(target.model) then return false end
        if not target.root or not target.root.Parent or not target.root:IsA("BasePart") then return false end
        if not target.humanoid or not target.humanoid.Parent or target.humanoid.Health <= 0 then return false end

        local myPlot = target.plot
        if not myPlot or not myPlot.Parent then
            myPlot = findNPCPlot()
        end
        if not myPlot then return false end

        -- Re-check BOTH constraints immediately before using the target.
        local currentSpeed = getHorizontalSpeed(target.root)
        if not isTargetSpeed(currentSpeed) then return false end

        local plotDistance = distanceToMyPlot(target.root.Position, myPlot)
        if plotDistance > NPC_PLOT_SCAN_RADIUS then return false end

        target.speed = currentSpeed
        target.plotDistance = plotDistance
        target.plot = myPlot
        return true
    end

    local function findNearestRunningNPC()
        local myPlot = findNPCPlot()
        if not myPlot then
            ENV.ZHM_NPCStatus = "Waiting for your plot"
            return nil
        end

        local best = nil
        local bestPlotDistance = math.huge
        local seenModels = {}

        -- Spatially scan ONLY the area around your plot. We no longer walk through
        -- Workspace:GetDescendants(), so far-away NPCs are never candidates.
        for _, part in ipairs(getPlotLocalParts(myPlot)) do
            local model, humanoid = getHumanoidModelFromPart(part)

            if model
                and humanoid
                and humanoid.Health > 0
                and not seenModels[model]
                and not isPlayerCharacter(model) then

                seenModels[model] = true
                local root = getModelRoot(model)

                if root and root:IsA("BasePart") and root.Parent then
                    local plotDistance = distanceToMyPlot(root.Position, myPlot)

                    if plotDistance <= NPC_PLOT_SCAN_RADIUS then
                        local speed = getHorizontalSpeed(root)

                        -- STRICT: do not target 11.99 or 16.01. Only 12.00-16.00 inclusive.
                        if isTargetSpeed(speed) and plotDistance < bestPlotDistance then
                            bestPlotDistance = plotDistance
                            best = {
                                model = model,
                                root = root,
                                humanoid = humanoid,
                                speed = speed,
                                plotDistance = plotDistance,
                                plot = myPlot,
                            }
                        end
                    end
                end
            end
        end

        return best
    end

    local function clickGameplayToSwing()
        local camera = Workspace.CurrentCamera
        if not camera then return false end
        local viewport = camera.ViewportSize
        local x = math.floor(viewport.X * 0.5)
        local y = math.floor(viewport.Y * 0.60)

        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(NPC_CLICK_HOLD_TIME)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    task.spawn(function()
        while isCurrent() do
            local anyNPCFeature = ENV.ZHM_NPCAutoSwing == true

            if anyNPCFeature and ENV.ZHM_SweepActive ~= true then
                if ENV.ZHM_NPCAutoSwing == true
                    and not rollingPinEquippedThisCharacter
                    and not equipInProgress then
                    task.spawn(equipRollingPinOnce)
                end

                local target = findNearestRunningNPC()
                if target and isStillValidRunningTarget(target) then
                    currentTarget = target
                    ENV.ZHM_NPCStatus = target.model.Name
                        .. " • " .. string.format("%.2f", target.speed) .. " studs/s"
                        .. " • " .. string.format("%.1f", target.plotDistance) .. "/20 from plot"

                    -- Swing-only mode: detecting an NPC never moves the character.
                    ENV.ZHM_NPCBusy = false
                else
                    currentTarget = nil
                    ENV.ZHM_NPCBusy = false
                    ENV.ZHM_NPCStatus = "Scanning plot • 12-16 studs/s • max 20 studs"
                end
            else
                currentTarget = nil
                ENV.ZHM_NPCBusy = false
                ENV.ZHM_NPCStatus = ENV.ZHM_SweepActive == true and "Paused by sweep" or "OFF"
            end

            task.wait(NPC_SCAN_INTERVAL)
        end

        currentTarget = nil
        ENV.ZHM_NPCBusy = false
        ENV.ZHM_NPCStatus = "Stopped"
    end)

    task.spawn(function()
        while isCurrent() do
            if ENV.ZHM_NPCAutoSwing == true and ENV.ZHM_SweepActive ~= true then
                local target = currentTarget
                local myRoot = getPlayerRoot()

                if target and myRoot and isStillValidRunningTarget(target) then
                    local distance = (myRoot.Position - target.root.Position).Magnitude
                    if distance <= NPC_SWING_MAX_DISTANCE then
                        clickGameplayToSwing()
                    end
                end
            end

            task.wait(NPC_SWING_INTERVAL)
        end
    end)
end

--------------------------------------------------------------------------------
-- 7. SMART POP-UP SUPPRESSOR
--------------------------------------------------------------------------------
local POPUP_KEYWORDS = {
    "bread slots", "fully stocked", "unlocked", "exp bar",
    "pesos reserved", "already baking", "display rack", "prep table", "tip jar"
}

local watchedLabels = setmetatable({}, {__mode = "k"})

local function shouldSuppressText(text)
    text = tostring(text or "")
    local lower = string.lower(text)
    for _, keyword in ipairs(POPUP_KEYWORDS) do
        if string.find(lower, keyword, 1, true) then return true end
    end
    return string.match(text, "%[X%d+%]") ~= nil
end

local function hideNotificationLabel(label)
    if not isCurrent() or not ENV.ZHM_HidePopups then return end
    if not label or not label:IsA("TextLabel") or not shouldSuppressText(label.Text) then return end

    pcall(function()
        if label.Parent and label.Parent:IsA("GuiObject") then
            label.Parent.Visible = false
        else
            label.Visible = false
        end
    end)
end

local function watchNotificationLabel(label)
    if not isCurrent() or not label or not label:IsA("TextLabel") or watchedLabels[label] then return end
    watchedLabels[label] = true
    hideNotificationLabel(label)
    label:GetPropertyChangedSignal("Text"):Connect(function() hideNotificationLabel(label) end)
end

for _, desc in ipairs(playerGui:GetDescendants()) do watchNotificationLabel(desc) end
playerGui.DescendantAdded:Connect(function(desc) if desc:IsA("TextLabel") then watchNotificationLabel(desc) end end)

--------------------------------------------------------------------------------
-- 8. SIMPLE / OPTIMIZED UI
--------------------------------------------------------------------------------
destroyNamedGui("ZHM_MasterUI")

-- Keep every feature enabled on execute.
for _, featureKey in ipairs({
    "ZHM_AutoWalk",
    "ZHM_AutoFarm",
    "ZHM_AutoBuy",
    "ZHM_AutoUpgrade",
    "ZHM_AutoAccept",
    "ZHM_AutoPrepareDough",
    "ZHM_AutoBake",
    "ZHM_AutoCollect",
    "ZHM_AutoCollectTip",
    "ZHM_AutoGiveOrder",
    "ZHM_AutoEnableBreads",
    "ZHM_HidePopups",
    "ZHM_AutoSweep",
    "ZHM_NPCAutoSwing",
}) do
    ENV[featureKey] = true
end

local UI_BG = Color3.fromRGB(18, 20, 25)
local UI_PANEL = Color3.fromRGB(25, 28, 34)
local UI_PANEL_2 = Color3.fromRGB(33, 37, 45)
local UI_ACCENT = Color3.fromRGB(75, 140, 255)
local UI_TEXT = Color3.fromRGB(242, 244, 248)
local UI_MUTED = Color3.fromRGB(145, 151, 163)
local UI_STROKE = Color3.fromRGB(53, 59, 70)
local UI_DANGER = Color3.fromRGB(235, 92, 92)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZHM_MasterUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 9999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mountGui(screenGui)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Size = UDim2.new(0, 340, 0, 390)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.BackgroundColor3 = UI_BG
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
addCorner(mainFrame, 10)
addStroke(mainFrame, UI_STROKE, 1, 0.15)

local mainScale = Instance.new("UIScale")
mainScale.Scale = 1
mainScale.Parent = mainFrame
applyResponsiveScale(mainScale, 370, 430)

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = UI_PANEL
header.BorderSizePixel = 0
header.Parent = mainFrame
addCorner(header, 10)

local headerMask = Instance.new("Frame")
headerMask.Size = UDim2.new(1, 0, 0, 10)
headerMask.Position = UDim2.new(0, 0, 1, -10)
headerMask.BackgroundColor3 = UI_PANEL
headerMask.BorderSizePixel = 0
headerMask.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -92, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "ZHM HUB"
titleLabel.TextColor3 = UI_TEXT
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 30, 0, 26)
minimizeBtn.Position = UDim2.new(1, -68, 0, 9)
minimizeBtn.BackgroundColor3 = UI_PANEL_2
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = UI_TEXT
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 15
minimizeBtn.Parent = header
addCorner(minimizeBtn, 7)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 26)
closeBtn.Position = UDim2.new(1, -34, 0, 9)
closeBtn.BackgroundColor3 = UI_PANEL_2
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = UI_DANGER
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.Parent = header
addCorner(closeBtn, 7)

closeBtn.Activated:Connect(function()
    screenGui:Destroy()
end)

makeDraggable(header, mainFrame)

local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, -16, 1, -52)
body.Position = UDim2.new(0, 8, 0, 48)
body.BackgroundTransparency = 1
body.Parent = mainFrame

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, 0, 0, 32)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar

local pageHost = Instance.new("Frame")
pageHost.Name = "Pages"
pageHost.Size = UDim2.new(1, 0, 1, -38)
pageHost.Position = UDim2.new(0, 0, 0, 38)
pageHost.BackgroundTransparency = 1
pageHost.ClipsDescendants = true
pageHost.Parent = body

local pages = {}
local tabButtons = {}
local infoUpdaters = {}
local TAB_COUNT = 4

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 2
    page.ScrollBarImageColor3 = UI_ACCENT
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = pageHost

    local padding = Instance.new("UIPadding")
    padding.PaddingBottom = UDim.new(0, 6)
    padding.Parent = page

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = page

    pages[name] = page
    return page
end

local function createTab(name, label)
    local button = Instance.new("TextButton")
    button.Name = name .. "Tab"
    button.Size = UDim2.new(1 / TAB_COUNT, -3, 1, 0)
    button.BackgroundColor3 = UI_PANEL
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Text = label
    button.TextColor3 = UI_MUTED
    button.Font = Enum.Font.GothamBold
    button.TextSize = 9
    button.Parent = tabBar
    addCorner(button, 7)

    tabButtons[name] = button
    return button
end

local function setActivePage(name)
    for pageName, page in pairs(pages) do
        page.Visible = pageName == name
    end

    for tabName, button in pairs(tabButtons) do
        local selected = tabName == name
        button.BackgroundColor3 = selected and UI_ACCENT or UI_PANEL
        button.TextColor3 = selected and Color3.fromRGB(255, 255, 255) or UI_MUTED
    end
end

local function createSection(parent, title)
    local label = Instance.new("TextLabel")
    label.Name = title:gsub("%s+", "") .. "Section"
    label.Size = UDim2.new(1, 0, 0, 24)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = UI_MUTED
    label.Font = Enum.Font.GothamBold
    label.TextSize = 9
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function createToggle(parent, title, description, envKey, defaultValue, masterKey)
    if ENV[envKey] == nil then ENV[envKey] = defaultValue == true end

    local row = Instance.new("Frame")
    row.Name = envKey
    row.Size = UDim2.new(1, 0, 0, description and 50 or 42)
    row.BackgroundColor3 = UI_PANEL
    row.BorderSizePixel = 0
    row.Parent = parent
    addCorner(row, 8)
    addStroke(row, UI_STROKE, 1, 0.45)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -82, 0, 18)
    label.Position = UDim2.new(0, 10, 0, description and 6 or 11)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = UI_TEXT
    label.Font = Enum.Font.GothamBold
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local desc = nil
    if description then
        desc = Instance.new("TextLabel")
        desc.Size = UDim2.new(1, -82, 0, 18)
        desc.Position = UDim2.new(0, 10, 0, 25)
        desc.BackgroundTransparency = 1
        desc.Text = description
        desc.TextColor3 = UI_MUTED
        desc.Font = Enum.Font.Gotham
        desc.TextSize = 7
        desc.TextTruncate = Enum.TextTruncate.AtEnd
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.Parent = row
    end

    local switch = Instance.new("TextButton")
    switch.Name = "Switch"
    switch.Size = UDim2.new(0, 54, 0, 28)
    switch.Position = UDim2.new(1, -64, 0.5, -14)
    switch.BorderSizePixel = 0
    switch.AutoButtonColor = true
    switch.Font = Enum.Font.GothamBold
    switch.TextSize = 9
    switch.Parent = row
    addCorner(switch, 7)

    local function refresh()
        local enabled = ENV[envKey] == true
        local masterEnabled = not masterKey or ENV[masterKey] == true

        switch.Text = enabled and "ON" or "OFF"
        switch.BackgroundColor3 = enabled and UI_ACCENT or UI_PANEL_2
        switch.TextColor3 = enabled and Color3.fromRGB(255, 255, 255) or UI_MUTED

        local disabledByMaster = masterKey and not masterEnabled
        row.BackgroundTransparency = disabledByMaster and 0.25 or 0
        label.TextTransparency = disabledByMaster and 0.35 or 0
        if desc then desc.TextTransparency = disabledByMaster and 0.45 or 0 end
        switch.BackgroundTransparency = disabledByMaster and 0.2 or 0
    end

    switch.Activated:Connect(function()
        ENV[envKey] = not (ENV[envKey] == true)
        refresh()
    end)

    refresh()
    return {Row = row, Refresh = refresh, Switch = switch}
end

local function createInfoCard(parent, title, getText, height)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, height or 62)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local titleLabel2 = Instance.new("TextLabel")
    titleLabel2.Size = UDim2.new(1, -20, 0, 17)
    titleLabel2.Position = UDim2.new(0, 10, 0, 7)
    titleLabel2.BackgroundTransparency = 1
    titleLabel2.Text = title
    titleLabel2.TextColor3 = UI_TEXT
    titleLabel2.Font = Enum.Font.GothamBold
    titleLabel2.TextSize = 9
    titleLabel2.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel2.Parent = card

    local value = Instance.new("TextLabel")
    value.Size = UDim2.new(1, -20, 1, -27)
    value.Position = UDim2.new(0, 10, 0, 24)
    value.BackgroundTransparency = 1
    value.Text = "Ready"
    value.TextColor3 = UI_MUTED
    value.Font = Enum.Font.Gotham
    value.TextSize = 8
    value.TextWrapped = true
    value.TextXAlignment = Enum.TextXAlignment.Left
    value.TextYAlignment = Enum.TextYAlignment.Top
    value.Parent = card

    infoUpdaters[#infoUpdaters + 1] = function()
        if not value.Parent then return end
        local ok, textValue = pcall(getText)
        if ok then value.Text = tostring(textValue or "Ready") end
    end

    return card
end

local farmPage = createPage("Farm")
local movePage = createPage("Movement")
local sidePage = createPage("SideJobs")
local extraPage = createPage("Extra")

local farmTab = createTab("Farm", "FARM")
local moveTab = createTab("Movement", "MOVE")
local sideTab = createTab("SideJobs", "SIDE")
local extraTab = createTab("Extra", "EXTRA")

farmTab.Activated:Connect(function() setActivePage("Farm") end)
moveTab.Activated:Connect(function() setActivePage("Movement") end)
sideTab.Activated:Connect(function() setActivePage("SideJobs") end)
extraTab.Activated:Connect(function() setActivePage("Extra") end)

createSection(farmPage, "Bakery Automation")
local masterFarmToggle = createToggle(farmPage, "Auto Farm", "Master bakery automation switch", "ZHM_AutoFarm", true)
local farmChildren = {
    createToggle(farmPage, "Auto Accept", "Accept customer orders", "ZHM_AutoAccept", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Prepare Dough", "Use prep table automatically", "ZHM_AutoPrepareDough", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Bake", "Bake available bread", "ZHM_AutoBake", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Collect", "Collect from every different BakingRack", "ZHM_AutoCollect", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Collect Tip", "Collect available money from the Tip Jar", "ZHM_AutoCollectTip", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Auto Give Order", "Deliver finished orders at the DisplayRack", "ZHM_AutoGiveOrder", true, "ZHM_AutoFarm"),
    createToggle(farmPage, "Enable Breads", "Enable bread options", "ZHM_AutoEnableBreads", true, "ZHM_AutoFarm"),
}
masterFarmToggle.Switch.Activated:Connect(function()
    task.defer(function()
        for _, toggleObj in ipairs(farmChildren) do
            toggleObj.Refresh()
        end
    end)
end)
createInfoCard(farmPage, "Bakery Status", function()
    return "Farm: " .. (ENV.ZHM_AutoFarm and "Enabled" or "Disabled")
        .. "\nBuy: " .. (ENV.ZHM_AutoBuy and "Enabled" or "Disabled")
        .. "\nUpgrade: " .. (ENV.ZHM_AutoUpgrade and "Enabled" or "Disabled")
end, 66)

createSection(movePage, "Movement")
local rackMovementToggle = createToggle(movePage, "Auto Rack Movement", "Instant TP between baking racks and display rack", "ZHM_AutoWalk", true)
local autoNearestPromptToggle = createToggle(movePage, "Instant Proximity (Night Auto)", "Automatically ON at night • OFF during day", "ZHM_AutoNearestPrompt", false)
createInfoCard(movePage, "Live Movement", function()
    if ENV.ZHM_SweepActive then
        return "Sweep active • rack paused • instant prompts ACTIVE"
    elseif ENV.ZHM_NPCBusy then
        return "NPC TP active • rack movement paused"
    elseif ENV.ZHM_AutoWalk then
        return "Rack TP active • 1s delay • DisplayRack 10s • PrepTable loop"
    end
    return "Movement idle"
end, 56)

-- Automatically disable Rack Movement for the entire night, not only while trash exists.
-- Restore the exact state the user had before night when day returns.
local rackStateBeforeNight = nil
local rackNightLock = false

local function guiVisibleForNightCheck(obj)
    if not obj or not obj:IsA("GuiObject") or not obj.Visible then return false end
    local current = obj.Parent
    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        current = current.Parent
    end
    return true
end

local function detectNightForRack()
    local weatherUI = playerGui:FindFirstChild("WeatherUI")
    local frame = weatherUI and weatherUI:FindFirstChild("Frame")
    if not frame then return false end

    local night = frame:FindFirstChild("Night")
    local day = frame:FindFirstChild("Day")

    if night and guiVisibleForNightCheck(night) then return true end
    if day and guiVisibleForNightCheck(day) then return false end

    for _, obj in ipairs(frame:GetDescendants()) do
        local lower = obj.Name:lower()
        if lower == "night" and guiVisibleForNightCheck(obj) then
            return true
        elseif lower == "day" and guiVisibleForNightCheck(obj) then
            return false
        end
    end

    return false
end

task.spawn(function()
    local lastPromptNightState = nil

    while isCurrent() do
        local nightNow = detectNightForRack()

        -- Night-only instant proximity automation:
        --   NIGHT = forced ON
        --   DAY   = forced OFF
        -- This is continuously enforced, so manually changing the toggle cannot
        -- accidentally leave instant proximity enabled during daytime.
        local desiredPromptState = nightNow == true
        if ENV.ZHM_AutoNearestPrompt ~= desiredPromptState then
            ENV.ZHM_AutoNearestPrompt = desiredPromptState
            autoNearestPromptToggle.Refresh()
        end

        if lastPromptNightState ~= nightNow then
            lastPromptNightState = nightNow
            report(
                "NearestPrompt",
                nightNow
                    and "Night detected • Instant Proximity automatically ON"
                    or "Day detected • Instant Proximity automatically OFF"
            )
        end

        if nightNow and not rackNightLock then
            rackNightLock = true
            rackStateBeforeNight = ENV.ZHM_AutoWalk == true
            ENV.ZHM_AutoWalk = false
            rackMovementToggle.Refresh()
            report("AutoWalk", "Night detected • Rack Movement automatically OFF")
        elseif not nightNow and rackNightLock then
            rackNightLock = false
            ENV.ZHM_AutoWalk = rackStateBeforeNight == true
            rackStateBeforeNight = nil
            rackMovementToggle.Refresh()
            report("AutoWalk", ENV.ZHM_AutoWalk and "Day detected • Rack Movement restored ON" or "Day detected • Rack Movement remains OFF")
        elseif nightNow and ENV.ZHM_AutoWalk == true then
            ENV.ZHM_AutoWalk = false
            rackMovementToggle.Refresh()
        end

        task.wait(0.25)
    end
end)

createSection(sidePage, "Side Jobs")
createToggle(sidePage, "Night Auto Sweep", "Sweep trash prompts at night", "ZHM_AutoSweep", true)
createToggle(sidePage, "Rolling Pin Swing", "Auto-equip and swing at detected moving NPCs (12-16 studs/sec)", "ZHM_NPCAutoSwing", true)
createInfoCard(sidePage, "Live Scanner", function()
    return "Sweep: " .. tostring(ENV.ZHM_SweepStatus or "Waiting")
        .. "\nNPC: " .. tostring(ENV.ZHM_NPCStatus or "Idle")
end, 64)

createSection(extraPage, "Extra Automation")
createToggle(extraPage, "Auto Buy All Market", "Buy all GUI Market items + world Buy prompts", "ZHM_AutoBuy", true)
createToggle(extraPage, "Auto Upgrade", "Upgrade bakery items", "ZHM_AutoUpgrade", true)
createToggle(extraPage, "Hide Popups", "Suppress known notifications", "ZHM_HidePopups", true)
createInfoCard(extraPage, "Status", function()
    local latestFeature, latestMessage
    for feature, message in pairs(ENV.ZHM_FeatureStatus) do
        latestFeature = feature
        latestMessage = message
    end
    if latestFeature and latestMessage then
        return tostring(latestFeature) .. ": " .. tostring(latestMessage)
    end
    return "Ready"
end, 58)

-- One shared status refresh loop instead of one loop per card.
task.spawn(function()
    while isCurrent() and screenGui.Parent do
        for _, updater in ipairs(infoUpdaters) do
            updater()
        end
        task.wait(0.5)
    end
end)

-- Simple compact mode. No tweens, shadows, pulsing, or animated gradients.
local minimized = false
local expandedSize = mainFrame.Size
local expandedPosition = mainFrame.Position

local miniButton = Instance.new("TextButton")
miniButton.Name = "MiniButton"
miniButton.AnchorPoint = Vector2.new(0.5, 0.5)
miniButton.Size = UDim2.new(0, 46, 0, 46)
miniButton.Position = expandedPosition
miniButton.BackgroundColor3 = UI_PANEL
miniButton.BorderSizePixel = 0
miniButton.Text = "Z"
miniButton.TextColor3 = UI_TEXT
miniButton.Font = Enum.Font.GothamBold
miniButton.TextSize = 16
miniButton.Visible = false
miniButton.Parent = screenGui
addCorner(miniButton, 10)
addStroke(miniButton, UI_STROKE, 1, 0.15)

makeDraggable(miniButton, miniButton)

local function setMinimized(value)
    minimized = value == true
    if minimized then
        miniButton.Position = mainFrame.Position
        mainFrame.Visible = false
        miniButton.Visible = true
    else
        mainFrame.Position = miniButton.Position
        miniButton.Visible = false
        mainFrame.Visible = true
    end
end

minimizeBtn.Activated:Connect(function()
    setMinimized(true)
end)

miniButton.Activated:Connect(function()
    setMinimized(false)
end)

setActivePage("Farm")
startAutomation()

task.delay(0.45, function()
    if screenGui and screenGui.Parent and not minimized then
        setMinimized(true)
    end
end)

print("[ZHM Simple UI] Loaded: optimized UI + existing automation")

