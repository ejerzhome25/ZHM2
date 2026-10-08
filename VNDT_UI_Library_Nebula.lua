--[[
    VNDT UI Library — NEBULA EDITION
    Premium light-black / charcoal UI
    Mobile-first, responsive, readable, reusable
    Version: 5.0-nebula
]]

local VNDT = {}
VNDT.__index = VNDT

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer

local Theme = {
    Background = Color3.fromRGB(25,26,30),
    Background2 = Color3.fromRGB(21,22,26),
    Surface = Color3.fromRGB(33,34,39),
    Surface2 = Color3.fromRGB(40,42,48),
    Surface3 = Color3.fromRGB(49,52,60),
    Surface4 = Color3.fromRGB(59,63,73),
    Stroke = Color3.fromRGB(79,82,94),
    StrokeSoft = Color3.fromRGB(65,68,79),
    Text = Color3.fromRGB(255,255,255),
    Muted = Color3.fromRGB(230,233,242),
    Muted2 = Color3.fromRGB(205,210,224),
    Accent = Color3.fromRGB(139,120,255),
    Accent2 = Color3.fromRGB(69,181,255),
    Accent3 = Color3.fromRGB(211,115,255),
    Success = Color3.fromRGB(91,219,153),
    Danger = Color3.fromRGB(247,94,119),
}

local function New(className, props)
    local o = Instance.new(className)
    for k,v in pairs(props or {}) do
        if k ~= "Parent" then o[k] = v end
    end
    if props and props.Parent then o.Parent = props.Parent end
    return o
end

local function Corner(p,r)
    return New("UICorner",{CornerRadius=UDim.new(0,r or 12),Parent=p})
end

local function Stroke(p,c,t,tr)
    return New("UIStroke",{
        Color=c or Theme.Stroke,
        Thickness=t or 1,
        Transparency=tr or 0,
        ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
        Parent=p
    })
end

local function Gradient(p,a,b,rot)
    return New("UIGradient",{
        Color=ColorSequence.new({
            ColorSequenceKeypoint.new(0,a),
            ColorSequenceKeypoint.new(1,b)
        }),
        Rotation=rot or 0,
        Parent=p
    })
end

local function Padding(p,l,r,t,b)
    return New("UIPadding",{
        PaddingLeft=UDim.new(0,l or 0),
        PaddingRight=UDim.new(0,r or l or 0),
        PaddingTop=UDim.new(0,t or 0),
        PaddingBottom=UDim.new(0,b or t or 0),
        Parent=p
    })
end

local function Tween(o,goal,d)
    local tw=TweenService:Create(
        o,
        TweenInfo.new(d or .16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
        goal
    )
    tw:Play()
    return tw
end

local function Label(p,text,size,color,font)
    return New("TextLabel",{
        BackgroundTransparency=1,
        Text=text or "",
        TextColor3=color or Theme.Text,
        TextSize=size or 14,
        Font=font or Enum.Font.GothamSemibold,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        Parent=p
    })
end

local function Button(p,props)
    props=props or {}
    props.AutoButtonColor=false
    props.Text=props.Text or ""
    props.Parent=p
    return New("TextButton",props)
end

local function GuiParent()
    local ok,res=pcall(function()
        if gethui then return gethui() end
        return game:GetService("CoreGui")
    end)
    if ok and res then return res end
    return Player and Player:WaitForChild("PlayerGui") or game:GetService("CoreGui")
end


local DEFAULT_BACKGROUND_URL = "https://raw.githubusercontent.com/ejerzhome25/ZHM2/main/assets/vndt_nebula_background.jpg"
local CachedDefaultBackgroundAsset = nil

local function ResolveCustomAsset(source, cacheDefault)
    if type(source) ~= "string" or source == "" then
        return ""
    end

    -- Roblox-native assets can be used directly.
    if source:match("^rbxasset") or source:match("^rbxthumb") then
        return source
    end

    local assetLoader = getcustomasset or getsynasset
    if not assetLoader and syn and syn.getcustomasset then
        assetLoader = syn.getcustomasset
    end

    -- Executor path: download the image once and turn it into a local custom asset.
    if source:match("^https?://") and writefile and assetLoader then
        if cacheDefault and CachedDefaultBackgroundAsset then
            return CachedDefaultBackgroundAsset
        end

        local okHttp, bytes = pcall(function()
            return game:HttpGet(source)
        end)

        if okHttp and type(bytes) == "string" and #bytes > 0 then
            local fileName = "VNDT_Nebula_Background_v2.jpg"
            local okWrite = pcall(function()
                writefile(fileName, bytes)
            end)

            if okWrite then
                local okAsset, asset = pcall(function()
                    return assetLoader(fileName)
                end)

                if okAsset and type(asset) == "string" and asset ~= "" then
                    if cacheDefault then
                        CachedDefaultBackgroundAsset = asset
                    end
                    return asset
                end
            end
        end
    end

    -- Allows callers to provide any other Content string supported by their environment.
    return source
end

local function GetBackgroundAsset(cfg)
    if cfg.DisableBackground == true then
        return ""
    end

    if type(cfg.BackgroundImage) == "string" and cfg.BackgroundImage ~= "" then
        return ResolveCustomAsset(cfg.BackgroundImage, false)
    end

    if CachedDefaultBackgroundAsset then
        return CachedDefaultBackgroundAsset
    end

    return ResolveCustomAsset(DEFAULT_BACKGROUND_URL, true)
end

local function Canvas(scroll,layout,extra)
    local function update()
        scroll.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+(extra or 12))
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
    update()
end

local function Drag(handle,target)
    local dragging,start,startPos
    handle.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            start=i.Position
            startPos=target.Position
            i.Changed:Connect(function()
                if i.UserInputState==Enum.UserInputState.End then dragging=false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-start
            target.Position=UDim2.new(
                startPos.X.Scale,startPos.X.Offset+d.X,
                startPos.Y.Scale,startPos.Y.Offset+d.Y
            )
        end
    end)
end

local function Row(parent,height)
    local r=New("Frame",{
        BackgroundColor3=Theme.Surface,
        BackgroundTransparency=.08,
        BorderSizePixel=0,
        Size=UDim2.new(1,0,0,height or 50),
        Parent=parent
    })
    Corner(r,18)
    Stroke(r,Theme.StrokeSoft,1,.12)
    Gradient(r,Theme.Surface2,Theme.Surface,90)
    return r
end

local Window={}
Window.__index=Window
local Tab={}
Tab.__index=Tab

function VNDT:SetTheme(partial)
    for k,v in pairs(partial or {}) do
        if Theme[k]~=nil then Theme[k]=v end
    end
end

function VNDT:GetTheme()
    return Theme
end

function VNDT:CreateWindow(cfg)
    cfg=cfg or {}
    local mobile=UIS.TouchEnabled and not UIS.KeyboardEnabled
    local cam=workspace.CurrentCamera
    local vp=cam and cam.ViewportSize or Vector2.new(1280,720)

    local width=cfg.Width or 620
    local height=cfg.Height or 430
    if mobile then
        width=math.floor(math.min(cfg.MobileWidth or 520,math.max(300,vp.X-16)))
        height=math.floor(math.min(cfg.MobileHeight or 390,math.max(300,vp.Y-20)))
    end

    local gui=New("ScreenGui",{
        Name="VNDT_"..HttpService:GenerateGUID(false),
        ResetOnSpawn=false,
        IgnoreGuiInset=true,
        DisplayOrder=999999,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
        Parent=GuiParent()
    })

    local main=New("Frame",{
        Name="Main",
        AnchorPoint=Vector2.new(.5,.5),
        Position=UDim2.fromScale(.5,.5),
        Size=UDim2.fromOffset(width,height),
        BackgroundColor3=Theme.Background,
        BorderSizePixel=0,
        ClipsDescendants=true,
        Parent=gui
    })
    Corner(main,24)
    Stroke(main,Theme.Stroke,1,.04)
    Gradient(main,Theme.Background,Theme.Background2,90)

    local backgroundAsset = GetBackgroundAsset(cfg)
    if backgroundAsset ~= "" then
        local backgroundImage = New("ImageLabel",{
            Name="VNDT_BackgroundImage",
            BackgroundTransparency=1,
            BorderSizePixel=0,
            Size=UDim2.fromScale(1,1),
            Position=UDim2.fromScale(0,0),
            Image=backgroundAsset,
            ImageColor3=cfg.BackgroundImageTint or Color3.fromRGB(162,164,176),
            ImageTransparency=cfg.BackgroundImageTransparency or .08,
            ScaleType=Enum.ScaleType.Crop,
            ZIndex=1,
            Parent=main
        })
        Corner(backgroundImage,24)
    end

    local accent=New("Frame",{
        BackgroundColor3=Theme.Accent,
        BorderSizePixel=0,
        Size=UDim2.new(1,0,0,3),
        Parent=main
    })
    Gradient(accent,Theme.Accent3,Theme.Accent2,0)

    local topH=mobile and 58 or 64
    local top=New("Frame",{
        BackgroundColor3=Theme.Surface,
        BackgroundTransparency=.10,
        BorderSizePixel=0,
        ZIndex=2,
        Size=UDim2.new(1,0,0,topH),
        Parent=main
    })
    Gradient(top,Theme.Surface2,Theme.Surface,90)

    local title=Label(top,cfg.Name or "VNDT",mobile and 17 or 18,Theme.Text,Enum.Font.GothamBold)
    title.Position=UDim2.fromOffset(16,mobile and 7 or 10)
    title.Size=UDim2.new(1,-120,0,24)

    local sub=Label(top,cfg.Subtitle or "Nebula Edition",11,Theme.Muted,Enum.Font.GothamSemibold)
    sub.Position=UDim2.fromOffset(16,mobile and 29 or 34)
    sub.Size=UDim2.new(1,-120,0,18)

    local function topButton(symbol,x)
        local b=Button(top,{
            AnchorPoint=Vector2.new(1,.5),
            Position=UDim2.new(1,x,.5,0),
            Size=UDim2.fromOffset(mobile and 38 or 36,mobile and 38 or 36),
            BackgroundColor3=Theme.Surface2,
            Text=symbol,
            TextColor3=Theme.Text,
            TextSize=17,
            Font=Enum.Font.GothamBold
        })
        Corner(b,12); Stroke(b,Theme.Stroke,1,.2); Gradient(b,Theme.Surface3,Theme.Surface2,90)
        return b
    end

    local minimize=topButton("—",-54)
    local close=topButton("×",-12)

    local tabH=mobile and 50 or 0
    local sideW=mobile and 0 or 166

    local sidebar=New("Frame",{
        BackgroundColor3=Theme.Surface,
        BackgroundTransparency=.10,
        BorderSizePixel=0,
        ZIndex=2,
        Position=mobile and UDim2.fromOffset(0,topH) or UDim2.fromOffset(0,topH),
        Size=mobile and UDim2.new(1,0,0,tabH) or UDim2.new(0,sideW,1,-topH),
        Parent=main
    })
    Gradient(sidebar,Theme.Surface,Theme.Background2,90)

    local tabs=New("ScrollingFrame",{
        BackgroundTransparency=1,
        BorderSizePixel=0,
        Position=mobile and UDim2.fromOffset(8,4) or UDim2.fromOffset(10,10),
        Size=mobile and UDim2.new(1,-16,1,-8) or UDim2.new(1,-20,1,-20),
        CanvasSize=UDim2.new(),
        ScrollBarThickness=mobile and 0 or 3,
        ScrollBarImageColor3=Theme.Accent,
        ScrollingDirection=mobile and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
        Parent=sidebar
    })

    local tabLayout=New("UIListLayout",{
        FillDirection=mobile and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        Padding=UDim.new(0,8),
        SortOrder=Enum.SortOrder.LayoutOrder,
        Parent=tabs
    })
    if mobile then
        local function tc()
            tabs.CanvasSize=UDim2.fromOffset(tabLayout.AbsoluteContentSize.X+8,0)
        end
        tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(tc); tc()
    else
        Canvas(tabs,tabLayout,8)
    end

    local pages=New("Frame",{
        BackgroundTransparency=1,
        ZIndex=2,
        Position=mobile and UDim2.fromOffset(0,topH+tabH) or UDim2.fromOffset(sideW,topH),
        Size=mobile and UDim2.new(1,0,1,-topH-tabH) or UDim2.new(1,-sideW,1,-topH),
        ClipsDescendants=true,
        Parent=main
    })

    local orb=Button(gui,{
        Name="VNDT_MinimizedOrb",
        Position=UDim2.fromOffset(18,76),
        Size=UDim2.fromOffset(mobile and 62 or 58,mobile and 62 or 58),
        BackgroundColor3=Theme.Accent,
        Text="V",
        TextColor3=Color3.new(1,1,1),
        TextSize=22,
        Font=Enum.Font.GothamBold,
        Visible=false,
        ZIndex=999
    })
    Corner(orb,999)
    Stroke(orb,Color3.new(1,1,1),1.4,.46)
    Gradient(orb,Theme.Accent3,Theme.Accent2,45)

    local inner=New("Frame",{
        AnchorPoint=Vector2.new(.5,.5),
        Position=UDim2.fromScale(.5,.5),
        Size=UDim2.new(1,-10,1,-10),
        BackgroundColor3=Color3.new(1,1,1),
        BackgroundTransparency=.9,
        BorderSizePixel=0,
        ZIndex=998,
        Parent=orb
    })
    Corner(inner,999)

    local dot=New("Frame",{
        AnchorPoint=Vector2.new(1,0),
        Position=UDim2.new(1,-4,0,4),
        Size=UDim2.fromOffset(10,10),
        BackgroundColor3=Theme.Success,
        BorderSizePixel=0,
        ZIndex=1000,
        Parent=orb
    })
    Corner(dot,999); Stroke(dot,Color3.new(1,1,1),1,.25)

    local self=setmetatable({
        Gui=gui,Main=main,Sidebar=sidebar,TabList=tabs,Pages=pages,
        Tabs={},SelectedTab=nil,Minimized=false,Orb=orb,Mobile=mobile
    },Window)

    Drag(top,main)
    Drag(orb,orb)

    minimize.MouseButton1Click:Connect(function()
        self.Minimized=true
        main.Visible=false
        orb.Visible=true
    end)

    orb.MouseButton1Click:Connect(function()
        self.Minimized=false
        orb.Visible=false
        main.Visible=true
    end)

    minimize.MouseEnter:Connect(function() Tween(minimize,{BackgroundColor3=Theme.Surface3}) end)
    minimize.MouseLeave:Connect(function() Tween(minimize,{BackgroundColor3=Theme.Surface2}) end)
    close.MouseEnter:Connect(function() Tween(close,{BackgroundColor3=Theme.Danger}) end)
    close.MouseLeave:Connect(function() Tween(close,{BackgroundColor3=Theme.Surface2}) end)
    close.MouseButton1Click:Connect(function() gui:Destroy() end)

    return self
end

function Window:CreateTab(name)
    local mobile=self.Mobile
    local b=Button(self.TabList,{
        Size=mobile and UDim2.fromOffset(112,40) or UDim2.new(1,0,0,42),
        BackgroundColor3=Theme.Surface,
        Text="",
        LayoutOrder=#self.Tabs+1
    })
    Corner(b,14); Stroke(b,Theme.StrokeSoft,1,.18); Gradient(b,Theme.Surface2,Theme.Surface,90)

    local line=New("Frame",{
        AnchorPoint=Vector2.new(0,.5),
        Position=UDim2.new(0,0,.5,0),
        Size=UDim2.fromOffset(4,20),
        BackgroundColor3=Theme.Accent,
        BackgroundTransparency=1,
        BorderSizePixel=0,
        Parent=b
    })
    Corner(line,999); Gradient(line,Theme.Accent3,Theme.Accent2,0)

    local txt=Label(b,name or "Tab",14,Theme.Muted,Enum.Font.GothamBold)
    txt.Position=UDim2.fromOffset(14,0)
    txt.Size=UDim2.new(1,-20,1,0)
    txt.TextTruncate=Enum.TextTruncate.AtEnd

    local page=New("ScrollingFrame",{
        BackgroundTransparency=1,
        BorderSizePixel=0,
        Size=UDim2.fromScale(1,1),
        CanvasSize=UDim2.new(),
        ScrollBarThickness=mobile and 7 or 3,
        ScrollBarImageColor3=Theme.Accent,
        ElasticBehavior=Enum.ElasticBehavior.WhenScrollable,
        ScrollingDirection=Enum.ScrollingDirection.Y,
        Visible=false,
        Parent=self.Pages
    })
    Padding(page,mobile and 12 or 16,mobile and 12 or 16,14,14)
    local layout=New("UIListLayout",{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder,Parent=page})
    Canvas(page,layout,22)

    local tab=setmetatable({Window=self,Button=b,Line=line,Text=txt,Page=page},Tab)
    table.insert(self.Tabs,tab)

    b.MouseButton1Click:Connect(function() self:SelectTab(tab) end)
    if not self.SelectedTab then self:SelectTab(tab) end
    return tab
end

function Window:SelectTab(tab)
    self.SelectedTab=tab
    for _,t in ipairs(self.Tabs) do
        local on=t==tab
        t.Page.Visible=on
        Tween(t.Button,{BackgroundColor3=on and Theme.Surface3 or Theme.Surface})
        Tween(t.Text,{TextColor3=on and Theme.Text or Theme.Muted})
        Tween(t.Line,{BackgroundTransparency=on and 0 or 1})
    end
end

function Window:Notify(cfg)
    cfg=cfg or {}
    local holder=self.Gui:FindFirstChild("VNDT_Notifications")
    if not holder then
        holder=New("Frame",{
            Name="VNDT_Notifications",
            BackgroundTransparency=1,
            AnchorPoint=Vector2.new(1,1),
            Position=UDim2.new(1,-12,1,-12),
            Size=UDim2.fromOffset(310,300),
            Parent=self.Gui
        })
        New("UIListLayout",{
            Padding=UDim.new(0,8),
            VerticalAlignment=Enum.VerticalAlignment.Bottom,
            HorizontalAlignment=Enum.HorizontalAlignment.Right,
            Parent=holder
        })
    end

    local card=New("Frame",{
        BackgroundColor3=Theme.Surface,
        BorderSizePixel=0,
        Size=UDim2.fromOffset(300,78),
        Parent=holder
    })
    Corner(card,16); Stroke(card,Theme.Stroke,1,.12); Gradient(card,Theme.Surface2,Theme.Surface,90)

    local bar=New("Frame",{BackgroundColor3=Theme.Accent,BorderSizePixel=0,Size=UDim2.new(0,4,1,0),Parent=card})
    Corner(bar,999); Gradient(bar,Theme.Accent3,Theme.Accent2,0)

    local t=Label(card,cfg.Title or "VNDT",13,Theme.Text,Enum.Font.GothamBold)
    t.Position=UDim2.fromOffset(16,8); t.Size=UDim2.new(1,-28,0,22)
    local c=Label(card,cfg.Content or "",12,Theme.Muted,Enum.Font.GothamMedium)
    c.Position=UDim2.fromOffset(16,31); c.Size=UDim2.new(1,-28,0,32); c.TextWrapped=true

    task.delay(cfg.Duration or 3,function()
        if card.Parent then
            Tween(card,{BackgroundTransparency=1},.18)
            Tween(t,{TextTransparency=1},.18)
            Tween(c,{TextTransparency=1},.18)
            task.delay(.2,function() if card then card:Destroy() end end)
        end
    end)
end

function Window:SetVisible(v) self.Gui.Enabled=not not v end
function Window:Destroy() if self.Gui then self.Gui:Destroy() end end

function Tab:CreateSection(text)
    local h=New("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,24),Parent=self.Page})
    local l=New("Frame",{BackgroundColor3=Theme.StrokeSoft,BorderSizePixel=0,Position=UDim2.new(0,0,.5,6),Size=UDim2.new(1,0,0,1),Parent=h})
    local chip=New("Frame",{BackgroundColor3=Theme.Background,BorderSizePixel=0,Size=UDim2.fromOffset(175,22),Parent=h})
    Corner(chip,999)
    local tx=Label(chip,string.upper(text or "SECTION"),12,Theme.Text,Enum.Font.GothamBold)
    tx.Size=UDim2.new(1,0,1,0)
    return h
end

function Tab:CreateLabel(text)
    local r=Row(self.Page,44)
    local tx=Label(r,text or "Label",14,Theme.Text,Enum.Font.GothamBold)
    tx.Position=UDim2.fromOffset(14,0); tx.Size=UDim2.new(1,-28,1,0)
    return {
        Set=function(_,v) tx.Text=tostring(v) end,
        Get=function() return tx.Text end
    }
end

function Tab:CreateButton(cfg)
    cfg=cfg or {}
    local desc=type(cfg.Description)=="string" and cfg.Description~=""
    local r=Row(self.Page,desc and 62 or 50)

    local tx=Label(r,cfg.Name or "Button",13,Theme.Text,Enum.Font.GothamBold)
    tx.Position=desc and UDim2.fromOffset(14,7) or UDim2.fromOffset(14,0)
    tx.Size=desc and UDim2.new(1,-54,0,22) or UDim2.new(1,-54,1,0)

    local d
    if desc then
        d=Label(r,cfg.Description,11,Theme.Muted,Enum.Font.GothamSemibold)
        d.Position=UDim2.fromOffset(14,31); d.Size=UDim2.new(1,-54,0,18); d.TextTruncate=Enum.TextTruncate.AtEnd
    end

    local arrow=Label(r,"›",20,Theme.Accent2,Enum.Font.GothamBold)
    arrow.AnchorPoint=Vector2.new(1,.5); arrow.Position=UDim2.new(1,-14,.5,0); arrow.Size=UDim2.fromOffset(18,18)
    arrow.TextXAlignment=Enum.TextXAlignment.Center

    local hit=Button(r,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})
    hit.MouseButton1Click:Connect(function() if cfg.Callback then task.spawn(cfg.Callback) end end)

    return {
        SetName=function(_,v) tx.Text=tostring(v) end,
        SetDescription=function(_,v) if d then d.Text=tostring(v or "") end end
    }
end

function Tab:CreateToggle(cfg)
    cfg=cfg or {}
    local value=cfg.Default==true
    local desc=type(cfg.Description)=="string" and cfg.Description~=""
    local r=Row(self.Page,desc and 64 or 52)

    local tx=Label(r,cfg.Name or "Toggle",13,Theme.Text,Enum.Font.GothamBold)
    tx.Position=desc and UDim2.fromOffset(14,7) or UDim2.fromOffset(14,0)
    tx.Size=desc and UDim2.new(1,-82,0,22) or UDim2.new(1,-82,1,0)

    local d
    if desc then
        d=Label(r,cfg.Description,11,Theme.Muted,Enum.Font.GothamSemibold)
        d.Position=UDim2.fromOffset(14,32); d.Size=UDim2.new(1,-82,0,18); d.TextTruncate=Enum.TextTruncate.AtEnd
    end

    local track=New("Frame",{
        AnchorPoint=Vector2.new(1,.5),
        Position=UDim2.new(1,-14,.5,0),
        Size=UDim2.fromOffset(48,26),
        BackgroundColor3=value and Theme.Accent or Theme.Surface3,
        BorderSizePixel=0,
        Parent=r
    })
    Corner(track,999); Gradient(track,value and Theme.Accent3 or Theme.Surface4,value and Theme.Accent2 or Theme.Surface3,0)

    local knob=New("Frame",{
        AnchorPoint=Vector2.new(.5,.5),
        Position=value and UDim2.new(1,-13,.5,0) or UDim2.new(0,13,.5,0),
        Size=UDim2.fromOffset(20,20),
        BackgroundColor3=Color3.fromRGB(249,249,252),
        BorderSizePixel=0,
        Parent=track
    })
    Corner(knob,999)

    local api={}
    local function render(fire)
        Tween(track,{BackgroundColor3=value and Theme.Accent or Theme.Surface3})
        Tween(knob,{Position=value and UDim2.new(1,-13,.5,0) or UDim2.new(0,13,.5,0)})
        if fire and cfg.Callback then task.spawn(cfg.Callback,value) end
    end

    local hit=Button(r,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})
    hit.MouseButton1Click:Connect(function() value=not value; render(true) end)

    function api:Set(v) value=not not v; render(true) end
    function api:Get() return value end
    function api:SetDescription(v) if d then d.Text=tostring(v or "") end end
    return api
end

function Tab:CreateSlider(cfg)
    cfg=cfg or {}
    local min,max=cfg.Min or 0,cfg.Max or 100
    local step=cfg.Increment or 1
    local value=math.clamp(cfg.Default or min,min,max)
    local r=Row(self.Page,78)

    local tx=Label(r,cfg.Name or "Slider",13,Theme.Text,Enum.Font.GothamBold)
    tx.Position=UDim2.fromOffset(14,8); tx.Size=UDim2.new(1,-92,0,22)

    local chip=New("Frame",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-14,0,8),Size=UDim2.fromOffset(72,24),BackgroundColor3=Theme.Surface3,BorderSizePixel=0,Parent=r})
    Corner(chip,999); Gradient(chip,Theme.Surface4,Theme.Surface3,0)
    local val=Label(chip,"",11,Theme.Text,Enum.Font.GothamBold); val.Size=UDim2.fromScale(1,1); val.TextXAlignment=Enum.TextXAlignment.Center

    local bar=New("Frame",{Position=UDim2.fromOffset(14,52),Size=UDim2.new(1,-28,0,8),BackgroundColor3=Theme.Surface3,BorderSizePixel=0,Parent=r})
    Corner(bar,999)
    local fill=New("Frame",{BackgroundColor3=Theme.Accent,BorderSizePixel=0,Parent=bar}); Corner(fill,999); Gradient(fill,Theme.Accent3,Theme.Accent2,0)
    local knob=New("Frame",{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(16,16),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Parent=bar}); Corner(knob,999)

    local dragging=false
    local api={}
    local function set(v,fire)
        v=math.clamp(v,min,max)
        v=math.floor(v/step+.5)*step
        value=math.clamp(v,min,max)
        local p=(value-min)/math.max(max-min,1)
        fill.Size=UDim2.fromScale(p,1)
        knob.Position=UDim2.new(p,0,.5,0)
        val.Text=tostring(value)..(cfg.Suffix or "")
        if fire and cfg.Callback then task.spawn(cfg.Callback,value) end
    end
    local function fromX(x)
        set(min+(max-min)*math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1),true)
    end
    bar.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; fromX(i.Position.X) end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then fromX(i.Position.X) end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)

    function api:Set(v) set(tonumber(v) or min,true) end
    function api:Get() return value end
    set(value,false)
    return api
end

function Tab:CreateInput(cfg)
    cfg=cfg or {}
    local r=Row(self.Page,58)
    local tx=Label(r,cfg.Name or "Input",13,Theme.Text,Enum.Font.GothamSemibold)
    tx.Position=UDim2.fromOffset(14,0); tx.Size=UDim2.new(.38,0,1,0)

    local boxHolder=New("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-14,.5,0),Size=UDim2.new(.58,0,0,36),BackgroundColor3=Theme.Surface2,BorderSizePixel=0,Parent=r})
    Corner(boxHolder,12); Stroke(boxHolder,Theme.Stroke,1,.22); Gradient(boxHolder,Theme.Surface3,Theme.Surface2,90)
    local box=New("TextBox",{BackgroundTransparency=1,Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-20,1,0),ClearTextOnFocus=false,Text=tostring(cfg.Default or ""),PlaceholderText=cfg.Placeholder or "Type...",PlaceholderColor3=Theme.Muted2,TextColor3=Theme.Text,TextSize=13,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,Parent=boxHolder})
    box.FocusLost:Connect(function(enter) if cfg.Callback then task.spawn(cfg.Callback,box.Text,enter) end end)

    return {
        Set=function(_,v) box.Text=tostring(v); if cfg.Callback then task.spawn(cfg.Callback,box.Text,false) end end,
        Get=function() return box.Text end
    }
end

function Tab:CreateDropdown(cfg)
    cfg=cfg or {}
    local options=cfg.Options or {}
    local selected=cfg.Default
    local open=false
    local closed=58
    local holder=Row(self.Page,closed)
    holder.ClipsDescendants=true

    local head=Button(holder,{BackgroundTransparency=1,Size=UDim2.new(1,0,0,closed)})
    local tx=Label(head,cfg.Name or "Dropdown",13,Theme.Text,Enum.Font.GothamBold)
    tx.Position=UDim2.fromOffset(14,0); tx.Size=UDim2.new(.42,0,1,0)

    local chip=New("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-38,.5,0),Size=UDim2.fromOffset(182,32),BackgroundColor3=Theme.Surface3,BorderSizePixel=0,Parent=head})
    Corner(chip,999); Stroke(chip,Theme.Stroke,1,.18); Gradient(chip,Theme.Surface4,Theme.Surface3,0)
    local summary=Label(chip,selected and tostring(selected) or (cfg.Placeholder or "Select"),13,Theme.Text,Enum.Font.GothamBold)
    summary.Position=UDim2.fromOffset(12,0); summary.Size=UDim2.new(1,-34,1,0); summary.TextTruncate=Enum.TextTruncate.AtEnd
    summary.TextTransparency=0
    local arrow=Label(chip,"›",17,Theme.Accent2,Enum.Font.GothamBold); arrow.AnchorPoint=Vector2.new(1,.5); arrow.Position=UDim2.new(1,-10,.5,0); arrow.Size=UDim2.fromOffset(14,14); arrow.TextXAlignment=Enum.TextXAlignment.Center; arrow.Rotation=90

    local list=New("ScrollingFrame",{BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(10,closed),Size=UDim2.new(1,-20,0,0),CanvasSize=UDim2.new(),ScrollBarThickness=5,ScrollBarImageColor3=Theme.Accent,Parent=holder})
    local ll=New("UIListLayout",{Padding=UDim.new(0,6),Parent=list}); Canvas(list,ll,4)
    local buttons={}
    local api={}

    local function choose(v,fire)
        selected=v
        summary.Text=selected and tostring(selected) or (cfg.Placeholder or "Select")
        summary.TextColor3=selected and Theme.Text or Theme.Muted
        for option,b in pairs(buttons) do b.BackgroundColor3=option==selected and Theme.Surface4 or Theme.Surface2 end
        if fire and cfg.Callback then task.spawn(cfg.Callback,selected) end
    end

    local function rebuild()
        for _,c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        table.clear(buttons)
        for i,opt in ipairs(options) do
            local b=Button(list,{LayoutOrder=i,Size=UDim2.new(1,0,0,40),BackgroundColor3=Theme.Surface2,Text=tostring(opt),TextColor3=Theme.Text,TextSize=13,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})
            Padding(b,12,12,0,0); Corner(b,12); Gradient(b,Theme.Surface3,Theme.Surface2,90)
            buttons[opt]=b
            b.MouseButton1Click:Connect(function()
                choose(opt,true)
                open=false
                Tween(holder,{Size=UDim2.new(1,0,0,closed)})
                Tween(arrow,{Rotation=90})
            end)
        end
        choose(selected,false)
    end

    head.MouseButton1Click:Connect(function()
        open=not open
        local h=math.min(math.max(46,#options*46),218)
        list.Size=UDim2.new(1,-20,0,h)
        Tween(holder,{Size=UDim2.new(1,0,0,open and closed+h+8 or closed)})
        Tween(arrow,{Rotation=open and 270 or 90})
    end)

    function api:Set(v,fire) choose(v,fire==true) end
    function api:Get() return selected end
    function api:SetOptions(v) options=v or {}; rebuild() end
    rebuild()
    return api
end

function Tab:CreateMultiDropdown(cfg)
    cfg=cfg or {}
    local options=cfg.Options or {}
    local selected=cfg.Selected or cfg.Default or {}
    local open=false
    local query=""
    local closed=60
    local holder=Row(self.Page,closed)
    holder.ClipsDescendants=true

    local head=Button(holder,{BackgroundTransparency=1,Size=UDim2.new(1,0,0,closed)})
    local tx=Label(head,cfg.Name or "Multi Select",13,Theme.Text,Enum.Font.GothamBold)
    tx.Position=UDim2.fromOffset(14,0); tx.Size=UDim2.new(.42,0,1,0)

    local chip=New("Frame",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-38,.5,0),Size=UDim2.fromOffset(190,32),BackgroundColor3=Theme.Surface3,BorderSizePixel=0,Parent=head})
    Corner(chip,999); Stroke(chip,Theme.Stroke,1,.18); Gradient(chip,Theme.Surface4,Theme.Surface3,0)
    local summary=Label(chip,cfg.Placeholder or "None selected",13,Theme.Text,Enum.Font.GothamBold)
    summary.Position=UDim2.fromOffset(12,0); summary.Size=UDim2.new(1,-34,1,0); summary.TextTruncate=Enum.TextTruncate.AtEnd
    local arrow=Label(chip,"›",17,Theme.Accent2,Enum.Font.GothamBold); arrow.AnchorPoint=Vector2.new(1,.5); arrow.Position=UDim2.new(1,-10,.5,0); arrow.Size=UDim2.fromOffset(14,14); arrow.TextXAlignment=Enum.TextXAlignment.Center; arrow.Rotation=90

    local body=New("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(10,closed),Size=UDim2.new(1,-20,0,0),Parent=holder})
    local search=New("TextBox",{BackgroundColor3=Theme.Surface2,BorderSizePixel=0,Size=UDim2.new(1,0,0,34),ClearTextOnFocus=false,Text="",PlaceholderText=cfg.SearchPlaceholder or "Search...",PlaceholderColor3=Theme.Muted2,TextColor3=Theme.Text,TextSize=13,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,Parent=body})
    Corner(search,12); Padding(search,10,10,0,0)

    local list=New("ScrollingFrame",{BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.fromOffset(0,40),Size=UDim2.new(1,0,0,44),CanvasSize=UDim2.new(),ScrollBarThickness=5,ScrollBarImageColor3=Theme.Accent,Parent=body})
    local ll=New("UIListLayout",{Padding=UDim.new(0,6),Parent=list}); Canvas(list,ll,4)
    local rows={}
    local api={}

    local function updateSummary()
        local count=0
        local only
        for _,opt in ipairs(options) do if selected[opt] then count+=1; only=opt end end
        if count==0 then summary.Text=cfg.Placeholder or "None selected"; summary.TextColor3=Theme.Muted
        elseif count==1 then summary.Text=tostring(only); summary.TextColor3=Theme.Text
        else summary.Text=tostring(count).." selected"; summary.TextColor3=Theme.Text end
    end

    local function refresh()
        local shown=0
        for opt,data in pairs(rows) do
            local visible=query=="" or string.find(string.lower(tostring(opt)),query,1,true)~=nil
            data.frame.Visible=visible
            if visible then shown+=1 end
            data.button.BackgroundColor3=selected[opt] and Theme.Surface4 or Theme.Surface2
            data.check.TextTransparency=selected[opt] and 0 or 1
        end
        updateSummary()
        local h=math.min(math.max(44,shown*46),cfg.MaxHeight or 210)
        list.Size=UDim2.new(1,0,0,h)
        body.Size=UDim2.new(1,-20,0,40+h)
        if open then holder.Size=UDim2.new(1,0,0,closed+48+h) end
    end

    local function rebuild()
        for _,c in ipairs(list:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
        table.clear(rows)
        for _,opt in ipairs(options) do
            local f=New("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,40),Parent=list})
            local b=Button(f,{Size=UDim2.fromScale(1,1),BackgroundColor3=Theme.Surface2,Text=tostring(opt),TextColor3=Theme.Text,TextSize=13,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})
            Padding(b,12,42,0,0); Corner(b,12); Gradient(b,Theme.Surface3,Theme.Surface2,90)
            local mark=Label(b,"✓",12,Color3.new(1,1,1),Enum.Font.GothamBold); mark.AnchorPoint=Vector2.new(1,.5); mark.Position=UDim2.new(1,-14,.5,0); mark.Size=UDim2.fromOffset(18,18); mark.TextXAlignment=Enum.TextXAlignment.Center
            rows[opt]={frame=f,button=b,check=mark}
            b.MouseButton1Click:Connect(function()
                selected[opt]=not selected[opt]
                refresh()
                if cfg.Callback then task.spawn(cfg.Callback,opt,selected[opt],selected) end
            end)
        end
        refresh()
    end

    head.MouseButton1Click:Connect(function()
        open=not open
        refresh()
        Tween(holder,{Size=UDim2.new(1,0,0,open and holder.Size.Y.Offset or closed)})
        if not open then Tween(holder,{Size=UDim2.new(1,0,0,closed)}) end
        Tween(arrow,{Rotation=open and 270 or 90})
    end)
    search:GetPropertyChangedSignal("Text"):Connect(function() query=string.lower(search.Text or ""); refresh() end)

    function api:SetOptions(v) options=v or {}; rebuild() end
    function api:Refresh(v) if v then options=v end; rebuild() end
    function api:GetSelected() return selected end
    function api:SetSelected(map,fire)
        for k in pairs(selected) do selected[k]=nil end
        for k,v in pairs(map or {}) do if v then selected[k]=true end end
        refresh()
        if fire and cfg.Callback then task.spawn(cfg.Callback,nil,nil,selected) end
    end
    function api:Clear(fire)
        for k in pairs(selected) do selected[k]=nil end
        refresh()
        if fire and cfg.Callback then task.spawn(cfg.Callback,nil,nil,selected) end
    end

    rebuild()
    return api
end

VNDT.Version="5.1-nebula-anime"
VNDT.Theme=Theme

return VNDT
