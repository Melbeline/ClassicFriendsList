-- ClassicFriendsList - characters in the friends list, the classic way (WoW Forever). The server keeps no character
-- friends there (Battle.net friends only), and its list takes none of the account's own characters: this addon keeps
-- a list of characters instead (for the whole account: one's own and friends'), and shows them in the friends
-- window, above the offline Battle.net friends, in the game's look: online or offline (see "Online or not" below),
-- with their level, class and zone (from their own ClassicFriendsList or Clara) and when last seen. The game's Add
-- Friend window in the 1.15 look, with two lines: the game's (a BattleTag, or a name the Forever way) and the
-- addon's, that adds a character to this list. Over a row: its tooltip; right-click: whisper, invite or remove.
-- It speaks Clara's language (the same addon messages): a player with Clara and one with ClassicFriendsList see each
-- other online at once. Clara loaded: this addon stays off (Clara keeps the same list).

local ADDON, ns = ...
local L = ns.L

local NAME_MAX = 12 + 1 + 64 -- a first name, a space, a surname (the game's own Add Friend box)
local KNOWN_AFTER = 120      -- seconds after login: every character counts as known (offline unless found online)
local TYPE = "classicFriend" -- the list entries' button type (the game's: numbers)

local issecret = issecretvalue or function() return false end

local CFL = {}
ns.CFL = CFL
_G.ClassicFriendsList = CFL

local db -- ClassicFriendsListDB
local off = false -- (Clara loaded: everything left to it)

---------------------------------------------------------------------------
-- The list (ClassicFriendsListDB.friends: lower-case whole name -> { name = "First Surname" })
---------------------------------------------------------------------------
local function Normal(name)
  if type(name) ~= "string" or issecret(name) then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if name == "" or #name > NAME_MAX then return nil end
  return name
end

local function List()
  if not db then return nil end
  if type(db.friends) ~= "table" then db.friends = {} end
  for key, alt in pairs(db.friends) do
    if type(key) ~= "string" or type(alt) ~= "table" or not Normal(alt.name) then db.friends[key] = nil end
  end
  return db.friends
end
CFL.List = List

-- A line in the chat as the game's own system lines (yellow), in the game's words when it has them
local function SaySystem(text)
  local frame = DEFAULT_CHAT_FRAME
  if not (frame and frame.AddMessage) then return end
  local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
  frame:AddMessage(text, info and info.r or 1, info and info.g or 1, info and info.b or 0)
end

-- Added or removed: said as the game says it of a friend ("Melbeline Moon added to friends."), the whole name
function CFL.Add(name)
  name = Normal(name)
  local list = List()
  if not (name and list) then return false end
  local key = name:lower()
  if list[key] then
    SaySystem((ERR_FRIEND_ALREADY_S or L.ALREADY):format(list[key].name))
    return false
  end
  list[key] = { name = name }
  SaySystem((ERR_FRIEND_ADDED_S or L.ADDED):format(name))
  CFL.Refresh()
  return true
end

function CFL.Remove(name)
  name = Normal(name)
  local list = List()
  if not (name and list) then return false end
  local alt = list[name:lower()]
  if not alt then
    SaySystem(L.NOT_LISTED:format(name))
    return false
  end
  list[name:lower()] = nil
  SaySystem((ERR_FRIEND_REMOVED_S or L.REMOVED):format(alt.name))
  CFL.Refresh()
  return true
end

-- In the list's order: online first, then by name.
local function Sorted()
  local out = {}
  for _, alt in pairs(List() or {}) do out[#out + 1] = alt end
  table.sort(out, function(a, b)
    local oa, ob = CFL.Online(a.name), CFL.Online(b.name)
    if oa ~= ob then return oa end
    return a.name:lower() < b.name:lower()
  end)
  return out
end
CFL.Sorted = Sorted

---------------------------------------------------------------------------
-- What the addon knows of a character: online, level, class, zone, last seen
---------------------------------------------------------------------------
-- The player's whole name ("First Surname"), as the game's own names give it
local function FullName()
  local name, surname
  if UnitNameUnmodified then
    local ok, a, b = pcall(UnitNameUnmodified, "player")
    if ok then name, surname = a, b end
  end
  if issecret(name) or type(name) ~= "string" or name == "" then
    name, surname = UnitName("player")
    if issecret(name) or type(name) ~= "string" or name == "" then return nil end
  end
  local consts = Constants and Constants.CharacterNameSeparatorConsts
  local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
  if type(sep) == "string" and not issecret(surname) and type(surname) == "string" and surname ~= ""
    and not name:find(sep, 1, true) then
    return name .. sep .. surname
  end
  return name
end

local function IsMe(name)
  local me = FullName()
  return type(me) == "string" and type(name) == "string" and me:lower() == name:lower()
end

-- Its first name
local function GameName(name) return name:match("^(%S+)") or name end
-- The name the server knows it by: the whole name, first name and surname (WoW Forever's names are unique with
-- their surname: a whisper to the first name alone finds no one), any realm part off, lower-case
local function Key(name) return ((name:match("^([^%-]+)") or name):gsub("^%s+", ""):gsub("%s+$", "")):lower() end

-- The server's answers (see "Online or not"): Key(name) -> { verdict = online, at, tried, sent }
local probes = {}
local startedAt -- (GetTime at login)

function CFL.Online(name)
  if IsMe(name) then return true end
  local p = probes[Key(name)]
  return p and p.verdict == true or false
end

-- Whether the addon knows yet if it is online: the server answered, or long enough since login
function CFL.Known(name)
  if IsMe(name) then return true end
  local p = probes[Key(name)]
  if p and p.verdict ~= nil then return true end
  return startedAt ~= nil and GetTime() - startedAt > KNOWN_AFTER
end

function CFL.Facts(name)
  local facts = {}
  if IsMe(name) then
    facts.level = UnitLevel and UnitLevel("player")
    facts.class = select(2, UnitClass("player"))
    facts.zone = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText())
    return facts
  end
  -- What its own addon said, and when it was last found online
  local alt = (List() or {})[name:lower()]
  if type(alt) == "table" then
    facts.level, facts.class = alt.level, alt.class
    if alt.zone and CFL.Online(name) then facts.zone = alt.zone end
    if type(alt.seen) == "number" then facts.at = alt.seen end
  end
  return facts
end

local function ClassName(class)
  return class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

local function Ago(at)
  if type(at) ~= "number" or at <= 0 or not time then return nil end
  local seconds = math.max(60, time() - at)
  local text = SecondsToTime and SecondsToTime(seconds, false, false, 1) or (math.floor(seconds / 60) .. " min")
  return L.LAST_SEEN:format(text)
end

---------------------------------------------------------------------------
-- The game's Add Friend window in the 1.x look (the 1.15 client's): "Add Friend" and its "?", the Battle.net
-- and faction icons with OR between, then two lines to type in. The top line is the game's own box, only
-- moved: a BattleTag, or a name sent the Forever way, by its own Enter and Add Friend button (the game's code,
-- untouched: an addon's code may not send a friend request). The bottom line, under its title, adds a character
-- to this addon's list, the classic way: at once, no request. Drawn over the game's window: its parts moved,
-- restyled or hidden, none of its values written; its "?" page left as the game's.
---------------------------------------------------------------------------
local ADD_W, ADD_H = 384, 280      -- the 1.15 window (232 high), a titled line more
local LINE_Y, LINE2_Y = -130, -176 -- the first line (where the 1.15 one is), the second under its title
local LINE_W = 280
local BUTTON_COORDS = { 0, 0.625, 0, 0.6875 }

local addPage, charBox, charAccept, leftIcon, leftFriend, leftHead, leftText, rightIcon

local function GameAddFriend()
  local frame, entry, box = AddFriendFrame, AddFriendEntryFrame, AddFriendNameEditBox
  local accept, cancel = AddFriendEntryFrameAcceptButton, AddFriendEntryFrameCancelButton
  if frame and entry and box and accept and cancel then return frame, entry, box, accept, cancel end
end

-- The 1.x red button (the 1.15 window's)
local function PanelLook(button)
  for _, part in ipairs({ { "Normal", "Up" }, { "Pushed", "Down" }, { "Disabled", "Disabled" }, { "Highlight", "Highlight" } }) do
    local state, file = part[1], part[2]
    button["Set" .. state .. "Texture"](button, "Interface\\Buttons\\UI-Panel-Button-" .. file)
    local tex = button["Get" .. state .. "Texture"](button)
    if tex then tex:SetTexCoord(unpack(BUTTON_COORDS)) end
  end
  local tex = button:GetHighlightTexture()
  if tex and tex.SetBlendMode then tex:SetBlendMode("ADD") end
end

-- The 1.x box border (Common-Input-Border), on the box's three pieces
local function InputLook(box, left, right, middle)
  local file = "Interface\\Common\\Common-Input-Border"
  left:SetTexture(file)
  left:SetTexCoord(0, 0.0625, 0, 0.625)
  left:ClearAllPoints()
  left:SetWidth(8)
  left:SetPoint("TOPLEFT", box, "TOPLEFT", -5, 0)
  left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -5, 0)
  right:SetTexture(file)
  right:SetTexCoord(0.9375, 1, 0, 0.625)
  right:ClearAllPoints()
  right:SetWidth(8)
  right:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
  middle:SetTexture(file)
  middle:SetTexCoord(0.0625, 0.9375, 0, 0.625)
  middle:ClearAllPoints()
  middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
  middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end

local function TopText()
  local box = AddFriendNameEditBox
  local ok, text = pcall(function() return box:GetText() end)
  return ok and type(text) == "string" and not issecret(text) and text or ""
end

-- The game's Add Friend button while the top line has text (its own state: the game's), ours for the bottom one
local function AddButtons()
  if not addPage then return end
  local _, _, _, accept = GameAddFriend()
  local top = TopText() ~= ""
  accept:SetShown(top)
  charAccept:SetShown(not top)
  charAccept:SetEnabled(Normal(charBox:GetText()) ~= nil)
end

-- The bottom line's character added (and the window shut when the top line is empty and it asks to)
local function AddCharacter(close)
  if not charBox then return false end
  local text = charBox:GetText()
  if not Normal(text) then return false end
  charBox:SetText("")
  CFL.Add(text)
  if close and TopText() == "" and AddFriendFrame and AddFriendFrame:IsShown() then
    if StaticPopupSpecial_Hide then StaticPopupSpecial_Hide(AddFriendFrame) else AddFriendFrame:Hide() end
  end
  AddButtons()
  return true
end
CFL.AddCharacter = AddCharacter

-- The left column as the game wrote its own (BattleTag or Real ID, or Battle.net unavailable in red)
local function MirrorLeft()
  local entry = AddFriendEntryFrame
  local holder = entry and entry.OptionsContainer and entry.OptionsContainer.LeftTextContainer
  if not (holder and leftHead) then return end
  local ok, title, desc, alpha, r, g, b = pcall(function()
    local r, g, b = holder.Description:GetTextColor()
    return holder.Title:GetText(), holder.Description:GetText(), holder.Title:GetAlpha(), r, g, b
  end)
  if not ok then return end
  if type(title) == "string" and not issecret(title) and title ~= "" then leftHead:SetText(title) end
  if type(desc) == "string" and not issecret(desc) then leftText:SetText(desc) end
  leftHead:SetAlpha(type(alpha) == "number" and alpha or 1)
  if type(r) == "number" then leftText:SetTextColor(r, g, b) end
  local grey = type(alpha) == "number" and alpha < 1 and 0.4 or 1
  leftIcon:SetVertexColor(grey, grey, grey)
  leftFriend:SetVertexColor(grey, grey, grey)
end

-- Each time the entry page shows: the game's border and cross off (the page has its own), the faction icon,
-- the left column, the bottom line empty, the button's 1.x text
local function DressShown()
  local frame, entry, _, accept = GameAddFriend()
  if not (frame and addPage) then return end
  local level = entry:GetFrameLevel()
  addPage:SetFrameLevel(level)
  charBox:SetFrameLevel(level + 2)
  charAccept:SetFrameLevel(level + 2)
  if frame.Border then frame.Border:Hide() end
  if frame.CloseButton then frame.CloseButton:Hide() end
  local faction = UnitFactionGroup("player")
  if faction == "Alliance" or faction == "Horde" then
    rightIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-" .. faction)
    rightIcon:Show()
  else
    rightIcon:Hide()
  end
  charBox:SetText("")
  MirrorLeft()
  accept:SetText(ADD_FRIEND or "Add Friend")
  AddButtons()
end

-- The "?" page (the game's): its border and cross back
local function Undress()
  local frame = AddFriendFrame
  if not frame then return end
  if frame.Border then frame.Border:Show() end
  if frame.CloseButton then frame.CloseButton:Show() end
end

local function Column(page, file, point, x)
  local icon = page:CreateTexture(nil, "BORDER")
  icon:SetTexture(file)
  icon:SetSize(40, 40)
  icon:SetAlpha(0.5)
  icon:SetPoint(point, page, point, x, -50)
  local friend = page:CreateTexture(nil, "ARTWORK")
  friend:SetTexture("Interface\\FriendsFrame\\PlusManz-PlusManz")
  friend:SetSize(36, 36)
  friend:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", -10, -4)
  local head = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  head:SetPoint("TOP", friend, "BOTTOM", 8, 4)
  local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  text:SetPoint("TOP", head, "BOTTOM", 0, -4)
  text:SetWidth(160)
  text:SetJustifyH("CENTER")
  return icon, friend, head, text
end

local function MakeCharBox(page, gameBox)
  local box = CreateFrame("EditBox", "ClassicFriendsListCharacterBox", page, "AutoCompleteEditBoxTemplate")
  box:SetSize(LINE_W, 20)
  box:SetPoint("TOP", page, "TOP", 0, LINE2_Y)
  box:SetAutoFocus(false)
  box:SetMaxLetters(NAME_MAX)
  local font = gameBox.GetFontObject and gameBox:GetFontObject()
  box:SetFontObject(font or GameFontHighlightSmall)
  InputLook(box, box:CreateTexture(nil, "BACKGROUND"), box:CreateTexture(nil, "BACKGROUND"), box:CreateTexture(nil, "BACKGROUND"))
  local gameFill = AddFriendNameEditBoxFill
  local fill = box:CreateFontString(nil, "BORDER", "GameFontDisableSmall")
  local fillFont = gameFill and gameFill.GetFontObject and gameFill:GetFontObject()
  if fillFont then fill:SetFontObject(fillFont) end
  fill:SetPoint("LEFT", box, "LEFT", 0, 0)
  fill:SetText(L.FILL)
  box.fill = fill
  -- its title, above it: the addon's line
  local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 3)
  title:SetText(L.LINE_TITLE)
  box.title = title
  local choices = AUTOCOMPLETE_LIST and AUTOCOMPLETE_LIST.MAIL
  if AutoCompleteEditBox_SetAutoCompleteSource and C_AutoComplete and choices then
    AutoCompleteEditBox_SetAutoCompleteSource(box, C_AutoComplete.GetAutoCompleteResults, choices.include, choices.exclude)
    box.addHighlightedText = true
  end
  box:SetScript("OnEnterPressed", function(self)
    if AutoCompleteEditBox_OnEnterPressed and AutoCompleteEditBox_OnEnterPressed(self) then return end
    AddCharacter(true)
  end)
  box:SetScript("OnTextChanged", function(self, userInput)
    if AutoCompleteEditBox_OnTextChanged then AutoCompleteEditBox_OnTextChanged(self, userInput) end
    self.fill:SetShown(self:GetText() == "")
    AddButtons()
  end)
  box:SetScript("OnTabPressed", function(self)
    if AutoCompleteEditBox_OnTabPressed and AutoCompleteEditBox_OnTabPressed(self) then return end
    gameBox:SetFocus()
  end)
  box:SetScript("OnEscapePressed", function(self)
    if AutoCompleteEditBox_OnEscapePressed and AutoCompleteEditBox_OnEscapePressed(self) then return end
    self:ClearFocus()
  end)
  box:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L.LINE_TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.TIP, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  box:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return box
end

local function MakeAddPage(frame, entry, box, accept, cancel)
  local page = CreateFrame("Frame", "ClassicFriendsListAddPage", entry, "BackdropTemplate")
  page:SetSize(ADD_W, ADD_H)
  page:SetPoint("TOP", frame, "TOP", 0, 0)
  page:EnableMouse(true)
  if page.SetBackdrop then
    page:SetBackdrop(BACKDROP_DIALOG_32_32 or {
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileEdge = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", page, "TOP", -12, -24)
  title:SetText(ADD_FRIEND or "Add Friend")
  local orLabel = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  orLabel:SetPoint("TOP", page, "TOP", 0, -66)
  orLabel:SetText(OR_CAPS or "OR")
  orLabel:SetTextColor(1, 1, 1)
  leftIcon, leftFriend, leftHead, leftText = Column(page, "Interface\\FriendsFrame\\PlusManz-BattleNet", "TOPLEFT", 92)
  leftHead:SetText(BATTLETAG_LABEL or "BattleTag")
  local rightHead, rightText
  rightIcon, rightHead, rightText = (function()
    local icon, _, head, text = Column(page, "Interface\\FriendsFrame\\PlusManz-Alliance", "TOPRIGHT", -82)
    return icon, head, text
  end)()
  rightHead:SetText(CHARACTER_FRIEND or "Character")
  rightText:SetText(L.CLASSIC)

  -- the game's parts: its "?" by the title, its box the top line, its two buttons at the 1.15 spots
  local info = AddFriendEntryFrameInfoButton
  if info then
    info:ClearAllPoints()
    info:SetPoint("LEFT", title, "RIGHT", 8, 0)
  end
  box:ClearAllPoints()
  box:SetPoint("TOP", page, "TOP", 0, LINE_Y)
  box:SetWidth(LINE_W)
  if box.Left and box.Right and AddFriendNameEditBoxMiddle then InputLook(box, box.Left, box.Right, AddFriendNameEditBoxMiddle) end
  accept:ClearAllPoints()
  accept:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 45, 30)
  accept:SetSize(118, 22)
  PanelLook(accept)
  cancel:ClearAllPoints()
  cancel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -50, 30)
  cancel:SetSize(118, 22)
  PanelLook(cancel)
  local hide = { entry.TitleContainer, entry.OptionsContainer, entry.EditBoxContainer and entry.EditBoxContainer.RequestInfoText }
  for i = 1, 3 do if hide[i] then hide[i]:Hide() end end

  addPage = page
  charBox = MakeCharBox(page, box)
  local errorText = entry.EditBoxContainer and entry.EditBoxContainer.ErrorMessage
  if errorText then
    errorText:ClearAllPoints()
    errorText:SetPoint("TOP", charBox, "BOTTOM", 0, -6)
  end
  charAccept = CreateFrame("Button", "ClassicFriendsListCharacterButton", page)
  charAccept:SetNormalFontObject(GameFontNormal)
  charAccept:SetHighlightFontObject(GameFontHighlight)
  charAccept:SetDisabledFontObject(GameFontDisable)
  charAccept:SetText(ADD_FRIEND or "Add Friend")
  charAccept:SetSize(118, 22)
  charAccept:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 45, 30)
  PanelLook(charAccept)
  charAccept:SetScript("OnClick", function() AddCharacter(true) end)
  CFL.addPage, CFL.charBox, CFL.charAccept = page, charBox, charAccept
end

-- Once: the page made, the game's window hooked (after its own code each time: nothing of it changed)
function CFL.DressAddFriend()
  if addPage then return true end
  local frame, entry, box, accept, cancel = GameAddFriend()
  if not frame then return false end
  MakeAddPage(frame, entry, box, accept, cancel)
  entry:HookScript("OnShow", DressShown)
  entry:HookScript("OnHide", Undress)
  box:HookScript("OnTextChanged", AddButtons)
  box:HookScript("OnTabPressed", function()
    if not (AutoCompleteBox and AutoCompleteBox:IsShown()) then charBox:SetFocus() end
  end)
  -- (both lines typed: the game's Add Friend or Enter sends the top one, the bottom one added after it)
  accept:HookScript("OnClick", function() AddCharacter(false) end)
  if AddFriendFrame_Accept then hooksecurefunc("AddFriendFrame_Accept", function() AddCharacter(false) end) end
  if AddFriendFrame_Show then hooksecurefunc("AddFriendFrame_Show", MirrorLeft) end
  if AddFriendEntryFrame_Init then
    hooksecurefunc("AddFriendEntryFrame_Init", function() accept:SetText(ADD_FRIEND or "Add Friend") end)
  end
  if entry:IsVisible() then DressShown() end
  return true
end

---------------------------------------------------------------------------
-- The list: the characters above the offline Battle.net friends
---------------------------------------------------------------------------
local function OfflineBNet(id)
  if not (C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return false end
  local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, id)
  if not ok or type(info) ~= "table" or info.isFavorite then return false end
  local game = info.gameAccountInfo
  return not (game and game.isOnline)
end

-- One the game lists itself (a character friend of another account): left where the game puts it.
local function GameFriend(name)
  if not (C_FriendList and C_FriendList.GetFriendInfo) then return false end
  local ok, info = pcall(C_FriendList.GetFriendInfo, name)
  return ok and type(info) == "table"
end

function CFL.AddToList()
  local frame = FriendsListFrame
  local box = frame and frame.ScrollBox
  if off or not (box and box.GetDataProvider and frame:IsShown()) then return 0 end
  local data = box:GetDataProvider()
  if not data then return 0 end
  local alts = {}
  for _, alt in ipairs(Sorted()) do
    if not GameFriend(alt.name) then alts[#alts + 1] = alt end
  end
  if #alts == 0 then return 0 end
  local BNET, DIVIDER = FRIENDS_BUTTON_TYPE_BNET, FRIENDS_BUTTON_TYPE_DIVIDER
  local size = data:GetSize()
  local at
  for i = 1, size do
    local entry = data:Find(i)
    if entry and entry.buttonType == BNET and OfflineBNet(entry.id) then at = i break end
  end
  local block = {}
  if not at then
    local last = size > 0 and data:Find(size)
    if last and last.buttonType ~= DIVIDER then block[#block + 1] = { buttonType = DIVIDER } end
    at = size + 1
  end
  for i, alt in ipairs(alts) do block[#block + 1] = { id = i, buttonType = TYPE, alt = alt } end
  if at <= size then block[#block + 1] = { buttonType = DIVIDER } end -- (then the offline Battle.net friends)
  for k, entry in ipairs(block) do data:InsertAtIndex(entry, at + k - 1) end
  return #alts
end

function CFL.Refresh()
  if FriendsListFrame and FriendsListFrame:IsShown() and FriendsList_Update then FriendsList_Update(true) end
  if CFL.SocialRefresh then CFL.SocialRefresh() end
end

---------------------------------------------------------------------------
-- A row: the game's friend row, drawn here; the mouse on a layer of ours (the game's own scripts read
-- its friends only)
---------------------------------------------------------------------------
local function Tip(catcher)
  local alt = catcher.alt
  if not alt then return end
  local facts = CFL.Facts(alt.name)
  GameTooltip:SetOwner(catcher, "ANCHOR_RIGHT")
  GameTooltip:SetText(alt.name, 1, 0.82, 0)
  if facts.level and facts.class then
    GameTooltip:AddLine((FRIENDS_LEVEL_TEMPLATE or "Level %d %s"):format(facts.level, ClassName(facts.class)), 1, 1, 1)
  end
  if CFL.Online(alt.name) then
    GameTooltip:AddLine(facts.zone or L.ONLINE, 0.2, 1, 0.2)
  else
    GameTooltip:AddLine(Ago(facts.at) or FRIENDS_LIST_OFFLINE or "Offline", 0.6, 0.6, 0.6)
  end
  GameTooltip:AddLine(L.ROW_HINT, 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function Menu(catcher)
  local alt = catcher.alt
  if not (alt and MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(catcher, function(_, root)
    root:CreateTitle(alt.name)
    if not IsMe(alt.name) then
      root:CreateButton(WHISPER or "Whisper", function()
        local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if tell then tell(alt.name) end
      end)
      root:CreateButton(PARTY_INVITE or INVITE or "Invite", function()
        local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if invite then invite(alt.name) end
      end)
    end
    root:CreateButton(L.REMOVE, function() CFL.Remove(alt.name) end)
  end)
end

local function Catcher(button)
  local catcher = button.classicFriend
  if catcher then return catcher end
  catcher = CreateFrame("Button", nil, button)
  catcher:SetAllPoints(button)
  catcher:SetFrameLevel(button:GetFrameLevel() + 10)
  catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  catcher:SetScript("OnEnter", function(self)
    if button.LockHighlight then button:LockHighlight() end
    Tip(self)
  end)
  catcher:SetScript("OnLeave", function()
    if button.UnlockHighlight then button:UnlockHighlight() end
    GameTooltip:Hide()
  end)
  catcher:SetScript("OnClick", function(self, which) if which == "RightButton" then Menu(self) end end)
  button.classicFriend = catcher
  return catcher
end
CFL.Catcher = Catcher

local function Color(color, alpha)
  if type(color) == "table" and color.GetRGBA then return color:GetRGBA() end
  return 0.588, 0.588, 0.588, alpha or 0.05
end

function CFL.DrawRow(button, entry)
  if not button then return end
  local alt = entry and entry.buttonType == TYPE and entry.alt
  if not alt then
    if button.classicFriend then button.classicFriend:Hide(); button.classicFriend.alt = nil end
    return
  end
  local online = CFL.Online(alt.name)
  local facts = CFL.Facts(alt.name)
  local nameText, info = alt.name, nil
  if online then
    if facts.level and facts.class then
      nameText = alt.name .. ", " .. (FRIENDS_LEVEL_TEMPLATE or "Level %d %s"):format(facts.level, ClassName(facts.class))
    end
    info = facts.zone or L.ONLINE
  else
    info = Ago(facts.at) or FRIENDS_LIST_OFFLINE or "Offline"
  end
  if button.background then
    button.background:SetColorTexture(Color(online and FRIENDS_WOW_BACKGROUND_COLOR or FRIENDS_OFFLINE_BACKGROUND_COLOR))
  end
  if button.status then
    button.status:SetTexture(online and (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")
      or (FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline"))
  end
  if button.name then
    button.name:SetText(nameText)
    local r, g, b = Color(online and FRIENDS_WOW_NAME_COLOR or FRIENDS_GRAY_COLOR)
    if not online and not FRIENDS_GRAY_COLOR then r, g, b = 0.486, 0.518, 0.541 end
    button.name:SetTextColor(r, g, b)
  end
  if button.info then button.info:SetText(info) end
  for _, key in ipairs({ "gameIcon", "travelPassButton", "summonButton", "Favorite" }) do
    if button[key] then button[key]:Hide() end
  end
  button:Show()
  local catcher = Catcher(button)
  catcher.alt = alt
  catcher:Show()
end

-- The game's own list update and rows
local hooked = false
local function Hook()
  if hooked or not FriendsFrame then return end
  hooked = true
  if FriendsList_Update then hooksecurefunc("FriendsList_Update", function() CFL.AddToList() end) end
  if FriendsFrame_UpdateFriendButton then
    hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button, entry) CFL.DrawRow(button, entry) end)
  end
end

---------------------------------------------------------------------------
-- The game's new social window (WoW Forever's friends window when its server turns it on: the default UI's). Its own
-- list is left alone: a line of an addon's in it, and the game refuses it its own friend search after ("blocked").
-- The characters show beside it instead, in a panel of ours along its right side while its friends page shows, in the
-- 1.x list's look: online first, "Name, Level 26 Priest" and the zone, or grey with when last seen; the tooltip and
-- right-click menu of the list; the mouse wheel scrolls it.
---------------------------------------------------------------------------
local PANEL_W, ROW_H, HEAD_H, PANEL_GAP = 300, 34, 34, 72
local panel, panelRows, panelOffset = nil, {}, 0

local function SocialPage() return SocialUIFrame and SocialUIFrame.FriendsList end

local function PanelRow(i)
  local row = panelRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, panel)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -HEAD_H - (i - 1) * (ROW_H + 2))
  row:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
  row.background = row:CreateTexture(nil, "BACKGROUND")
  row.background:SetAllPoints()
  row.status = row:CreateTexture(nil, "ARTWORK")
  row.status:SetSize(16, 16)
  row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
  row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  row.name:SetPoint("TOPLEFT", row.status, "TOPRIGHT", 4, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.name:SetJustifyH("LEFT")
  row.info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
  row.info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.info:SetJustifyH("LEFT")
  row.info:SetTextColor(0.486, 0.518, 0.541)
  panelRows[i] = row
  return row
end

local function UpdatePanel()
  local page = SocialPage()
  if not (panel and page and page:IsVisible()) or off then
    if panel then panel:Hide() end
    return
  end
  local alts, online = {}, 0
  for _, alt in ipairs(Sorted()) do
    if not GameFriend(alt.name) then
      alts[#alts + 1] = alt
      if CFL.Online(alt.name) then online = online + 1 end
    end
  end
  if #alts == 0 then panel:Hide() return end
  panel.title:SetText(L.SOCIAL_HEADER:format(online, #alts))
  local height = panel:GetHeight()
  local fits = math.max(1, math.floor(((height and height > 0 and height or 400) - HEAD_H - 12) / (ROW_H + 2)))
  panelOffset = math.max(0, math.min(panelOffset, #alts - fits))
  for i = 1, math.max(fits, #panelRows) do
    local alt = i <= fits and alts[i + panelOffset]
    if alt then
      CFL.DrawRow(PanelRow(i), { buttonType = TYPE, alt = alt })
    elseif panelRows[i] then
      panelRows[i]:Hide()
    end
  end
  panel:Show()
end

function CFL.SocialRefresh() if panel then UpdatePanel() end end

function CFL.HookSocial()
  if panel then return true end
  local page = SocialPage()
  if not (page and page.HookScript and SocialUIFrame) then return false end
  panel = CreateFrame("Frame", "ClassicFriendsListPanel", SocialUIFrame, "BackdropTemplate")
  panel:SetWidth(PANEL_W)
  panel:SetPoint("TOPLEFT", SocialUIFrame, "TOPRIGHT", PANEL_GAP, 0)
  panel:SetPoint("BOTTOMLEFT", SocialUIFrame, "BOTTOMRIGHT", PANEL_GAP, 0)
  panel:EnableMouse(true)
  panel:EnableMouseWheel(true)
  if panel.SetBackdrop then
    panel:SetBackdrop(BACKDROP_DARK_DIALOG_32_32 or BACKDROP_DIALOG_32_32 or {
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileEdge = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  panel.title:SetPoint("TOP", panel, "TOP", 0, -14)
  panel:SetScript("OnMouseWheel", function(_, delta)
    panelOffset = math.max(0, panelOffset - delta)
    UpdatePanel()
  end)
  panel:Hide()
  CFL.panel = panel
  page:HookScript("OnShow", UpdatePanel)
  page:HookScript("OnHide", function() panel:Hide() end)
  if page:IsVisible() then UpdatePanel() end
  return true
end

---------------------------------------------------------------------------
-- Coming and going: said in the chat as the game says it of a friend, the list redrawn
---------------------------------------------------------------------------
local wasOnline = {} -- lower-case whole name -> online when last looked
local settled = false -- (the first moments after login: the ones already online heard, not announced)
local function Announce(alt, online)
  local frame = DEFAULT_CHAT_FRAME
  if not (frame and frame.AddMessage) then return end
  local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
  local r, g, b = info and info.r or 1, info and info.g or 1, info and info.b or 0
  local text
  if online then
    text = (ERR_FRIEND_ONLINE_SS or "|Hplayer:%s|h[%s]|h has come online."):format(alt.name, alt.name)
  else
    text = (ERR_FRIEND_OFFLINE_S or "%s has gone offline."):format(alt.name)
  end
  frame:AddMessage(text, r, g, b)
end
local function Look(announce)
  local changed = false
  for key, alt in pairs(List() or {}) do
    if not IsMe(alt.name) and CFL.Known(alt.name) then
      local on = CFL.Online(alt.name) and true or false
      if wasOnline[key] ~= nil and wasOnline[key] ~= on then
        changed = true
        if announce and settled then Announce(alt, on) end
      end
      wasOnline[key] = on
    end
  end
  if changed then CFL.Refresh() end
end
CFL.Look = Look

---------------------------------------------------------------------------
-- Online or not, for any character. The addon asks the server, one character a second (each one every 10
-- seconds, every 3 while the friends list is open, at once as it opens), with an addon message whispered to it,
-- which its player never sees: offline (or unknown, or of the other faction) the server answers "No player named
-- ... is currently playing" (that line hidden from the chat when it answers our question); online it says nothing
-- for 2 seconds. A character heard in the chat is online at once. Between two players with this addon or Clara
-- (the same messages: "ClaraFriends") that have each other in their lists it is at once both ways: the question is
-- a hello (asked of everyone at login, the first 8 at once), the answer comes with its level, class and zone, and a
-- goodbye goes at logout (not at a reload). Not asked: the character played now.
---------------------------------------------------------------------------
local PROBE_PREFIX = "ClaraFriends" -- (Clara's own: the two speak together)
local PROBE_EVERY = 1     -- seconds between two questions
local PROBE_ROUND = 10    -- seconds at least between two questions to the same character
local PROBE_ROUND_OPEN = 3 -- the same while the friends list is open
local PROBE_WAIT = 2      -- seconds without the server's "no player named": online
local PROBE_BURST = 8     -- questions asked at once at login, goodbyes said at once at logout
local PROBE_HIDE = 10     -- seconds the server's answer to a question is hidden from the chat (a late one too)
local PROBE_SETTLE = 3    -- seconds after the world shows before asking (answers held in a loading screen came late)
local pausedUntil = math.huge -- (no question before the world shows)
local REPLY_EVERY = 2     -- seconds at least between two answers to the same asker (its hello answered at once)
local replied = {}        -- Key(name) -> when answered last
local hideUntil = {}      -- Key(name) -> until when the server's answer to our question is hidden
local hiddenText, hiddenUntil -- (one answer shown by several chat windows: hidden in each)
local lastAsked = 0

-- The list's character a name points to: by its whole name; a first name alone (no surname heard), the one
-- character of the list with that first name
local function Listed(key)
  local byFirst, count = nil, 0
  for _, alt in pairs(List() or {}) do
    local own = Key(alt.name)
    if own == key then return alt, own end
    if not key:find(" ", 1, true) and GameName(own) == key then byFirst, count = alt, count + 1 end
  end
  if count == 1 then return byFirst, Key(byFirst.name) end
end

-- The name as the game writes it, from a name heard whole (its sender's): "Melbeline moon" typed, "Melbeline Moon" heard
local function Respell(alt, heard)
  if issecret(heard) or type(heard) ~= "string" then return end
  local proper = ((heard:match("^([^%-]+)") or heard):gsub("^%s+", ""):gsub("%s+$", ""))
  if proper ~= alt.name and proper:lower() == alt.name:lower() then
    alt.name = proper
    CFL.Refresh()
  end
end

local function SetVerdict(key, online)
  local p = probes[key] or {}
  probes[key] = p
  p.sent = nil
  local changed = p.verdict ~= online
  p.verdict, p.at = online, GetTime()
  local alt = Listed(key)
  if online and alt and time then alt.seen = time() end
  if changed then Look(true) end
end
CFL.SetVerdict = SetVerdict

local function Whisper(to, text)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PROBE_PREFIX, text, "WHISPER", to)
  if not ok then return false end
  local codes = Enum and Enum.SendAddonMessageResult
  if result == 12 or (codes and codes.TargetOffline ~= nil and result == codes.TargetOffline) then return false, true end
  local success = codes and codes.Success
  return result == nil or result == true or result == 0 or (success ~= nil and result == success)
end

local function ListOpen()
  return (FriendsFrame ~= nil and FriendsFrame:IsVisible()) or (SocialUIFrame ~= nil and SocialUIFrame:IsVisible()) or false
end

-- One question to one character; false when the game refused to send it now (throttled: asked again later)
local function AskOne(alt, now)
  local key = Key(alt.name)
  local p = probes[key] or {}
  probes[key] = p
  local sent, offline = Whisper(alt.name, "?")
  if sent then
    p.tried, p.sent = now, now
    hideUntil[key] = now + PROBE_HIDE
  elseif offline then -- (the game said so at once)
    p.tried = now
    SetVerdict(key, false)
  else
    return false
  end
  return true
end

-- The characters to ask, the longest unasked first
local function Due(now, round)
  local due = {}
  for _, alt in pairs(List() or {}) do
    if not IsMe(alt.name) then
      local p = probes[Key(alt.name)]
      local last = p and p.tried or 0
      if not (p and p.sent) and now - last >= round then due[#due + 1] = { alt = alt, last = last } end
    end
  end
  -- (the ones with the addon first: their hello and answer are the fast ones)
  table.sort(due, function(a, b)
    if (a.alt.clara and true or false) ~= (b.alt.clara and true or false) then return a.alt.clara == true end
    return a.last < b.last
  end)
  return due
end

local function AskServer()
  local now = GetTime()
  for key, p in pairs(probes) do
    if p.sent and now - p.sent >= PROBE_WAIT then SetVerdict(key, true) end
  end
  if now - lastAsked < PROBE_EVERY or now < pausedUntil then return end
  local due = Due(now, ListOpen() and PROBE_ROUND_OPEN or PROBE_ROUND)
  if due[1] then
    if AskOne(due[1].alt, now) then lastAsked = now else lastAsked = now + 2 end -- (refused: a short pause)
  end
end
CFL.AskServer = AskServer

-- Everyone asked again at once (login, the friends list opened): the first PROBE_BURST now, the rest a second each
local function AskAll()
  local now = GetTime()
  for _, p in pairs(probes) do if not p.sent then p.tried = 0 end end
  for i, entry in ipairs(Due(now, 0)) do
    if i > PROBE_BURST or not AskOne(entry.alt, now) then break end
  end
  lastAsked = now
end
CFL.AskAll = AskAll

-- The ones known to have the addon greeted the moment the world shows (theirs shows this character online at once,
-- and answers at once): the rest are asked a moment later, when the server's answers come in time
local function Hello()
  local now, n = GetTime(), 0
  for _, alt in pairs(List() or {}) do
    if n >= PROBE_BURST then break end
    if alt.clara and not IsMe(alt.name) then
      local p = probes[Key(alt.name)]
      if not (p and p.sent) and AskOne(alt, now) then n = n + 1 end
    end
  end
end

-- At logout, a goodbye to the ones online (theirs shows this character offline at once); not at a reload
local reloading = false
local function Goodbye()
  if reloading then return end
  local n = 0
  for _, alt in pairs(List() or {}) do
    if n >= PROBE_BURST then break end
    if alt.clara and not IsMe(alt.name) and CFL.Online(alt.name) then -- (only the addon hears it)
      Whisper(alt.name, "!")
      n = n + 1
    end
  end
end

-- The name in the server's "No player named '%s' is currently playing", as Key gives it
local notFound
local function NotFoundName(text)
  if issecret(text) or type(text) ~= "string" or type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return nil end
  if not notFound then
    local escaped = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    notFound = "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
  end
  local name = text:match(notFound)
  return name and Key(name)
end

local function HideOurs(_, _, text, ...)
  if off then return false end
  local now = GetTime()
  if text == hiddenText and hiddenUntil and now <= hiddenUntil then return true end
  local key = NotFoundName(text)
  if key and hideUntil[key] and now <= hideUntil[key] then
    hideUntil[key] = nil
    hiddenText, hiddenUntil = text, now + 1
    return true
  end
  return false
end

local function Answer(sender)
  local level = UnitLevel and UnitLevel("player") or 0
  local _, class = UnitClass("player")
  local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
  if issecret(zone) or type(zone) ~= "string" then zone = "" end
  Whisper(sender, ("I|%d|%s|%s"):format(tonumber(level) or 0, class or "", (zone:gsub("|", ""))))
end

local CHAT_PRESENCE = { "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }

local probeEvents = CreateFrame("Frame")
probeEvents:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if event == "PLAYER_LOGOUT" then
    Goodbye()
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- A loading screen held the answers: the questions then unanswered are asked again, a moment after the world
    -- shows (everyone at once after a login or reload), not taken for online.
    for _, p in pairs(probes) do p.sent = nil end
    pausedUntil = GetTime() + PROBE_SETTLE
    if a1 or a2 then
      Hello()
      C_Timer.After(PROBE_SETTLE, AskAll)
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    local key = NotFoundName(a1)
    if not key then return end
    local alt, own = Listed(key)
    if alt then SetVerdict(own, false) end
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, text, channel, sender = a1, a2, a3, a4
    if prefix ~= PROBE_PREFIX or channel ~= "WHISPER" then return end
    if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    local alt, own = Listed(Key(sender))
    if not alt then return end -- (only the characters in this list: answered and heard)
    Respell(alt, sender)
    alt.clara = true -- (it has the addon or Clara: greeted first, told goodbye)
    if text == "!" then SetVerdict(own, false) return end -- (its goodbye)
    SetVerdict(own, true)
    if text == "?" then
      local now = GetTime()
      if replied[own] and now - replied[own] < REPLY_EVERY then return end
      replied[own] = now
      Answer(sender)
    else
      local level, class, zone = text:match("^I|(%d+)|(%u*)|(.*)$")
      if level then
        alt.level, alt.class, alt.zone = tonumber(level), class ~= "" and class or nil, zone ~= "" and zone or nil
        alt.levelAt = time and time() or nil
        CFL.Refresh()
      end
    end
  else -- heard in the chat
    if issecret(a2) or type(a2) ~= "string" or a2 == "" then return end
    local alt, own = Listed(Key(a2))
    if alt then
      Respell(alt, a2)
      SetVerdict(own, true)
    end
  end
end)

local probing = false
local function StartProbes()
  if probing then return end
  probing = true
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PROBE_PREFIX) end
  probeEvents:RegisterEvent("CHAT_MSG_SYSTEM")
  probeEvents:RegisterEvent("CHAT_MSG_ADDON")
  for _, event in ipairs(CHAT_PRESENCE) do probeEvents:RegisterEvent(event) end
  local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if AddFilter then AddFilter("CHAT_MSG_SYSTEM", HideOurs) end
  probeEvents:RegisterEvent("PLAYER_LOGOUT")
  if type(ReloadUI) == "function" then hooksecurefunc("ReloadUI", function() reloading = true end) end
  if C_UI and type(C_UI.Reload) == "function" then hooksecurefunc(C_UI, "Reload", function() reloading = true end) end
  if FriendsFrame and FriendsFrame.HookScript then
    FriendsFrame:HookScript("OnShow", function() if GetTime() >= pausedUntil then AskAll() end end)
  end
  if SocialUIFrame and SocialUIFrame.HookScript then
    SocialUIFrame:HookScript("OnShow", function() if GetTime() >= pausedUntil then AskAll() end end)
  end
  probeEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  C_Timer.NewTicker(1, AskServer)
end

---------------------------------------------------------------------------
-- /rl: the interface reloaded (as /reload); with Clara loaded too
---------------------------------------------------------------------------
SLASH_CLASSICFRIENDSLISTRELOAD1 = "/rl"
SlashCmdList.CLASSICFRIENDSLISTRELOAD = function()
  if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end

---------------------------------------------------------------------------
-- /cfl add First Surname, /cfl remove First Surname, /cfl list
---------------------------------------------------------------------------
SLASH_CLASSICFRIENDSLIST1 = "/cfl"
SLASH_CLASSICFRIENDSLIST2 = "/classicfriendslist"
SlashCmdList.CLASSICFRIENDSLIST = function(msg)
  if off then SaySystem(L.CLARA) return end
  local word, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  word = (word or ""):lower()
  if word == "add" and rest ~= "" then
    CFL.Add(rest)
  elseif (word == "remove" or word == "del") and rest ~= "" then
    CFL.Remove(rest)
  elseif word == "list" then
    local all = Sorted()
    if #all == 0 then SaySystem(L.LIST_EMPTY) return end
    SaySystem(L.LIST_HEAD:format(#all))
    for _, alt in ipairs(all) do
      SaySystem("  " .. alt.name .. " - " .. (CFL.Online(alt.name) and L.ONLINE or (FRIENDS_LIST_OFFLINE or "Offline")))
    end
  else
    SaySystem(L.HELP)
  end
end

---------------------------------------------------------------------------
-- Start: the saved list at load; at login, off if Clara runs (it keeps the same list), else everything
---------------------------------------------------------------------------
local function ClaraLoaded()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  return loaded and loaded("ClaraComboPoints") and true or false
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" then
    if name ~= ADDON then return end
    if type(ClassicFriendsListDB) ~= "table" then ClassicFriendsListDB = {} end
    db = ClassicFriendsListDB
    List()
    return
  end
  self:UnregisterAllEvents()
  if ClaraLoaded() then
    off = true
    SaySystem(L.CLARA)
    return
  end
  startedAt = GetTime()
  if not db then
    if type(ClassicFriendsListDB) ~= "table" then ClassicFriendsListDB = {} end
    db = ClassicFriendsListDB
  end
  List()
  Hook()
  local dressed, social = CFL.DressAddFriend(), CFL.HookSocial()
  if not (dressed and social) then
    -- (the game's Add Friend window and its social window load with their friends windows: dressed as they come)
    local wait = CreateFrame("Frame")
    wait:RegisterEvent("ADDON_LOADED")
    wait:SetScript("OnEvent", function(waiter)
      dressed = dressed or CFL.DressAddFriend()
      social = social or CFL.HookSocial()
      if dressed and social then waiter:UnregisterAllEvents() end
    end)
  end
  Look(false)
  StartProbes()
  C_Timer.After(20, function() settled = true end)
  -- (one that left without a word: gone once not heard for a while)
  C_Timer.NewTicker(20, function() Look(true) end)
end)
