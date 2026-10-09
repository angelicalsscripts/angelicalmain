--[[
  LEGAL NOTICE — proprietary loader. Full product is server-delivered after auth.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
-- ============================================================
-- PASTE YOUR NEW WORKER URL HERE (no trailing slash)
-- Example: https://angelical-auth.YOURSUBDOMAIN.workers.dev
-- ============================================================
local AUTH = "https://angelical-auth.bonniebluesbangbus67.workers.dev"
local SESSION_FILE = "angelical_Session.json"

local function spring(obj, t, props)
	local tw = TweenService:Create(obj, TweenInfo.new(t or 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function httpRequest(opts)
	local req = (syn and syn.request)
		or (http and http.request)
		or http_request
		or request
		or (fluxus and fluxus.request)
	if type(req) ~= "function" then
		return nil, "no_http"
	end
	local ok, res = pcall(function()
		return req(opts)
	end)
	if not ok then
		return nil, "http_error"
	end
	return res, nil
end

local function base()
	return AUTH:gsub("/+$", "")
end

local function postJson(path, body, token)
	local headers = {
		["Content-Type"] = "application/json",
		["Accept"] = "application/json",
	}
	if type(token) == "string" and token ~= "" then
		headers["X-Session-Token"] = token
	end
	local url = base() .. path
	local bodyStr = HttpService:JSONEncode(body or {})
	local res, err = httpRequest({
		Url = url,
		url = url,
		Method = "POST",
		method = "POST",
		Headers = headers,
		headers = headers,
		Body = bodyStr,
		body = bodyStr,
	})
	if not res then
		return nil, err or "network"
	end
	local code = tonumber(res.StatusCode or res.Status or res.status_code or 0) or 0
	local raw = tostring(res.Body or res.body or res.data or "")
	-- strip BOM / whitespace
	raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
	if raw == "" then
		return nil, "empty_body:" .. tostring(code)
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(data) ~= "table" then
		local snip = raw:sub(1, 60):gsub("%s+", " ")
		return nil, "bad_json:" .. tostring(code) .. ":" .. snip
	end
	data._status = code
	return data, nil
end

local function fetchBody(token)
	local res, err = httpRequest({
		Url = base() .. "/v1/script/body",
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
			["Accept"] = "text/plain,*/*",
			["X-Session-Token"] = tostring(token),
		},
		Body = HttpService:JSONEncode({
			token = token,
			roblox = tostring(LocalPlayer.Name or ""),
		}),
	})
	if not res then
		return nil, err or "network"
	end
	local code = tonumber(res.StatusCode or res.Status or 0) or 0
	local raw = res.Body or res.body or ""
	if type(raw) ~= "string" then
		return nil, "empty_body"
	end
	if code ~= 200 then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(data) == "table" and data.error then
			return nil, tostring(data.error)
		end
		return nil, "body_http_" .. tostring(code)
	end
	if #raw < 80 then
		return nil, "body_too_small"
	end
	return raw, nil
end

local function hwid()
	local id = ""
	pcall(function()
		local ok, svc = pcall(function()
			return game:GetService("RbxAnalyticsService")
		end)
		if ok and svc and svc.GetClientId then
			id = tostring(svc:GetClientId() or "")
		end
	end)
	if id == "" then
		pcall(function()
			if type(gethwid) == "function" then
				id = tostring(gethwid() or "")
			end
		end)
	end
	if id == "" then
		id = "RBX-" .. tostring(LocalPlayer.UserId) .. "-" .. tostring(game.PlaceId)
	end
	return id
end

local function loadSession()
	if not (readfile and isfile and isfile(SESSION_FILE)) then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(SESSION_FILE))
	end)
	if ok and type(data) == "table" and data.LoggedIn == true and type(data.Token) == "string" then
		return data
	end
	return nil
end

local function saveSession(username, role, token)
	role = tostring(role or "User")
	if role:lower() == "admin" then role = "Admin"
	elseif role:lower() == "user" then role = "User" end
	local payload = {
		LoggedIn = true,
		Username = tostring(username or ""),
		Role = role,
		UserId = tonumber(LocalPlayer.UserId) or 0,
		RobloxName = tostring(LocalPlayer.Name or ""),
		SavedAt = os.time(),
		Token = token,
	}
	pcall(function()
		if writefile then
			writefile(SESSION_FILE, HttpService:JSONEncode(payload))
		end
	end)
	_G.AngelicalSessionToken = token
end

local function doLogin(username, password)
	local hid = hwid()
	local roblox = tostring(LocalPlayer.Name or "")
	local data, err1 = postJson("/v1/login", {
		username = username,
		password = password,
		hwid = hid,
		roblox = roblox,
	})
	if data and data.ok == true and type(data.token) == "string" then
		return data, nil, nil
	end
	local adm, err2 = postJson("/v1/admin-login", {
		username = username,
		password = password,
		hwid = hid,
		roblox = roblox,
	})
	if adm and adm.ok == true and type(adm.token) == "string" then
		return adm, nil, nil
	end
	if type(data) == "table" and data.error then
		return nil, tostring(data.error), data
	end
	if type(adm) == "table" and adm.error then
		return nil, tostring(adm.error), adm
	end
	-- network / non-JSON: show real reason (do not hide as wrong password)
	return nil, tostring(err1 or err2 or "invalid_credentials"), data or adm
end

local function ackWarning(token, warnId)
	if not warnId or not token then return end
	postJson("/v1/user/ack-warning", {
		token = token,
		id = tostring(warnId),
		roblox = tostring(LocalPlayer.Name or ""),
	}, token)
end

local function downloadProduct(token)
	local meta, err = postJson("/v1/script/payload", {
		token = token,
		hwid = hwid(),
		roblox = tostring(LocalPlayer.Name or ""),
	}, token)
	if not meta or meta.ok ~= true then
		return nil, (meta and meta.error) or err or "payload_failed"
	end
	local tok = meta.token or token
	local src, err2 = fetchBody(tok)
	if not src then
		return nil, err2 or "download_failed"
	end
	return {
		token = tok,
		username = meta.username,
		role = meta.role or "user",
		script = src,
		warnings = meta.warnings or {},
	}, nil
end

local function errText(code, extra)
	code = tostring(code or "")
	if code == "banned" then
		local scope = type(extra) == "table" and extra.scope
		local target = type(extra) == "table" and extra.target
		if scope == "roblox" then
			return "Roblox banned (" .. tostring(target or "?") .. ") — /unban roblox:name"
		end
		if scope == "user" then
			return "Username banned (" .. tostring(target or "?") .. ") — /unban username:name"
		end
		return "Banned — /clearbans or /unban"
	end
	if code == "hwid_mismatch" then
		return "HWID locked to another device"
	end
	if code == "invalid_credentials" or code == "invalid_session" then
		return "Wrong username or password (or ADMIN_USER secret not set on worker)"
	end
	if code == "roblox_not_allowed" then
		return "Admin only on carlyywins / carlyyloses"
	end
	if code == "kv_not_bound" then
		return "Worker KV not bound (AUTH_KV)"
	end
	if code == "no_payload" then
		return "Payload URL missing or empty on worker"
	end
	if code == "network" or code == "no_http" or code == "http_error" then
		return "Cannot reach worker — check AUTH URL in loader"
	end
	if tostring(code):find("bad_json", 1, true) then
		return "Bad response from worker. Check AUTH URL. Detail: " .. tostring(code)
	end
	if tostring(code):find("empty_body", 1, true) then
		return "Empty response from worker (HTTP). Check AUTH URL / deploy."
	end
	if code == "no_payload" then
		return "Product missing on server (re-upload)"
	end
	if code == "disabled" then
		return "Product is disabled"
	end
	if code == "no_http" then
		return "Executor HTTP not available"
	end
	if code == "network" or code == "http_error" then
		return "Network error"
	end
	if code == "body_too_small" or code == "download_failed" then
		return "Download failed — redeploy worker"
	end
	if string.find(code, "body_http", 1, true) then
		return "Download error (" .. code .. ")"
	end
	if string.find(code, "bad_json", 1, true) then
		return "Server response error — redeploy worker"
	end
	return code
end

local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
pcall(function()
	local old = pg:FindFirstChild("AngelicalLoaderGui")
	if old then
		old:Destroy()
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "AngelicalLoaderGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.IgnoreGuiInset = true
end)
gui.Parent = pg

local authGroup = Instance.new("Frame")
authGroup.Name = "AuthGroup"
authGroup.Size = UDim2.fromScale(1, 1)
authGroup.BackgroundTransparency = 1
authGroup.Parent = gui

local frost = Instance.new("Frame")
frost.Size = UDim2.fromScale(1, 1)
frost.BackgroundColor3 = Color3.fromRGB(4, 4, 6)
frost.BackgroundTransparency = 1
frost.BorderSizePixel = 0
frost.Parent = authGroup
spring(frost, 0.35, { BackgroundTransparency = 0.15 })

local card = Instance.new("Frame")
card.Name = "AuthCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.52)
card.Size = UDim2.fromOffset(300, 340)
card.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
card.BackgroundTransparency = 1
card.BorderSizePixel = 0
card.ClipsDescendants = true
card.Parent = authGroup
local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 12)
cardCorner.Parent = card
local cardStroke = Instance.new("UIStroke")
cardStroke.Color = Color3.fromRGB(36, 36, 40)
cardStroke.Transparency = 1
cardStroke.Thickness = 1
cardStroke.Parent = card
spring(card, 0.4, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) })
spring(cardStroke, 0.4, { Transparency = 0.25 })

local function fontMedium()
	local f = Enum.Font.GothamMedium
	pcall(function()
		f = Enum.Font.BuilderSansMedium
	end)
	return f
end

local function fontReg()
	local f = Enum.Font.Gotham
	pcall(function()
		f = Enum.Font.BuilderSans
	end)
	return f
end

local authTitle = Instance.new("TextLabel")
authTitle.BackgroundTransparency = 1
authTitle.Position = UDim2.fromOffset(16, 20)
authTitle.Size = UDim2.new(1, -32, 0, 26)
authTitle.Font = fontMedium()
authTitle.Text = "Angelical"
authTitle.TextSize = 20
authTitle.TextColor3 = Color3.fromRGB(245, 245, 248)
authTitle.TextXAlignment = Enum.TextXAlignment.Left
authTitle.Parent = card

local authSubtitle = Instance.new("TextLabel")
authSubtitle.BackgroundTransparency = 1
authSubtitle.Position = UDim2.fromOffset(16, 48)
authSubtitle.Size = UDim2.new(1, -32, 0, 18)
authSubtitle.Font = fontReg()
authSubtitle.Text = "Sign in or create an account"
authSubtitle.TextSize = 13
authSubtitle.TextColor3 = Color3.fromRGB(140, 140, 148)
authSubtitle.TextXAlignment = Enum.TextXAlignment.Left
authSubtitle.Parent = card

local modeToggle = Instance.new("TextButton")
modeToggle.Position = UDim2.fromOffset(16, 78)
modeToggle.Size = UDim2.new(1, -32, 0, 32)
modeToggle.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
modeToggle.BorderSizePixel = 0
modeToggle.Font = fontReg()
modeToggle.Text = "LOGIN  •  SWITCH TO REGISTER"
modeToggle.TextSize = 11
modeToggle.TextColor3 = Color3.fromRGB(155, 157, 161)
modeToggle.AutoButtonColor = false
modeToggle.Parent = card
local modeCorner = Instance.new("UICorner")
modeCorner.CornerRadius = UDim.new(0, 8)
modeCorner.Parent = modeToggle

local function makeBox(y, ph)
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(16, y)
	box.Size = UDim2.new(1, -32, 0, 36)
	box.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	box.BorderSizePixel = 0
	box.Font = fontReg()
	box.PlaceholderText = ph
	box.Text = ""
	box.TextSize = 14
	box.TextColor3 = Color3.fromRGB(240, 240, 245)
	box.PlaceholderColor3 = Color3.fromRGB(110, 110, 118)
	box.ClearTextOnFocus = false
	box.Parent = card
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = box
	return box
end

local userBox = makeBox(120, "Username")
local passBox = makeBox(164, "Password")
local keyBox = makeBox(208, "Product key")
keyBox.Visible = false

local authStatus = Instance.new("TextLabel")
authStatus.BackgroundTransparency = 1
authStatus.Position = UDim2.fromOffset(16, 214)
authStatus.Size = UDim2.new(1, -32, 0, 28)
authStatus.Font = fontReg()
authStatus.Text = ""
authStatus.TextSize = 12
authStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
authStatus.TextXAlignment = Enum.TextXAlignment.Left
authStatus.TextWrapped = true
authStatus.Parent = card

local authSubmit = Instance.new("TextButton")
authSubmit.Position = UDim2.fromOffset(16, 256)
authSubmit.Size = UDim2.new(1, -32, 0, 40)
authSubmit.BackgroundColor3 = Color3.fromRGB(245, 245, 248)
authSubmit.BorderSizePixel = 0
authSubmit.Font = fontMedium()
authSubmit.Text = "Continue"
authSubmit.TextSize = 14
authSubmit.TextColor3 = Color3.fromRGB(16, 16, 18)
authSubmit.AutoButtonColor = false
authSubmit.Parent = card
local subCorner = Instance.new("UICorner")
subCorner.CornerRadius = UDim.new(0, 8)
subCorner.Parent = authSubmit

authSubmit.MouseEnter:Connect(function()
	spring(authSubmit, 0.12, { BackgroundColor3 = Color3.fromRGB(228, 228, 232) })
end)
authSubmit.MouseLeave:Connect(function()
	spring(authSubmit, 0.12, { BackgroundColor3 = Color3.fromRGB(245, 245, 248) })
end)

local isRegister = false
local function layout()
	if isRegister then
		modeToggle.Text = "REGISTER  •  SWITCH TO LOGIN"
		authSubtitle.Text = "New account + product key"
		authSubmit.Text = "Create account"
		keyBox.Visible = true
		authStatus.Position = UDim2.fromOffset(16, 256)
		authSubmit.Position = UDim2.fromOffset(16, 300)
		spring(card, 0.2, { Size = UDim2.fromOffset(300, 400) })
	else
		modeToggle.Text = "LOGIN  •  SWITCH TO REGISTER"
		authSubtitle.Text = "Sign in or create an account"
		authSubmit.Text = "Continue"
		keyBox.Visible = false
		authStatus.Position = UDim2.fromOffset(16, 214)
		authSubmit.Position = UDim2.fromOffset(16, 256)
		spring(card, 0.2, { Size = UDim2.fromOffset(300, 340) })
	end
end
layout()

modeToggle.MouseButton1Click:Connect(function()
	isRegister = not isRegister
	authStatus.Text = ""
	layout()
end)

local function setStatus(msg, ok)
	authStatus.Text = tostring(msg or "")
	if ok then
		authStatus.TextColor3 = Color3.fromRGB(120, 200, 140)
	else
		authStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
	end
end

local function showWarnsThenRun(result)
	local warns = result.warnings or {}
	local function run()
		local fn, err = loadstring(result.script)
		if not fn then
			setStatus("Load error: " .. tostring(err), false)
			return
		end
		pcall(function()
			gui:Destroy()
		end)
		fn()
	end
	if #warns == 0 then
		run()
		return
	end
	local idx = 1
	local layer = Instance.new("Frame")
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	layer.BackgroundTransparency = 0.45
	layer.Parent = gui
	local c = Instance.new("Frame")
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.Size = UDim2.fromOffset(300, 160)
	c.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
	c.Parent = layer
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 12)
	cc.Parent = c
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Position = UDim2.fromOffset(16, 16)
	tl.Size = UDim2.new(1, -32, 0, 24)
	tl.Font = fontMedium()
	tl.Text = "Warning"
	tl.TextSize = 16
	tl.TextColor3 = Color3.fromRGB(245, 245, 248)
	tl.TextXAlignment = Enum.TextXAlignment.Left
	tl.Parent = c
	local bd = Instance.new("TextLabel")
	bd.BackgroundTransparency = 1
	bd.Position = UDim2.fromOffset(16, 48)
	bd.Size = UDim2.new(1, -32, 0, 50)
	bd.Font = fontReg()
	bd.TextSize = 13
	bd.TextColor3 = Color3.fromRGB(170, 170, 178)
	bd.TextXAlignment = Enum.TextXAlignment.Left
	bd.TextWrapped = true
	bd.Parent = c
	local okb = Instance.new("TextButton")
	okb.Position = UDim2.fromOffset(16, 110)
	okb.Size = UDim2.new(1, -32, 0, 36)
	okb.BackgroundColor3 = Color3.fromRGB(245, 245, 248)
	okb.Font = fontMedium()
	okb.Text = "OK"
	okb.TextSize = 13
	okb.TextColor3 = Color3.fromRGB(16, 16, 18)
	okb.Parent = c
	local oc = Instance.new("UICorner")
	oc.CornerRadius = UDim.new(0, 8)
	oc.Parent = okb
	local function show()
		if idx > #warns then
			layer:Destroy()
			run()
			return
		end
		local w = warns[idx]
		bd.Text = tostring((type(w) == "table" and w.message) or w)
		idx = idx + 1
	end
	okb.MouseButton1Click:Connect(function()
		local prev = warns[idx - 1]
		if type(prev) == "table" and prev.id then
			pcall(function()
				ackWarning(result.token, prev.id)
			end)
		end
		show()
	end)
	show()
end

local busy = false
authSubmit.MouseButton1Click:Connect(function()
	if busy then
		return
	end
	local u = userBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	local p = passBox.Text
	local k = keyBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if u == "" or p == "" then
		setStatus("Enter username and password", false)
		return
	end
	if isRegister and k == "" then
		setStatus("Enter your product key", false)
		return
	end
	busy = true
	authSubmit.Text = "..."
	coroutine.wrap(function()
		if isRegister then
			setStatus("Registering...", true)
			local reg = postJson("/v1/register", {
				username = u,
				password = p,
				key = k,
				hwid = hwid(),
				roblox = tostring(LocalPlayer.Name or ""),
			})
			if not reg or reg.ok ~= true then
				setStatus(errText(reg and reg.error or "register_failed", reg), false)
				busy = false
				layout()
				return
			end
		end

		setStatus("Logging in...", true)
		local login, lerr, ldata = doLogin(u, p)
		if not login then
			setStatus(errText(lerr, ldata), false)
			busy = false
			layout()
			return
		end

		setStatus("Downloading...", true)
		local product, perr = downloadProduct(login.token)
		if not product then
			setStatus(errText(perr), false)
			busy = false
			layout()
			return
		end

		saveSession(product.username or u, product.role or login.role or "User", product.token)
		setStatus("Starting...", true)
		showWarnsThenRun(product)
	end)()
end)

coroutine.wrap(function()
	local sess = loadSession()
	if not sess then
		return
	end
	setStatus("Restoring session...", true)
	local product = downloadProduct(sess.Token)
	if product then
		saveSession(product.username or sess.Username, product.role or sess.Role, product.token)
		showWarnsThenRun(product)
	else
		setStatus("", false)
	end
end)()
