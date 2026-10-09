-- <w> : by wleo : yoruka.id
-- by hermawan script vd
-- LocalScript → StarterPlayer > StarterPlayerScripts  (khusus game VD buatan sendiri, tanpa key)
--
-- CARA BACA FILE INI (untuk belajar LocalScript):
--  1. LocalScript jalan di komputer/HP pemain saja → dia bisa baca & ubah tampilan, kamera, GUI, karakter sendiri.
--  2. Server tidak tahu apa yang diubah LocalScript. Makanya semua fitur "kekuatan" di sini hanya efek lokal.
--  3. Game asli harus tetap divalidasi di Script server (kecepatan, teleport, damage). Script ini cocok untuk
--     menguji & memahami alur game, sekaligus melihat celah apa yang bisa dipakai pemain nakal.

------------------------------------------------------------------------
-- BAGIAN 1 — KONFIGURASI (sesuaikan dengan nama objek/team di game kamu)
------------------------------------------------------------------------
local CFG = {
	-- Objek dicari lewat CollectionService Tag dulu; kalau kosong, dicari berdasarkan potongan nama.
	GeneratorTag = "Generator", GeneratorNames = {"generator"},
	GateTag = "Gate", GateNames = {"gate"},
	HookTag = "Hook", HookNames = {"hook"},
	PalletTag = "Pallet", PalletNames = {"pallet"},
	WindowTag = "Window", WindowNames = {"window", "vault"},

	-- Cara mengenali killer: nama Team, ATAU Attribute "Role" di Player/Character.
	KillerTeamName = "Killer",
	RoleAttribute = "Role",
	RoleKillerValue = "Killer",

	ProgressAttribute = "Progress", -- Attribute progress generator di Model-nya (0-100)

	-- Status teman (untuk ESP teman sekarat / di-hook). Isi sesuai game kamu:
	StateAttribute = "State",                      -- Attribute string di Player/Character, mis. "Downed"
	DownedValues = {"downed", "knocked", "dying", "crawling"},
	HookedValues = {"hooked", "hook"},
	DownedBoolAttr = "Downed", HookedBoolAttr = "Hooked", -- atau Attribute boolean
	-- Kalau tidak ada Attribute sama sekali, HP <= 25% dianggap "KRITIS".

	-- LOBBY: pemain di lobby TIDAK kena ESP / aim / HUD. Cukup salah satu cara ini terisi di game kamu:
	InLobbyAttr = "InLobby",    -- Attribute boolean di Player/Character: true = sedang di lobby
	InGameAttr = "InGame",      -- Attribute boolean: false = sedang di lobby
	LobbyTeamNames = {"lobby", "spectator", "waiting"}, -- nama Team lobby (huruf kecil)
	LobbyZoneTag = "LobbyZone", -- Tag Part area lobby (atau beri nama part "LobbyZone")
	LobbyZoneNames = {"lobbyzone", "lobby_zone", "lobbyarea"},
	LobbyZoneHeight = 80,       -- tinggi area lobby di atas part (studs)
	TerrorRadius = 48,              -- jarak (studs) killer dianggap "dekat"
}

------------------------------------------------------------------------
-- BAGIAN 2 — SERVICE & FUNGSI BANTU
------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Stats = game:GetService("Stats")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer -- pemain yang menjalankan script ini
local cam = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() cam = workspace.CurrentCamera end)

local old = player:WaitForChild("PlayerGui"):FindFirstChild("VDHermawan")
if old then old:Destroy() end

local BG, CARD, CARD2 = Color3.fromRGB(15, 14, 19), Color3.fromRGB(27, 25, 34), Color3.fromRGB(44, 40, 54)
local ACC, TXT, SUB = Color3.fromRGB(228, 62, 72), Color3.fromRGB(240, 238, 244), Color3.fromRGB(150, 145, 168)
local RED, CYAN, GOLD = Color3.fromRGB(255, 70, 80), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 200, 70)

-- mk = bikin Instance + isi properti sekaligus (biar kode pendek)
local function mk(class, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	return o
end
local function round(o, r) mk("UICorner", {CornerRadius = UDim.new(0, r or 8), Parent = o}) end
local function getChar() return player.Character end
local function getRoot() local c = player.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = player.Character return c and c:FindFirstChildOfClass("Humanoid") end

local S = {} -- status semua toggle: S.nama = true/false

local gui = mk("ScreenGui", {Name = "VDHermawan", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 900, Parent = player.PlayerGui})

-- toast kecil di bawah layar
local function notify(text)
	local f = mk("TextLabel", {
		Size = UDim2.fromOffset(240, 28), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24),
		BackgroundColor3 = CARD, TextColor3 = TXT, Font = Enum.Font.GothamMedium, TextSize = 12, Text = text, Parent = gui,
	})
	round(f, 8)
	mk("UIStroke", {Color = ACC, Thickness = 1, Parent = f})
	task.delay(2, function()
		TweenService:Create(f, TweenInfo.new(0.3), {BackgroundTransparency = 1, TextTransparency = 1}):Play()
		task.wait(0.35)
		f:Destroy()
	end)
end

------------------------------------------------------------------------
-- BAGIAN 3 — DATA OBJEK GAME (generator, gate, hook, pallet, window)
------------------------------------------------------------------------
local KINDS = {
	{key = "gen", label = "GEN", color = GOLD, tag = CFG.GeneratorTag, names = CFG.GeneratorNames, main = true},
	{key = "gate", label = "GATE", color = CYAN, tag = CFG.GateTag, names = CFG.GateNames, main = true},
	{key = "hook", label = "HOOK", color = RED, tag = CFG.HookTag, names = CFG.HookNames, main = true},
	{key = "pallet", label = "PALLET", color = Color3.fromRGB(200, 160, 110), tag = CFG.PalletTag, names = CFG.PalletNames, main = false},
	{key = "window", label = "WINDOW", color = Color3.fromRGB(170, 130, 255), tag = CFG.WindowTag, names = CFG.WindowNames, main = false},
}
local lists = {gen = {}, gate = {}, hook = {}, pallet = {}, window = {}}

local function nameMatches(inst, names)
	local n = inst.Name:lower()
	for _, p in ipairs(names) do
		if n:find(p, 1, true) then return true end
	end
	return false
end
local function collect(tag, names)
	local tagged = CollectionService:GetTagged(tag)
	if #tagged > 0 then return tagged end
	local out = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and nameMatches(d, names) then
			local par = d.Parent
			-- lewati part yang induknya (Model) sudah cocok, biar tidak dobel
			if not (par and par:IsA("Model") and nameMatches(par, names)) then table.insert(out, d) end
		end
	end
	return out
end
local function refreshLists()
	for _, k in ipairs(KINDS) do lists[k.key] = collect(k.tag, k.names) end
end
local function anchorPart(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
end
local function posOf(inst)
	if inst:IsA("Model") then return inst:GetPivot().Position end
	return inst.Position
end
-- Deteksi peran otomatis (Team / Attribute). Kalau game kamu beda, pakai override manual di tab Aim.
local roleOverride = nil   -- nil = otomatis, "Killer"/"Survivor" = paksa peran SAYA
local manualKillers = {}   -- pemain yang ditandai manual sebagai killer
local function isKillerAuto(p)
	if p.Team and p.Team.Name == CFG.KillerTeamName then return true end
	if p:GetAttribute(CFG.RoleAttribute) == CFG.RoleKillerValue then return true end
	local c = p.Character
	return c ~= nil and c:GetAttribute(CFG.RoleAttribute) == CFG.RoleKillerValue
end
local function isKiller(p)
	if p == player and roleOverride then return roleOverride == "Killer" end
	if manualKillers[p] then return true end
	return isKillerAuto(p)
end
-- hidup = punya HumanoidRootPart; Humanoid boleh tidak ada (killer custom rig) tapi kalau ada HP harus > 0
local function alive(p)
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return r ~= nil and (h == nil or h.Health > 0)
end
-- status teman: "OK" / "KRITIS" / "DOWN" (sekarat) / "HOOK" (digantung)
local function statusOf(p)
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local function attr(n)
		local v = p:GetAttribute(n)
		if v == nil and c then v = c:GetAttribute(n) end
		return v
	end
	local st = attr(CFG.StateAttribute)
	st = st and tostring(st):lower() or nil
	local function inList(list)
		for _, x in ipairs(list) do
			if st == x then return true end
		end
		return false
	end
	if attr(CFG.HookedBoolAttr) == true or (st and inList(CFG.HookedValues)) then return "HOOK" end
	if attr(CFG.DownedBoolAttr) == true or (st and inList(CFG.DownedValues)) then return "DOWN" end
	if h and h.MaxHealth > 0 and h.Health / h.MaxHealth <= 0.25 then return "KRITIS" end
	return "OK"
end
local STATUS_COL = {
	OK = Color3.fromRGB(90, 255, 150), KRITIS = Color3.fromRGB(255, 190, 60),
	DOWN = Color3.fromRGB(255, 120, 40), HOOK = Color3.fromRGB(255, 70, 210),
}
-- ===== DETEKSI LOBBY =====
-- Konsep: pemain dianggap "di lobby" kalau Attribute/Team/zona lobby cocok. Hasilnya dipakai ESP, aim, dan HUD
-- lewat inMatch(p) → pemain lobby otomatis dilewati. lobbyMe = apakah SAYA sendiri sedang di lobby.
local lobbyMe = false
local lobbyZones, lobbyCache = {}, {}
local function refreshLobbyZones()
	lobbyZones = CollectionService:GetTagged(CFG.LobbyZoneTag)
	if #lobbyZones == 0 then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and nameMatches(d, CFG.LobbyZoneNames) then table.insert(lobbyZones, d) end
		end
	end
	lobbyCache = {}
end
local baseRefresh = refreshLists
refreshLists = function() baseRefresh() refreshLobbyZones() end
local function inZone(part, pos)
	local lp = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Z) <= h.Z and lp.Y >= -h.Y - 10 and lp.Y <= h.Y + CFG.LobbyZoneHeight
end
local function inLobby(p)
	local now = tick()
	local cached = lobbyCache[p]
	if cached and now - cached[2] < 0.3 then return cached[1] end
	local c = p.Character
	local function attr(n)
		local v = p:GetAttribute(n)
		if v == nil and c then v = c:GetAttribute(n) end
		return v
	end
	local res = false
	local st = attr(CFG.StateAttribute)
	if attr(CFG.InLobbyAttr) == true or attr(CFG.InGameAttr) == false then
		res = true
	elseif st ~= nil and tostring(st):lower() == "lobby" then
		res = true
	elseif p.Team then
		local tn = p.Team.Name:lower()
		for _, n in ipairs(CFG.LobbyTeamNames) do
			if tn == n then res = true end
		end
	end
	if not res and c then
		local r = c:FindFirstChild("HumanoidRootPart")
		if r then
			for _, z in ipairs(lobbyZones) do
				if z.Parent and inZone(z, r.Position) then res = true break end
			end
		end
	end
	lobbyCache[p] = {res, now}
	return res
end
-- hidup DAN sedang di dalam match (bukan lobby)
local function inMatch(p)
	return alive(p) and not (S.lobbyFilter and inLobby(p))
end

-- cari pemain lain terdekat yang lolos filter (lobby dilewati)
local function nearestPlayer(filter)
	local root = getRoot()
	if not root then return end
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and inMatch(p) and filter(p) then
			local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
			if not bd or d < bd then best, bd = p, d end
		end
	end
	return best, bd
end
local function nearestObject(key)
	local root = getRoot()
	if not root then return end
	local best, bd
	for _, inst in ipairs(lists[key]) do
		if inst.Parent then
			local d = (posOf(inst) - root.Position).Magnitude
			if not bd or d < bd then best, bd = inst, d end
		end
	end
	return best, bd
end
local function tpTo(pos)
	local r = getRoot()
	if r then
		r.AssemblyLinearVelocity = Vector3.zero
		r.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
	end
end

------------------------------------------------------------------------
-- BAGIAN 4 — KERANGKA MENU (panel, tombol "-" dan "x", tab, komponen)
------------------------------------------------------------------------
local panel = mk("Frame", {
	Name = "Panel", Size = UDim2.fromOffset(340, 440), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = BG, ClipsDescendants = true, Parent = gui,
})
round(panel, 12)
mk("UIStroke", {Color = ACC, Thickness = 1.5, Transparency = 0.15, Parent = panel})
mk("UIScale", {Scale = math.clamp(gui.AbsoluteSize.X / 460, 0.7, 1), Parent = panel})

local header = mk("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = CARD, BorderSizePixel = 0, Parent = panel})
mk("UIGradient", {Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 190)), Parent = header})
mk("TextLabel", {
	Size = UDim2.new(1, -90, 0, 22), Position = UDim2.fromOffset(12, 4), BackgroundTransparency = 1, Text = "VD SCRIPT",
	TextColor3 = TXT, Font = Enum.Font.GothamBlack, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
})
mk("TextLabel", {
	Size = UDim2.new(1, -90, 0, 14), Position = UDim2.fromOffset(12, 26), BackgroundTransparency = 1, Text = "by hermawan script vd",
	TextColor3 = ACC, Font = Enum.Font.GothamMedium, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
})
local function headBtn(txt, x, col)
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, x, 0, 8), BackgroundColor3 = CARD2, Text = txt, TextColor3 = TXT,
		Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false, Parent = header,
	})
	round(b, 7)
	b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = col}):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = CARD2}):Play() end)
	return b
end
local btnClose = headBtn("x", -36, ACC)
local btnMin = headBtn("-", -70, Color3.fromRGB(70, 120, 255))

-- geser panel lewat header (mouse & sentuh)
do
	local dragging, startM, startP = false, Vector2.zero, panel.Position
	header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, startM, startP = true, Vector2.new(i.Position.X, i.Position.Y), panel.Position
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = Vector2.new(i.Position.X, i.Position.Y) - startM
			panel.Position = UDim2.new(startP.X.Scale, startP.X.Offset + d.X, startP.Y.Scale, startP.Y.Offset + d.Y)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

local tabBar = mk("ScrollingFrame", {
	Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, 50), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), Parent = panel,
})
mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = tabBar})
local content = mk("Frame", {Size = UDim2.new(1, -12, 1, -90), Position = UDim2.fromOffset(6, 84), BackgroundTransparency = 1, Parent = panel})

local pages, tabBtns = {}, {}
local function selectTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabBtns) do
		local on = n == name
		TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = on and ACC or CARD, TextColor3 = on and Color3.new(1, 1, 1) or SUB}):Play()
	end
end
local function newTab(name)
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(74, 28), BackgroundColor3 = CARD, Text = name, TextColor3 = SUB, Font = Enum.Font.GothamBold,
		TextSize = 12, AutoButtonColor = false, Parent = tabBar,
	})
	round(b, 8)
	local pg = mk("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = ACC,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false, Parent = content,
	})
	mk("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pg})
	mk("UIPadding", {PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), Parent = pg})
	pages[name], tabBtns[name] = pg, b
	b.MouseButton1Click:Connect(function() selectTab(name) end)
	return pg
end

-- komponen UI
local function section(parent, text)
	mk("TextLabel", {Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = text:upper(), TextColor3 = SUB,
		Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = parent})
end
local function label(parent, text)
	local l = mk("TextLabel", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = CARD, Text = "  " .. text, TextColor3 = TXT,
		Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent})
	round(l, 8)
	return l
end
local function button(parent, text, cb)
	local b = mk("TextButton", {Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = CARD, Text = text, TextColor3 = TXT,
		Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false, Parent = parent})
	round(b, 8)
	b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = CARD2}):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = CARD}):Play() end)
	if cb then b.MouseButton1Click:Connect(function() cb(b) end) end
	return b
end
-- toggle: klik → on/off, memanggil cb(nilaiBaru). Mengembalikan fungsi setter.
local function toggle(parent, text, key, cb)
	S[key] = false
	local b = button(parent, text)
	local function paint()
		b.Text = (S[key] and "●  " or "○  ") .. text
		b.TextColor3 = S[key] and ACC or TXT
	end
	local function set(v)
		S[key] = v
		paint()
		local ok, err = pcall(cb or function() end, v)
		if not ok then warn("[vd] " .. key .. ": " .. tostring(err)) end
	end
	b.MouseButton1Click:Connect(function() set(not S[key]) end)
	paint()
	return set
end
local function slider(parent, text, min, max, def, cb)
	local f = mk("Frame", {Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = CARD, Parent = parent})
	round(f, 8)
	local lbl = mk("TextLabel", {Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 3), BackgroundTransparency = 1,
		Text = text .. ": " .. def, TextColor3 = TXT, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = f})
	local bar = mk("TextButton", {Size = UDim2.new(1, -16, 0, 8), Position = UDim2.new(0, 8, 1, -17), BackgroundColor3 = CARD2, Text = "", AutoButtonColor = false, Parent = f})
	round(bar, 4)
	local fill = mk("Frame", {Size = UDim2.new((def - min) / (max - min), 0, 1, 0), BackgroundColor3 = ACC, Parent = bar})
	round(fill, 4)
	local dragging = false
	local function upd(x)
		local r = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		local v = math.floor(min + (max - min) * r + 0.5)
		fill.Size = UDim2.new(r, 0, 1, 0)
		lbl.Text = text .. ": " .. v
		cb(v)
	end
	bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true upd(i.Position.X) end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then upd(i.Position.X) end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

-- tombol "x" = sembunyikan ke bubble "VD"; tombol "-" = lipat/buka isi panel
local bubble = mk("TextButton", {
	Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 10, 0.4, 0), BackgroundColor3 = CARD, Text = "VD", TextColor3 = ACC,
	Font = Enum.Font.GothamBlack, TextSize = 16, Visible = false, Parent = gui,
})
round(bubble, 23)
mk("UIStroke", {Color = ACC, Thickness = 1.5, Parent = bubble})
local minimized = false
btnClose.MouseButton1Click:Connect(function() panel.Visible = false bubble.Visible = true end)
bubble.MouseButton1Click:Connect(function() panel.Visible = true bubble.Visible = false end)
btnMin.MouseButton1Click:Connect(function()
	minimized = not minimized
	btnMin.Text = minimized and "+" or "-"
	TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {Size = UDim2.fromOffset(340, minimized and 44 or 440)}):Play()
end)

------------------------------------------------------------------------
-- BAGIAN 5 — ESP OBJEKTIF (label generator/gate/hook/pallet/window)
-- Konsep: BillboardGui menempel di Part → teks selalu menghadap layar & tembus tembok (AlwaysOnTop).
------------------------------------------------------------------------
local objTags = {}
local function clearObjTags()
	for _, t in ipairs(objTags) do t.bb:Destroy() end
	objTags = {}
end
local function buildObjTags()
	clearObjTags()
	for _, k in ipairs(KINDS) do
		local show = (k.main and S.objMain) or (not k.main and S.objExtra)
		if show then
			for i, inst in ipairs(lists[k.key]) do
				local a = anchorPart(inst)
				if a then
					local bb = mk("BillboardGui", {Size = UDim2.fromOffset(110, 34), AlwaysOnTop = true, StudsOffset = Vector3.new(0, 3, 0), Adornee = a, Parent = gui})
					local l = mk("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextColor3 = k.color, Font = Enum.Font.GothamBold,
						TextSize = 12, TextStrokeTransparency = 0.4, Text = k.label, Parent = bb})
					table.insert(objTags, {inst = inst, name = k.label .. " " .. i, label = l, bb = bb})
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- BAGIAN 6 — ESP PEMAIN (Highlight = siluet tembus tembok)
------------------------------------------------------------------------
local pTags = {}
local function clearPlayerTag(p)
	local t = pTags[p]
	if t then t.hl:Destroy() t.bb:Destroy() pTags[p] = nil end
end
local function syncPlayerTags()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local ch = p.Character
			local k = isKiller(p)
			local want = ch ~= nil and not lobbyMe and inMatch(p) and ((k and S.espKiller) or (not k and (S.espSurv or S.espTeam)))
			local t = pTags[p]
			if want then
				if t and t.char ~= ch then clearPlayerTag(p) t = nil end
				if not t then
					local hl = mk("Highlight", {Adornee = ch, FillTransparency = 0.6, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = gui})
					local head = ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
					local bb = mk("BillboardGui", {Size = UDim2.fromOffset(130, 30), AlwaysOnTop = true, StudsOffset = Vector3.new(0, 3, 0), Adornee = head, Parent = gui})
					local l = mk("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
						TextStrokeTransparency = 0.4, Text = p.DisplayName, Parent = bb})
					t = {hl = hl, bb = bb, lbl = l, char = ch}
					pTags[p] = t
				end
				local col = k and RED or STATUS_COL[statusOf(p)]
				t.hl.FillColor, t.hl.OutlineColor, t.lbl.TextColor3 = col, col, col
			elseif t then
				clearPlayerTag(p)
			end
		end
	end
	for p in pairs(pTags) do
		if not p.Parent then clearPlayerTag(p) end
	end
end

------------------------------------------------------------------------
-- BAGIAN 7 — AIM ASSIST (kamera mengunci target)
-- Konsep: WorldToViewportPoint mengubah posisi 3D → posisi layar 2D. Target dipilih yang paling dekat
-- dengan tengah layar (di dalam lingkaran FOV), lalu kamera diputar pakai CFrame.lookAt + Lerp.
-- smooth = 100 → kamera langsung "snap" ke target (brutal). Makin kecil makin halus.
------------------------------------------------------------------------
local aim = {fov = 220, smooth = 100, part = "Head", wall = false, predict = true, rmb = false, mode = "Lawan", autofire = false}
local circle = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(aim.fov * 2, aim.fov * 2),
	BackgroundTransparency = 1, Visible = false, ZIndex = 0, Parent = gui,
})
round(circle, 999)
mk("UIStroke", {Color = ACC, Thickness = 1.5, Transparency = 0.3, Parent = circle})

-- "+" merah = penanda target yang sedang dikunci (mengikuti posisi target di layar)
local reticle = mk("TextLabel", {
	Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Text = "+", TextColor3 = RED,
	Font = Enum.Font.GothamBlack, TextSize = 40, TextStrokeTransparency = 0.2, Visible = false, ZIndex = 10, Parent = gui,
})
-- "+" putih = crosshair tetap di tengah layar (opsional)
local centerCross = mk("TextLabel", {
	Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
	Text = "+", TextColor3 = TXT, Font = Enum.Font.GothamBold, TextSize = 26, TextStrokeTransparency = 0.3, Visible = false, ZIndex = 10, Parent = gui,
})

local function wantTarget(p)
	if aim.mode == "Semua" then return true end
	if aim.mode == "Killer" then return isKiller(p) end
	if aim.mode == "Survivor" then return not isKiller(p) end
	return isKiller(player) ~= isKiller(p) -- "Lawan": killer → bidik survivor, survivor → bidik killer
end
local function clearLine(part)
	if not player.Character then return true end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {player.Character, part.Parent}
	local o = cam.CFrame.Position
	return workspace:Raycast(o, part.Position - o, rp) == nil
end
-- mengembalikan bagian tubuh target + jarak pikselnya ke tengah layar
local function bestTarget()
	local vs = cam.ViewportSize
	local center = Vector2.new(vs.X / 2, vs.Y / 2)
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and wantTarget(p) and inMatch(p) then
			local ch = p.Character
			local part = ch:FindFirstChild(aim.part) or ch:FindFirstChild("HumanoidRootPart")
			local sp, onScreen = cam:WorldToViewportPoint(part.Position)
			if onScreen then
				local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
				if d <= aim.fov and (not bd or d < bd) and (not aim.wall or clearLine(part)) then best, bd = part, d end
			end
		end
	end
	return best, bd
end
local lastFire = 0
RunService:BindToRenderStep("VDAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local t
	if S.aim and not lobbyMe then t = bestTarget() end
	if not t then
		reticle.Visible = false
		return
	end
	local sp = cam:WorldToViewportPoint(t.Position)
	reticle.Position = UDim2.fromOffset(sp.X, sp.Y)
	reticle.Visible = true
	if aim.rmb and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
	local pos = t.Position
	if aim.predict then pos += t.AssemblyLinearVelocity * 0.07 end -- bidik sedikit ke depan arah gerak target
	local goal = CFrame.lookAt(cam.CFrame.Position, pos)
	cam.CFrame = (aim.smooth >= 100) and goal or cam.CFrame:Lerp(goal, math.clamp(aim.smooth / 100, 0.03, 1))
	-- auto fire: kalau target sudah tepat di tengah, aktifkan Tool yang sedang dipegang
	if aim.autofire and tick() - lastFire > 0.15 then
		local sp2 = cam:WorldToViewportPoint(t.Position)
		local vs = cam.ViewportSize
		if (Vector2.new(sp2.X, sp2.Y) - Vector2.new(vs.X / 2, vs.Y / 2)).Magnitude < 40 then
			local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
			if tool then tool:Activate() lastFire = tick() end
		end
	end
end)

------------------------------------------------------------------------
-- BAGIAN 8 — GERAKAN (speed, jump, fly, noclip, infinite jump)
------------------------------------------------------------------------
local cfgv = {speed = nil, jump = nil, flySpeed = 70}
local flyBV, flyBG
local setFly -- diisi nanti saat toggle Fly dibuat
local function stopFly()
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	local h = getHum()
	if h then h.PlatformStand = false end
end
local function startFly()
	local r, h = getRoot(), getHum()
	if not (r and h) then return false end
	stopFly()
	flyBV = mk("BodyVelocity", {MaxForce = Vector3.new(1e9, 1e9, 1e9), Velocity = Vector3.zero, Parent = r})
	flyBG = mk("BodyGyro", {MaxTorque = Vector3.new(1e9, 1e9, 1e9), P = 9e4, Parent = r})
	h.PlatformStand = true
	return true
end

local promptOrig = {}
local function setInstantPrompts(on)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			if on then
				if promptOrig[d] == nil then promptOrig[d] = d.HoldDuration end
				d.HoldDuration = 0
			elseif promptOrig[d] ~= nil then
				d.HoldDuration = promptOrig[d]
			end
		end
	end
end
workspace.DescendantAdded:Connect(function(d)
	if S.instant and d:IsA("ProximityPrompt") then
		promptOrig[d] = d.HoldDuration
		d.HoldDuration = 0
	end
end)

UIS.JumpRequest:Connect(function()
	if S.infjump then
		local h = getHum()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)
RunService.Stepped:Connect(function()
	if S.noclip and player.Character then
		for _, p in ipairs(player.Character:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end
end)
player.Idled:Connect(function()
	if S.antiafk then
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end
end)
player.CharacterAdded:Connect(function(char)
	flyBV, flyBG = nil, nil
	local h = char:WaitForChild("Humanoid", 10)
	char:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.4)
	if S.fly and setFly then setFly(false) end
	if h then
		if cfgv.speed then h.WalkSpeed = cfgv.speed end
		if cfgv.jump then h.UseJumpPower = true h.JumpPower = cfgv.jump end
	end
end)

------------------------------------------------------------------------
-- BAGIAN 9 — LOOP UTAMA (Heartbeat = jalan tiap frame)
-- Pola penting: jangan kerjakan hal berat tiap frame; yang berat dijalankan tiap 0.25 detik (akumulator "acc").
------------------------------------------------------------------------
local warnFrame = mk("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 20, 30), BackgroundTransparency = 1, ZIndex = 0, Visible = false, Parent = gui})
local warnLbl = mk("TextLabel", {Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromScale(0, 0.12), BackgroundTransparency = 1, Text = "",
	TextColor3 = Color3.fromRGB(255, 90, 90), Font = Enum.Font.GothamBlack, TextSize = 20, TextStrokeTransparency = 0.3, Visible = false, Parent = gui})
local objLbl = mk("TextLabel", {Size = UDim2.fromOffset(240, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
	BackgroundColor3 = BG, BackgroundTransparency = 0.25, TextColor3 = GOLD, Font = Enum.Font.GothamBold, TextSize = 13, Text = "", Visible = false, Parent = gui})
round(objLbl, 8)
local function hudLabel(y, col)
	local l = mk("TextLabel", {Size = UDim2.fromOffset(250, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y),
		BackgroundColor3 = BG, BackgroundTransparency = 0.25, TextColor3 = col, Font = Enum.Font.GothamBold, TextSize = 13, Text = "", Visible = false, Parent = gui})
	round(l, 8)
	return l
end
local allyLbl = hudLabel(38, STATUS_COL.DOWN)
local killerLbl = hudLabel(68, RED)
local huntLbl = hudLabel(98, CYAN)
local genLbl = hudLabel(128, GOLD)
-- state fitur Player / Killer
local pl = {sel = nil, mode = nil, ang = 0, dist = 6, spinSpeed = 8, atkRange = 12, lastAtk = 0, genDone = -1, noFxOff = {}}

-- papan status live: semua pemain yang sedang main (lobby disembunyikan)
local scoreFrame = mk("Frame", {
	Size = UDim2.fromOffset(240, 0), AutomaticSize = Enum.AutomaticSize.Y, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 64),
	BackgroundColor3 = BG, BackgroundTransparency = 0.3, Visible = false, Parent = gui,
})
round(scoreFrame, 8)
mk("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scoreFrame})
mk("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = scoreFrame})
local function refreshScore()
	for _, c in ipairs(scoreFrame:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	scoreFrame.Visible = (S.score or S.scoreS) and not lobbyMe or false
	if not scoreFrame.Visible then return end
	local root = getRoot()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and inMatch(p) then
			n += 1
			local k = isKiller(p)
			local st = k and "KILLER" or statusOf(p)
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			local d = root and (p.Character.HumanoidRootPart.Position - root.Position).Magnitude or 0
			mk("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = n, TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = k and RED or STATUS_COL[st], TextStrokeTransparency = 0.6,
				Text = string.format("%s  [%s]  %dHP  %dm", p.DisplayName, st, math.floor(h and h.Health or 0), math.floor(d)), Parent = scoreFrame,
			})
		end
	end
	if n == 0 then scoreFrame.Visible = false end
end

local ARROWS = {"↑", "↗", "→", "↘", "↓", "↙", "←", "↖"}
local function arrowTo(vec)
	local look, rt = cam.CFrame.LookVector, cam.CFrame.RightVector
	local f = Vector3.new(look.X, 0, look.Z)
	local r = Vector3.new(rt.X, 0, rt.Z)
	local v = Vector3.new(vec.X, 0, vec.Z)
	if f.Magnitude < 0.01 or v.Magnitude < 0.1 then return "●" end
	f, r, v = f.Unit, r.Unit, v.Unit
	local ang = math.deg(math.atan2(v:Dot(r), v:Dot(f)))
	return ARROWS[math.floor(((ang + 360 + 22.5) % 360) / 45) + 1]
end

local acc, infoAcc = 0, 0
local lastStatus = {}
local infoFps, infoPing, infoRole
RunService.Heartbeat:Connect(function(dt)
	local root, hum = getRoot(), getHum()
	if not (root and hum) then return end
	local now = tick()
	lobbyMe = (S.lobbyFilter and inLobby(player)) or false

	-- fly
	if S.fly and flyBV and flyBG and flyBV.Parent then
		local dir = Vector3.zero
		if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
		if dir.Magnitude == 0 and hum.MoveDirection.Magnitude > 0 then dir = cam.CFrame.LookVector * hum.MoveDirection.Magnitude end
		flyBV.Velocity = dir * cfgv.flySpeed
		flyBG.CFrame = cam.CFrame
	end

	-- kunci speed/jump supaya tidak di-reset script game
	if cfgv.speed and hum.WalkSpeed ~= cfgv.speed then hum.WalkSpeed = cfgv.speed end
	if cfgv.jump and hum.JumpPower ~= cfgv.jump then hum.UseJumpPower = true hum.JumpPower = cfgv.jump end

	-- lingkaran FOV aim
	circle.Visible = S.aim and true or false
	circle.Size = UDim2.fromOffset(aim.fov * 2, aim.fov * 2)

	-- radar killer: cari killer terdekat, layar berkedip merah makin dekat makin cepat
	if S.radar and not lobbyMe and not isKiller(player) then
		local _, d = nearestPlayer(isKiller)
		if d and d <= CFG.TerrorRadius then
			local k = 1 - d / CFG.TerrorRadius
			warnFrame.Visible, warnLbl.Visible = true, true
			warnFrame.BackgroundTransparency = 1 - (0.08 + 0.22 * k) * (0.6 + 0.4 * math.sin(now * (4 + 8 * k)))
			warnLbl.Text = string.format("KILLER %dm", d)
		else
			warnFrame.Visible, warnLbl.Visible = false, false
		end
	else
		warnFrame.Visible, warnLbl.Visible = false, false
	end

	-- panah ke generator terdekat yang belum selesai
	if S.arrow and not lobbyMe then
		local best, bd
		for _, inst in ipairs(lists.gen) do
			local prog = inst:GetAttribute(CFG.ProgressAttribute)
			if inst.Parent and not (prog and prog >= 100) then
				local d = (posOf(inst) - root.Position).Magnitude
				if not bd or d < bd then best, bd = inst, d end
			end
		end
		objLbl.Visible = best ~= nil
		if best then objLbl.Text = string.format("%s  GEN  %dm", arrowTo(posOf(best) - root.Position), bd) end
	else
		objLbl.Visible = false
	end

	-- panah ke teman yang sekarat / di-hook (survivor)
	if S.allyArrow and not lobbyMe then
		local ally, bd
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and inMatch(p) and not isKiller(p) then
				local st = statusOf(p)
				if st == "DOWN" or st == "HOOK" then
					local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
					if not bd or d < bd then ally, bd = p, d end
				end
			end
		end
		allyLbl.Visible = ally ~= nil
		if ally then
			allyLbl.Text = string.format("%s %s [%s] %dm", arrowTo(ally.Character.HumanoidRootPart.Position - root.Position), ally.DisplayName, statusOf(ally), bd)
		end
	else
		allyLbl.Visible = false
	end
	-- HUD killer: nama, jarak, arah
	if S.killerHud and not lobbyMe then
		local k, d = nearestPlayer(isKiller)
		killerLbl.Visible = k ~= nil
		if k then killerLbl.Text = string.format("%s KILLER %s %dm", arrowTo(k.Character.HumanoidRootPart.Position - root.Position), k.DisplayName, d) end
	else
		killerLbl.Visible = false
	end
	-- HUD pemburu (killer): survivor terdekat
	if S.huntHud and not lobbyMe then
		local v, d = nearestPlayer(function(x) return not isKiller(x) end)
		huntLbl.Visible = v ~= nil
		if v then huntLbl.Text = string.format("%s %s [%s] %dm", arrowTo(v.Character.HumanoidRootPart.Position - root.Position), v.DisplayName, statusOf(v), d) end
	else
		huntLbl.Visible = false
	end

	-- ===== fitur Player (jalan tiap frame) =====
	local sp = pl.sel
	if pl.mode and sp and sp.Parent and alive(sp) then
		local tr = sp.Character.HumanoidRootPart
		if pl.mode == "follow" then
			root.CFrame = CFrame.lookAt((tr.CFrame * CFrame.new(0, 0, pl.dist)).Position, tr.Position)
		elseif pl.mode == "orbit" then
			pl.ang += dt * 1.6
			root.CFrame = CFrame.lookAt(tr.Position + Vector3.new(math.cos(pl.ang) * pl.dist, 2, math.sin(pl.ang) * pl.dist), tr.Position)
		end
	end
	if S.spec and sp and sp.Character then
		local sh = sp.Character:FindFirstChildOfClass("Humanoid")
		if sh and cam.CameraSubject ~= sh then cam.CameraSubject = sh end
	end
	if S.spin then root.CFrame = root.CFrame * CFrame.Angles(0, dt * pl.spinSpeed, 0) end
	if S.bhop and hum.MoveDirection.Magnitude > 0.1 and hum.FloorMaterial ~= Enum.Material.Air then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	if S.freeze and not root.Anchored then root.Anchored = true end
	if S.antisit and hum.Sit then hum.Sit = false hum:ChangeState(Enum.HumanoidStateType.Jumping) end

	-- survivor: kabur otomatis menjauh dari killer
	if S.flee and not lobbyMe and not isKiller(player) then
		local kp, kd = nearestPlayer(isKiller)
		if kp and kd < CFG.TerrorRadius * 0.6 then
			local away = (root.Position - kp.Character.HumanoidRootPart.Position) * Vector3.new(1, 0, 1)
			if away.Magnitude > 0.1 then hum:MoveTo(root.Position + away.Unit * 30) end
		end
	end
	-- killer: hadap survivor terdekat + serang otomatis (Tool:Activate)
	if (S.faceHunt or S.autoAtk) and not lobbyMe then
		local v, vd = nearestPlayer(function(x) return not isKiller(x) end)
		if v then
			local tp = v.Character.HumanoidRootPart.Position
			if S.faceHunt and vd <= 60 then
				root.CFrame = CFrame.lookAt(root.Position, Vector3.new(tp.X, root.Position.Y, tp.Z))
			end
			if S.autoAtk and vd <= pl.atkRange and now - pl.lastAtk > 0.45 then
				local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
				if tool then tool:Activate() pl.lastAtk = now end
			end
		end
	end

	-- auto chase (killer): jalan otomatis ke survivor terdekat
	if S.chase then
		local p = nearestPlayer(function(x) return not isKiller(x) end)
		if p then hum:MoveTo(p.Character.HumanoidRootPart.Position) end
	end

	-- tugas ringan tiap 0.25 detik
	acc += dt
	if acc >= 0.25 then
		acc = 0
		-- HUD generator + notif saat generator selesai
		if S.genHud or S.genHudK then
			local total, done, sum = 0, 0, 0
			for _, g in ipairs(lists.gen) do
				if g.Parent then
					total += 1
					local pr = g:GetAttribute(CFG.ProgressAttribute) or 0
					sum += math.min(pr, 100)
					if pr >= 100 then done += 1 end
				end
			end
			genLbl.Visible = total > 0 and not lobbyMe
			genLbl.Text = string.format("GENERATOR %d/%d selesai  •  total %d%%", done, total, math.floor(total > 0 and sum / total or 0))
			if pl.genDone >= 0 and done > pl.genDone then notify("Generator selesai! " .. done .. "/" .. total) end
			pl.genDone = done
		else
			genLbl.Visible = false
		end
		-- jejak survivor (scratch marks) untuk killer
		if S.marks and not lobbyMe then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and inMatch(p) and not isKiller(p) then
					local r = p.Character.HumanoidRootPart
					if r.AssemblyLinearVelocity.Magnitude > 4 then
						local m = mk("Part", {
							Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.Neon,
							Color = Color3.fromRGB(255, 90, 60), Size = Vector3.new(0.7, 0.2, 0.7), CFrame = CFrame.new(r.Position - Vector3.new(0, 2.9, 0)), Parent = workspace,
						})
						game:GetService("Debris"):AddItem(m, 7)
					end
				end
			end
		end
		-- matikan efek layar bawaan game (blur / flash / warna)
		if S.noFx then
			for _, e in ipairs(Lighting:GetChildren()) do
				if (e:IsA("BlurEffect") or e:IsA("ColorCorrectionEffect") or e:IsA("BloomEffect") or e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect"))
					and e.Enabled and e.Name:sub(1, 3) ~= "VD_" then
					pl.noFxOff[e] = true
					e.Enabled = false
				end
			end
		end
		for _, t in ipairs(objTags) do
			t.bb.Enabled = not lobbyMe
			if t.inst.Parent then
				local d = (posOf(t.inst) - root.Position).Magnitude
				local prog = t.inst:GetAttribute(CFG.ProgressAttribute)
				t.label.Text = t.name .. (prog and (" " .. math.floor(prog) .. "%") or "") .. "\n" .. math.floor(d) .. "m"
			end
		end
		for p, t in pairs(pTags) do
			local c = p.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if r then
				local k = isKiller(p)
				local st = (not k) and statusOf(p) or nil
				local col = k and RED or STATUS_COL[st]
				t.hl.FillColor, t.hl.OutlineColor, t.lbl.TextColor3 = col, col, col
				t.lbl.Text = string.format("%s%s\n%dm • HP %d", p.DisplayName, (st and st ~= "OK") and (" [" .. st .. "]") or "",
					(r.Position - root.Position).Magnitude, h and h.Health or 0)
			end
		end
		-- notifikasi saat status teman berubah jadi sekarat / di-hook
		if S.allyAlert then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and not isKiller(p) and p.Character and inMatch(p) and not lobbyMe then
					local st = statusOf(p)
					if st ~= lastStatus[p] and (st == "DOWN" or st == "HOOK") then
						notify(p.DisplayName .. (st == "DOWN" and " SEKARAT!" or " DI-HOOK!"))
					end
					lastStatus[p] = st
				end
			end
		end
	end

	infoAcc += dt
	if infoAcc >= 0.5 and infoFps then
		infoAcc = 0
		infoFps.Text = "  FPS: " .. math.floor(1 / math.max(dt, 0.001))
		pcall(function() infoPing.Text = "  Ping: " .. math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) .. " ms" end)
		infoRole.Text = "  Peran: " .. (isKiller(player) and "KILLER" or "SURVIVOR")
	end
end)

-- sinkronkan ESP pemain tiap 1 detik (pemain bisa ganti role/respawn)
task.spawn(function()
	while gui.Parent do
		if S.espKiller or S.espSurv or S.espTeam or next(pTags) then syncPlayerTags() end
		if S.score or S.scoreS or scoreFrame.Visible then refreshScore() end
		task.wait(1)
	end
end)

------------------------------------------------------------------------
-- BAGIAN 10 — GRAFIK (efek di Lighting; semua lokal)
------------------------------------------------------------------------
local function fx(class, name)
	local e = Lighting:FindFirstChild("VD_" .. name)
	if not e then e = Instance.new(class) e.Name = "VD_" .. name e.Parent = Lighting end
	return e
end
local function offFx()
	for _, n in ipairs({"Bloom", "Rays", "Color", "DoF", "Atmos"}) do
		local e = Lighting:FindFirstChild("VD_" .. n)
		if e then e:Destroy() end
	end
end
local presets = {
	Low = function()
		offFx()
		Lighting.GlobalShadows = false
		pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level02 end)
	end,
	Medium = function()
		offFx()
		Lighting.GlobalShadows = true
		pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level08 end)
		local c = fx("ColorCorrectionEffect", "Color") c.Contrast, c.Saturation = 0.05, 0.08
	end,
	High = function()
		offFx()
		Lighting.GlobalShadows = true
		Lighting.Brightness = 2
		pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level14 end)
		local b = fx("BloomEffect", "Bloom") b.Intensity, b.Size, b.Threshold = 0.5, 24, 1.8
		local r = fx("SunRaysEffect", "Rays") r.Intensity, r.Spread = 0.06, 0.6
		local c = fx("ColorCorrectionEffect", "Color") c.Contrast, c.Saturation = 0.1, 0.15
	end,
	Ultra = function()
		offFx()
		Lighting.GlobalShadows = true
		Lighting.Brightness = 2.4
		Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = 1, 1
		pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level21 end)
		local b = fx("BloomEffect", "Bloom") b.Intensity, b.Size, b.Threshold = 0.7, 36, 1.6
		local r = fx("SunRaysEffect", "Rays") r.Intensity, r.Spread = 0.1, 0.8
		local c = fx("ColorCorrectionEffect", "Color") c.Contrast, c.Saturation, c.TintColor = 0.15, 0.2, Color3.fromRGB(255, 248, 240)
		local d = fx("DepthOfFieldEffect", "DoF") d.FarIntensity, d.FocusDistance, d.InFocusRadius, d.NearIntensity = 0.15, 60, 40, 0
		local a = fx("Atmosphere", "Atmos") a.Density, a.Haze, a.Color = 0.25, 1, Color3.fromRGB(190, 200, 215)
	end,
	Horror = function()
		offFx()
		Lighting.GlobalShadows = true
		Lighting.Brightness = 0.6
		Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(18, 18, 26), Color3.fromRGB(24, 24, 34)
		Lighting.ClockTime = 0
		local c = fx("ColorCorrectionEffect", "Color") c.Contrast, c.Saturation, c.Brightness, c.TintColor = 0.25, -0.25, -0.05, Color3.fromRGB(200, 210, 255)
		local a = fx("Atmosphere", "Atmos") a.Density, a.Haze, a.Color, a.Offset = 0.45, 2, Color3.fromRGB(70, 75, 95), 0.2
		local b = fx("BloomEffect", "Bloom") b.Intensity, b.Size, b.Threshold = 0.4, 20, 2
	end,
}
local fullbrightBackup
local function setFullbright(on)
	if on then
		fullbrightBackup = {Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ClockTime, Lighting.FogEnd}
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd = 2.5, 14, 1e6
		Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170), Color3.fromRGB(170, 170, 170)
	elseif fullbrightBackup then
		Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ClockTime, Lighting.FogEnd = table.unpack(fullbrightBackup)
	end
end

------------------------------------------------------------------------
-- BAGIAN 11 — ISI MENU (tab Survivor, Killer, Aim, Gerak, Teleport, Grafik)
------------------------------------------------------------------------
-- ---- TAB SURVIVOR ----
local pSurv = newTab("Survivor")
section(pSurv, "Informasi")
toggle(pSurv, "Label Generator / Gate / Hook", "objMain", function() buildObjTags() end)
toggle(pSurv, "Label Pallet & Window", "objExtra", function() buildObjTags() end)
toggle(pSurv, "Panah ke Generator Terdekat", "arrow")
toggle(pSurv, "ESP Killer (siluet + jarak + HP)", "espKiller", function() syncPlayerTags() end)
toggle(pSurv, "ESP Teman (hijau sehat, oranye sekarat, ungu di-hook)", "espTeam", function() syncPlayerTags() end)
toggle(pSurv, "Notif Teman Sekarat / Di-hook", "allyAlert")
toggle(pSurv, "Panah ke Teman Sekarat", "allyArrow")
toggle(pSurv, "HUD Killer (nama, jarak, arah)", "killerHud")
toggle(pSurv, "Radar Killer (layar berkedip)", "radar")
slider(pSurv, "Radius Radar (studs)", 15, 150, CFG.TerrorRadius, function(v) CFG.TerrorRadius = v end)
toggle(pSurv, "HUD Generator (jumlah selesai + persen)", "genHud")
toggle(pSurv, "Papan Status Pemain (live)", "scoreS", function() refreshScore() end)
section(pSurv, "Bantuan Aksi")
toggle(pSurv, "Auto Kabur (menjauh saat killer dekat)", "flee")
button(pSurv, "TP ke Generator Belum Selesai Terdekat", function()
	local root = getRoot()
	local best, bd
	for _, g in ipairs(lists.gen) do
		local pr = g:GetAttribute(CFG.ProgressAttribute) or 0
		if g.Parent and pr < 100 and root then
			local d = (posOf(g) - root.Position).Magnitude
			if not bd or d < bd then best, bd = g, d end
		end
	end
	if best then tpTo(posOf(best)) notify("TP generator") else notify("Semua generator selesai / tidak ada") end
end)
button(pSurv, "TP ke Gate Terjauh dari Killer", function()
	local k = nearestPlayer(isKiller)
	local best, bd
	for _, g in ipairs(lists.gate) do
		if g.Parent and k then
			local d = (posOf(g) - k.Character.HumanoidRootPart.Position).Magnitude
			if not bd or d > bd then best, bd = g, d end
		end
	end
	if best then tpTo(posOf(best)) notify("TP gate aman") else notify("Killer / gate tidak ditemukan") end
end)
toggle(pSurv, "Instant Prompt (tanpa tahan tombol)", "instant", function(on) setInstantPrompts(on) end)
button(pSurv, "TP ke Generator Terdekat", function()
	local g = nearestObject("gen")
	if g then tpTo(posOf(g)) notify("TP generator") else notify("Generator tidak ditemukan") end
end)
button(pSurv, "TP ke Gate Terdekat", function()
	local g = nearestObject("gate")
	if g then tpTo(posOf(g)) notify("TP gate") else notify("Gate tidak ditemukan") end
end)
button(pSurv, "TP Menjauh dari Killer (30 studs)", function()
	local k = nearestPlayer(isKiller)
	local r = getRoot()
	if k and r then
		local away = (r.Position - k.Character.HumanoidRootPart.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then tpTo(r.Position + away.Unit * 30 - Vector3.new(0, 5, 0)) end
	else
		notify("Killer tidak ditemukan")
	end
end)
button(pSurv, "TP ke Teman Sekarat Terdekat", function()
	local p = nearestPlayer(function(x)
		if isKiller(x) then return false end
		local st = statusOf(x)
		return st == "DOWN" or st == "HOOK"
	end)
	if p then tpTo(p.Character.HumanoidRootPart.Position) notify("TP → " .. p.DisplayName) else notify("Tidak ada teman sekarat") end
end)
button(pSurv, "TP ke Teman Terdekat", function()
	local p = nearestPlayer(function(x) return not isKiller(x) end)
	if p then tpTo(p.Character.HumanoidRootPart.Position) notify("TP → " .. p.DisplayName) else notify("Teman tidak ditemukan") end
end)

-- ---- TAB KILLER ----
local pKill = newTab("Killer")
section(pKill, "Berburu")
toggle(pKill, "ESP Survivor (siluet + jarak + HP)", "espSurv", function() syncPlayerTags() end)
toggle(pKill, "Auto Chase (jalan ke survivor terdekat)", "chase")
button(pKill, "TP ke Survivor Terdekat", function()
	local p = nearestPlayer(function(x) return not isKiller(x) end)
	if p then tpTo(p.Character.HumanoidRootPart.Position) notify("TP → " .. p.DisplayName) else notify("Survivor tidak ditemukan") end
end)
button(pKill, "TP ke Belakang Survivor Terdekat", function()
	local p = nearestPlayer(function(x) return not isKiller(x) end)
	local r = getRoot()
	if p and r then
		local tr = p.Character.HumanoidRootPart
		local pos = (tr.CFrame * CFrame.new(0, 0, 3)).Position
		r.CFrame = CFrame.lookAt(pos, tr.Position)
		notify("Di belakang " .. p.DisplayName)
	else
		notify("Survivor tidak ditemukan")
	end
end)
toggle(pKill, "Panah ke Survivor Terdekat (+ status)", "huntHud")
button(pKill, "TP ke Survivor Sekarat Terdekat", function()
	local p = nearestPlayer(function(x)
		if isKiller(x) then return false end
		local st = statusOf(x)
		return st == "DOWN" or st == "KRITIS"
	end)
	if p then tpTo(p.Character.HumanoidRootPart.Position) notify("TP → " .. p.DisplayName) else notify("Tidak ada survivor sekarat") end
end)
button(pKill, "TP ke Survivor HP Terendah", function()
	local best, bh
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and inMatch(p) and not isKiller(p) then
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			local hp = h and h.Health or 100
			if not bh or hp < bh then best, bh = p, hp end
		end
	end
	if best then tpTo(best.Character.HumanoidRootPart.Position) notify("TP → " .. best.DisplayName) else notify("Survivor tidak ditemukan") end
end)
section(pKill, "Serang & Kejar")
toggle(pKill, "Auto Attack (Tool aktif saat survivor dekat)", "autoAtk")
slider(pKill, "Jarak Serang (studs)", 5, 30, pl.atkRange, function(v) pl.atkRange = v end)
toggle(pKill, "Hadap Survivor Terdekat (auto)", "faceHunt")
toggle(pKill, "Jejak Survivor (tanda langkah 7 detik)", "marks")
button(pKill, "TP ke Survivor Terjauh", function()
	local root = getRoot()
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and inMatch(p) and not isKiller(p) and root then
			local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
			if not bd or d > bd then best, bd = p, d end
		end
	end
	if best then tpTo(best.Character.HumanoidRootPart.Position) notify("TP → " .. best.DisplayName) else notify("Survivor tidak ditemukan") end
end)
section(pKill, "Informasi")
toggle(pKill, "Papan Status Survivor (live)", "score", function() refreshScore() end)
toggle(pKill, "HUD Generator (jumlah selesai + persen)", "genHudK")
toggle(pKill, "Anti Efek Layar Game (blur/flash)", "noFx", function(on)
	if not on then
		for e in pairs(pl.noFxOff) do
			if e.Parent then e.Enabled = true end
		end
		pl.noFxOff = {}
	end
end)
local function genByProgress(highest)
	local best, bp
	for _, g in ipairs(lists.gen) do
		local pr = g:GetAttribute(CFG.ProgressAttribute) or 0
		if g.Parent and pr < 100 and (not bp or (highest and pr > bp) or (not highest and pr < bp)) then best, bp = g, pr end
	end
	return best, bp
end
button(pKill, "TP ke Generator Progres Tertinggi (jaga)", function()
	local g, pr = genByProgress(true)
	if g then tpTo(posOf(g)) notify("Generator " .. math.floor(pr) .. "%") else notify("Generator tidak ditemukan") end
end)
button(pKill, "TP ke Generator Progres Terendah", function()
	local g, pr = genByProgress(false)
	if g then tpTo(posOf(g)) notify("Generator " .. math.floor(pr) .. "%") else notify("Generator tidak ditemukan") end
end)
section(pKill, "Teleport Objek")
for _, k in ipairs({{"hook", "Hook"}, {"gen", "Generator"}, {"gate", "Gate"}, {"pallet", "Pallet"}, {"window", "Window"}}) do
	button(pKill, "TP ke " .. k[2] .. " Terdekat", function()
		local o = nearestObject(k[1])
		if o then tpTo(posOf(o)) notify("TP " .. k[2]) else notify(k[2] .. " tidak ditemukan") end
	end)
end

-- ---- TAB PLAYER (semua fitur terkait pemain: teleport pemain dipisah dari teleport objek) ----
local pPlayer = newTab("Player")
section(pPlayer, "Pilih Pemain")
local plHolder, selLbl
local rebuildPlayers
button(pPlayer, "Refresh Daftar Pemain", function() rebuildPlayers() end)
plHolder = mk("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = pPlayer})
mk("UIListLayout", {Padding = UDim.new(0, 4), Parent = plHolder})
selLbl = label(pPlayer, "Terpilih: -")
local function selectPlayer(p)
	pl.sel = p
	selLbl.Text = "  Terpilih: " .. (p and p.DisplayName or "-")
end
rebuildPlayers = function()
	for _, c in ipairs(plHolder:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local root = getRoot()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local tag = isKiller(p) and "KILLER" or statusOf(p)
			if inLobby(p) then tag = "LOBBY" end
			local d = (root and p.Character and p.Character:FindFirstChild("HumanoidRootPart")) and math.floor((p.Character.HumanoidRootPart.Position - root.Position).Magnitude) or 0
			local b = button(plHolder, "", function() selectPlayer(p) end)
			b.Text = string.format("[%s] %s • %dm", tag, p.DisplayName, d)
			b.TextColor3 = (tag == "KILLER") and RED or (tag == "LOBBY" and SUB or STATUS_COL[tag] or TXT)
		end
	end
end
Players.PlayerAdded:Connect(function() task.wait(0.5) rebuildPlayers() end)
Players.PlayerRemoving:Connect(function(p)
	if pl.sel == p then selectPlayer(nil) end
	task.defer(rebuildPlayers)
end)

local function needSel()
	local p = pl.sel
	if p and p.Parent and alive(p) then return p end
	notify("Pilih pemain dulu / pemain tidak aktif")
end

section(pPlayer, "Aksi ke Pemain Terpilih")
button(pPlayer, "TP ke Pemain", function()
	local p = needSel()
	if p then tpTo(p.Character.HumanoidRootPart.Position) end
end)
button(pPlayer, "TP ke Belakang Pemain", function()
	local p, r = needSel(), getRoot()
	if p and r then
		local tr = p.Character.HumanoidRootPart
		r.CFrame = CFrame.lookAt((tr.CFrame * CFrame.new(0, 0, 4)).Position, tr.Position)
	end
end)
button(pPlayer, "TP ke Atas Pemain (20 studs)", function()
	local p = needSel()
	if p then tpTo(p.Character.HumanoidRootPart.Position + Vector3.new(0, 20, 0)) end
end)
button(pPlayer, "Hadap ke Pemain", function()
	local p, r = needSel(), getRoot()
	if p and r then
		local t = p.Character.HumanoidRootPart.Position
		r.CFrame = CFrame.lookAt(r.Position, Vector3.new(t.X, r.Position.Y, t.Z))
	end
end)
local infoPl = label(pPlayer, "Info: -")
button(pPlayer, "Lihat Info Pemain", function()
	local p, r = needSel(), getRoot()
	if p and r then
		local h = p.Character:FindFirstChildOfClass("Humanoid")
		local role = isKiller(p) and "KILLER" or "SURVIVOR"
		infoPl.Text = string.format("  %s • %s • HP %d • %dm%s", role, isKiller(p) and "-" or statusOf(p), math.floor(h and h.Health or 0),
			math.floor((p.Character.HumanoidRootPart.Position - r.Position).Magnitude), inLobby(p) and " • LOBBY" or "")
	end
end)
slider(pPlayer, "Jarak Follow / Orbit", 3, 30, pl.dist, function(v) pl.dist = v end)
local setFollow, setOrbit, setSpec
setFollow = toggle(pPlayer, "Follow (ikuti dari belakang)", "follow", function(on)
	if on then
		if not needSel() then setFollow(false) return end
		if S.orbit then setOrbit(false) end
		pl.mode = "follow"
	elseif pl.mode == "follow" then
		pl.mode = nil
	end
end)
setOrbit = toggle(pPlayer, "Orbit (berputar mengelilingi)", "orbit", function(on)
	if on then
		if not needSel() then setOrbit(false) return end
		if S.follow then setFollow(false) end
		pl.mode = "orbit"
	elseif pl.mode == "orbit" then
		pl.mode = nil
	end
end)
setSpec = toggle(pPlayer, "Spectate (lihat dari sudut pandangnya)", "spec", function(on)
	if on then
		if not needSel() then setSpec(false) end
	else
		local h = getHum()
		if h then cam.CameraSubject = h end
	end
end)

section(pPlayer, "Teleport Pemain Cepat")
button(pPlayer, "TP ke Pemain Terdekat", function()
	local p = nearestPlayer(function() return true end)
	if p then tpTo(p.Character.HumanoidRootPart.Position) notify("TP → " .. p.DisplayName) else notify("Tidak ada pemain di match") end
end)
button(pPlayer, "TP ke Pemain Terjauh", function()
	local root = getRoot()
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and inMatch(p) and root then
			local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
			if not bd or d > bd then best, bd = p, d end
		end
	end
	if best then tpTo(best.Character.HumanoidRootPart.Position) notify("TP → " .. best.DisplayName) else notify("Tidak ada pemain di match") end
end)
button(pPlayer, "TP ke Pemain Acak", function()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and inMatch(p) then table.insert(list, p) end
	end
	if #list > 0 then
		local p = list[math.random(1, #list)]
		tpTo(p.Character.HumanoidRootPart.Position)
		notify("TP → " .. p.DisplayName)
	else
		notify("Tidak ada pemain di match")
	end
end)
button(pPlayer, "Spectate Pemain Terdekat", function()
	local p = nearestPlayer(function() return true end)
	if p then
		selectPlayer(p)
		if not S.spec then setSpec(true) end
	else
		notify("Tidak ada pemain di match")
	end
end)
button(pPlayer, "Berhenti Spectate", function() if S.spec then setSpec(false) end end)

section(pPlayer, "Kontrol Diri Sendiri")
local setLobbyF = toggle(pPlayer, "Filter Lobby (ESP/Aim/HUD mati untuk pemain lobby)", "lobbyFilter")
setLobbyF(true)
toggle(pPlayer, "Click TP (tahan Ctrl + klik, PC)", "clicktp")
toggle(pPlayer, "Tap TP (sentuh dunia untuk TP, HP)", "taptp")
toggle(pPlayer, "Spin (berputar)", "spin")
slider(pPlayer, "Kecepatan Spin", 1, 30, pl.spinSpeed, function(v) pl.spinSpeed = v end)
toggle(pPlayer, "Auto Bunny Hop", "bhop")
toggle(pPlayer, "Anti Duduk", "antisit")
toggle(pPlayer, "Freeze (kunci posisi)", "freeze", function(on)
	local r = getRoot()
	if r then r.Anchored = on end
end)
toggle(pPlayer, "Buka Batas Zoom Kamera", "zoom", function(on) player.CameraMaxZoomDistance = on and 1000 or 128 end)
slider(pPlayer, "Gravitasi", 20, 400, math.floor(workspace.Gravity), function(v) workspace.Gravity = v end)
button(pPlayer, "Reset Gravitasi (196)", function() workspace.Gravity = 196.2 notify("Gravitasi normal") end)
button(pPlayer, "Duduk / Berdiri", function() local h = getHum() if h then h.Sit = not h.Sit end end)

UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	local ok = (i.UserInputType == Enum.UserInputType.MouseButton1 and S.clicktp and UIS:IsKeyDown(Enum.KeyCode.LeftControl))
		or (i.UserInputType == Enum.UserInputType.Touch and S.taptp)
	if not ok then return end
	local ray = cam:ScreenPointToRay(i.Position.X, i.Position.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {player.Character}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, rp)
	if hit then tpTo(hit.Position) end
end)
rebuildPlayers()

-- ---- TAB AIM ----
local pAim = newTab("Aim")
section(pAim, "Aim Assist (kunci kamera)")
toggle(pAim, "Aim Aktif", "aim")
slider(pAim, "Kekuatan Kunci (100 = brutal/snap)", 5, 100, aim.smooth, function(v) aim.smooth = v end)
slider(pAim, "Radius FOV (px)", 50, 500, aim.fov, function(v) aim.fov = v end)
local setWall = toggle(pAim, "Cek Dinding (hanya yang terlihat)", "aimwall", function(on) aim.wall = on end)
local setPred = toggle(pAim, "Prediksi Gerakan", "aimpred", function(on) aim.predict = on end)
toggle(pAim, "Hanya saat Tahan Klik Kanan (PC)", "aimrmb", function(on) aim.rmb = on end)
setWall(false)
setPred(true)
section(pAim, "Target")
local modeBtn
modeBtn = button(pAim, "Target: Lawan (otomatis)", function()
	local order = {Lawan = "Killer", Killer = "Survivor", Survivor = "Semua", Semua = "Lawan"}
	aim.mode = order[aim.mode]
	modeBtn.Text = "Target: " .. aim.mode .. (aim.mode == "Lawan" and " (otomatis)" or "")
end)
local partBtn
partBtn = button(pAim, "Bagian Tubuh: Head", function()
	local order = {Head = "UpperTorso", UpperTorso = "HumanoidRootPart", HumanoidRootPart = "Head"}
	aim.part = order[aim.part] or "Head"
	partBtn.Text = "Bagian Tubuh: " .. aim.part
end)
label(pAim, "Lawan: killer membidik survivor, survivor membidik killer.")
toggle(pAim, "Auto Fire (Activate Tool saat target di tengah)", "autofire", function(on) aim.autofire = on end)
toggle(pAim, "Crosshair + di Tengah Layar", "cross", function(on) centerCross.Visible = on end)
section(pAim, "Peran (pakai ini kalau deteksi salah)")
local roleBtn
roleBtn = button(pAim, "Peran Saya: Auto", function()
	if roleOverride == nil then roleOverride = "Survivor" elseif roleOverride == "Survivor" then roleOverride = "Killer" else roleOverride = nil end
	roleBtn.Text = "Peran Saya: " .. (roleOverride or "Auto")
end)
local killerHolder = mk("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = pAim})
mk("UIListLayout", {Padding = UDim.new(0, 4), Parent = killerHolder})
local function rebuildKillerMarks()
	for _, c in ipairs(killerHolder:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local b
			local function paint() b.Text = (manualKillers[p] and "[KILLER] " or "[survivor] ") .. p.DisplayName end
			b = button(killerHolder, "", function()
				manualKillers[p] = (not manualKillers[p]) or nil
				paint()
			end)
			paint()
		end
	end
end
button(pAim, "Refresh Daftar Pemain (tandai killer manual)", rebuildKillerMarks)
rebuildKillerMarks()

-- ---- TAB GERAK ----
local pMove = newTab("Gerak")
section(pMove, "Kecepatan")
slider(pMove, "Walk Speed", 16, 300, 16, function(v)
	cfgv.speed = (v ~= 16) and v or nil
	local h = getHum()
	if h then h.WalkSpeed = v end
end)
slider(pMove, "Jump Power", 50, 400, 50, function(v)
	cfgv.jump = (v ~= 50) and v or nil
	local h = getHum()
	if h then h.UseJumpPower = true h.JumpPower = v end
end)
slider(pMove, "Kecepatan Fly", 20, 300, cfgv.flySpeed, function(v) cfgv.flySpeed = v end)
section(pMove, "Gerakan")
setFly = toggle(pMove, "Fly (WASD / Space / Shift)", "fly", function(on)
	if on then
		if not startFly() then S.fly = false notify("Karakter belum siap") end
	else
		stopFly()
	end
end)
toggle(pMove, "Noclip (tembus tembok)", "noclip")
toggle(pMove, "Infinite Jump", "infjump")
toggle(pMove, "Anti AFK", "antiafk")
button(pMove, "Respawn", function() local h = getHum() if h then h.Health = 0 end end)
section(pMove, "Info")
infoRole = label(pMove, "Peran: -")
infoFps = label(pMove, "FPS: -")
infoPing = label(pMove, "Ping: -")

-- ---- TAB TELEPORT ----
local pTp = newTab("Teleport")
section(pTp, "Objek Map (teleport pemain ada di tab Player)")
local tpHolder
local function rebuildTP()
	for _, c in ipairs(tpHolder:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	refreshLists()
	for _, k in ipairs(KINDS) do
		for i, inst in ipairs(lists[k.key]) do
			button(tpHolder, k.label .. " " .. i, function() tpTo(posOf(inst)) end)
		end
	end
	local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if sp then button(tpHolder, "Spawn", function() tpTo(sp.Position) end) end
end
button(pTp, "Muat / Refresh Daftar", function() rebuildTP() buildObjTags() notify("Daftar diperbarui") end)
local home
button(pTp, "Simpan Posisi Sekarang (Home)", function()
	local r = getRoot()
	if r then home = r.Position notify("Home tersimpan") end
end)
button(pTp, "TP ke Home", function() if home then tpTo(home) else notify("Belum ada Home") end end)
section(pTp, "Slot Posisi")
local slots = {}
for n = 1, 3 do
	button(pTp, "Simpan Slot " .. n, function()
		local r = getRoot()
		if r then slots[n] = r.Position notify("Slot " .. n .. " tersimpan") end
	end)
	button(pTp, "TP Slot " .. n, function() if slots[n] then tpTo(slots[n]) else notify("Slot " .. n .. " kosong") end end)
end
section(pTp, "Lompatan Cepat")
button(pTp, "TP ke Tengah Map (rata-rata generator)", function()
	local sum, n = Vector3.zero, 0
	for _, g in ipairs(lists.gen) do
		if g.Parent then sum += posOf(g) n += 1 end
	end
	if n > 0 then tpTo(sum / n) notify("TP tengah map") else notify("Generator tidak ditemukan") end
end)
button(pTp, "TP ke Gate Terjauh dari Saya", function()
	local root = getRoot()
	local best, bd
	for _, g in ipairs(lists.gate) do
		if g.Parent and root then
			local d = (posOf(g) - root.Position).Magnitude
			if not bd or d > bd then best, bd = g, d end
		end
	end
	if best then tpTo(posOf(best)) else notify("Gate tidak ditemukan") end
end)
button(pTp, "Maju 30 studs", function()
	local r = getRoot()
	if r then r.CFrame = r.CFrame + r.CFrame.LookVector * 30 end
end)
button(pTp, "Naik 50 studs", function()
	local r = getRoot()
	if r then r.CFrame = r.CFrame + Vector3.new(0, 50, 0) end
end)
section(pTp, "Daftar Objek")
tpHolder = mk("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = pTp})
mk("UIListLayout", {Padding = UDim.new(0, 4), Parent = tpHolder})

-- ---- TAB GRAFIK ----
local pGfx = newTab("Grafik")
section(pGfx, "Preset")
for _, n in ipairs({"Low", "Medium", "High", "Ultra", "Horror"}) do
	button(pGfx, "Preset " .. n, function() presets[n]() notify("Grafik " .. n) end)
end
section(pGfx, "Atur Manual")
toggle(pGfx, "Fullbright (terang total)", "fullbright", setFullbright)
toggle(pGfx, "Bayangan (Shadows)", "shadows", function(on) Lighting.GlobalShadows = on end)
slider(pGfx, "Kecerahan", 0, 6, math.floor(Lighting.Brightness), function(v) Lighting.Brightness = v end)
slider(pGfx, "Jam Dunia", 0, 24, math.floor(Lighting.ClockTime), function(v) Lighting.ClockTime = v end)
slider(pGfx, "FOV Kamera", 40, 110, math.floor(cam.FieldOfView), function(v) cam.FieldOfView = v end)
slider(pGfx, "Bloom", 0, 10, 0, function(v)
	local b = fx("BloomEffect", "Bloom")
	b.Intensity, b.Size, b.Threshold = v / 10, 24, 1.8
end)
button(pGfx, "Matikan Semua Efek Grafik", function() offFx() notify("Efek dimatikan") end)

------------------------------------------------------------------------
-- BAGIAN 12 — MULAI
------------------------------------------------------------------------
refreshLists()
rebuildTP()
selectTab("Survivor")
notify("VD Script aktif • by hermawan")

gui.Destroying:Connect(function()
	pcall(function() RunService:UnbindFromRenderStep("VDAim") end)
	clearObjTags()
	for p in pairs(pTags) do clearPlayerTag(p) end
end)
