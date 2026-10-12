const YOUTUBE_URL = "https://m.youtube.com/watch?v=dQw4w9WgXcQ";
const THUMBNAIL = "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg";
const BASE_URL = "https://zhmontop2123.vercel.app";

function previewHtml() {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Rick Astley - Never Gonna Give You Up</title>
  <link rel="canonical" href="${YOUTUBE_URL}">
  <meta property="og:site_name" content="YouTube">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Rick Astley - Never Gonna Give You Up">
  <meta property="og:description" content="Watch on YouTube">
  <meta property="og:url" content="${YOUTUBE_URL}">
  <meta property="og:image" content="${THUMBNAIL}">
  <meta property="og:image:secure_url" content="${THUMBNAIL}">
  <meta property="og:image:width" content="1280">
  <meta property="og:image:height" content="720">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Rick Astley - Never Gonna Give You Up">
  <meta name="twitter:description" content="Watch on YouTube">
  <meta name="twitter:image" content="${THUMBNAIL}">
</head>
<body><a href="${YOUTUBE_URL}">Watch on YouTube</a></body>
</html>`;
}

function luaLoader(getKeyUrl) {
  const safeGetKeyUrl = JSON.stringify(getKeyUrl || (BASE_URL + "/getkey"));
  return `local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "VNDT_KeySystem"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(330, 190)
main.Position = UDim2.new(0.5, -165, 0.5, -95)
main.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
main.BorderSizePixel = 0
main.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -24, 0, 36)
title.Position = UDim2.fromOffset(12, 10)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(245,245,245)
title.Text = "VNDT KEY SYSTEM"
title.Parent = main

local box = Instance.new("TextBox")
box.Size = UDim2.new(1, -24, 0, 42)
box.Position = UDim2.fromOffset(12, 56)
box.BackgroundColor3 = Color3.fromRGB(10, 13, 18)
box.TextColor3 = Color3.fromRGB(235,235,235)
box.PlaceholderText = "Enter key"
box.Text = ""
box.ClearTextOnFocus = false
box.Font = Enum.Font.Gotham
box.TextSize = 14
box.Parent = main
local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(0, 10)
bc.Parent = box

local get = Instance.new("TextButton")
get.Size = UDim2.new(0.5, -18, 0, 38)
get.Position = UDim2.fromOffset(12, 108)
get.BackgroundColor3 = Color3.fromRGB(35, 42, 56)
get.TextColor3 = Color3.fromRGB(255,255,255)
get.Text = "Get Key"
get.Font = Enum.Font.GothamBold
get.TextSize = 14
get.Parent = main
local gc = Instance.new("UICorner")
gc.CornerRadius = UDim.new(0, 10)
gc.Parent = get

local verify = Instance.new("TextButton")
verify.Size = UDim2.new(0.5, -18, 0, 38)
verify.Position = UDim2.new(0.5, 6, 0, 108)
verify.BackgroundColor3 = Color3.fromRGB(55, 70, 96)
verify.TextColor3 = Color3.fromRGB(255,255,255)
verify.Text = "Verify"
verify.Font = Enum.Font.GothamBold
verify.TextSize = 14
verify.Parent = main
local vc = Instance.new("UICorner")
vc.CornerRadius = UDim.new(0, 10)
vc.Parent = verify

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -24, 0, 28)
status.Position = UDim2.fromOffset(12, 151)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(170, 180, 195)
status.Text = "Get a key, then paste it above."
status.Parent = main

local getKeyUrl = ${safeGetKeyUrl}

get.MouseButton1Click:Connect(function()
  local opened = pcall(function()
    GuiService:OpenBrowserWindow(getKeyUrl)
  end)
  if not opened and setclipboard then
    setclipboard(getKeyUrl)
    status.Text = "Link copied. Open it in your browser."
  else
    status.Text = "Opening key link..."
  end
end)

verify.MouseButton1Click:Connect(function()
  local key = box.Text:gsub("%s+", "")
  if key == "" then
    status.Text = "Enter your key first."
    return
  end

  status.Text = "Verifying..."

  local ok, body = pcall(function()
    return game:HttpGet("${BASE_URL}/source?key=" .. key)
  end)

  if not ok then
    status.Text = "Request failed."
    return
  end

  local fn, compileErr = loadstring(body)
  if not fn then
    status.Text = "Invalid response."
    return
  end

  gui:Destroy()
  local ran, runErr = pcall(fn)
  if not ran then
    warn(runErr)
  end
end)
`;
}

export default function handler(req, res) {
  const ua = String(req.headers["user-agent"] || "").toLowerCase();
  const fetchDest = String(req.headers["sec-fetch-dest"] || "").toLowerCase();
  const fetchMode = String(req.headers["sec-fetch-mode"] || "").toLowerCase();

  const isDiscord = ua.includes("discordbot") || ua.includes("discord");
  const isBrowserNavigation = fetchDest === "document" || fetchMode === "navigate";

  if (req.method === "HEAD") {
    res.setHeader("Content-Type", (isDiscord || isBrowserNavigation) ? "text/html; charset=utf-8" : "text/plain; charset=utf-8");
    res.setHeader("Cache-Control", "no-store, max-age=0");
    res.status(200).end();
    return;
  }

  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  if (isDiscord) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    res.status(200).send(previewHtml());
    return;
  }

  if (isBrowserNavigation) {
    res.setHeader("Cache-Control", "no-store");
    res.redirect(302, YOUTUBE_URL);
    return;
  }

  const getKeyUrl = "https://link-center.net/10091664/9XJMMJvxrZ9a";

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.status(200).send(luaLoader(getKeyUrl));
}
