--// NETWORK PAUSE BYPASS
pcall(function()
    game:GetService("CoreGui").RobloxGui["CoreScripts/NetworkPause"]:Destroy()
end)

--// SERVICES
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// EASY CONFIG & PATHS
local GUI_NAME = "ZHM_UI_Template"
local HUB_TITLE = "ZHM HUB - Desk Fan 1"
local MINI_TEXT = "Z"
local CONFIG_FOLDER = "ZHM_HUB"
local CONFIG_FILE = "ZHM_HUB/Config.json"

local TAB_DEFINITIONS = {
    {Key = "Main", Label = "MAIN"},
    {Key = "Auto", Label = "AUTO"},
    {Key = "Misc", Label = "MISC"},
    {Key = "Settings", Label = "SETTINGS"},
}

--// THEME
local UI_BG      = Color3.fromRGB(18, 20, 25)
local UI_PANEL   = Color3.fromRGB(25, 28, 34)
local UI_PANEL_2 = Color3.fromRGB(33, 37, 45)
local UI_ACCENT  = Color3.fromRGB(75, 140, 255)
local UI_TEXT    = Color3.fromRGB(242, 244, 248)
local UI_MUTED   = Color3.fromRGB(145, 151, 163)
local UI_STROKE  = Color3.fromRGB(53, 59, 70)
local UI_DANGER  = Color3.fromRGB(235, 92, 92)

--------------------------------------------------
-- ALWAYS-ON UI CLEANER (CashFrame & Hub Protection)
--------------------------------------------------
local function getCashFrame()
    local gameUI = playerGui:FindFirstChild("GameUI")
    if not gameUI then return nil end
    local HUD = gameUI:FindFirstChild("HUD")
    if not HUD then return nil end
    local bottomLeft = HUD:FindFirstChild("BottomLeft")
    if not bottomLeft then return nil end
    return bottomLeft:FindFirstChild("CashFrame")
end

local function shouldKeep(obj)
    -- 1. Keep Mobile Touch Controls
    local touchGui = playerGui:FindFirstChild("TouchGui")
    if obj.Name == "TouchGui" or (touchGui and obj:IsDescendantOf(touchGui)) then
        return true
    end

    -- 2. Protect ZHM Hub & ESP ScreenGuis
    local rootGui = obj:FindFirstAncestorOfClass("ScreenGui") or (obj:IsA("ScreenGui") and obj)
    if rootGui and (rootGui.Name:find("ZHM") or rootGui.Name:find("Hub") or rootGui.Name == GUI_NAME) then
        return true
    end

    -- 3. Keep CashFrame & Hierarchy
    local cashFrame = getCashFrame()
    if cashFrame then
        if obj == cashFrame or obj:IsDescendantOf(cashFrame) or cashFrame:IsDescendantOf(obj) then
            return true
        end
    end

    return false
end

local function purgeUI()
    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("GuiObject") and not shouldKeep(obj) then
            pcall(function() obj:Destroy() end)
        end
    end
end

-- Run initial cleanup & setup active listener
purgeUI()

playerGui.DescendantAdded:Connect(function(obj)
    if obj:IsA("GuiObject") then
        task.defer(function()
            if obj and obj.Parent and not shouldKeep(obj) then
                pcall(function() obj:Destroy() end)
            end
        end)
    end
end)

--// UI HELPERS
local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 10)
    corner.Parent = parent
    return corner
end

local function addStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or UI_STROKE
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = parent
    return stroke
end

local function getGuiParents()
    local parents = {}
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then table.insert(parents, hui) end
    end
    table.insert(parents, CoreGui)
    table.insert(parents, playerGui)
    return parents
end

local function destroyNamedGui(name)
    for _, parent in ipairs(getGuiParents()) do
        pcall(function()
            local old = parent:FindFirstChild(name)
            if old then old:Destroy() end
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
    if not mounted or not gui.Parent then gui.Parent = playerGui end
    return gui.Parent
end

local function makeDraggable(handle, target)
    target = target or handle
    local dragging, dragInput, dragStart, startPosition
    handle.Active = true

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
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
            target.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
end

local function applyResponsiveScale(scaleObject, baseWidth, baseHeight)
    local viewportConnection, cameraConnection
    local function update()
        local camera = Workspace.CurrentCamera
        if not camera then return end
        local viewport = camera.ViewportSize
        local widthScale = viewport.X / (baseWidth or 420)
        local heightScale = viewport.Y / (baseHeight or 520)
        scaleObject.Scale = math.clamp(math.min(widthScale, heightScale, 1), 0.55, 1)
    end
    local function bindCamera()
        if viewportConnection then viewportConnection:Disconnect() viewportConnection = nil end
        local camera = Workspace.CurrentCamera
        if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update) end
        update()
    end
    bindCamera()
    cameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
    return function()
        if viewportConnection then viewportConnection:Disconnect() end
        if cameraConnection then cameraConnection:Disconnect() end
    end
end

--// CLEAN OLD COPY
destroyNamedGui(GUI_NAME)

--// ROOT GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 9999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mountGui(screenGui)

--// MAIN WINDOW
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Size = UDim2.new(0, 340, 0, 420)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.BackgroundColor3 = UI_BG
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
addCorner(mainFrame, 10)
addStroke(mainFrame, UI_STROKE, 1, 0.15)

local mainScale = Instance.new("UIScale")
mainScale.Scale = 1
mainScale.Parent = mainFrame
local disconnectResponsiveScale = applyResponsiveScale(mainScale, 370, 460)

--// HEADER
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = UI_PANEL
header.BorderSizePixel = 0
header.Parent = mainFrame
addCorner(header, 10)

local headerMask = Instance.new("Frame")
headerMask.Name = "HeaderMask"
headerMask.Size = UDim2.new(1, 0, 0, 10)
headerMask.Position = UDim2.new(0, 0, 1, -10)
headerMask.BackgroundColor3 = UI_PANEL
headerMask.BorderSizePixel = 0
headerMask.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -92, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = HUB_TITLE
titleLabel.TextColor3 = UI_TEXT
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name = "Minimize"
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
closeBtn.Name = "Close"
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

makeDraggable(header, mainFrame)

--// BODY
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
pageHost.ClipsDescendants = false
pageHost.Parent = body

local pages = {}
local tabButtons = {}
local TAB_COUNT = #TAB_DEFINITIONS

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

local function createToggle(parent, title, description, defaultValue, callback)
    local enabled = defaultValue == true
    local row = Instance.new("Frame")
    row.Name = title:gsub("%W+", "") .. "Toggle"
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

    if description then
        local desc = Instance.new("TextLabel")
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
        switch.Text = enabled and "ON" or "OFF"
        switch.BackgroundColor3 = enabled and UI_ACCENT or UI_PANEL_2
        switch.TextColor3 = enabled and Color3.fromRGB(255, 255, 255) or UI_MUTED
    end

    switch.Activated:Connect(function()
        enabled = not enabled
        refresh()
        if callback then task.spawn(callback, enabled) end
    end)

    refresh()
    return {
        Row = row,
        Switch = switch,
        Get = function() return enabled end,
        Set = function(value)
            enabled = value == true
            refresh()
            if callback then task.spawn(callback, enabled) end
        end,
        Refresh = refresh,
    }
end

local function createActionButton(parent, title, description, buttonText, callback)
    local row = Instance.new("Frame")
    row.Name = title:gsub("%W+", "") .. "Button"
    row.Size = UDim2.new(1, 0, 0, description and 50 or 42)
    row.BackgroundColor3 = UI_PANEL
    row.BorderSizePixel = 0
    row.Parent = parent
    addCorner(row, 8)
    addStroke(row, UI_STROKE, 1, 0.45)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -110, 0, 18)
    label.Position = UDim2.new(0, 10, 0, description and 6 or 11)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = UI_TEXT
    label.Font = Enum.Font.GothamBold
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    if description then
        local desc = Instance.new("TextLabel")
        desc.Size = UDim2.new(1, -110, 0, 18)
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

    local btn = Instance.new("TextButton")
    btn.Name = "Btn"
    btn.Size = UDim2.new(0, 85, 0, 28)
    btn.Position = UDim2.new(1, -95, 0.5, -14)
    btn.BackgroundColor3 = UI_ACCENT
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = true
    btn.Text = buttonText or "ACTION"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.Parent = row
    addCorner(btn, 7)

    btn.Activated:Connect(function()
        if callback then task.spawn(callback) end
    end)

    return row
end

local function createInfoCard(parent, title, textValue, height)
    local card = Instance.new("Frame")
    card.Name = title:gsub("%W+", "") .. "Info"
    card.Size = UDim2.new(1, 0, 0, height or 62)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -20, 0, 17)
    titleText.Position = UDim2.new(0, 10, 0, 7)
    titleText.BackgroundTransparency = 1
    titleText.Text = title
    titleText.TextColor3 = UI_TEXT
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 9
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = card

    local value = Instance.new("TextLabel")
    value.Size = UDim2.new(1, -20, 1, -27)
    value.Position = UDim2.new(0, 10, 0, 24)
    value.BackgroundTransparency = 1
    value.Text = textValue or "Ready"
    value.TextColor3 = UI_MUTED
    value.Font = Enum.Font.Gotham
    value.TextSize = 8
    value.TextWrapped = true
    value.TextXAlignment = Enum.TextXAlignment.Left
    value.TextYAlignment = Enum.TextYAlignment.Top
    value.Parent = card

    return {
        Card = card,
        Label = value,
        SetText = function(text) value.Text = tostring(text or "") end,
    }
end

local function createMultiDropdown(parent, title, options, callback)
    local selectedOptions = {}
    local optionButtons = {}
    local isOpen = false

    local card = Instance.new("Frame")
    card.Name = title:gsub("%W+", "") .. "MultiDropdown"
    card.Size = UDim2.new(1, 0, 0, 64)
    card.BackgroundColor3 = UI_PANEL
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.ZIndex = 5
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, UI_STROKE, 1, 0.45)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 18)
    label.Position = UDim2.new(0, 10, 0, 7)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = UI_TEXT
    label.Font = Enum.Font.GothamBold
    label.TextSize = 9
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 6
    label.Parent = card

    local selectBtn = Instance.new("TextButton")
    selectBtn.Size = UDim2.new(1, -20, 0, 28)
    selectBtn.Position = UDim2.new(0, 10, 0, 28)
    selectBtn.BackgroundColor3 = UI_PANEL_2
    selectBtn.BorderSizePixel = 0
    selectBtn.Text = "  None Selected"
    selectBtn.TextColor3 = UI_MUTED
    selectBtn.Font = Enum.Font.GothamMedium
    selectBtn.TextSize = 10
    selectBtn.TextXAlignment = Enum.TextXAlignment.Left
    selectBtn.ZIndex = 6
    selectBtn.Parent = card
    addCorner(selectBtn, 7)

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 20, 0, 28)
    arrow.Position = UDim2.new(1, -25, 0, 28)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▼"
    arrow.TextColor3 = UI_MUTED
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 9
    arrow.ZIndex = 6
    arrow.Parent = card

    local listHolder = Instance.new("ScrollingFrame")
    listHolder.Size = UDim2.new(1, -20, 0, (#options * 28))
    listHolder.Position = UDim2.new(0, 10, 0, 62)
    listHolder.BackgroundTransparency = 1
    listHolder.BorderSizePixel = 0
    listHolder.ScrollBarThickness = 3
    listHolder.CanvasSize = UDim2.new(0, 0, 0, #options * 30)
    listHolder.ZIndex = 6
    listHolder.Parent = card

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = listHolder

    local function updateDisplay()
        local list = {}
        for opt, active in pairs(selectedOptions) do
            if active then table.insert(list, opt) end
        end
        if #list == 0 then
            selectBtn.Text = "  None Selected"
            selectBtn.TextColor3 = UI_MUTED
        else
            selectBtn.Text = "  " .. table.concat(list, ", ")
            selectBtn.TextColor3 = UI_TEXT
        end
        if callback then task.spawn(callback, selectedOptions) end
    end

    for _, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, 26)
        optBtn.BackgroundColor3 = UI_PANEL_2
        optBtn.BorderSizePixel = 0
        optBtn.Text = "  [ ] " .. tostring(opt)
        optBtn.TextColor3 = UI_MUTED
        optBtn.Font = Enum.Font.GothamMedium
        optBtn.TextSize = 9
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.ZIndex = 6
        optBtn.Parent = listHolder
        addCorner(optBtn, 5)

        optionButtons[opt] = optBtn

        optBtn.Activated:Connect(function()
            local current = selectedOptions[opt] == true
            selectedOptions[opt] = not current
            if selectedOptions[opt] then
                optBtn.Text = "  [X] " .. tostring(opt)
                optBtn.TextColor3 = UI_ACCENT
            else
                optBtn.Text = "  [ ] " .. tostring(opt)
                optBtn.TextColor3 = UI_MUTED
            end
            updateDisplay()
        end)
    end

    selectBtn.Activated:Connect(function()
        isOpen = not isOpen
        card.Size = isOpen and UDim2.new(1, 0, 0, 68 + (#options * 28)) or UDim2.new(1, 0, 0, 64)
        arrow.Text = isOpen and "▲" or "▼"
    end)

    return {
        Card = card,
        Get = function() return selectedOptions end,
        Set = function(newSelected)
            selectedOptions = {}
            for opt, active in pairs(newSelected or {}) do
                if active then selectedOptions[opt] = true end
            end
            for _, opt in ipairs(options) do
                local optBtn = optionButtons[opt]
                local isAct = selectedOptions[opt] == true
                if optBtn then
                    if isAct then
                        optBtn.Text = "  [X] " .. tostring(opt)
                        optBtn.TextColor3 = UI_ACCENT
                    else
                        optBtn.Text = "  [ ] " .. tostring(opt)
                        optBtn.TextColor3 = UI_MUTED
                    end
                end
            end
            updateDisplay()
        end
    }
end

for _, tab in ipairs(TAB_DEFINITIONS) do
    createPage(tab.Key)
    local button = createTab(tab.Key, tab.Label)
    button.Activated:Connect(function() setActivePage(tab.Key) end)
end

--// TABS & PAGES
local toggles = {}
local mainPage = pages.Main
createSection(mainPage, "STATUS & OVERVIEW")
local statusCard = createInfoCard(mainPage, "Current Status", "Idle", 58)

createSection(mainPage, "CRATE SHOP CONFIG")
local crateOptions = {"Common", "Rare", "Very Rare", "Epic", "Special", "Legendary", "Hyper", "Vintage"}
local selectedCrates = {}
local crateDropdown = createMultiDropdown(mainPage, "Select Crate Types to Buy", crateOptions, function(results) selectedCrates = results end)

local autoPage = pages.Auto
createSection(autoPage, "AUTOMATION MODULES")
local autoBuyActive, autoRestockActive, autoClaimPaymentActive, autoUnlockActive, autoSpeedTpActive = false, false, false, false, false

toggles.AutoBuy = createToggle(autoPage, "Enable Auto-Buy", "Automatically buys checked crates from shop", false, function(e) autoBuyActive = e end)
toggles.AutoRestock = createToggle(autoPage, "Auto Restock Racks (1-100)", "Automatically restocks all clothing racks (1 to 100)", false, function(e) autoRestockActive = e end)
toggles.AutoClaimPayment = createToggle(autoPage, "Auto Claim Payment", "Spam claims customer payments automatically", false, function(e) autoClaimPaymentActive = e end)
toggles.AutoUnlock = createToggle(autoPage, "Auto Unlock Racks", "Spam unlocks new clothing racks via remote", false, function(e) autoUnlockActive = e end)
toggles.AutoSpeedTp = createToggle(autoPage, "Auto Tween to Speed 10-13 NPC", "Continuously tracks and glides to nearest NPC, swings 3s, then returns to Desk Fan 1", false, function(e) autoSpeedTpActive = e end)

local miscPage = pages.Misc
createSection(miscPage, "UTILITIES & EXTRAS")
createInfoCard(miscPage, "Bale Handler", "Background processing handles crate bales automatically.", 58)

local settingsPage = pages.Settings

--------------------------------------------------
-- CONFIGURATION SAVE / LOAD SYSTEM
--------------------------------------------------
local saveConfig, loadConfig

saveConfig = function()
    if not writefile then
        statusCard.SetText("[Config] System Error: writefile function missing!")
        return
    end

    local data = {
        AutoLoad = toggles.AutoLoad and toggles.AutoLoad.Get() or false,
        SelectedCrates = crateDropdown and crateDropdown.Get() or {},
        AutoBuy = toggles.AutoBuy and toggles.AutoBuy.Get() or false,
        AutoRestock = toggles.AutoRestock and toggles.AutoRestock.Get() or false,
        AutoClaimPayment = toggles.AutoClaimPayment and toggles.AutoClaimPayment.Get() or false,
        AutoUnlock = toggles.AutoUnlock and toggles.AutoUnlock.Get() or false,
        AutoSpeedTp = toggles.AutoSpeedTp and toggles.AutoSpeedTp.Get() or false,
    }

    pcall(function()
        if makefolder and isfolder and not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
    end)

    local success, err = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)

    if success then
        statusCard.SetText("[Config] Settings saved to workspace/" .. CONFIG_FILE)
    else
        statusCard.SetText("[Config] Save failed: " .. tostring(err))
    end
end

loadConfig = function(isAutoBoot)
    if not readfile or not isfile then
        if not isAutoBoot then
            statusCard.SetText("[Config] System Error: readfile/isfile function missing!")
        end
        return
    end

    local exists = false
    pcall(function() exists = isfile(CONFIG_FILE) end)
    if not exists then
        if not isAutoBoot then
            statusCard.SetText("[Config] No saved configuration file found.")
        end
        return
    end

    local success, data = pcall(function()
        local raw = readfile(CONFIG_FILE)
        return HttpService:JSONEncode(raw)
    end)

    if success and type(data) == "table" then
        if isAutoBoot and data.AutoLoad == false then
            return -- Auto-load on boot is disabled in saved file
        end

        if data.AutoLoad ~= nil and toggles.AutoLoad then toggles.AutoLoad.Set(data.AutoLoad) end
        if data.SelectedCrates and crateDropdown then crateDropdown.Set(data.SelectedCrates) end
        if data.AutoBuy ~= nil and toggles.AutoBuy then toggles.AutoBuy.Set(data.AutoBuy) end
        if data.AutoRestock ~= nil and toggles.AutoRestock then toggles.AutoRestock.Set(data.AutoRestock) end
        if data.AutoClaimPayment ~= nil and toggles.AutoClaimPayment then toggles.AutoClaimPayment.Set(data.AutoClaimPayment) end
        if data.AutoUnlock ~= nil and toggles.AutoUnlock then toggles.AutoUnlock.Set(data.AutoUnlock) end
        if data.AutoSpeedTp ~= nil and toggles.AutoSpeedTp then toggles.AutoSpeedTp.Set(data.AutoSpeedTp) end

        statusCard.SetText("[Config] Settings loaded successfully!")
    else
        if not isAutoBoot then
            statusCard.SetText("[Config] Failed to load config JSON.")
        end
    end
end

createSection(settingsPage, "CONFIG MANAGER")

toggles.AutoLoad = createToggle(settingsPage, "Auto Load Config On Start", "Automatically loads saved settings when script runs", false, function(e)
    task.defer(saveConfig)
end)

createActionButton(settingsPage, "Save Config", "Saves all active settings & toggles to file", "SAVE", function()
    saveConfig()
end)

createActionButton(settingsPage, "Load Config", "Restores saved settings & toggles from file", "LOAD", function()
    loadConfig(false)
end)

createSection(settingsPage, "INTERFACE CONTROLS")
createInfoCard(settingsPage, "ZHM HUB Info", "Version 3.26 - Permanent Auto-Minimize On Execute", 65)

--// REMOTES & LOOPS
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local purchaseRemote = remotesFolder:WaitForChild("PurchaseCrateCash")
local openBalesRemote = remotesFolder:WaitForChild("OpenBales")
local restockRemote = remotesFolder:WaitForChild("RequestRestock")
local claimPaymentRemote = remotesFolder:WaitForChild("ClaimPayment")
local unlockRackRemote = remotesFolder:WaitForChild("RequestUnlockRack")

local hangerAnimRemote = remotesFolder:WaitForChild("HangerAnim")
local setHangerLookRemote = remotesFolder:WaitForChild("SetHangerLook")
local swingRainbowHangerRemote = remotesFolder:WaitForChild("SwingRainbowHanger")

--// CLICK / TAP SIMULATOR HELPER
local function clickScreen()
    pcall(function()
        if mouse1click then
            mouse1click()
        elseif VirtualUser then
            VirtualUser:Button1Down(Vector2.new(200, 200))
            task.wait(0.05)
            VirtualUser:Button1Up(Vector2.new(200, 200))
        end
    end)
end

--// ROBUST FORCE EQUIP HANGER
local function forceEquipHangerOnce()
    task.spawn(function()
        for i = 1, 15 do
            local char = player.Character
            local backpack = player:FindFirstChild("Backpack")
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            
            if char and humanoid then
                local alreadyEquipped = false
                for _, child in ipairs(char:GetChildren()) do
                    if child:IsA("Tool") then
                        alreadyEquipped = true
                        break
                    end
                end
                
                if not alreadyEquipped and backpack then
                    local foundTool = nil
                    for _, item in ipairs(backpack:GetChildren()) do
                        if item:IsA("Tool") then
                            local n = item.Name:lower()
                            if n:find("hanger") or n:find("rainbow") or n:find("swing") or n:find("red") then
                                foundTool = item
                                break
                            end
                        end
                    end
                    
                    if not foundTool then
                        for _, item in ipairs(backpack:GetChildren()) do
                            if item:IsA("Tool") then
                                foundTool = item
                                break
                            end
                        end
                    end
                    
                    if foundTool then
                        pcall(function() humanoid:EquipTool(foundTool) end)
                        pcall(function() foundTool.Parent = char end)
                    end
                end
                
                for _, child in ipairs(char:GetChildren()) do
                    if child:IsA("Tool") then return end
                end
            end
            task.wait(0.3)
        end
    end)
end

--------------------------------------------------------
-- DYNAMIC SHOP OWNERSHIP & DESK FAN 1 LOGIC
--------------------------------------------------------
local SHOP_COUNT = 6
local MyShop = nil
local MyShopNumber = nil
local MyShopName = nil

local OWNER_KEYWORDS = {"owner", "userid", "user_id", "username", "player", "playerid", "player_id", "shopowner", "plotowner"}
local SLOT_KEYWORDS = {"shop", "shopid", "shop_id", "shopnumber", "shop_number", "slot", "slotid", "plot", "plotid", "base", "baseid"}

local function normalize(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%p]", "")
end

local myUsername = normalize(player.Name)
local myDisplayName = normalize(player.DisplayName)

local function keywordMatch(name, list)
    local cleaned = normalize(name)
    for _, keyword in ipairs(list) do
        local key = normalize(keyword)
        if cleaned == key or string.find(cleaned, key, 1, true) then
            return true
        end
    end
    return false
end

local function valueMatchesMe(value)
    if value == nil then return false end
    if typeof(value) == "Instance" then return value == player end
    local number = tonumber(value)
    if number and number == player.UserId then return true end
    local text = normalize(value)
    if text ~= "" and (text == myUsername or (myDisplayName ~= "" and text == myDisplayName)) then
        return true
    end
    return false
end

local function getPlayerRoot()
    local character = player.Character
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end

local function getShop(number)
    return Workspace:FindFirstChild("THRIFT_SHOP" .. tostring(number))
end

local function scanAttributes(instance)
    local attributes = {}
    pcall(function() attributes = instance:GetAttributes() end)
    for name, value in pairs(attributes) do
        if keywordMatch(name, OWNER_KEYWORDS) and valueMatchesMe(value) then
            return true
        end
    end
    return false
end

local function scanValueObject(object)
    if not keywordMatch(object.Name, OWNER_KEYWORDS) then return false end
    if object:IsA("ObjectValue") then
        if object.Value == player then return true end
    elseif object:IsA("StringValue") or object:IsA("IntValue") or object:IsA("NumberValue") then
        if valueMatchesMe(object.Value) then return true end
    end
    return false
end

local function scanTextForMe(object)
    local text = nil
    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
        text = object.Text
    elseif object:IsA("StringValue") then
        text = object.Value
    end
    if not text then return false end
    local cleaned = normalize(text)
    if cleaned == "" then return false end
    if myUsername ~= "" and string.find(cleaned, myUsername, 1, true) then return true end
    if myDisplayName ~= "" and string.find(cleaned, myDisplayName, 1, true) then return true end
    return false
end

local function scanShopOwnership(shop)
    if scanAttributes(shop) then return true end
    for _, object in ipairs(shop:GetDescendants()) do
        if scanAttributes(object) or scanValueObject(object) or scanTextForMe(object) then
            return true
        end
    end
    return false
end

local function searchContainerForShopNumber(container)
    if not container then return nil end
    for _, object in ipairs(container:GetDescendants()) do
        local attributes = {}
        pcall(function() attributes = object:GetAttributes() end)
        for name, value in pairs(attributes) do
            if keywordMatch(name, SLOT_KEYWORDS) then
                local number = tonumber(value)
                if number and number >= 1 and number <= SHOP_COUNT and getShop(number) then
                    return number
                end
            end
        end
        if object:IsA("IntValue") or object:IsA("NumberValue") or object:IsA("StringValue") then
            if keywordMatch(object.Name, SLOT_KEYWORDS) then
                local number = tonumber(object.Value)
                if number and number >= 1 and number <= SHOP_COUNT and getShop(number) then
                    return number
                end
            end
        end
    end
    return nil
end

local function characterInsideShop(shop)
    if not shop or not shop:IsA("Model") then return false end
    local root = getPlayerRoot()
    if not root then return false end
    local success, boxCFrame, boxSize = pcall(function() return shop:GetBoundingBox() end)
    if not success or not boxCFrame or not boxSize then return false end
    local localPosition = boxCFrame:PointToObjectSpace(root.Position)
    local half = boxSize / 2
    return math.abs(localPosition.X) <= half.X + 5 and math.abs(localPosition.Y) <= half.Y + 15 and math.abs(localPosition.Z) <= half.Z + 5
end

local function findMyShop()
    for number = 1, SHOP_COUNT do
        local shop = getShop(number)
        if shop and scanShopOwnership(shop) then
            return shop, number, "Ownership Match"
        end
    end
    local number = searchContainerForShopNumber(player)
    if number then return getShop(number), number, "Player Data Match" end
    number = searchContainerForShopNumber(playerGui)
    if number then return getShop(number), number, "PlayerGui Match" end

    for number = 1, SHOP_COUNT do
        local shop = getShop(number)
        if shop and characterInsideShop(shop) then
            return shop, number, "Character Inside Shop"
        end
    end
    return nil, nil, "Not Found"
end

local function acquireMyShop()
    local shop, number, reason = findMyShop()
    if not shop then
        shop = getShop(1)
        number = 1
    end
    MyShop = shop
    MyShopNumber = number
    MyShopName = "THRIFT_SHOP" .. tostring(number)
end

acquireMyShop()

local function getDeskFan1Part()
    if not MyShop then return nil end
    for _, obj in ipairs(MyShop:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local n = obj.Name:lower()
            if (n:find("desk") and n:find("fan") and (n:find("1") or n:find("one"))) or (n:find("fan") and n:find("1")) then
                if obj:IsA("Model") then
                    local part = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("PrimaryPart") or obj:FindFirstChildWhichIsA("BasePart", true)
                    if part then return part end
                elseif obj:IsA("BasePart") then
                    return obj
                end
            end
        end
    end
    return MyShop.PrimaryPart or MyShop:FindFirstChildWhichIsA("BasePart", true)
end

local function teleportToDeskFan1()
    local char = player.Character
    local root = getPlayerRoot()
    local fanPart = getDeskFan1Part()
    if char and root then
        if fanPart then
            local targetCFrame = fanPart.CFrame
            if targetCFrame then
                pcall(function() char:PivotTo(targetCFrame + Vector3.new(0, 3, 0)) end)
                return
            end
        end
    end
end

--// HELPER FUNCTIONS FOR NPC TRACKING
local function getNPCRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model.PrimaryPart
end

local function getNPCHead(model)
    if not model then return nil end
    return model:FindFirstChild("Head") or getNPCRoot(model)
end

-- Smooth initial approach to moving NPC
local function glideToNPC(npc, speedStudsPerSec)
    speedStudsPerSec = speedStudsPerSec or 95
    local maxTimeout = os.clock() + 2.5
    
    while npc and npc.Parent and os.clock() < maxTimeout do
        local npcRoot = getNPCRoot(npc)
        local playerRoot = getPlayerRoot()
        if not npcRoot or not playerRoot then break end
        
        local targetPos = npcRoot.Position
        local currentPos = playerRoot.Position
        local distance = (currentPos - targetPos).Magnitude
        
        if distance <= 3.5 then
            break
        end
        
        local dt = RunService.Heartbeat:Wait()
        local stepDistance = speedStudsPerSec * dt
        local alpha = math.clamp(stepDistance / distance, 0, 1)
        
        local newPos = currentPos:Lerp(targetPos, alpha)
        pcall(function()
            playerRoot.CFrame = CFrame.new(newPos, targetPos)
            playerRoot.AssemblyLinearVelocity = Vector3.zero
        end)
    end
end

-- Continuous Glue-Tracking + Swing for full 3 Seconds
local function attackAndFollowNPC(npc, durationSec)
    durationSec = durationSec or 3.0
    local startTime = os.clock()
    
    while os.clock() - startTime < durationSec do
        local npcRoot = getNPCRoot(npc)
        local playerRoot = getPlayerRoot()
        
        if not npc or not npc.Parent or not npcRoot or not playerRoot then
            break
        end

        -- Keep player glued right next to the walking NPC
        local npcPos = npcRoot.Position
        local npcLook = npcRoot.CFrame.LookVector
        local followPos = npcPos - (npcLook * 2.5) + Vector3.new(0, 0.5, 0)
        
        pcall(function()
            playerRoot.CFrame = CFrame.new(followPos, npcPos)
            playerRoot.AssemblyLinearVelocity = Vector3.zero
        end)

        -- Fire swing remotes continuously
        pcall(function() setHangerLookRemote:FireServer(npcRoot) end)
        pcall(function() setHangerLookRemote:FireServer(npcRoot.CFrame) end)
        
        pcall(function()
            local char = player.Character
            local tool = char and char:FindFirstChildOfClass("Tool")
            if tool then tool:Activate() end
            
            swingRainbowHangerRemote:FireServer()
            swingRainbowHangerRemote:FireServer(true)
            swingRainbowHangerRemote:FireServer(npc)
            hangerAnimRemote:FireServer("swing")
        end)
        
        clickScreen()
        RunService.Heartbeat:Wait()
    end
end

-- Glide directly back to Desk Fan 1
local function glideToPosition(targetCFrame, speedStudsPerSec)
    local char = player.Character
    local root = getPlayerRoot()
    if not char or not root then return end
    
    speedStudsPerSec = speedStudsPerSec or 90
    local currentPos = root.Position
    local targetPos = targetCFrame.Position
    local distance = (currentPos - targetPos).Magnitude
    
    if distance < 1 then
        pcall(function() char:PivotTo(targetCFrame) end)
        return
    end
    
    local timeElapsed = 0
    local totalTime = math.clamp(distance / speedStudsPerSec, 0.1, 0.8)
    
    while timeElapsed < totalTime do
        local dt = RunService.Heartbeat:Wait()
        timeElapsed = timeElapsed + dt
        local alpha = math.clamp(timeElapsed / totalTime, 0, 1)
        
        local activeRoot = getPlayerRoot()
        if not activeRoot then break end
        
        local lerpPos = currentPos:Lerp(targetPos, alpha)
        local lerpRot = activeRoot.CFrame:Lerp(targetCFrame, alpha)
        
        pcall(function()
            activeRoot.CFrame = CFrame.new(lerpPos) * (lerpRot - lerpRot.Position)
            activeRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end)
    end
    
    pcall(function()
        local finalRoot = getPlayerRoot()
        if finalRoot then
            finalRoot.CFrame = targetCFrame
            finalRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end
    end)
end

local function tweenBackToDeskFan1()
    local fanPart = getDeskFan1Part()
    if fanPart then
        local targetCFrame = fanPart.CFrame + Vector3.new(0, 3, 0)
        glideToPosition(targetCFrame, 90)
    else
        teleportToDeskFan1()
    end
end

--// STARTUP EXECUTION
task.spawn(function()
    task.wait(1.0)
    forceEquipHangerOnce()
    teleportToDeskFan1()
    task.wait(0.5)
    pcall(function()
        local char = player.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        if tool then tool:Activate() end
    end)
    clickScreen()
end)

player.CharacterAdded:Connect(function()
    task.wait(0.8)
    forceEquipHangerOnce()
    teleportToDeskFan1()
    purgeUI()
end)

--// LOCAL NPC SCANNING (Speed 10-13 Filter, Max Distance 50 Studs)
local NPCData = {}
local speedScreenGui = Instance.new("ScreenGui")
speedScreenGui.Name = "ZHM_NPC_ESP"
speedScreenGui.ResetOnSpawn = false
speedScreenGui.Parent = playerGui

local function isPlayerCharacter(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then return true end
    end
    return false
end

local function isValidSpeedNPC(model)
    if not model or not model:IsA("Model") or isPlayerCharacter(model) then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    
    local speed = humanoid.WalkSpeed
    if speed < 10 or speed > 13 then
        return false
    end
    
    return true
end

local function createESP(npc)
    if NPCData[npc] then return end
    local root = getNPCRoot(npc)
    if not root then return end

    local Billboard = Instance.new("BillboardGui")
    Billboard.Name = "ZHM_NPC_ESP"
    Billboard.Size = UDim2.new(0, 210, 0, 70)
    Billboard.StudsOffset = Vector3.new(0, 4, 0)
    Billboard.AlwaysOnTop = true
    Billboard.Adornee = getNPCHead(npc)
    Billboard.Parent = speedScreenGui

    local Text = Instance.new("TextLabel")
    Text.Size = UDim2.new(1, 0, 1, 0)
    Text.BackgroundTransparency = 1
    Text.Text = npc.Name .. "\nSpeed: Valid | Dist: 0m"
    Text.TextColor3 = Color3.fromRGB(255, 255, 255)
    Text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    Text.TextStrokeTransparency = 0
    Text.Font = Enum.Font.GothamBold
    Text.TextSize = 14
    Text.TextWrapped = true
    Text.Parent = Billboard

    local Highlight = Instance.new("Highlight")
    Highlight.Name = "ZHM_HIGHLIGHT"
    Highlight.Adornee = npc
    Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    Highlight.FillTransparency = 0.85
    Highlight.OutlineTransparency = 0
    Highlight.Parent = speedScreenGui

    NPCData[npc] = {
        Billboard = Billboard,
        Text = Text,
        Highlight = Highlight,
    }
end

local function removeNPC(npc)
    local data = NPCData[npc]
    if not data then return end
    if data.Billboard then data.Billboard:Destroy() end
    if data.Highlight then data.Highlight:Destroy() end
    NPCData[npc] = nil
end

local function scanNearbyNPCs()
    local playerRoot = getPlayerRoot()
    if not playerRoot then return end
    
    local containers = {Workspace}
    for _, folderName in ipairs({"NPCs", "Clients", "Customers", "Characters", "Mobs"}) do
        local f = Workspace:FindFirstChild(folderName)
        if f then table.insert(containers, f) end
    end
    
    local scannedThisCycle = {}
    for _, container in ipairs(containers) do
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Model") and isValidSpeedNPC(obj) then
                local root = getNPCRoot(obj)
                if root then
                    local dist = (root.Position - playerRoot.Position).Magnitude
                    if dist <= 50 then
                        scannedThisCycle[obj] = true
                        if not NPCData[obj] then
                            createESP(obj)
                        end
                    end
                end
            end
        end
    end
    
    for npc, _ in pairs(NPCData) do
        local root = getNPCRoot(npc)
        local dist = root and playerRoot and (root.Position - playerRoot.Position).Magnitude or 999
        if not scannedThisCycle[npc] or not npc.Parent or not isValidSpeedNPC(npc) or dist > 50 then
            removeNPC(npc)
        end
    end
end

task.spawn(function()
    while speedScreenGui.Parent do
        scanNearbyNPCs()
        task.wait(0.5)
    end
end)

--// TRIGGER LIVE-TRACKING ACTION + 3-SECOND SWING + RETURN
local isHandlingNpc = false

local function triggerHangerAction(npc)
    if isHandlingNpc then return end
    isHandlingNpc = true

    forceEquipHangerOnce()

    statusCard.SetText("[ZHM] Approaching NPC (" .. npc.Name .. ")...")
    glideToNPC(npc, 95)

    statusCard.SetText("[ZHM] Reached NPC | Tracking & Swinging for 3s...")
    attackAndFollowNPC(npc, 3.0)

    statusCard.SetText("[ZHM] Swing finished. Gliding back to Desk Fan 1...")
    tweenBackToDeskFan1()

    task.wait(0.5)
    isHandlingNpc = false
end

RunService.Heartbeat:Connect(function()
    local playerRoot = getPlayerRoot()
    for npc, data in pairs(NPCData) do
        local root = getNPCRoot(npc)
        if root and playerRoot then
            local distance = (root.Position - playerRoot.Position).Magnitude
            local humanoid = npc:FindFirstChildOfClass("Humanoid")
            local spd = humanoid and humanoid.WalkSpeed or 0
            data.Text.Text = npc.Name .. "\nSpd: " .. spd .. " | Dist: " .. string.format("%.1f", distance) .. "m"
        end
    end

    if autoSpeedTpActive and not isHandlingNpc and playerRoot then
        local nearestNpc = nil
        local shortestDist = 50

        for npc, _ in pairs(NPCData) do
            local root = getNPCRoot(npc)
            if root then
                local dist = (root.Position - playerRoot.Position).Magnitude
                if dist <= shortestDist then
                    shortestDist = dist
                    nearestNpc = npc
                end
            end
        end

        if nearestNpc then
            task.spawn(function()
                triggerHangerAction(nearestNpc)
            end)
        end
    end
end)

--// Auto Loops
task.spawn(function()
    while true do
        if autoBuyActive then
            local purchasedAny = false
            for crateName, isEnabled in pairs(selectedCrates) do
                if isEnabled and autoBuyActive then
                    pcall(function() purchaseRemote:FireServer(crateName) end)
                    purchasedAny = true
                    statusCard.SetText("Purchasing: " .. crateName)
                    task.wait(0.2)
                end
            end
            if not purchasedAny then
                statusCard.SetText("Idle (No crates selected to buy)")
                task.wait(0.5)
            end
        else
            statusCard.SetText("Idle (Waiting to start)")
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        for _, crateName in ipairs(crateOptions) do
            pcall(function() openBalesRemote:FireServer(crateName, 1) end)
            task.wait(0.3)
        end
    end
end)

task.spawn(function()
    while true do
        if autoRestockActive then
            pcall(function()
                for i = 1, 100 do
                    restockRemote:FireServer(i)
                    task.wait(0.02)
                end
            end)
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while true do
        if autoClaimPaymentActive then
            pcall(function()
                claimPaymentRemote:FireServer()
                for _, obj in ipairs(Workspace:GetDescendants()) do
                    if obj:IsA("Model") and (obj.Name:find("Customer") or obj:FindFirstChild("Humanoid")) then
                        claimPaymentRemote:FireServer(obj)
                    end
                end
            end)
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while true do
        if autoUnlockActive then
            pcall(function()
                for i = 1, 15 do
                    unlockRackRemote:FireServer(i)
                    task.wait(0.05)
                end
            end)
        end
        task.wait(1)
    end
end)

--// MINIMIZE / RESTORE
local minimized = false
local miniButton = Instance.new("TextButton")
miniButton.Name = "MiniButton"
miniButton.AnchorPoint = Vector2.new(0.5, 0.5)
miniButton.Size = UDim2.new(0, 46, 0, 46)
miniButton.Position = mainFrame.Position
miniButton.BackgroundColor3 = UI_PANEL
miniButton.BorderSizePixel = 0
miniButton.Text = MINI_TEXT
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

minimizeBtn.Activated:Connect(function() setMinimized(true) end)
miniButton.Activated:Connect(function() setMinimized(false) end)

closeBtn.Activated:Connect(function()
    if disconnectResponsiveScale then disconnectResponsiveScale() end
    speedScreenGui:Destroy()
    screenGui:Destroy()
end)

if TAB_DEFINITIONS[1] then setActivePage(TAB_DEFINITIONS[1].Key) end

--// AUTO-LOAD CONFIG & ALWAYS AUTO-MINIMIZE ON BOOT
task.spawn(function()
    task.wait(0.5)
    loadConfig(true)
    setMinimized(true) -- Always auto-minimizes upon execution
end)

print("[ZHM HUB] Loaded Successfully with Permanent Auto-Minimize & Config Management!")
