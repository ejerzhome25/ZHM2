--[[
    VNDT UI Library
    Simple • Clean • Aesthetic
    Custom Roblox UI library built from scratch.

    Basic usage:
        local VNDT = loadstring(game:HttpGet("RAW_LINK"))()
        local Window = VNDT:CreateWindow({Name = "VNDT Hub", Subtitle = "My Script"})
        local Main = Window:CreateTab("Main")
]]

local VNDT = {}
VNDT.__index = VNDT

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local Theme = {
    Background = Color3.fromRGB(16, 17, 21),
    Surface = Color3.fromRGB(23, 24, 29),
    Surface2 = Color3.fromRGB(29, 31, 37),
    Surface3 = Color3.fromRGB(36, 38, 45),
    Stroke = Color3.fromRGB(55, 58, 68),
    Text = Color3.fromRGB(238, 240, 246),
    Muted = Color3.fromRGB(155, 160, 175),
    Accent = Color3.fromRGB(120, 135, 255),
    Danger = Color3.fromRGB(240, 95, 105)
}

local function New(className, properties)
    local object = Instance.new(className)

    for key, value in pairs(properties or {}) do
        if key ~= "Parent" then
            object[key] = value
        end
    end

    if properties and properties.Parent then
        object.Parent = properties.Parent
    end

    return object
end

local function Corner(parent, radius)
    return New("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
        Parent = parent
    })
end

local function Stroke(parent, color, thickness, transparency)
    return New("UIStroke", {
        Color = color or Theme.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent
    })
end

local function Tween(object, goal, duration)
    local tween = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        goal
    )

    tween:Play()
    return tween
end

local function Label(parent, text, size, color, font)
    return New("TextLabel", {
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = color or Theme.Text,
        TextSize = size or 14,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = parent
    })
end

local function Button(parent, properties)
    properties = properties or {}
    properties.Text = properties.Text or ""
    properties.AutoButtonColor = false
    properties.Parent = parent
    return New("TextButton", properties)
end

local function GetGuiParent()
    if gethui then
        local ok, result = pcall(gethui)
        if ok and result then
            return result
        end
    end

    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and coreGui then
        return coreGui
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function UpdateCanvas(scroller, layout, extra)
    local function Update()
        scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + (extra or 12))
    end

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(Update)
    Update()
end

local function MakeDraggable(handle, target)
    local dragging = false
    local startInput
    local startPosition
    local originalPosition

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInput = input.Position
            originalPosition = target.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        startPosition = input.Position - startInput

        target.Position = UDim2.new(
            originalPosition.X.Scale,
            originalPosition.X.Offset + startPosition.X,
            originalPosition.Y.Scale,
            originalPosition.Y.Offset + startPosition.Y
        )
    end)
end

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

function VNDT:SetTheme(values)
    for key, value in pairs(values or {}) do
        if Theme[key] ~= nil then
            Theme[key] = value
        end
    end
end

function VNDT:CreateWindow(config)
    config = config or {}

    local gui = New("ScreenGui", {
        Name = "VNDT_" .. HttpService:GenerateGUID(false),
        ResetOnSpawn = false,
        IgnoreGuiInset = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = GetGuiParent()
    })

    local width = config.Width or 580
    local height = config.Height or 380

    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        width = config.MobileWidth or math.min(width, 520)
        height = config.MobileHeight or math.min(height, 350)
    end

    local shadow = New("ImageLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width + 30, height + 30),
        Image = "rbxassetid://1316045217",
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.55,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(10, 10, 118, 118),
        Parent = gui
    })

    local main = New("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = gui
    })
    Corner(main, 13)
    Stroke(main, Theme.Stroke, 1, 0.15)

    local topbar = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 54),
        Parent = main
    })

    New("Frame", {
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
        Parent = topbar
    })

    local title = Label(
        topbar,
        config.Name or "VNDT",
        17,
        Theme.Text,
        Enum.Font.GothamBold
    )
    title.Position = UDim2.fromOffset(18, 7)
    title.Size = UDim2.new(1, -110, 0, 22)

    local subtitle = Label(
        topbar,
        config.Subtitle or "Custom UI",
        11,
        Theme.Muted,
        Enum.Font.Gotham
    )
    subtitle.Position = UDim2.fromOffset(18, 28)
    subtitle.Size = UDim2.new(1, -110, 0, 18)

    local minimize = Button(topbar, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -48, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Surface2,
        Text = "—",
        TextColor3 = Theme.Text,
        TextSize = 16,
        Font = Enum.Font.GothamBold
    })
    Corner(minimize, 8)
    Stroke(minimize, Theme.Stroke, 1, 0.25)

    local close = Button(topbar, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Surface2,
        Text = "×",
        TextColor3 = Theme.Muted,
        TextSize = 18,
        Font = Enum.Font.Gotham
    })
    Corner(close, 8)
    Stroke(close, Theme.Stroke, 1, 0.25)

    local sidebar = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 54),
        Size = UDim2.new(0, 150, 1, -54),
        Parent = main
    })

    New("Frame", {
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        Parent = sidebar
    })

    local tabList = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -16, 1, -16),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = sidebar
    })

    local tabLayout = New("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabList
    })
    UpdateCanvas(tabList, tabLayout, 8)

    local pages = New("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(150, 54),
        Size = UDim2.new(1, -150, 1, -54),
        ClipsDescendants = true,
        Parent = main
    })

    local pageLayout = New("UIPageLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        EasingDirection = Enum.EasingDirection.Out,
        EasingStyle = Enum.EasingStyle.Quad,
        TweenTime = 0.2,
        GamepadInputEnabled = false,
        ScrollWheelInputEnabled = false,
        TouchInputEnabled = false,
        Parent = pages
    })

    local self = setmetatable({
        Gui = gui,
        Main = main,
        Shadow = shadow,
        Topbar = topbar,
        Sidebar = sidebar,
        TabList = tabList,
        Pages = pages,
        PageLayout = pageLayout,
        Tabs = {},
        SelectedTab = nil,
        Minimized = false,
        OriginalSize = main.Size
    }, Window)

    MakeDraggable(topbar, main)

    main:GetPropertyChangedSignal("Position"):Connect(function()
        shadow.Position = main.Position
    end)

    main:GetPropertyChangedSignal("Size"):Connect(function()
        shadow.Size = UDim2.fromOffset(
            main.AbsoluteSize.X + 30,
            main.AbsoluteSize.Y + 30
        )
    end)

    minimize.MouseButton1Click:Connect(function()
        self.Minimized = not self.Minimized

        if self.Minimized then
            self.OriginalSize = main.Size
            Tween(main, {
                Size = UDim2.fromOffset(main.AbsoluteSize.X, 54)
            })
            minimize.Text = "+"
        else
            Tween(main, {
                Size = self.OriginalSize
            })
            minimize.Text = "—"
        end
    end)

    close.MouseEnter:Connect(function()
        Tween(close, {
            BackgroundColor3 = Theme.Danger,
            TextColor3 = Color3.new(1, 1, 1)
        })
    end)

    close.MouseLeave:Connect(function()
        Tween(close, {
            BackgroundColor3 = Theme.Surface2,
            TextColor3 = Theme.Muted
        })
    end)

    close.MouseButton1Click:Connect(function()
        Tween(main, {
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(
                main.AbsoluteSize.X * 0.94,
                main.AbsoluteSize.Y * 0.94
            )
        }, 0.15)

        Tween(shadow, {
            ImageTransparency = 1
        }, 0.15)

        task.delay(0.18, function()
            if gui then
                gui:Destroy()
            end
        end)
    end)

    return self
end

function Window:CreateTab(name)
    local tabButton = Button(self.TabList, {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Theme.Surface,
        Text = "",
        LayoutOrder = #self.Tabs + 1
    })
    Corner(tabButton, 9)

    local indicator = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 18),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = tabButton
    })
    Corner(indicator, 99)

    local tabText = Label(
        tabButton,
        name or "Tab",
        13,
        Theme.Muted,
        Enum.Font.GothamMedium
    )
    tabText.Position = UDim2.fromOffset(12, 0)
    tabText.Size = UDim2.new(1, -18, 1, 0)

    local page = New("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = UserInputService.TouchEnabled and 5 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = self.Pages
    })

    New("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),
        Parent = page
    })

    local layout = New("UIListLayout", {
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = page
    })
    UpdateCanvas(page, layout, 22)

    local tab = setmetatable({
        Window = self,
        Button = tabButton,
        Indicator = indicator,
        Text = tabText,
        Page = page,
        Layout = layout
    }, Tab)

    table.insert(self.Tabs, tab)

    tabButton.MouseButton1Click:Connect(function()
        self:SelectTab(tab)
    end)

    tabButton.MouseEnter:Connect(function()
        if self.SelectedTab ~= tab then
            Tween(tabButton, {
                BackgroundColor3 = Theme.Surface2
            })
        end
    end)

    tabButton.MouseLeave:Connect(function()
        if self.SelectedTab ~= tab then
            Tween(tabButton, {
                BackgroundColor3 = Theme.Surface
            })
        end
    end)

    if not self.SelectedTab then
        self:SelectTab(tab)
    end

    return tab
end

function Window:SelectTab(tab)
    self.SelectedTab = tab

    for _, current in ipairs(self.Tabs) do
        local selected = current == tab

        Tween(current.Button, {
            BackgroundColor3 = selected and Theme.Surface2 or Theme.Surface
        })

        Tween(current.Text, {
            TextColor3 = selected and Theme.Text or Theme.Muted
        })

        Tween(current.Indicator, {
            BackgroundTransparency = selected and 0 or 1
        })
    end

    self.PageLayout:JumpTo(tab.Page)
end

function Window:Notify(config)
    config = config or {}

    local holder = self.Gui:FindFirstChild("VNDT_Notifications")

    if not holder then
        holder = New("Frame", {
            Name = "VNDT_Notifications",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -14, 1, -14),
            Size = UDim2.fromOffset(310, 300),
            Parent = self.Gui
        })

        New("UIListLayout", {
            Padding = UDim.new(0, 8),
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = holder
        })
    end

    local card = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(295, 70),
        Parent = holder
    })
    Corner(card, 10)
    Stroke(card, Theme.Stroke, 1, 0.15)

    local title = Label(
        card,
        config.Title or "VNDT",
        13,
        Theme.Text,
        Enum.Font.GothamBold
    )
    title.Position = UDim2.fromOffset(13, 8)
    title.Size = UDim2.new(1, -26, 0, 20)
    title.TextTransparency = 1

    local body = Label(
        card,
        config.Content or "",
        12,
        Theme.Muted,
        Enum.Font.Gotham
    )
    body.Position = UDim2.fromOffset(13, 29)
    body.Size = UDim2.new(1, -26, 0, 32)
    body.TextWrapped = true
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextTransparency = 1

    Tween(card, {BackgroundTransparency = 0})
    Tween(title, {TextTransparency = 0})
    Tween(body, {TextTransparency = 0})

    task.delay(config.Duration or 3, function()
        if not card.Parent then
            return
        end

        Tween(card, {BackgroundTransparency = 1})
        Tween(title, {TextTransparency = 1})
        Tween(body, {TextTransparency = 1})

        task.delay(0.2, function()
            if card then
                card:Destroy()
            end
        end)
    end)
end


function Tab:CreateMultiDropdown(config)
    config = config or {}

    local options = config.Options or {}
    local selected = config.Selected or config.Default or {}
    local searchable = config.Searchable ~= false
    local opened = false
    local query = ""
    local maxListHeight = config.MaxHeight or 185

    local holder = new("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 54),
        ClipsDescendants = true,
        Parent = self.Page
    })
    corner(holder, 10)
    stroke(holder, Theme.Stroke, 1, 0.22)

    local header = makeButton(holder, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 54)
    })

    local title = textLabel(header, config.Name or "Multi Select", 12, Theme.Muted, Enum.Font.GothamMedium)
    title.Position = UDim2.fromOffset(13, 4)
    title.Size = UDim2.new(0.48, -13, 0, 22)

    local summary = textLabel(header, config.Placeholder or "None selected", 11, Theme.Text, Enum.Font.Gotham)
    summary.Position = UDim2.fromOffset(13, 26)
    summary.Size = UDim2.new(1, -48, 0, 21)
    summary.TextTruncate = Enum.TextTruncate.AtEnd

    local arrow = textLabel(header, "⌄", 14, Theme.Muted, Enum.Font.GothamBold)
    arrow.AnchorPoint = Vector2.new(1, 0)
    arrow.Position = UDim2.new(1, -12, 0, 0)
    arrow.Size = UDim2.fromOffset(22, 54)
    arrow.TextXAlignment = Enum.TextXAlignment.Center

    local body = new("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 54),
        Size = UDim2.new(1, -16, 0, 0),
        Parent = holder
    })

    local searchHeight = searchable and 34 or 0
    local searchBox

    if searchable then
        local searchHolder = new("Frame", {
            Position = UDim2.fromOffset(0, 3),
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = Theme.Surface2,
            BorderSizePixel = 0,
            Parent = body
        })
        corner(searchHolder, 8)
        stroke(searchHolder, Theme.Stroke, 1, 0.3)

        searchBox = new("TextBox", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(10, 0),
            Size = UDim2.new(1, -20, 1, 0),
            ClearTextOnFocus = false,
            Text = "",
            PlaceholderText = config.SearchPlaceholder or "Search...",
            PlaceholderColor3 = Theme.Muted,
            TextColor3 = Theme.Text,
            TextSize = 11,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = searchHolder
        })
    end

    local list = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, searchHeight + 4),
        Size = UDim2.new(1, 0, 0, maxListHeight),
        CanvasSize = UDim2.new(),
        ScrollBarThickness = UserInputService.TouchEnabled and 5 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = body
    })

    local listLayout = new("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list
    })
    setCanvas(list, listLayout, 4)

    local optionButtons = {}

    local function selectedCount()
        local count = 0
        for _, option in ipairs(options) do
            if selected[option] == true then
                count += 1
            end
        end
        return count
    end

    local function updateSummary()
        local count = selectedCount()
        if count == 0 then
            summary.Text = config.Placeholder or "None selected"
            summary.TextColor3 = Theme.Muted
            return
        end

        if count == 1 then
            for _, option in ipairs(options) do
                if selected[option] == true then
                    summary.Text = tostring(option)
                    break
                end
            end
        else
            summary.Text = tostring(count) .. " selected"
        end

        summary.TextColor3 = Theme.Text
    end

    local function matchesSearch(option)
        if query == "" then return true end
        return string.find(string.lower(tostring(option)), query, 1, true) ~= nil
    end

    local function updateBodyHeight()
        local visibleCount = 0
        for _, button in pairs(optionButtons) do
            if button.Visible then
                visibleCount += 1
            end
        end

        local listHeight = math.min(maxListHeight, math.max(36, visibleCount * 39))
        list.Size = UDim2.new(1, 0, 0, listHeight)
        body.Size = UDim2.new(1, -16, 0, searchHeight + listHeight + 10)

        if opened then
            holder.Size = UDim2.new(1, 0, 0, 54 + body.Size.Y.Offset)
        end
    end

    local function renderOptions()
        for option, button in pairs(optionButtons) do
            local active = selected[option] == true
            button.Text = (active and "✓  " or "    ") .. tostring(option)
            button.BackgroundColor3 = active and Theme.Surface3 or Theme.Surface2
            button.TextColor3 = active and Theme.Text or Theme.Muted
            button.Visible = matchesSearch(option)
        end

        updateSummary()
        updateBodyHeight()
    end

    local function rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        table.clear(optionButtons)

        for index, option in ipairs(options) do
            local button = makeButton(list, {
                LayoutOrder = index,
                Size = UDim2.new(1, -2, 0, 34),
                BackgroundColor3 = Theme.Surface2,
                Text = tostring(option),
                TextColor3 = Theme.Muted,
                TextSize = 11,
                Font = Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Left
            })
            corner(button, 8)
            padding(button, 10, 10, 0, 0)
            optionButtons[option] = button

            button.MouseButton1Click:Connect(function()
                selected[option] = not (selected[option] == true)
                renderOptions()

                if config.Callback then
                    task.spawn(config.Callback, option, selected[option], selected)
                end
            end)
        end

        renderOptions()
    end

    local function setOpen(value)
        opened = value == true

        if opened then
            updateBodyHeight()
            tween(arrow, nil, {Rotation = 180})
        else
            tween(holder, nil, {Size = UDim2.new(1, 0, 0, 54)})
            tween(arrow, nil, {Rotation = 0})
        end
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not opened)
    end)

    if searchBox then
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            query = string.lower(searchBox.Text or "")
            renderOptions()
        end)
    end

    local api = {}

    function api:SetOptions(newOptions)
        options = newOptions or {}
        rebuild()
    end

    function api:Refresh(newOptions)
        if newOptions then
            options = newOptions
        end
        rebuild()
    end

    function api:GetSelected()
        return selected
    end

    function api:SetSelected(map, fire)
        for key in pairs(selected) do
            selected[key] = nil
        end

        for key, value in pairs(map or {}) do
            if value == true then
                selected[key] = true
            end
        end

        renderOptions()

        if fire and config.Callback then
            task.spawn(config.Callback, nil, nil, selected)
        end
    end

    function api:Clear(fire)
        for key in pairs(selected) do
            selected[key] = nil
        end

        renderOptions()

        if fire and config.Callback then
            task.spawn(config.Callback, nil, nil, selected)
        end
    end

    rebuild()
    return api
end

function Window:SetVisible(state)
    self.Gui.Enabled = state == true
end

function Window:Destroy()
    if self.Gui then
        self.Gui:Destroy()
    end
end

local function CreateRow(tab, height)
    local row = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height or 44),
        Parent = tab.Page
    })

    Corner(row, 10)
    Stroke(row, Theme.Stroke, 1, 0.22)

    return row
end

function Tab:CreateSection(text)
    local section = New("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 26),
        Parent = self.Page
    })

    local sectionText = Label(
        section,
        string.upper(text or "SECTION"),
        11,
        Theme.Muted,
        Enum.Font.GothamBold
    )
    sectionText.Position = UDim2.fromOffset(3, 0)
    sectionText.Size = UDim2.new(1, -6, 1, 0)

    return section
end

function Tab:CreateLabel(text)
    local row = CreateRow(self, 40)

    local label = Label(
        row,
        text or "Label",
        13,
        Theme.Muted,
        Enum.Font.Gotham
    )
    label.Position = UDim2.fromOffset(13, 0)
    label.Size = UDim2.new(1, -26, 1, 0)

    local api = {}

    function api:Set(value)
        label.Text = tostring(value)
    end

    function api:Get()
        return label.Text
    end

    return api
end

function Tab:CreateButton(config)
    config = config or {}

    local row = CreateRow(self, 44)

    local title = Label(
        row,
        config.Name or "Button",
        13,
        Theme.Text,
        Enum.Font.GothamMedium
    )
    title.Position = UDim2.fromOffset(13, 0)
    title.Size = UDim2.new(1, -48, 1, 0)

    local arrow = Label(
        row,
        "›",
        20,
        Theme.Muted,
        Enum.Font.Gotham
    )
    arrow.AnchorPoint = Vector2.new(1, 0)
    arrow.Position = UDim2.new(1, -13, 0, 0)
    arrow.Size = UDim2.fromOffset(20, 44)
    arrow.TextXAlignment = Enum.TextXAlignment.Center

    local click = Button(row, {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1)
    })

    click.MouseEnter:Connect(function()
        Tween(row, {BackgroundColor3 = Theme.Surface2})
        Tween(arrow, {TextColor3 = Theme.Accent})
    end)

    click.MouseLeave:Connect(function()
        Tween(row, {BackgroundColor3 = Theme.Surface})
        Tween(arrow, {TextColor3 = Theme.Muted})
    end)

    click.MouseButton1Click:Connect(function()
        if config.Callback then
            task.spawn(config.Callback)
        end
    end)

    local api = {}

    function api:SetName(value)
        title.Text = tostring(value)
    end

    return api
end

function Tab:CreateToggle(config)
    config = config or {}

    local value = config.Default == true
    local row = CreateRow(self, 48)

    local title = Label(
        row,
        config.Name or "Toggle",
        13,
        Theme.Text,
        Enum.Font.GothamMedium
    )
    title.Position = UDim2.fromOffset(13, 0)
    title.Size = UDim2.new(1, -72, 1, 0)

    local track = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -13, 0.5, 0),
        Size = UDim2.fromOffset(42, 23),
        BackgroundColor3 = value and Theme.Accent or Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row
    })
    Corner(track, 99)

    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = value
            and UDim2.new(1, -12, 0.5, 0)
            or UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(17, 17),
        BackgroundColor3 = Color3.fromRGB(245, 246, 250),
        BorderSizePixel = 0,
        Parent = track
    })
    Corner(knob, 99)

    local click = Button(row, {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1)
    })

    local api = {}

    local function Render(fireCallback)
        Tween(track, {
            BackgroundColor3 = value and Theme.Accent or Theme.Surface3
        })

        Tween(knob, {
            Position = value
                and UDim2.new(1, -12, 0.5, 0)
                or UDim2.new(0, 12, 0.5, 0)
        })

        if fireCallback and config.Callback then
            task.spawn(config.Callback, value)
        end
    end

    function api:Set(newValue)
        value = newValue == true
        Render(true)
    end

    function api:Get()
        return value
    end

    click.MouseButton1Click:Connect(function()
        value = not value
        Render(true)
    end)

    return api
end

function Tab:CreateSlider(config)
    config = config or {}

    local minimum = config.Min or 0
    local maximum = config.Max or 100
    local increment = config.Increment or 1
    local value = math.clamp(config.Default or minimum, minimum, maximum)

    local row = CreateRow(self, 66)

    local title = Label(
        row,
        config.Name or "Slider",
        13,
        Theme.Text,
        Enum.Font.GothamMedium
    )
    title.Position = UDim2.fromOffset(13, 2)
    title.Size = UDim2.new(1, -90, 0, 30)

    local valueText = Label(
        row,
        tostring(value),
        12,
        Theme.Accent,
        Enum.Font.GothamBold
    )
    valueText.AnchorPoint = Vector2.new(1, 0)
    valueText.Position = UDim2.new(1, -13, 0, 2)
    valueText.Size = UDim2.fromOffset(70, 30)
    valueText.TextXAlignment = Enum.TextXAlignment.Right

    local bar = New("Frame", {
        Position = UDim2.fromOffset(13, 43),
        Size = UDim2.new(1, -26, 0, 6),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row
    })
    Corner(bar, 99)

    local fill = New("Frame", {
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = bar
    })
    Corner(fill, 99)

    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Color3.fromRGB(246, 247, 250),
        BorderSizePixel = 0,
        Parent = bar
    })
    Corner(knob, 99)

    local dragging = false
    local api = {}

    local function SetValue(newValue, fireCallback)
        newValue = math.clamp(newValue, minimum, maximum)
        newValue = math.floor((newValue / increment) + 0.5) * increment
        newValue = math.clamp(newValue, minimum, maximum)

        value = newValue

        local denominator = math.max(maximum - minimum, 1)
        local percent = (value - minimum) / denominator

        fill.Size = UDim2.fromScale(percent, 1)
        knob.Position = UDim2.new(percent, 0, 0.5, 0)
        valueText.Text = tostring(value) .. (config.Suffix or "")

        if fireCallback and config.Callback then
            task.spawn(config.Callback, value)
        end
    end

    local function UpdateFromX(x)
        local percent = math.clamp(
            (x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X,
            0,
            1
        )

        SetValue(
            minimum + ((maximum - minimum) * percent),
            true
        )
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            UpdateFromX(input.Position.X)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (
            input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        ) then
            UpdateFromX(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    function api:Set(newValue)
        SetValue(tonumber(newValue) or minimum, true)
    end

    function api:Get()
        return value
    end

    SetValue(value, false)
    return api
end

function Tab:CreateInput(config)
    config = config or {}

    local row = CreateRow(self, 54)

    local title = Label(
        row,
        config.Name or "Input",
        12,
        Theme.Muted,
        Enum.Font.GothamMedium
    )
    title.Position = UDim2.fromOffset(13, 0)
    title.Size = UDim2.new(0.42, -13, 1, 0)

    local holder = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -13, 0.5, 0),
        Size = UDim2.new(0.54, 0, 0, 32),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Parent = row
    })
    Corner(holder, 8)
    Stroke(holder, Theme.Stroke, 1, 0.25)

    local textBox = New("TextBox", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 1, 0),
        ClearTextOnFocus = false,
        Text = tostring(config.Default or ""),
        PlaceholderText = config.Placeholder or "Type...",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder
    })

    textBox.Focused:Connect(function()
        Tween(holder, {BackgroundColor3 = Theme.Surface3})
    end)

    textBox.FocusLost:Connect(function(enterPressed)
        Tween(holder, {BackgroundColor3 = Theme.Surface2})

        if config.Callback then
            task.spawn(config.Callback, textBox.Text, enterPressed)
        end
    end)

    local api = {}

    function api:Set(value)
        textBox.Text = tostring(value)

        if config.Callback then
            task.spawn(config.Callback, textBox.Text, false)
        end
    end

    function api:Get()
        return textBox.Text
    end

    return api
end

function Tab:CreateDropdown(config)
    config = config or {}

    local options = config.Options or {}
    local selected = config.Default
    local opened = false

    local holder = New("Frame", {
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 50),
        ClipsDescendants = true,
        Parent = self.Page
    })
    Corner(holder, 10)
    Stroke(holder, Theme.Stroke, 1, 0.22)

    local top = Button(holder, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 50)
    })

    local title = Label(
        top,
        config.Name or "Dropdown",
        12,
        Theme.Muted,
        Enum.Font.GothamMedium
    )
    title.Position = UDim2.fromOffset(13, 0)
    title.Size = UDim2.new(0.43, -13, 1, 0)

    local selectedText = Label(
        top,
        selected and tostring(selected) or (config.Placeholder or "Select"),
        12,
        selected and Theme.Text or Theme.Muted,
        Enum.Font.Gotham
    )
    selectedText.AnchorPoint = Vector2.new(1, 0)
    selectedText.Position = UDim2.new(1, -34, 0, 0)
    selectedText.Size = UDim2.new(0.52, 0, 1, 0)
    selectedText.TextXAlignment = Enum.TextXAlignment.Right
    selectedText.TextTruncate = Enum.TextTruncate.AtEnd

    local arrow = Label(
        top,
        "⌄",
        14,
        Theme.Muted,
        Enum.Font.GothamBold
    )
    arrow.AnchorPoint = Vector2.new(1, 0)
    arrow.Position = UDim2.new(1, -12, 0, 0)
    arrow.Size = UDim2.fromOffset(18, 50)
    arrow.TextXAlignment = Enum.TextXAlignment.Center

    local list = New("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 50),
        Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = holder
    })

    local listLayout = New("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list
    })

    local optionButtons = {}
    local api = {}

    local function Close()
        opened = false

        Tween(holder, {
            Size = UDim2.new(1, 0, 0, 50)
        })

        Tween(arrow, {
            Rotation = 0
        })
    end

    local function Select(value, fireCallback)
        selected = value
        selectedText.Text = tostring(value)
        selectedText.TextColor3 = Theme.Text

        for option, button in pairs(optionButtons) do
            Tween(button, {
                BackgroundColor3 = option == selected
                    and Theme.Surface3
                    or Theme.Surface2
            })
        end

        if fireCallback and config.Callback then
            task.spawn(config.Callback, selected)
        end
    end

    local function Rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        table.clear(optionButtons)

        for index, option in ipairs(options) do
            local optionButton = Button(list, {
                LayoutOrder = index,
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = option == selected
                    and Theme.Surface3
                    or Theme.Surface2,
                Text = tostring(option),
                TextColor3 = Theme.Text,
                TextSize = 12,
                Font = Enum.Font.Gotham,
                Parent = list
            })
            optionButton.TextXAlignment = Enum.TextXAlignment.Left

            New("UIPadding", {
                PaddingLeft = UDim.new(0, 10),
                PaddingRight = UDim.new(0, 10),
                Parent = optionButton
            })

            Corner(optionButton, 8)

            optionButton.MouseButton1Click:Connect(function()
                Select(option, true)
                Close()
            end)

            optionButtons[option] = optionButton
        end
    end

    local function RenderOpen()
        local height = math.min((#options * 39) + 11, 205)

        Tween(holder, {
            Size = UDim2.new(
                1,
                0,
                0,
                opened and (50 + height) or 50
            )
        })

        Tween(arrow, {
            Rotation = opened and 180 or 0
        })
    end

    top.MouseButton1Click:Connect(function()
        opened = not opened
        RenderOpen()
    end)

    function api:Set(value)
        Select(value, true)
    end

    function api:Get()
        return selected
    end

    function api:SetOptions(newOptions)
        options = newOptions or {}
        Rebuild()

        if opened then
            RenderOpen()
        end
    end

    Rebuild()
    return api
end

return VNDT
