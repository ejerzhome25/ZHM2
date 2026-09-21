-- // Services Setup
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- Localized fast-path references
local task_wait = task.wait
local string_lower = string.lower
local string_find = string.find
local math_clamp = math.clamp
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_huge = math.huge
local Vector3_new = Vector3.new
local CFrame_new = CFrame.new

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

if ENV.ZHM_AutoSweep == nil then ENV.ZHM_AutoSweep = true end
if ENV.ZHM_NPCAutoTP == nil then ENV.ZHM_NPCAutoTP = true end
if ENV.ZHM_NPCAutoSwing == nil then ENV.ZHM_NPCAutoSwing = true end
ENV.ZHM_SweepActive = false
ENV.ZHM_NPCBusy = false
ENV.ZHM_NPCStatus = "Idle"
ENV.ZHM_SweepStatus = "Waiting"
if type(ENV.CashierAutoAccept) == "table" then
    ENV.CashierAutoAccept.Enabled = false
    ENV.CashierAutoAccept = nil
end

local THEME = {
    Background  = Color3.fromRGB(12, 14, 20),
    Surface     = Color3.fromRGB(18, 22, 30),
    Surface2    = Color3.fromRGB(25, 31, 42),
    Surface3    = Color3.fromRGB(35, 43, 58),
    Accent      = Color3.fromRGB(99, 102, 241),
    Accent2     = Color3.fromRGB(129, 140, 248),
    Success     = Color3.fromRGB(34, 197, 94),
    Danger      = Color3.fromRGB(239, 68, 68),
    Warning     = Color3.fromRGB(245, 158, 11),
    Text        = Color3.fromRGB(243, 244, 246),
    Muted       = Color3.fromRGB(156, 163, 175),
    Stroke      = Color3.fromRGB(45, 55, 72)
}

local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
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
    local baseColor = button.BackgroundColor3

    button.MouseEnter:Connect(function()
        if hoverColor then button.BackgroundColor3 = hoverColor end
    end)

    button.MouseLeave:Connect(function()
        if hoverColor then button.BackgroundColor3 = baseColor end
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
        local widthScale = viewport.X / (baseWidth or 340)
        local heightScale = viewport.Y / (baseHeight or 400)
        local scale = math_clamp(math_min(widthScale, heightScale, 1), 0.6, 1)

        scaleObject.Scale = scale
        scaleObject:SetAttribute("ResponsiveScale", scale)
    end

    update()

    if Workspace.CurrentCamera then
        Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
    end

    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        task_wait()
        update()
    end)

    return update
end

--------------------------------------------------------------------------------
-- 0. KEY SYSTEM
--------------------------------------------------------------------------------
local CORRECT_KEY = "TANGINAMO"

destroyNamedGui("ZHM_KeySystemUI")

local keyScreenGui = Instance.new("ScreenGui")
keyScreenGui.Name = "ZHM_KeySystemUI"
keyScreenGui.ResetOnSpawn = false
keyScreenGui.IgnoreGuiInset = false
keyScreenGui.DisplayOrder = 99999
keyScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mountGui(keyScreenGui)

local keyCard = Instance.new("Frame")
keyCard.Name = "KeyCard"
keyCard.AnchorPoint = Vector2.new(0.5, 0.5)
keyCard.Size = UDim2.new(0, 290, 0, 170)
keyCard.Position = UDim2.new(0.5, 0, 0.46, 0)
keyCard.BackgroundColor3 = THEME.Surface
keyCard.BorderSizePixel = 0
keyCard.Parent = keyScreenGui
addCorner(keyCard, 12)
addStroke(keyCard, THEME.Stroke, 1, 0.2)

local keyScale = Instance.new("UIScale")
keyScale.Scale = 0.9
keyScale.Parent = keyCard
applyResponsiveScale(keyScale, 340, 400)

local keyAccent = Instance.new("Frame")
keyAccent.Size = UDim2.new(1, 0, 0, 3)
keyAccent.BackgroundColor3 = THEME.Accent
keyAccent.BorderSizePixel = 0
keyAccent.ZIndex = 2
keyAccent.Parent = keyCard
addGradient(keyAccent, THEME.Accent, THEME.Accent2, 0)

local keyBadge = Instance.new("Frame")
keyBadge.Size = UDim2.new(0, 30, 0, 30)
keyBadge.Position = UDim2.new(0, 14, 0, 14)
keyBadge.BackgroundColor3 = THEME.Accent
keyBadge.BorderSizePixel = 0
keyBadge.ZIndex = 2
keyBadge.Parent = keyCard
addCorner(keyBadge, 8)

local keyBadgeText = Instance.new("TextLabel")
keyBadgeText.Size = UDim2.fromScale(1, 1)
keyBadgeText.BackgroundTransparency = 1
keyBadgeText.Text = "Z"
keyBadgeText.TextColor3 = THEME.Text
keyBadgeText.Font = Enum.Font.GothamBold
keyBadgeText.TextSize = 16
keyBadgeText.ZIndex = 3
keyBadgeText.Parent = keyBadge

local keyTitle = Instance.new("TextLabel")
keyTitle.Size = UDim2.new(1, -60, 0, 18)
keyTitle.Position = UDim2.new(0, 52, 0, 12)
keyTitle.BackgroundTransparency = 1
keyTitle.Text = "ZHM HUB"
keyTitle.TextColor3 = THEME.Text
keyTitle.Font = Enum.Font.GothamBold
keyTitle.TextSize = 13
keyTitle.TextXAlignment = Enum.TextXAlignment.Left
keyTitle.ZIndex = 2
keyTitle.Parent = keyCard

local keySubtitle = Instance.new("TextLabel")
keySubtitle.Size = UDim2.new(1, -60, 0, 14)
keySubtitle.Position = UDim2.new(0, 52, 0, 28)
keySubtitle.BackgroundTransparency = 1
keySubtitle.Text = "Enter key to access script"
keySubtitle.TextColor3 = THEME.Muted
keySubtitle.Font = Enum.Font.Gotham
keySubtitle.TextSize = 9
keySubtitle.TextXAlignment = Enum.TextXAlignment.Left
keySubtitle.ZIndex = 2
keySubtitle.Parent = keyCard

local keyInputWrap = Instance.new("Frame")
keyInputWrap.Size = UDim2.new(1, -28, 0, 34)
keyInputWrap.Position = UDim2.new(0, 14, 0, 58)
keyInputWrap.BackgroundColor3 = THEME.Surface2
keyInputWrap.BorderSizePixel = 0
keyInputWrap.ZIndex = 2
keyInputWrap.Parent = keyCard
addCorner(keyInputWrap, 8)
local keyInputStroke = addStroke(keyInputWrap, THEME.Stroke, 1, 0.3)

local keyTextBox = Instance.new("TextBox")
keyTextBox.Size = UDim2.new(1, -16, 1, 0)
keyTextBox.Position = UDim2.new(0, 8, 0, 0)
keyTextBox.BackgroundTransparency = 1
keyTextBox.Text = ""
keyTextBox.TextColor3 = THEME.Text
keyTextBox.PlaceholderText = "Paste access key..."
keyTextBox.PlaceholderColor3 = THEME.Muted
keyTextBox.Font = Enum.Font.GothamMedium
keyTextBox.TextSize = 11
keyTextBox.ClearTextOnFocus = false
keyTextBox.TextXAlignment = Enum.TextXAlignment.Left
keyTextBox.ZIndex = 3
keyTextBox.Parent = keyInputWrap

keyTextBox.Focused:Connect(function()
    keyInputStroke.Color = THEME.Accent
    keyInputStroke.Transparency = 0
end)

keyTextBox.FocusLost:Connect(function()
    keyInputStroke.Color = THEME.Stroke
    keyInputStroke.Transparency = 0.3
end)

local submitBtn = Instance.new("TextButton")
submitBtn.Size = UDim2.new(1, -28, 0, 32)
submitBtn.Position = UDim2.new(0, 14, 0, 102)
submitBtn.BackgroundColor3 = THEME.Accent
submitBtn.BorderSizePixel = 0
submitBtn.Text = "UNLOCK HUB"
submitBtn.TextColor3 = THEME.Text
submitBtn.Font = Enum.Font.GothamBold
submitBtn.TextSize = 11
submitBtn.ZIndex = 2
submitBtn.Parent = keyCard
addCorner(submitBtn, 8)
bindPressAnimation(submitBtn, Color3.fromRGB(110, 114, 245))

makeDraggable(keyCard, keyCard)

local keyValidated = false
local keyBusy = false

local function validateKey()
    if keyBusy or keyValidated then return end
    keyBusy = true

    if keyTextBox.Text == CORRECT_KEY then
        keyValidated = true
        submitBtn.Text = "ACCESS GRANTED"
        submitBtn.BackgroundColor3 = THEME.Success
        keyInputStroke.Color = THEME.Success
        keyInputStroke.Transparency = 0
        task_wait(0.1)

        if keyScreenGui then keyScreenGui:Destroy() end
    else
        submitBtn.Text = "INVALID KEY"
        submitBtn.BackgroundColor3 = THEME.Danger
        keyInputStroke.Color = THEME.Danger
        keyInputStroke.Transparency = 0
        task_wait(0.3)
        submitBtn.Text = "UNLOCK HUB"
        submitBtn.BackgroundColor3 = THEME.Accent
        keyInputStroke.Color = THEME.Stroke
        keyInputStroke.Transparency = 0.3
        keyBusy = false
    end
end

submitBtn.Activated:Connect(validateKey)
keyTextBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then validateKey() end
end)

repeat task_wait() until keyValidated or ENV.ZHM_Controller ~= controller
if ENV.ZHM_Controller ~= controller then return end

--------------------------------------------------------------------------------
-- STATIONARY AUTOMATION
--------------------------------------------------------------------------------
ENV.ZHM_AutoFarm = ENV.ZHM_AutoFarm == true
ENV.ZHM_AutoBuy = ENV.ZHM_AutoBuy == true
ENV.ZHM_AutoUpgrade = ENV.ZHM_AutoUpgrade == true
for _, key in ipairs({ "ZHM_AutoAccept", "ZHM_AutoPrepareDough", "ZHM_AutoBake", "ZHM_AutoCollect", "ZHM_AutoEnableBreads", "ZHM_HidePopups" }) do
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

    if ENV.ZHM_SweepActive == true then
        return false
    end

    if key == "ZHM_AutoWalk" and ENV.ZHM_NPCBusy == true then
        return false
    end

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
    local now = os.clock()
    if not last or now - last >= 20 then
        notices[feature] = now
        warn("[ZHM/" .. feature .. "] " .. message)
    end
end

local function resolve(root, names)
    for i = 1, #names do
        root = root and root:FindFirstChild(names[i])
        if not root then return nil end
    end
    return root
end

local function ui(names)
    return resolve(player:FindFirstChildOfClass("PlayerGui"), names)
end

local cachedMyPlot = nil

local function findMyPlot()
    if cachedMyPlot and cachedMyPlot.Parent then
        return cachedMyPlot
    end

    local shops = resolve(Workspace, { "Game", "Shops" })
    if not shops then return nil end

    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    local closestPlot = nil
    local shortestDist = math_huge

    for _, plot in ipairs(shops:GetChildren()) do
        local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")
        if owner and owner:IsA("ValueBase") then
            if owner.Value == player or owner.Value == player.Name or owner.Value == player.UserId then
                cachedMyPlot = plot
                return plot
            end
        end

        if plot:GetAttribute("OwnerUserId") == player.UserId then
            cachedMyPlot = plot
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

    cachedMyPlot = shops:FindFirstChild(ENV.ZHM_PlotName) or closestPlot
    return cachedMyPlot
end

--------------------------------------------------------------------------------
-- AUTO-WALK / RACK MOVEMENT
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
        local lowerName = string_lower(desc.Name)
        if string_find(lowerName, "displayrack", 1, true) or string_find(lowerName, "display", 1, true) then
            local part = getPartFromContainer(desc)
            if part then return part.Position end
        end
    end

    return nil
end

local cachedBakingRacksPlot = nil
local cachedBakingRacks = {}

local function getAllBakingRacks(plot)
    if not plot then return {} end
    if cachedBakingRacksPlot == plot and #cachedBakingRacks > 0 then
        local valid = true
        for i = 1, #cachedBakingRacks do
            if not cachedBakingRacks[i].instance.Parent then
                valid = false
                break
            end
        end
        if valid then return cachedBakingRacks end
    end

    local equipment = plot:FindFirstChild("Equipment") or plot
    local racks = {}
    local seenParts = {}

    for _, desc in ipairs(equipment:GetDescendants()) do
        local lowerName = string_lower(desc.Name)
        if (string_find(lowerName, "bakingrack", 1, true) or string_find(lowerName, "normalbakingrack", 1, true))
            and not string_find(lowerName, "prompt", 1, true) then
            local part = getPartFromContainer(desc)
            if part and not seenParts[part] then
                seenParts[part] = true
                table.insert(racks, { instance = desc, part = part, position = part.Position })
            end
        end
    end

    cachedBakingRacksPlot = plot
    cachedBakingRacks = racks
    return racks
end

local function moveToPosition(targetPos, speed)
    local char = player.Character
    if not char then return false end

    local rootPart = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid then return false end

    speed = speed or 28

    local startCFrame = rootPart.CFrame
    local targetCFrame = CFrame_new(targetPos) * startCFrame.Rotation
    local flatStart = Vector3_new(startCFrame.Position.X, 0, startCFrame.Position.Z)
    local flatTarget = Vector3_new(targetPos.X, 0, targetPos.Z)
    local distance = (flatStart - flatTarget).Magnitude
    local duration = distance / math_max(speed, 1)

    if duration <= 0.05 then
        rootPart.CFrame = targetCFrame
        return true
    end

    local elapsed = 0
    humanoid.PlatformStand = true

    while elapsed < duration do
        if not running("ZHM_AutoWalk") then break end

        local currentChar = player.Character
        local currentRoot = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
        if currentRoot ~= rootPart then break end

        local dt = RunService.Heartbeat:Wait()
        elapsed += dt
        local alpha = math_clamp(elapsed / duration, 0, 1)
        rootPart.CFrame = startCFrame:Lerp(targetCFrame, alpha)
    end

    if humanoid and humanoid.Parent then
        humanoid.PlatformStand = false
    end

    return elapsed >= duration
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

                    for i = 1, #allRacks do
                        local rack = allRacks[i]
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

                        report("AutoWalk", "Moving to BakingRack: " .. nextRack.instance.Name)
                        moveToPosition(nextRack.position + Vector3_new(0, 2.5, 0), 28)

                        if running("ZHM_AutoWalk") then
                            task_wait(0.3)
                        end
                    else
                        local displayPos = getDisplayRackPos(myPlot)

                        if displayPos then
                            report("AutoWalk", "Moving to DisplayRack...")
                            moveToPosition(displayPos + Vector3_new(0, 2.5, 0), 28)

                            if running("ZHM_AutoWalk") then
                                task_wait(3)
                            end
                        else
                            task_wait(0.5)
                        end

                        table.clear(visitedRacks)
                    end
                else
                    task_wait(0.5)
                end
            else
                table.clear(visitedRacks)
                task_wait(0.5)
            end

            task_wait(0.05)
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
        task_wait()
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
            task_wait()
        end
    end
end

local cachedEquipmentPromptsPlot = nil
local cachedEquipmentPrompts = {}

local function collectEquipmentPrompts()
    local plot = findMyPlot()
    if not plot then report("Collect", "Plot unavailable; check ZHM_PlotName."); return end
    
    if cachedEquipmentPromptsPlot ~= plot then
        cachedEquipmentPromptsPlot = plot
        table.clear(cachedEquipmentPrompts)
        for _, prompt in ipairs(plot:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") then
                table.insert(cachedEquipmentPrompts, prompt)
            end
        end
    end

    for i = 1, #cachedEquipmentPrompts do
        if not farming("ZHM_AutoCollect") then return end
        local prompt = cachedEquipmentPrompts[i]
        if prompt and prompt.Parent and prompt.Enabled then
            local name = string_lower(prompt.Name)
            local action = string_lower(prompt.ActionText or "")
            local recognized = name == "pickupllaneraprompt" or name == "displayrackprompt"
                or name == "rackdeliverprompt" or string_find(name, "collect", 1, true)
                or string_find(name, "pickup", 1, true) or action == "collect" or action == "give order"
            if recognized and name ~= "bakeprompt" and name ~= "cashierprompt" then
                firePromptSafe(prompt, "Collect")
                task_wait()
            end
        end
    end
end

-- MARKET AUTO BUY
local MARKET_CATEGORY_DELAY = 0.12
local MARKET_BUY_DELAY = 0.035
local MARKET_EMPTY_WAIT = 0.30

local function marketVisible(guiObject)
    if not guiObject or not guiObject:IsA("GuiObject") or not guiObject.Visible then
        return false
    end

    local current = guiObject.Parent
    while current and current ~= playerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        current = current.Parent
    end

    return true
end

local function marketButtonFrom(container)
    if not container then return nil end
    if container:IsA("GuiButton") then return container end
    return container:FindFirstChildWhichIsA("GuiButton", true)
end

local function marketClick(container)
    local button = marketButtonFrom(container)
    if not button then return false end

    if type(getconnections) == "function" then
        for _, eventName in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Up", "MouseButton1Down" }) do
            local signal = button[eventName]
            if signal then
                local ok, connections = pcall(getconnections, signal)
                if ok and connections then
                    local fired = false
                    for _, connection in ipairs(connections) do
                        if connection.Enabled ~= false and connection.ForeignState ~= true
                            and connection.LuaConnection ~= false and type(connection.Fire) == "function" then
                            local success = pcall(function()
                                if eventName == "Activated" then
                                    connection:Fire(nil, 1)
                                elseif eventName == "MouseButton1Down" or eventName == "MouseButton1Up" then
                                    local center = button.AbsolutePosition + button.AbsoluteSize / 2
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

    if marketVisible(button) and button.AbsoluteSize.X > 0 and button.AbsoluteSize.Y > 0 then
        local center = button.AbsolutePosition + button.AbsoluteSize / 2
        local x, y = math_floor(center.X), math_floor(center.Y)
        local ok = pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task_wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        if ok then return true end
    end

    return false
end

local function getMarketFrame()
    local mainUI = playerGui:FindFirstChild("MainUI")
    local market = mainUI and mainUI:FindFirstChild("Market", true)
    if not market then return nil end
    return market:FindFirstChild("Frame") or market:FindFirstChild("Frame", true)
end

local function marketVisibleInside(guiObject, stopAt)
    local current = guiObject
    while current and current ~= stopAt do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        current = current.Parent
    end
    return current == stopAt
end

local function getMarketCategoryRoot(frame)
    if not frame then return nil end
    return frame:FindFirstChild("Category") or frame:FindFirstChild("Category", true)
end

local function collectMarketCategories(categoryRoot)
    local categories = {}
    if not categoryRoot then return categories end

    if categoryRoot:IsA("GuiButton") then
        categories[#categories + 1] = categoryRoot
    end

    for _, obj in ipairs(categoryRoot:GetDescendants()) do
        if obj:IsA("GuiButton") and marketVisibleInside(obj, categoryRoot) then
            categories[#categories + 1] = obj
        end
    end

    table.sort(categories, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    return categories
end

local function isMarketBuyButton(button, categoryRoot)
    if not button or not button:IsA("GuiButton") then return false end
    if categoryRoot and button:IsDescendantOf(categoryRoot) then return false end

    local ownName = string_lower(button.Name or "")
    local ownText = button:IsA("TextButton") and string_lower(button.Text or "") or ""

    if ownName == "buy" or ownName == "money"
        or string_find(ownName, "buy", 1, true)
        or ownText == "buy" or string_find(ownText, "buy", 1, true) then
        return true
    end

    local current = button.Parent
    for _ = 1, 4 do
        if not current then break end
        local name = string_lower(current.Name or "")
        if name == "buy" or name == "money" or string_find(name, "buy", 1, true) then
            return true
        end
        current = current.Parent
    end

    return false
end

local function collectMarketBuyButtons(frame, categoryRoot)
    local buttons = {}
    local seen = {}
    if not frame then return buttons end

    for _, obj in ipairs(frame:GetDescendants()) do
        if obj:IsA("GuiButton") and not seen[obj]
            and marketVisibleInside(obj, frame)
            and isMarketBuyButton(obj, categoryRoot) then
            seen[obj] = true
            buttons[#buttons + 1] = obj
        end
    end

    table.sort(buttons, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    return buttons
end

local function autoBuyMarket()
    if not running("ZHM_AutoBuy") then return end

    local frame = getMarketFrame()
    if not frame then
        report("Market", "MainUI.Market.Frame unavailable; waiting for Market UI.")
        task_wait(MARKET_EMPTY_WAIT)
        return
    end

    local categoryRoot = getMarketCategoryRoot(frame)
    local categories = collectMarketCategories(categoryRoot)

    local passes = math_max(#categories, 1)
    local totalBought = 0

    for index = 1, passes do
        if not running("ZHM_AutoBuy") then return end

        frame = getMarketFrame() or frame
        categoryRoot = getMarketCategoryRoot(frame)

        if #categories > 0 then
            local liveCategories = collectMarketCategories(categoryRoot)
            local categoryButton = liveCategories[index] or categories[index]
            if categoryButton and categoryButton.Parent then
                marketClick(categoryButton)
                task_wait(MARKET_CATEGORY_DELAY)
                RunService.Heartbeat:Wait()
            end
        end

        if not running("ZHM_AutoBuy") then return end

        frame = getMarketFrame() or frame
        categoryRoot = getMarketCategoryRoot(frame)
        local buyButtons = collectMarketBuyButtons(frame, categoryRoot)

        if #buyButtons == 0 then
            local deadline = os.clock() + MARKET_EMPTY_WAIT
            repeat
                task_wait(0.03)
                frame = getMarketFrame() or frame
                categoryRoot = getMarketCategoryRoot(frame)
                buyButtons = collectMarketBuyButtons(frame, categoryRoot)
            until #buyButtons > 0 or os.clock() >= deadline or not running("ZHM_AutoBuy")
        end

        for _, buyButton in ipairs(buyButtons) do
            if not running("ZHM_AutoBuy") then return end
            if buyButton and buyButton.Parent and marketClick(buyButton) then
                totalBought += 1
            end
            task_wait(MARKET_BUY_DELAY)
        end
    end

    if totalBought > 0 then
        report("Market", "Auto Buy dispatched " .. tostring(totalBought) .. " purchase button(s).")
    else
        report("Market", "No active Buy/Money buttons detected yet.")
        task_wait(MARKET_EMPTY_WAIT)
    end
end

local function autoUpgradeBakery()
    local items = ui({ "MainUI", "Bakery", "Frame", "ScrollingFrame", "Upgrade", "Items" })
    if not items then report("Upgrade", "Upgrade Money controls unavailable."); return end
    for _, item in ipairs(sortedChildren(items)) do
        if not running("ZHM_AutoUpgrade") then return end
        local button = resolve(item, { "Main_Frame", "Buttons", "Money" })
        if button then triggerButton(button, "Upgrade"); task_wait() end
    end
end

local farmJobs = {
    { Key = "ZHM_AutoAccept", Name = "Accept", Interval = 0.05, Run = autoAccept },
    { Key = "ZHM_AutoPrepareDough", Name = "Dough", Interval = 0.1, Run = autoPrepareDough },
    { Key = "ZHM_AutoBake", Name = "Bake", Interval = 0.1, Run = bakeAllBreads },
    { Key = "ZHM_AutoCollect", Name = "Collect", Interval = 0.05, Run = collectEquipmentPrompts },
    { Key = "ZHM_AutoEnableBreads", Name = "Breads", Interval = 0.2, Run = autoEnableBreads },
}

local function startAutomation()
    task.spawn(function()
        local nextRun = {}
        while isCurrent() do
            local now = os.clock()
            for i = 1, #farmJobs do
                local job = farmJobs[i]
                if farming(job.Key) and now >= (nextRun[job.Key] or 0) then
                    local ok, err = pcall(job.Run)
                    if not ok then report(job.Name, tostring(err)) end
                    nextRun[job.Key] = now + job.Interval
                end
            end
            task_wait()
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
                task_wait()
            end
        end)
    end
end

startAutomation()

--------------------------------------------------------------------------------
-- NIGHT TRASH AUTO SWEEP
--------------------------------------------------------------------------------
do
    local SWEEP_SCAN_INTERVAL = 0.15
    local SWEEP_TP_HEIGHT_OFFSET = 2.5
    local SWEEP_TP_BACK_OFFSET = 1.5
    local SWEEP_PROMPT_FIRE_DELAY = 0.08
    local SWEEP_LOOP_DELAY = 0.15

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
            local lower = string_lower(obj.Name)
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
                local name = string_lower(obj.Name)
                local action = string_lower(tostring(obj.ActionText or ""))

                if name == "sweep"
                    or name == "sweepprompt"
                    or string_find(name, "sweep", 1, true)
                    or string_find(action, "sweep", 1, true) then
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
            local distA = partA and (root.Position - partA.Position).Magnitude or math_huge
            local distB = partB and (root.Position - partB.Position).Magnitude or math_huge
            return distA < distB
        end)

        return prompts
    end

    local function teleportToPrompt(prompt)
        local root = getRoot()
        local part = getPromptPart(prompt)
        if not root or not part then return false end

        root.CFrame = part.CFrame * CFrame_new(0, SWEEP_TP_HEIGHT_OFFSET, SWEEP_TP_BACK_OFFSET)
        return true
    end

    local function makePromptInstant(prompt)
        if not prompt then return end
        pcall(function() prompt.HoldDuration = 0 end)
        pcall(function() prompt.MaxActivationDistance = math_max(prompt.MaxActivationDistance, 15) end)
        pcall(function() prompt.RequiresLineOfSight = false end)
    end

    local function fireSweepPrompt(prompt)
        if not prompt or not prompt.Parent or not prompt.Enabled then return false end
        makePromptInstant(prompt)

        if type(fireproximityprompt) == "function" then
            local ok = pcall(function() fireproximityprompt(prompt) end)
            return ok
        end

        return false
    end

    task.spawn(function()
        while isCurrent() do
            if ENV.ZHM_AutoSweep ~= true then
                ENV.ZHM_SweepActive = false
                ENV.ZHM_SweepStatus = "OFF"
                task_wait(0.2)
            elseif isNight() then
                local prompts = sortPromptsByDistance(getSweepPrompts())

                if #prompts > 0 then
                    ENV.ZHM_SweepActive = true
                    ENV.ZHM_NPCBusy = false
                    ENV.ZHM_SweepStatus = "Sweeping " .. tostring(#prompts) .. " target(s)"

                    for i = 1, #prompts do
                        local prompt = prompts[i]
                        if not isCurrent() or ENV.ZHM_AutoSweep ~= true or not isNight() then
                            break
                        end

                        if prompt and prompt.Parent and prompt.Enabled and teleportToPrompt(prompt) then
                            task_wait(SWEEP_PROMPT_FIRE_DELAY)
                            if not isNight() then break end
                            fireSweepPrompt(prompt)
                            task_wait(SWEEP_LOOP_DELAY)
                        end
                    end
                else
                    ENV.ZHM_SweepActive = false
                    ENV.ZHM_SweepStatus = "Night • no trash"
                end

                task_wait(SWEEP_SCAN_INTERVAL)
            else
                ENV.ZHM_SweepActive = false
                ENV.ZHM_SweepStatus = "Waiting for night"
                task_wait(0.25)
            end
        end

        ENV.ZHM_SweepActive = false
        ENV.ZHM_SweepStatus = "Stopped"
    end)
end

--------------------------------------------------------------------------------
-- RUNNING NPC AUTO TP + ROLLING PIN SWING
--------------------------------------------------------------------------------
do
    local ROLLING_PIN_SLOT = "1"
    local rollingPinEquippedThisCharacter = false
    local equipInProgress = false

    local MIN_TARGET_SPEED = 12
    local MAX_TARGET_SPEED = 16
    local NPC_SCAN_INTERVAL = 0.08
    local NPC_MAX_DISTANCE = 2500
    local NPC_PLOT_SCAN_RADIUS = 20
    local NPC_TP_HEIGHT_OFFSET = 2.5
    local NPC_TP_BACK_OFFSET = 2
    local NPC_TP_COOLDOWN = 0.25
    local NPC_SWING_INTERVAL = 0.08
    local NPC_CLICK_HOLD_TIME = 0.025
    local NPC_SWING_MAX_DISTANCE = 15

    local lastTeleport = 0
    local cachedPlot = nil
    local currentTarget = nil

    local activeHumanoids = {}

    local function registerHumanoid(desc)
        if desc:IsA("Humanoid") then
            activeHumanoids[desc] = true
        end
    end

    local function unregisterHumanoid(desc)
        if desc:IsA("Humanoid") then
            activeHumanoids[desc] = nil
        end
    end

    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("Humanoid") then
            activeHumanoids[desc] = true
        end
    end

    Workspace.DescendantAdded:Connect(registerHumanoid)
    Workspace.DescendantRemoving:Connect(unregisterHumanoid)

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
        local x = math_floor(pos.X + size.X / 2)
        local y = math_floor(pos.Y + size.Y / 2)

        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task_wait(0.05)
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
            task_wait(0.1)
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
        cachedMyPlot = nil
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
        return Players:GetPlayerFromCharacter(model) ~= nil
    end

    local function getHorizontalSpeed(part)
        if not part then return 0 end
        local velocity = part.AssemblyLinearVelocity
        return Vector3_new(velocity.X, 0, velocity.Z).Magnitude
    end

    local function isTargetSpeed(speed)
        return type(speed) == "number"
            and speed == speed
            and speed >= MIN_TARGET_SPEED
            and speed <= MAX_TARGET_SPEED
    end

    local function isStillValidRunningTarget(target)
        if not target or not target.model or not target.model.Parent then return false end
        if isPlayerCharacter(target.model) then return false end
        if not target.root or not target.root.Parent or not target.root:IsA("BasePart") then return false end
        if not target.humanoid or not target.humanoid.Parent or target.humanoid.Health <= 0 then return false end

        local currentSpeed = getHorizontalSpeed(target.root)
        if not isTargetSpeed(currentSpeed) then
            return false
        end

        target.speed = currentSpeed
        return true
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

    local function plotDistanceFromPlayer(plot)
        local myRoot = getPlayerRoot()
        if not myRoot or not plot then return math_huge end

        local scanRoot = getPlotPositionFolder(plot)
        local nearest = math_huge
        if scanRoot:IsA("BasePart") then
            nearest = (myRoot.Position - scanRoot.Position).Magnitude
        end

        for _, obj in ipairs(scanRoot:GetDescendants()) do
            if obj:IsA("BasePart") then
                local d = (myRoot.Position - obj.Position).Magnitude
                if d < nearest then nearest = d end
            end
        end

        return nearest
    end

    local function findNPCPlot()
        if cachedPlot and cachedPlot.Parent then return cachedPlot end

        local gameFolder = Workspace:FindFirstChild("Game")
        local shops = gameFolder and gameFolder:FindFirstChild("Shops")
        if not shops then return nil end

        for _, plot in ipairs(shops:GetChildren()) do
            local owner = plot:FindFirstChild("Owner")
                or plot:FindFirstChild("Player")
                or plot:FindFirstChild("OwnerPlayer")
                or plot:FindFirstChild("PlotOwner")

            if owner and owner:IsA("ValueBase") then
                local value = owner.Value
                if value == player or value == player.Name or value == player.UserId then
                    cachedPlot = plot
                    return plot
                end
            end

            local ownerUserId = plot:GetAttribute("OwnerUserId")
            local ownerName = plot:GetAttribute("Owner")
                or plot:GetAttribute("OwnerName")
                or plot:GetAttribute("PlayerName")

            if ownerUserId == player.UserId or ownerName == player.Name then
                cachedPlot = plot
                return plot
            end
        end

        local closestPlot = nil
        local closestDistance = math_huge
        for _, plot in ipairs(shops:GetChildren()) do
            local d = plotDistanceFromPlayer(plot)
            if d < closestDistance then
                closestDistance = d
                closestPlot = plot
            end
        end

        cachedPlot = closestPlot
        return closestPlot
    end

    local function distanceToMyPlot(position, plot)
        if not position or not plot then return math_huge end
        local scanRoot = getPlotPositionFolder(plot)
        if not scanRoot then return math_huge end

        local nearest = math_huge
        if scanRoot:IsA("BasePart") then
            nearest = (position - scanRoot.Position).Magnitude
        end

        for _, obj in ipairs(scanRoot:GetDescendants()) do
            if obj:IsA("BasePart") then
                local d = (position - obj.Position).Magnitude
                if d < nearest then nearest = d end
            end
        end

        if nearest == math_huge then
            for _, obj in ipairs(plot:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local d = (position - obj.Position).Magnitude
                    if d < nearest then nearest = d end
                end
            end
        end

        return nearest
    end

    local function findNearestRunningNPC()
        local myRoot = getPlayerRoot()
        if not myRoot then return nil end

        local myPlot = findNPCPlot()
        if not myPlot then
            ENV.ZHM_NPCStatus = "Waiting for your plot"
            return nil
        end

        local best = nil
        local bestDistance = math_huge
        local seenModels = {}

        for obj in pairs(activeHumanoids) do
            if obj.Parent and obj.Health > 0 then
                local model = obj.Parent
                if model
                    and model:IsA("Model")
                    and not seenModels[model]
                    and not isPlayerCharacter(model) then

                    seenModels[model] = true
                    local root = getModelRoot(model)

                    if root and root:IsA("BasePart") and root.Parent then
                        local plotDistance = distanceToMyPlot(root.Position, myPlot)

                        if plotDistance <= NPC_PLOT_SCAN_RADIUS then
                            local speed = getHorizontalSpeed(root)

                            if isTargetSpeed(speed) then
                                local playerDistance = (myRoot.Position - root.Position).Magnitude

                                if playerDistance <= NPC_MAX_DISTANCE and playerDistance < bestDistance then
                                    bestDistance = playerDistance
                                    best = {
                                        model = model,
                                        root = root,
                                        humanoid = obj,
                                        speed = speed,
                                        distance = playerDistance,
                                        plotDistance = plotDistance,
                                        plot = myPlot,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end

        return best
    end

    local function teleportToNPC(info)
        if ENV.ZHM_NPCAutoTP ~= true then return false end
        if ENV.ZHM_SweepActive == true then return false end
        if not info or not info.model or not info.root or not info.humanoid then return false end
        if not info.model.Parent or not info.root.Parent or not info.humanoid.Parent then return false end
        if isPlayerCharacter(info.model) then return false end
        if info.humanoid.Health <= 0 then return false end

        local exactSpeed = getHorizontalSpeed(info.root)
        if not isTargetSpeed(exactSpeed) then
            return false
        end

        local myPlot = info.plot
        if not myPlot or not myPlot.Parent then
            myPlot = findNPCPlot()
        end
        if not myPlot then return false end

        local exactPlotDistance = distanceToMyPlot(info.root.Position, myPlot)
        if exactPlotDistance > NPC_PLOT_SCAN_RADIUS then
            return false
        end

        local myRoot = getPlayerRoot()
        if not myRoot or not myRoot.Parent then return false end

        exactSpeed = getHorizontalSpeed(info.root)
        if not isTargetSpeed(exactSpeed) then
            return false
        end

        info.speed = exactSpeed
        info.plotDistance = exactPlotDistance
        info.plot = myPlot
        myRoot.CFrame = info.root.CFrame * CFrame_new(0, NPC_TP_HEIGHT_OFFSET, NPC_TP_BACK_OFFSET)
        return true
    end

    local function clickGameplayToSwing()
        local camera = Workspace.CurrentCamera
        if not camera then return false end
        local viewport = camera.ViewportSize
        local x = math_floor(viewport.X * 0.5)
        local y = math_floor(viewport.Y * 0.60)

        return pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task_wait(NPC_CLICK_HOLD_TIME)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    task.spawn(function()
        while isCurrent() do
            local anyNPCFeature = ENV.ZHM_NPCAutoTP == true or ENV.ZHM_NPCAutoSwing == true

            if anyNPCFeature and ENV.ZHM_SweepActive ~= true then
                if ENV.ZHM_NPCAutoSwing == true
                    and not rollingPinEquippedThisCharacter
                    and not equipInProgress then
                    task.spawn(equipRollingPinOnce)
                end

                local target = findNearestRunningNPC()
                if target and isStillValidRunningTarget(target) then
                    currentTarget = target
                    ENV.ZHM_NPCStatus = target.model.Name .. " • " .. string.format("%.1f", target.speed) .. "s/s"

                    if ENV.ZHM_NPCAutoTP == true then
                        ENV.ZHM_NPCBusy = true
                        if os.clock() - lastTeleport >= NPC_TP_COOLDOWN and teleportToNPC(target) then
                            lastTeleport = os.clock()
                        end
                    else
                        ENV.ZHM_NPCBusy = false
                    end
                else
                    currentTarget = nil
                    ENV.ZHM_NPCBusy = false
                    ENV.ZHM_NPCStatus = "Scanning"
                end
            else
                currentTarget = nil
                ENV.ZHM_NPCBusy = false
                ENV.ZHM_NPCStatus = ENV.ZHM_SweepActive == true and "Paused by sweep" or "OFF"
            end

            task_wait(NPC_SCAN_INTERVAL)
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

                if target and target.root and target.root.Parent and myRoot then
                    local speed = getHorizontalSpeed(target.root)
                    local distance = (myRoot.Position - target.root.Position).Magnitude
                    if isTargetSpeed(speed) and distance <= NPC_SWING_MAX_DISTANCE then
                        clickGameplayToSwing()
                    end
                end
            end

            task_wait(NPC_SWING_INTERVAL)
        end
    end)
end

--------------------------------------------------------------------------------
-- SMART POP-UP SUPPRESSOR
--------------------------------------------------------------------------------
local POPUP_KEYWORDS = {
    "bread slots", "fully stocked", "unlocked", "exp bar",
    "pesos reserved", "already baking", "display rack", "prep table", "tip jar"
}

local watchedLabels = setmetatable({}, {__mode = "k"})

local function shouldSuppressText(text)
    text = tostring(text or "")
    local lower = string_lower(text)
    for i = 1, #POPUP_KEYWORDS do
        if string_find(lower, POPUP_KEYWORDS[i], 1, true) then return true end
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
-- ULTRA-COMPACT MODERN CLEAN UI
--------------------------------------------------------------------------------
destroyNamedGui("ZHM_MasterUI")

for _, featureKey in ipairs({
    "ZHM_AutoWalk",
    "ZHM_AutoFarm",
    "ZHM_AutoBuy",
    "ZHM_AutoUpgrade",
    "ZHM_AutoAccept",
    "ZHM_AutoPrepareDough",
    "ZHM_AutoBake",
    "ZHM_AutoCollect",
    "ZHM_AutoEnableBreads",
    "ZHM_HidePopups",
    "ZHM_AutoSweep",
    "ZHM_NPCAutoTP",
    "ZHM_NPCAutoSwing",
}) do
    ENV[featureKey] = true
end

local function tween(obj, duration, props, style, direction)
    if not obj then return nil end
    local ok, tw = pcall(function()
        local info = TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
        local tweenObj = TweenService:Create(obj, info, props)
        tweenObj:Play()
        return tweenObj
    end)
    return ok and tw or nil
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZHM_MasterUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 9999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mountGui(screenGui)

-- Compact main dimensions
local expandedSize = UDim2.new(0, 320, 0, 360)
local minimizedSize = UDim2.new(0, 200, 0, 48)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Size = expandedSize
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.BackgroundColor3 = THEME.Background
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
addCorner(mainFrame, 12)
addStroke(mainFrame, THEME.Stroke, 1, 0.2)

local mainScale = Instance.new("UIScale")
mainScale.Scale = 1
mainScale.Parent = mainFrame
applyResponsiveScale(mainScale, 340, 400)

local shell = Instance.new("Frame")
shell.Size = UDim2.fromScale(1, 1)
shell.BackgroundColor3 = THEME.Background
shell.BorderSizePixel = 0
shell.Parent = mainFrame
addCorner(shell, 12)

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, -12, 0, 36)
header.Position = UDim2.new(0, 6, 0, 6)
header.BackgroundColor3 = THEME.Surface
header.BorderSizePixel = 0
header.ZIndex = 3
header.Parent = shell
addCorner(header, 8)
addStroke(header, THEME.Stroke, 1, 0.4)

local logo = Instance.new("Frame")
logo.Size = UDim2.new(0, 24, 0, 24)
logo.Position = UDim2.new(0, 6, 0.5, -12)
logo.BackgroundColor3 = THEME.Accent
logo.BorderSizePixel = 0
logo.ZIndex = 5
logo.Parent = header
addCorner(logo, 6)

local logoText = Instance.new("TextLabel")
logoText.Size = UDim2.fromScale(1, 1)
logoText.BackgroundTransparency = 1
logoText.Text = "Z"
logoText.TextColor3 = THEME.Text
logoText.Font = Enum.Font.GothamBold
logoText.TextSize = 13
logoText.ZIndex = 6
logoText.Parent = logo

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -100, 1, 0)
titleLabel.Position = UDim2.new(0, 36, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "ZHM HUB"
titleLabel.TextColor3 = THEME.Text
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 12
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 5
titleLabel.Parent = header

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name = "MinimizeButton"
minimizeBtn.Active = true
minimizeBtn.Size = UDim2.new(0, 20, 0, 20)
minimizeBtn.Position = UDim2.new(1, -48, 0.5, -10)
minimizeBtn.BackgroundColor3 = THEME.Surface2
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = THEME.Text
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 13
minimizeBtn.ZIndex = 7
minimizeBtn.Parent = header
addCorner(minimizeBtn, 6)
addStroke(minimizeBtn, THEME.Stroke, 1, 0.5)
bindPressAnimation(minimizeBtn, THEME.Surface3)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.Active = true
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -24, 0.5, -10)
closeBtn.BackgroundColor3 = THEME.Surface2
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = THEME.Danger
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.ZIndex = 7
closeBtn.Parent = header
addCorner(closeBtn, 6)
addStroke(closeBtn, THEME.Stroke, 1, 0.5)
bindPressAnimation(closeBtn, THEME.Surface3)

closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

makeDraggable(header, mainFrame)

local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, -12, 1, -52)
body.Position = UDim2.new(0, 6, 0, 46)
body.BackgroundTransparency = 1
body.ZIndex = 3
body.Parent = shell

--------------------------------------------------------------------------------
-- MINIMIZE FUNCTIONALITY (ULTRA-COMPACT)
--------------------------------------------------------------------------------
local isMinimized = false

local function toggleMinimize()
    isMinimized = not isMinimized
    minimizeBtn.Text = isMinimized and "+" or "−"
    body.Visible = not isMinimized
    tween(mainFrame, 0.18, { Size = isMinimized and minimizedSize or expandedSize })
end

minimizeBtn.MouseButton1Click:Connect(toggleMinimize)

--------------------------------------------------------------------------------
-- TABS & CONTAINER CREATION
--------------------------------------------------------------------------------
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, 0, 0, 26)
tabBar.BackgroundColor3 = THEME.Surface
tabBar.BorderSizePixel = 0
tabBar.ZIndex = 3
tabBar.Parent = body
addCorner(tabBar, 8)
addStroke(tabBar, THEME.Stroke, 1, 0.4)

local tabPadding = Instance.new("UIPadding")
tabPadding.PaddingLeft = UDim.new(0, 4)
tabPadding.PaddingRight = UDim.new(0, 4)
tabPadding.PaddingTop = UDim.new(0, 3)
tabPadding.PaddingBottom = UDim.new(0, 3)
tabPadding.Parent = tabBar

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar

local pageHost = Instance.new("Frame")
pageHost.Name = "Pages"
pageHost.Size = UDim2.new(1, 0, 1, -32)
pageHost.Position = UDim2.new(0, 0, 0, 32)
pageHost.BackgroundTransparency = 1
pageHost.ClipsDescendants = true
pageHost.ZIndex = 3
pageHost.Parent = body

local pages = {}
local tabButtons = {}
local activePage = nil
local TAB_COUNT = 4

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.fromScale(1, 1)
    page.Position = UDim2.new(0, 0, 0, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 2
    page.ScrollBarImageColor3 = THEME.Accent
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.ZIndex = 3
    page.Parent = pageHost

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 2)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.PaddingRight = UDim.new(0, 2)
    padding.Parent = page

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 5)
    layout.Parent = page

    pages[name] = page
    return page
end

local function createTab(name, label)
    local button = Instance.new("TextButton")
    button.Name = name .. "Tab"
    button.Size = UDim2.new(1 / TAB_COUNT, -3, 1, 0)
    button.BackgroundColor3 = THEME.Surface2
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = label
    button.TextColor3 = THEME.Muted
    button.Font = Enum.Font.GothamBold
    button.TextSize = 8.5
    button.ZIndex = 4
    button.Parent = tabBar
    addCorner(button, 6)

    tabButtons[name] = {Button = button}
    
    button.Activated:Connect(function()
        for pageName, page in pairs(pages) do
            page.Visible = (pageName == name)
        end

        for tabName, bundle in pairs(tabButtons) do
            local selected = (tabName == name)
            bundle.Button.BackgroundColor3 = selected and THEME.Accent or THEME.Surface2
            bundle.Button.TextColor3 = selected and THEME.Text or THEME.Muted
        end
    end)

    return button
end

local function createSection(parent, title)
    local section = Instance.new("Frame")
    section.Name = title:gsub("%s+", "") .. "Section"
    section.Size = UDim2.new(1, 0, 0, 22)
    section.BackgroundTransparency = 1
    section.BorderSizePixel = 0
    section.ZIndex = 3
    section.Parent = parent

    local titleLabel2 = Instance.new("TextLabel")
    titleLabel2.Size = UDim2.new(1, 0, 1, 0)
    titleLabel2.Position = UDim2.new(0, 2, 0, 0)
    titleLabel2.BackgroundTransparency = 1
    titleLabel2.Text = title:upper()
    titleLabel2.TextColor3 = THEME.Muted
    titleLabel2.Font = Enum.Font.GothamBold
    titleLabel2.TextSize = 8
    titleLabel2.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel2.ZIndex = 4
    titleLabel2.Parent = section

    return section
end

local function createToggle(parent, title, envKey, defaultValue)
    if ENV[envKey] == nil then ENV[envKey] = defaultValue == true end

    local row = Instance.new("Frame")
    row.Name = envKey
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundColor3 = THEME.Surface
    row.BorderSizePixel = 0
    row.ZIndex = 3
    row.Parent = parent
    addCorner(row, 8)
    local rowStroke = addStroke(row, THEME.Stroke, 1, 0.4)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -50, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = THEME.Text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 9.5
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4
    label.Parent = row

    local switch = Instance.new("TextButton")
    switch.Name = "Switch"
    switch.Size = UDim2.new(0, 34, 0, 18)
    switch.Position = UDim2.new(1, -42, 0.5, -9)
    switch.BackgroundColor3 = THEME.Surface3
    switch.BorderSizePixel = 0
    switch.AutoButtonColor = false
    switch.Text = ""
    switch.ZIndex = 4
    switch.Parent = row
    addCorner(switch, 99)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = THEME.Text
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    knob.Parent = switch
    addCorner(knob, 99)

    local function refresh(animated)
        local enabled = ENV[envKey] == true
        switch.BackgroundColor3 = enabled and THEME.Accent or THEME.Surface3

        local knobPos = enabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        if animated then
            tween(knob, 0.12, {Position = knobPos})
        else
            knob.Position = knobPos
        end
    end

    switch.Activated:Connect(function()
        ENV[envKey] = not (ENV[envKey] == true)
        refresh(true)
    end)

    refresh(false)
    return {Row = row, Refresh = refresh, Switch = switch}
end

local function createInfoCard(parent, title, getValueFunc)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 42)
    card.BackgroundColor3 = THEME.Surface
    card.BorderSizePixel = 0
    card.ZIndex = 3
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, THEME.Stroke, 1, 0.4)

    local titleLabel2 = Instance.new("TextLabel")
    titleLabel2.Size = UDim2.new(1, -16, 0, 14)
    titleLabel2.Position = UDim2.new(0, 8, 0, 6)
    titleLabel2.BackgroundTransparency = 1
    titleLabel2.Text = title
    titleLabel2.TextColor3 = THEME.Muted
    titleLabel2.Font = Enum.Font.GothamBold
    titleLabel2.TextSize = 8
    titleLabel2.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel2.ZIndex = 4
    titleLabel2.Parent = card

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(1, -16, 0, 16)
    valueLabel.Position = UDim2.new(0, 8, 0, 20)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = getValueFunc and getValueFunc() or "N/A"
    valueLabel.TextColor3 = THEME.Accent2
    valueLabel.Font = Enum.Font.GothamMedium
    valueLabel.TextSize = 9
    valueLabel.TextXAlignment = Enum.TextXAlignment.Left
    valueLabel.ZIndex = 4
    valueLabel.Parent = card

    if getValueFunc then
        task.spawn(function()
            while card.Parent and isCurrent() do
                valueLabel.Text = tostring(getValueFunc())
                task_wait(0.5)
            end
        end)
    end

    return card
end

--------------------------------------------------------------------------------
-- PAGE SETUP & CONTROLS
--------------------------------------------------------------------------------
createTab("Farm", "FARM")
createTab("Auto", "AUTO")
createTab("NPC", "NPC")
createTab("Info", "INFO")

local farmPage = createPage("Farm")
local autoPage = createPage("Auto")
local npcPage = createPage("NPC")
local infoPage = createPage("Info")

-- 1. FARM TAB
createSection(farmPage, "Bakery Operations")
createToggle(farmPage, "Auto Walk Racks", "ZHM_AutoWalk", true)
createToggle(farmPage, "Auto Accept Orders", "ZHM_AutoAccept", true)
createToggle(farmPage, "Auto Prep Dough", "ZHM_AutoPrepareDough", true)
createToggle(farmPage, "Auto Bake Breads", "ZHM_AutoBake", true)
createToggle(farmPage, "Auto Collect Items", "ZHM_AutoCollect", true)
createToggle(farmPage, "Auto Enable Breads", "ZHM_AutoEnableBreads", true)

-- 2. AUTO TAB
createSection(autoPage, "Automation Settings")
createToggle(autoPage, "Auto Buy Market", "ZHM_AutoBuy", true)
createToggle(autoPage, "Auto Upgrade Bakery", "ZHM_AutoUpgrade", true)
createToggle(autoPage, "Night Trash Sweep", "ZHM_AutoSweep", true)
createToggle(autoPage, "Hide Game Popups", "ZHM_HidePopups", true)

-- 3. NPC TAB
createSection(npcPage, "Runner NPC Targeter")
createToggle(npcPage, "NPC Auto Teleport", "ZHM_NPCAutoTP", true)
createToggle(npcPage, "NPC Rolling Pin Swing", "ZHM_NPCAutoSwing", true)

-- 4. INFO TAB
createSection(infoPage, "System Status")
createInfoCard(infoPage, "SWEEP STATUS", function() return ENV.ZHM_SweepStatus end)
createInfoCard(infoPage, "NPC TARGET STATUS", function() return ENV.ZHM_NPCStatus end)
createInfoCard(infoPage, "ACTIVE PLOT", function() return (cachedMyPlot and cachedMyPlot.Name) or ENV.ZHM_PlotName or "Searching..." end)

-- Set default page
farmPage.Visible = true
tabButtons["Farm"].Button.BackgroundColor3 = THEME.Accent
tabButtons["Farm"].Button.TextColor3 = THEME.Text