-- ClassicFriendsList - characters in the friends list, the classic way (WoW Forever). The server keeps no character
-- friends there (Battle.net friends only), and its list takes none of the account's own characters: this addon keeps
-- a list of characters instead (for the whole account: one's own and friends'), and shows them in the friends
-- window (WoW Forever's: in two sections of their own, online and offline, placed by the player; the older one: above
-- the offline Battle.net friends), in the game's look: online or offline (see "Online or not" below),
-- with their level, class and zone (from their own ClassicFriendsList or Clara) and when last seen. The game's Add
-- Friend window in the 1.15 look, with two lines: the game's (a BattleTag, or a name the Forever way) and the
-- addon's, that adds a character to this list. Over a row: its tooltip; right-click: invite, whisper or remove.
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
  -- (each word with its capital, as the game writes a name: "Elle woods" typed, "Elle Woods" kept). Its first letter
  -- whole: an accented one is two bytes ("é"), and the game's capitals, which read UTF-8, broke its first byte taken
  -- alone ("Miss ▯milia"); "émilia" typed, "Émilia" kept.
  name = (name:gsub("%S+", function(word)
    local first, rest = word:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
    if not first then return word end
    return first:upper() .. rest
  end))
  return name
end

-- A name the earlier capitals broke (its accented first letter cut in two, kept so: "Éclair" became "▯clair"): the
-- replacement sign in it, or bytes that are no UTF-8
local function Broken(name)
  if type(name) ~= "string" or issecret(name) then return false end
  if name:find("\239\191\189", 1, true) then return true end
  local i, n = 1, #name
  while i <= n do
    local b = name:byte(i)
    local len = b < 128 and 1 or (b >= 194 and b <= 223) and 2 or (b >= 224 and b <= 239) and 3 or (b >= 240 and b <= 244) and 4
    if not len then return true end
    for k = i + 1, i + len - 1 do
      local c = name:byte(k)
      if not c or c < 128 or c > 191 then return true end
    end
    i = i + len
  end
  return false
end
CFL.Broken = Broken
-- Its plain letters alone, lower-case (the accented ones, and what is left of a broken one, dropped): a broken name
-- and its whole spelling alike ("▯clair Chazal", "Éclair Chazal": "clair chazal")
local function Plain(name) return ((name:gsub("[\128-\255]", "")):lower()) end
-- A name kept without its accented letters (an earlier version dropped them: "Miss Émilia" kept as "Miss Milia"):
-- none of its own letters accented, the whole name's plain letters the same, first name and surname
local function LostAccents(kept, whole)
  return type(kept) == "string" and not kept:find("[\128-\255]") and whole:find("[\128-\255]") ~= nil
    and Plain(kept) == Plain(whole)
end

local function List()
  if not db then return nil end
  if type(db.friends) ~= "table" then db.friends = {} end
  local list, moved = db.friends, nil
  for key, alt in pairs(list) do
    if type(key) ~= "string" or type(alt) ~= "table" or type(alt.name) ~= "string" then list[key] = nil
    else
      -- (a broken name: its whole spelling back from its key, when that one is whole)
      if Broken(alt.name) and not Broken(key) and key:find("[\128-\255]") and Plain(key) == Plain(alt.name) then
        alt.name = key
      end
      if not Normal(alt.name) then list[key] = nil
      else
        alt.name = Normal(alt.name)
        if Broken(key) and not Broken(alt.name) then moved = moved or {}; moved[key] = alt end
      end
    end
  end
  -- (one kept under a broken key, its name whole: kept under its whole one)
  for key, alt in pairs(moved or {}) do
    list[key] = nil
    local whole = alt.name:lower()
    if not list[whole] then list[whole] = alt end
  end
  return list
end
CFL.List = List

-- A whole name seen or heard as the game writes it (a sender, a unit, a Battle.net friend's character, a character
-- known), or one of the names kept lower-case: one of the list whose name is broken takes it back, under its whole
-- name. Its first name and surname must match whole (their plain letters).
function CFL.Mend(heard)
  if issecret(heard) or type(heard) ~= "string" then return false end
  local proper = ((heard:match("^([^%-]+)") or heard):gsub("^%s+", ""):gsub("%s+$", ""))
  if proper == "" or not proper:find("[\128-\255]") or Broken(proper) then return false end
  local list = List()
  if not list then return false end
  local plain = Plain(proper)
  for key, alt in pairs(list) do
    if (Broken(alt.name) or LostAccents(alt.name, proper)) and Plain(alt.name) == plain then
      local name = Normal(proper)
      if not name then return false end
      list[key] = nil
      if not list[name:lower()] then list[name:lower()] = alt end
      alt.name = name
      if CFL.Refresh then CFL.Refresh() end
      return true
    end
  end
  return false
end

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

-- Its name typed again, whole (a name an earlier version broke or kept without its accents, never heard whole since:
-- "Miss Milia" renamed "Miss Émilia"); its place in the list and its section kept
function CFL.Rename(old, typed)
  local list = List()
  local name = Normal(typed)
  if not (list and name and type(old) == "string") then return false end
  local key, alt
  for k, a in pairs(list) do if a.name == old then key, alt = k, a break end end
  if not alt then return false end
  local new = name:lower()
  if new ~= key and list[new] then
    SaySystem((ERR_FRIEND_ALREADY_S or L.ALREADY):format(list[new].name))
    return false
  end
  list[key] = nil
  list[new] = alt
  alt.name = name
  CFL.Refresh()
  return true
end

-- The name typed in the game's own box (Enter or its button; Escape and Cancel close it)
local RENAME = "CLASSICFRIENDSLIST_RENAME"
local function AskName(alt)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  local function Box(dialog) return dialog and (dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())) end
  StaticPopupDialogs[RENAME] = StaticPopupDialogs[RENAME] or {
    text = "%s", button1 = L.RENAME, button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 32,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self, data)
      local box = Box(self)
      if box then box:SetText(data and data.name or ""); box:HighlightText(); box:SetFocus() end
    end,
    OnAccept = function(self, data)
      local box = Box(self)
      if data and box then CFL.Rename(data.name, box:GetText() or "") end
    end,
    EditBoxOnEnterPressed = function(box, data)
      if data then CFL.Rename(data.name, box:GetText() or "") end
      local dialog = box:GetParent()
      if dialog then dialog:Hide() end
    end,
    EditBoxOnEscapePressed = function(box) local dialog = box:GetParent(); if dialog then dialog:Hide() end end,
  }
  StaticPopup_Show(RENAME, L.RENAME_ASK, nil, { name = alt.name })
end
CFL.AskName = AskName -- (for the tests)

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

-- The server's answers (see "Online or not"): Key(name) -> { verdict = online, at, tried, sent, asked }
local probes = {}
local startedAt -- (GetTime at login)

function CFL.Online(name)
  if IsMe(name) then return true end
  if CFL.Elsewhere and CFL.Elsewhere(name) then return false end
  local p = probes[Key(name)]
  return p and p.verdict == true or false
end

-- Whether the addon knows yet if it is online: the server answered, or long enough since login
function CFL.Known(name)
  if IsMe(name) or (CFL.Elsewhere and CFL.Elsewhere(name)) then return true end
  local p = probes[Key(name)]
  if p and p.verdict ~= nil then return true end
  return startedAt ~= nil and GetTime() - startedAt > KNOWN_AFTER
end

-- Its sex (for the class's name, "Prêtresse" for a woman as the game says it since TBC): 2 male, 3 female, by
-- Key(name), for the whole account: one's own characters say theirs as they log in, a character's own addon says it
-- with its answer, the game tells it of one seen (in the chat, the group, the target, under the mouse)
local function Sexes()
  local store = db
  if type(store) ~= "table" then return nil end
  if type(store.sexes) ~= "table" then store.sexes = {} end
  return store.sexes
end
-- One's own characters' level and class, kept for the account as each logs in and levels up (another of them
-- shows its level and class, its class color, even before its addon answers)
local function Mine()
  if not db then return nil end
  if type(db.chars) ~= "table" then db.chars = {} end
  return db.chars
end
local function KeepMe(level)
  local me, mine = FullName(), Mine()
  if not (me and mine) then return end
  local _, class = UnitClass("player")
  mine[Key(me)] = { level = tonumber(level) or (UnitLevel and UnitLevel("player")), class = class, at = time and time() }
end
CFL.KeepMe = KeepMe

-- One of this WoW account's other characters (each kept as it logs in): never online while the player plays (a WoW
-- account plays one character at a time), never asked. (The player's other WoW accounts: Clara knows theirs, by its
-- gold tracker and its sync; this addon alone does not.)
local function OnThisAccount(name)
  if type(name) ~= "string" or IsMe(name) then return false end
  local mine = Mine()
  return mine ~= nil and mine[Key(name)] ~= nil
end
CFL.OnThisAccount = OnThisAccount
CFL.Elsewhere = OnThisAccount

-- The list's broken names mended from every whole name the addon knows: the characters seen (their sex kept), the
-- player's own, the Battle.net friends' characters in the game (nothing done while none is broken)
local function MendKnown()
  local any = false
  for _, alt in pairs(List() or {}) do
    if Broken(alt.name) or not alt.name:find("[\128-\255]") then any = true break end -- (broken, or perhaps its accents lost)
  end
  if not any then return end
  local names = {}
  for key in pairs(Sexes() or {}) do names[#names + 1] = key end
  for key in pairs(Mine() or {}) do names[#names + 1] = key end
  if C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
    local okCount, count = pcall(BNGetNumFriends)
    for i = 1, (okCount and type(count) == "number" and not issecret(count)) and count or 0 do
      local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
      local game = ok and type(info) == "table" and info.gameAccountInfo
      if type(game) == "table" then names[#names + 1] = game.characterName end
    end
  end
  for _, name in ipairs(names) do
    if type(name) == "string" then CFL.Mend(name) end
  end
end
CFL.MendKnown = MendKnown

local function SexOf(name)
  local sexes = Sexes()
  return sexes and sexes[Key(name)]
end

function CFL.Facts(name)
  local facts = {}
  if IsMe(name) then
    facts.level = UnitLevel and UnitLevel("player")
    facts.class = select(2, UnitClass("player"))
    facts.sex = UnitSex and UnitSex("player")
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
  local own = (Mine() or {})[Key(name)]
  if type(own) == "table" and not facts.level then facts.level, facts.class = own.level, own.class end
  facts.sex = (type(alt) == "table" and alt.sex) or SexOf(name)
  return facts
end

local function ClassName(class, sex)
  if not class then return nil end
  local names = sex == 3 and LOCALIZED_CLASS_NAMES_FEMALE or LOCALIZED_CLASS_NAMES_MALE
  return (names and names[class]) or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

-- A name in its class's color (the game's own class colors), when its class is known
local function ClassColored(text, class)
  if type(class) ~= "string" or class == "" then return text end
  local ok, color = pcall(function()
    return (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
      or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  end)
  if not ok or type(color) ~= "table" then return text end
  if color.WrapTextInColorCode then return color:WrapTextInColorCode(text) end
  if type(color.r) ~= "number" then return text end
  return ("|cff%02x%02x%02x%s|r"):format(math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5), text)
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
  -- (not forced: the game keeps where the list is scrolled to)
  if FriendsListFrame and FriendsListFrame:IsShown() and FriendsList_Update then FriendsList_Update() end
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
  GameTooltip:SetText(ClassColored(alt.name, facts.class), 1, 0.82, 0)
  if facts.level and facts.class then
    GameTooltip:AddLine((FRIENDS_LEVEL_TEMPLATE or "Level %d %s"):format(facts.level, ClassName(facts.class, facts.sex)), 1, 1, 1)
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
      -- (Invite first, then Whisper. In a group led by another, without being its assistant: Suggest Invite, as the
      -- game's own menus say it: the same invite, which the server hands to the leader; the group full: said so.)
      local suggest = IsInGroup and IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
      root:CreateButton(suggest and (SUGGEST_INVITE or "Suggest Invite") or (PARTY_INVITE or INVITE or "Invite"), function()
        if suggest and C_PartyInfo and C_PartyInfo.IsPartyFull and C_PartyInfo.IsPartyFull() then
          local say = ChatFrameUtil and ChatFrameUtil.DisplaySystemMessageInPrimary
          if say then say(ERR_GROUP_FULL or "Your party is full.") end
          return
        end
        local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if invite then invite(alt.name) end
      end)
      root:CreateButton(WHISPER or "Whisper", function()
        local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if tell then tell(alt.name) end
      end)
    end
    root:CreateButton(L.RENAME, function() AskName(alt) end)
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
      nameText = ClassColored(alt.name, facts.class) .. ", " .. (FRIENDS_LEVEL_TEMPLATE or "Level %d %s"):format(facts.level, ClassName(facts.class, facts.sex))
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
-- The game's new social window (WoW Forever's friends window when its server turns it on: the default UI's): the
-- characters in its friends list, in two sections of their own made as the game's own (a header, folded by a click
-- and kept so), "Characters online" and "Characters offline", on the game's cards. By default the ones online on top,
-- those offline after the Battle.net friends; the sections' order is the player's (see "The sections moved" below). Put in the list as the game builds
-- it, before it lays it out; what shows changing (a character online or gone, one added, a section moved) the list
-- is arranged again in place. The game's card-size cache, filled as it lays out our lines too, emptied after each
-- read (else the game would refuse its own friend search at its next refresh: an empty list). Each card drawn by the
-- game from what is known of the character; the mouse on a layer of ours (tooltip, right-click menu), the Battle.net
-- party and summon buttons hidden. The search box filters them too.
---------------------------------------------------------------------------
local HEADER_FAVORITES, HEADER_FRIENDS = 1, 2 -- (the game's FriendsListHeaderType: its two sections)
local SECTIONS = { "online", "favorites", "friends", "offline" } -- (all of them, in their first order: the ones online on top)
local OLD_FIRST = { "favorites", "friends", "online", "offline" } -- (the first order until 19 November: kept as it was, today's)
local BNET = { favorites = true, friends = true }
local OURS = { online = "cflOnline", offline = "cflOffline" } -- (our headers' types: the game keeps their fold)
local socialView
local socialNodes = { online = {}, offline = {} } -- (our cards in the list shown, per section, in order)
local socialFrames = {} -- (the cards drawn now with ours: frame -> node)
local arranged -- (the list last arranged here)

local function IndexOf(list, value)
  for i, v in ipairs(list) do if v == value then return i end end
  return nil
end

-- The sections' order and our sections' folds (ClassicFriendsListDB.friendSections, for the whole WoW account): each section once,
-- one unknown dropped, one missing put back at its first place
local function SectionStore()
  local sv = db
  if type(sv) ~= "table" then return nil end
  local store = sv.friendSections
  if type(store) ~= "table" then store = {}; sv.friendSections = store end
  local order = {}
  for _, key in ipairs(type(store.order) == "table" and store.order or {}) do
    if IndexOf(SECTIONS, key) and not IndexOf(order, key) then order[#order + 1] = key end
  end
  for i, key in ipairs(SECTIONS) do
    if not IndexOf(order, key) then table.insert(order, math.min(i, #order + 1), key) end
  end
  -- (the earlier first order, never changed: the characters online on top now, as the first order has them)
  if store.v ~= 2 then
    local same = #order == #OLD_FIRST
    for i, key in ipairs(OLD_FIRST) do same = same and order[i] == key end
    if same then order = { unpack(SECTIONS) } end
    store.v = 2
  end
  store.order = order
  if type(store.folded) ~= "table" then store.folded = {} end
  return store
end
CFL.SectionStore = SectionStore

-- What the game's card reads of a friend, for a character
local function SocialInfo(alt)
  local online = CFL.Online(alt.name)
  local facts = CFL.Facts(alt.name)
  -- All on the card's top line, as the 1.x list: "Name, Level 26 Priest", the name in its class color when online
  -- (the game wraps it in its own color: the class's, inside, shows); no character line (the name not twice); the
  -- zone or when last seen on the line under it
  local shown = alt.name
  if online then
    shown = ClassColored(alt.name, facts.class)
    if facts.level and facts.class then
      shown = shown .. ", " .. (FRIENDS_LEVEL_TEMPLATE or "Level %d %s"):format(facts.level, ClassName(facts.class, facts.sex))
    end
  end
  local character = nil
  local levels = Enum and Enum.BattleNetFriendLevel
  local raf = Enum and Enum.RafLinkType
  return {
    accountName = shown, battleTag = "", note = "", friendTags = {}, isFavorite = false, isAFK = false,
    isDND = false, customMessage = "", customMessageTime = 0, rafLinkType = raf and raf.None or 0,
    friendLevel = levels and levels.Title, lastOnlineTime = (not online and facts.at) or 0,
    gameAccountInfo = {
      isOnline = online, characterName = character, characterLevel = facts.level,
      className = facts.class and ClassName(facts.class, facts.sex) or nil, classFilename = facts.class,
      areaName = online and (facts.zone or L.ONLINE) or nil, richPresence = facts.zone,
      clientProgram = online and (BNET_CLIENT_WOW or "WoW") or "", wowProjectID = WOW_PROJECT_ID,
      factionName = UnitFactionGroup("player"), realmID = 0, isInCurrentRegion = true,
      isGameAFK = false, isGameBusy = false,
    },
  }
end

local function SocialMatches(alt)
  local bar = socialView and socialView.FilterBar and socialView.FilterBar.SearchBar
  local ok, text = pcall(function() return bar and bar:GetText() end)
  if not ok or type(text) ~= "string" or issecret(text) or text == "" then return true end
  return alt.name:lower():find(text:lower(), 1, true) ~= nil
end

-- The characters the list shows (the search box's), online and offline apart
local function SocialAlts()
  local online, offline = {}, {}
  for _, alt in ipairs(Sorted()) do
    if not GameFriend(alt.name) and SocialMatches(alt) then
      local list = CFL.Online(alt.name) and online or offline
      list[#list + 1] = alt
    end
  end
  return online, offline
end

-- A section of the list (a line at its top): its key; nil for any other line
local function SectionKey(node)
  local data = node and node.GetData and node:GetData()
  if type(data) ~= "table" or data.headerText == nil then return nil end
  if data.cflSection then return data.cflSection end
  if data.headerType == HEADER_FAVORITES then return "favorites" end
  if data.headerType == HEADER_FRIENDS then return "friends" end
  return nil
end

local function HeaderText(key, count)
  return (key == "online" and L.SECTION_ONLINE or L.SECTION_OFFLINE):format(count)
end

-- A line made apart (in a list of its own), then given to ours: the whole change shown at once
local function NewNode(provider, data)
  local made = CreateTreeDataProvider and CreateTreeDataProvider()
  if made then return made:Insert(data) end
  local node = provider:Insert(data)
  provider:GetRootNode():Remove(node, true)
  return node
end
local function Adopt(node, parent, provider)
  node.parent, node.dataProvider = parent, provider
  for _, child in ipairs(node.nodes or {}) do Adopt(child, node, provider) end
  return node
end

-- One of our sections: its header (folded as it was left), a spacer under it as the game's, its cards
local function NewSection(provider, root, key, alts)
  local section = NewNode(provider, { headerType = OURS[key], headerText = HeaderText(key, #alts), cflSection = key })
  local store = SectionStore()
  section.collapsed = store and store.folded[key] == true or nil
  section:Insert({ isSpacer = true })
  local cards = {}
  for i, alt in ipairs(alts) do cards[i] = section:Insert({ classicFriend = alt, accountInfo = SocialInfo(alt) }) end
  return Adopt(section, root, provider), cards
end

-- The list's sections in the player's order, ours made again, a spacer between two (as the game's); a list shown:
-- laid out again once
local function Arrange(provider)
  if off then return end
  local root = provider and provider.GetRootNode and provider:GetRootNode()
  local nodes = root and root.GetNodes and root:GetNodes()
  local store = SectionStore()
  if type(nodes) ~= "table" or not store then return end
  local sections, others = {}, {}
  for _, node in ipairs(nodes) do
    local key = SectionKey(node)
    local data = node:GetData()
    if key then
      if BNET[key] then sections[key] = node end
    elseif not (type(data) == "table" and data.isSpacer) then
      others[#others + 1] = node -- (anything else of the game's: kept first, as it was)
    end
  end
  local online, offline = SocialAlts()
  socialNodes = { online = {}, offline = {} }
  if #online > 0 then sections.online, socialNodes.online = NewSection(provider, root, "online", online) end
  if #offline > 0 then sections.offline, socialNodes.offline = NewSection(provider, root, "offline", offline) end
  local lines = {}
  for _, node in ipairs(others) do lines[#lines + 1] = node end
  for _, key in ipairs(store.order) do
    local section = sections[key]
    if section then
      if #lines > 0 then lines[#lines + 1] = Adopt(NewNode(provider, { isSpacer = true }), root, provider) end
      lines[#lines + 1] = section
    end
  end
  for i = #nodes, 1, -1 do nodes[i] = nil end
  for i, node in ipairs(lines) do nodes[i] = node end
  arranged = provider
  if provider.Invalidate then provider:Invalidate() end
end

---------------------------------------------------------------------------
-- The game's Battle.net friends put back when its own search gave none: the game builds its list with a friend search
-- (C_BattleNet.SearchFriends) it refuses when the list is built in an addon's name, any addon's (the search then gives
-- nothing: the Battle.net friends gone, our characters alone). The player has some, no search typed, no filter
-- ticked: they are put in as the game puts them (its two sections, their counts and folds, each friend's card). Each
-- time it happens is kept for the report: when, and from where the list was built.
---------------------------------------------------------------------------
CFL.bnetBack = { count = 0, last = nil }
function CFL.BnetBack(view, provider)
  local back = CFL.bnetBack
  local root = provider and provider.GetRootNode and provider:GetRootNode()
  if type(root) ~= "table" or type(root.GetNodes) ~= "function" then return false end
  for _, node in ipairs(root:GetNodes()) do
    if BNET[SectionKey(node) or ""] then return false end -- (the game's own there)
    local data = node.GetData and node:GetData()
    if type(data) == "table" and data.friendIndex then return false end
  end
  -- (a search typed or a filter ticked: none found may be right)
  local bar = view and view.FilterBar and view.FilterBar.SearchBar
  local okText, text = pcall(function() return bar and bar:GetText() end)
  if okText and type(text) == "string" and not issecret(text) and text ~= "" then return false end
  for _, on in pairs(type(view) == "table" and type(view.selectedSearchFilterOptions) == "table" and view.selectedSearchFilterOptions or {}) do
    if on then return false end
  end
  local okCount, total = pcall(BNGetNumFriends)
  if not okCount or type(total) ~= "number" or issecret(total) or total <= 0 then return false end
  if not (C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return false end
  local lists = { [HEADER_FAVORITES] = { online = 0 }, [HEADER_FRIENDS] = { online = 0 } }
  for index = 1, total do
    local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, index)
    if ok and type(info) == "table" then
      local list = lists[info.isFavorite and HEADER_FAVORITES or HEADER_FRIENDS]
      list[#list + 1] = { friendIndex = index, accountInfo = info }
      local game = info.gameAccountInfo
      if type(game) == "table" and game.isOnline then list.online = list.online + 1 end
    end
  end
  local headers = { [HEADER_FAVORITES] = SOCIAL_UI_FAVORITE_FRIENDS_LIST_HEADER, [HEADER_FRIENDS] = SOCIAL_UI_FRIENDS_LIST_HEADER }
  local put = 0
  for _, headerType in ipairs({ HEADER_FAVORITES, HEADER_FRIENDS }) do
    local list = lists[headerType]
    if #list > 0 and type(headers[headerType]) == "string" then
      if put > 0 then provider:Insert({ isSpacer = true }) end
      local section = provider:Insert({ headerType = headerType, headerText = headers[headerType]:format(list.online, #list) })
      local collapsed = view and view.IsHeaderCollapsed and view:IsHeaderCollapsed(headerType) or false
      if section.SetCollapsed then
        local C = TreeDataProviderConstants or {}
        section:SetCollapsed(collapsed, C.RetainChildCollapse, C.SkipInvalidation)
      end
      section:Insert({ isSpacer = true })
      for _, data in ipairs(list) do section:Insert(data) end
      put = put + #list
    end
  end
  if put == 0 then return false end
  back.count = back.count + 1
  local okStack, stack = pcall(debugstack, 3, 8, 0)
  back.last = { at = date and date("%H:%M:%S") or "", friends = put, stack = okStack and stack or "" }
  return true
end

-- For Clara's report: how often the game's list came without its Battle.net friends, and from where the last time
function CFL.BnetReport()
  local back = CFL.bnetBack
  local out = { ("friends list: the game's own search gave no Battle.net friend %d time(s) this session%s"):format(back.count,
    back.count > 0 and " (put back by Clara each time)" or "") }
  if back.last then
    out[#out + 1] = ("    last at %s, %d friends put back; the list built from:"):format(back.last.at, back.last.friends)
    for line in tostring(back.last.stack):gmatch("[^\n]+") do out[#out + 1] = "      " .. line end
  end
  return out
end

local function ShownProvider()
  local box = socialView and socialView.ScrollBox
  local provider = box and box.GetDataProvider and box:GetDataProvider()
  return provider ~= nil and provider == arranged and provider or nil
end

-- A card of ours: the mouse layer on it, the Battle.net party and summon buttons hidden
local function DressCard(frame, alt)
  if frame.PartyButton then frame.PartyButton:Hide() end
  if frame.RAFSummonButton then frame.RAFSummonButton:Hide() end
  frame.classicFriendHid = true
  local catcher = CFL.Catcher(frame)
  catcher.alt = alt
  catcher:Show()
end

-- Each card as the list draws it: ours dressed; a Battle.net friend's as the game made it (its party button back
-- when the card was ours before)
local function SocialCard(_, frame, node)
  local data = node and node.GetData and node:GetData()
  local alt = type(data) == "table" and data.classicFriend
  if not alt then
    socialFrames[frame] = nil
    if frame.classicFriend then frame.classicFriend:Hide(); frame.classicFriend.alt = nil end
    if frame.classicFriendHid and frame.PartyButton then frame.PartyButton:Show() end
    frame.classicFriendHid = nil
    return
  end
  socialFrames[frame] = node
  DressCard(frame, alt)
end

-- A card of ours drawn again in place (the same characters online and offline: no line put in or taken out)
local function Redraw(frame, node)
  local data = node:GetData()
  local alt = data.classicFriend
  local info = data.accountInfo
  local game = info and info.gameAccountInfo
  if not (alt and game) then return end
  local online = game.isOnline
  pcall(function()
    local nameColor = online and HIGHLIGHT_FONT_COLOR or FRIENDS_GRAY_COLOR
    if frame.FriendName then
      frame.FriendName:SetText(nameColor and nameColor.WrapTextInColorCode and nameColor:WrapTextInColorCode(info.accountName) or info.accountName)
    end
    if frame.Location then
      local text = online and (game.areaName or "") or (FriendsListUtil and FriendsListUtil.GetLastOnlineText(info) or "")
      local color = online and FRIENDS_GRAY_COLOR or DARKGRAY_COLOR
      frame.Location:SetText(color and color.WrapTextInColorCode and color:WrapTextInColorCode(text) or text)
    end
    if frame.PresenceHolder and frame.PresenceHolder.SetPresence and SocialUIUtil then
      frame.PresenceHolder:SetPresence(SocialUIUtil.GetPresenceTypeForBattleNetAccountInfo(info))
    end
    if frame.Background then frame.Background:SetAtlas(online and "friends-card-default" or "friends-card-disabled", false) end
    if frame.GameIconHolder then
      if online and C_Texture and frame.GameIconHolder.Icon then
        C_Texture.SetTitleIconTexture(frame.GameIconHolder.Icon, BNET_CLIENT_WOW or "WoW", Enum.TitleIconVersion.Small)
      end
      frame.GameIconHolder:SetShown(online)
    end
  end)
  DressCard(frame, alt)
end

-- What changed, while the list shows: the same characters online and offline, their cards drawn again in place;
-- else the list arranged again (a character coming online goes to its section at once)
function CFL.SocialRefresh()
  if not (socialView and socialView:IsVisible()) then return end
  local provider = ShownProvider()
  if not provider then return end
  local online, offline = SocialAlts()
  local now = { online = online, offline = offline }
  for key, alts in pairs(now) do
    if #alts ~= #socialNodes[key] then return Arrange(provider) end
  end
  for key, alts in pairs(now) do
    for i, node in ipairs(socialNodes[key]) do
      local data = node:GetData()
      data.classicFriend, data.accountInfo = alts[i], SocialInfo(alts[i])
    end
  end
  for frame, node in pairs(socialFrames) do
    if frame:IsVisible() then Redraw(frame, node) end
  end
end

---------------------------------------------------------------------------
-- The sections moved: a padlock beside the window's X. Unlocked, each section (the Battle.net favorites and friends,
-- and ours) is dragged by its header to where it goes among the others, the list scrolling by itself as it is pushed
-- against its top or its bottom (faster the further past); the order is kept. Its right-click menu: the characters
-- online, or offline, above the Battle.net friends (else after them), the first order back. Locked again as the
-- window closes.
---------------------------------------------------------------------------
local LOCK = "Interface\\Buttons\\LockButton-"
local SCROLL_ZONE = 28                    -- the list scrolls with the cursor this near its top or bottom, or past them
local SCROLL_SLOW, SCROLL_FAST = 150, 1500 -- its speed in the list's units a second: at the zone's edge, pushed far
local unlocked = false
local lockButton, ghost, marker, driver
local grips = setmetatable({}, { __mode = "k" }) -- (a header's frame -> its grip)
local drag -- (the section dragged: { key =, shown =, slot = })

local function Click() if SOUNDKIT and PlaySound then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end end

-- The list's sections in their order, as it shows
local function ShownKeys()
  local provider = ShownProvider()
  local root = provider and provider:GetRootNode()
  local keys = {}
  for _, node in ipairs(root and root:GetNodes() or {}) do
    local key = SectionKey(node)
    if key then keys[#keys + 1] = key end
  end
  return keys
end

-- The order kept, after the sections shown were put in this order (those not shown left where they were)
local function KeepShownOrder(shown)
  local store = SectionStore()
  if not store then return end
  local out, n = {}, 0
  for _, key in ipairs(store.order) do
    if IndexOf(shown, key) then n = n + 1; out[#out + 1] = shown[n] else out[#out + 1] = key end
  end
  store.order = out
end

local function Rearrange()
  local provider = ShownProvider()
  if provider then Arrange(provider) end
end

-- Is this section of ours above the Battle.net friends? Put it there, or after them (online before offline)
local function Above(key)
  local store = SectionStore()
  if not store then return false end
  local order = store.order
  return IndexOf(order, key) < math.min(IndexOf(order, "favorites"), IndexOf(order, "friends"))
end
CFL.SectionAbove = Above
local function SetAbove(key, above)
  local store = SectionStore()
  if not store then return end
  local order = store.order
  table.remove(order, IndexOf(order, key))
  local first = math.min(IndexOf(order, "favorites"), IndexOf(order, "friends"))
  local last = math.max(IndexOf(order, "favorites"), IndexOf(order, "friends"))
  local other = IndexOf(order, key == "online" and "offline" or "online")
  local at
  if above then
    at = first
    if key == "online" and other < first then at = other end
  else
    at = last + 1
    if key == "offline" and other > last then at = other + 1 end
  end
  table.insert(order, at, key)
  Rearrange()
end
CFL.SetSectionAbove = SetAbove
local function ResetOrder()
  local store = SectionStore()
  if not store then return end
  store.order = { unpack(SECTIONS) }
  Rearrange()
end
CFL.ResetSectionOrder = ResetOrder

-- Raw screen units (the cursor's): a frame's top and bottom
local function Edges(frame)
  local top, bottom = frame:GetTop(), frame:GetBottom()
  if not (top and bottom) then return nil end
  local scale = frame:GetEffectiveScale()
  return top * scale, bottom * scale
end

-- Where the section dragged would go: after how many of the sections shown (0: first). The cursor over another
-- section (its header or its cards): before it when that one is above the dragged one, after it when below; over the
-- dragged one itself: where it is. Above all the lines in sight: before the first in sight (the list scrolls on up);
-- below them all: after the last. Each section's lines in sight kept (seen: key -> { top, bottom }) for the marker.
local function Slot(y, fromKey)
  local box = socialView.ScrollBox
  local shown, seen = ShownKeys(), {}
  local under, firstKey, firstTop, lastKey, lastBottom
  box:ForEachFrame(function(frame, node)
    local top, bottom = Edges(frame)
    if not top or not frame:IsVisible() then return nil end
    local key = SectionKey(node) or SectionKey(node and node.GetParent and node:GetParent())
    if not key then return nil end -- (a spacer between two sections)
    local at = seen[key]
    if at then at[1], at[2] = math.max(at[1], top), math.min(at[2], bottom) else seen[key] = { top, bottom } end
    if y <= top and y > bottom then under = key end
    if not firstTop or top > firstTop then firstTop, firstKey = top, key end
    if not lastBottom or bottom < lastBottom then lastBottom, lastKey = bottom, key end
    return nil
  end)
  local from = IndexOf(shown, fromKey or (drag and drag.key)) or 0
  local slot
  if under then
    local i = IndexOf(shown, under) or 0
    if i < from then slot = i - 1 elseif i > from then slot = i else slot = from end
  elseif firstTop and y > firstTop then
    slot = math.max(0, (IndexOf(shown, firstKey) or 1) - 1)
    if (IndexOf(shown, firstKey) or 1) > from and from > 0 then slot = from end
  elseif lastBottom and y <= lastBottom then
    slot = IndexOf(shown, lastKey) or #shown
    if slot < from then slot = from end
  else
    slot = drag and drag.slot or from -- (between two sections: as it was)
  end
  return slot, shown, seen
end
CFL.SectionSlot = Slot

-- The line where it would go: over the next section's first line in sight, else under the one before it, else at the
-- list's top or bottom
local function PlaceMarker(slot, shown, seen)
  local box = socialView.ScrollBox
  local top, bottom = Edges(box)
  local left, right = box:GetLeft(), box:GetRight()
  if not (top and left and right) then marker:Hide() return end
  local ui = UIParent:GetEffectiveScale()
  local boxScale = box:GetEffectiveScale()
  local next = shown[slot + 1] and seen[shown[slot + 1]]
  local previous = shown[slot] and seen[shown[slot]]
  local y
  if next then y = next[1] + 2 * boxScale
  elseif previous then y = previous[2] - 2 * boxScale
  elseif slot >= #shown then y = bottom
  else y = top end
  y = math.min(top, math.max(bottom, y))
  marker:ClearAllPoints()
  marker:SetPoint("LEFT", UIParent, "BOTTOMLEFT", (left * boxScale) / ui + 8, y / ui)
  marker:SetWidth((right - left) * boxScale / ui - 16)
  marker:Show()
end

-- The list scrolled with the cursor near its top or bottom, or pushed past them
local function AutoScroll(y, elapsed)
  local box = socialView.ScrollBox
  local top, bottom = Edges(box)
  if not top or not (box.GetDerivedScrollRange and box.ScrollToOffset) then return end
  local zone = SCROLL_ZONE * box:GetEffectiveScale()
  local push
  if y > top - zone then push = -(y - (top - zone)) elseif y < bottom + zone then push = (bottom + zone) - y end
  if not push then return end
  local range = box:GetDerivedScrollRange()
  if not range or range <= 0 then return end
  local depth = math.min(1, math.abs(push) / (zone * 4))
  local speed = SCROLL_SLOW + (SCROLL_FAST - SCROLL_SLOW) * depth
  local offset = box:GetDerivedScrollOffset() + (push < 0 and -1 or 1) * speed * elapsed
  box:ScrollToOffset(math.max(0, math.min(range, offset)), true)
end

local function StopDrag()
  drag = nil
  if ghost then ghost:Hide() end
  if marker then marker:Hide() end
end

-- Dropped: the section taken out of the order shown and put back where it was let go
local function Drop()
  local d = drag
  StopDrag()
  if not (d and d.slot and d.shown) then return end
  local from = IndexOf(d.shown, d.key)
  if not from then return end
  local order = { unpack(d.shown) }
  table.remove(order, from)
  table.insert(order, d.slot >= from and d.slot or d.slot + 1, d.key)
  KeepShownOrder(order)
  Rearrange()
  Click()
end
CFL.DropSection = function(key, slot) drag = { key = key, shown = ShownKeys(), slot = slot }; Drop() end

-- A section a place up (-1) or down (1) among those shown
function CFL.MoveSection(key, step)
  local shown = ShownKeys()
  local from = IndexOf(shown, key)
  local to = from and from + step
  if not (to and to >= 1 and to <= #shown) then return end
  shown[from], shown[to] = shown[to], shown[from]
  KeepShownOrder(shown)
  Rearrange()
  Click()
end

local function DragStep(_, elapsed)
  if not drag then return end
  if not IsMouseButtonDown("LeftButton") then return Drop() end
  if not (socialView and socialView:IsVisible()) then return StopDrag() end
  local x, y = GetCursorPosition()
  local ui = UIParent:GetEffectiveScale()
  ghost:ClearAllPoints()
  ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / ui, y / ui)
  AutoScroll(y, elapsed or 0)
  local slot, shown, seen = Slot(y)
  drag.slot, drag.shown = slot, shown
  PlaceMarker(slot, shown, seen)
end

local function StartDrag(key, header)
  if drag or not key then return end
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    local fill = ghost:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.08, 0.06, 0.02, 0.85)
    -- (a gold edge: top, bottom, left, right)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
      { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
      local edge = ghost:CreateTexture(nil, "BORDER")
      edge:SetColorTexture(1, 0.82, 0, 0.9)
      edge:SetPoint(side[1])
      edge:SetPoint(side[2])
      if side[3] then edge:SetWidth(1) else edge:SetHeight(1) end
    end
    ghost.text = ghost:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ghost.text:SetPoint("LEFT", 8, 0)
    ghost.text:SetPoint("RIGHT", -8, 0)
    ghost.text:SetJustifyH("LEFT")
    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("TOOLTIP")
    marker:SetHeight(3)
    local line = marker:CreateTexture(nil, "ARTWORK")
    line:SetAllPoints()
    line:SetColorTexture(1, 0.82, 0, 1)
    marker:Hide()
  end
  local ui = UIParent:GetEffectiveScale()
  local scale = header:GetEffectiveScale() / ui
  ghost:SetSize((header:GetWidth() or 300) * scale, (header:GetHeight() or 24) * scale)
  ghost.text:SetText(header.ButtonText and header.ButtonText:GetText() or key)
  drag = { key = key }
  GameTooltip:Hide()
  ghost:Show()
  Click()
  DragStep(nil, 0)
end

-- The grip over a header (shown while unlocked): the whole header, a move sign before its fold button
local function Grip(frame)
  local grip = grips[frame]
  if grip then return grip end
  grip = CreateFrame("Button", nil, frame)
  grip:SetAllPoints(frame)
  local glow = grip:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetColorTexture(1, 0.82, 0, 0.12)
  local sign = grip:CreateTexture(nil, "OVERLAY")
  sign:SetSize(16, 16)
  sign:SetTexture("Interface\\Cursor\\UI-Cursor-Move")
  if frame.CollapseButton then sign:SetPoint("RIGHT", frame.CollapseButton, "LEFT", -4, 0) else sign:SetPoint("RIGHT", -30, 0) end
  grip:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then StartDrag(self.key, frame) end end)
  -- (up and down a place without dragging: two arrows before the move sign)
  for i, step in ipairs({ -1, 1 }) do
    local arrow = CreateFrame("Button", nil, grip)
    arrow:SetSize(16, 16)
    local face = step < 0 and "Interface\\Buttons\\Arrow-Up-" or "Interface\\Buttons\\Arrow-Down-"
    arrow:SetNormalTexture(face .. "Up")
    arrow:SetPushedTexture(face .. "Down")
    arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    arrow:SetPoint("RIGHT", sign, "LEFT", -2 - (2 - i) * 16, step < 0 and 2 or -2)
    arrow:SetScript("OnClick", function() CFL.MoveSection(grip.key, step) end)
    arrow:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(step < 0 and L.MOVE_UP or L.MOVE_DOWN, 1, 1, 1)
      GameTooltip:Show()
    end)
    arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip[step < 0 and "up" or "down"] = arrow
  end
  grip:SetScript("OnEnter", function(self)
    if drag then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.DRAG_TIP, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grips[frame] = grip
  return grip
end
function CFL.SectionGrip(frame) return grips[frame] end

-- The grips on the headers in sight, while unlocked
local function SyncGrips()
  local box = socialView and socialView.ScrollBox
  local on = {}
  if unlocked and box and box:IsVisible() and box.ForEachFrame then
    box:ForEachFrame(function(frame, node)
      local key = SectionKey(node)
      if key then
        local grip = Grip(frame)
        grip.key = key
        grip:SetFrameLevel(frame:GetFrameLevel() + 10)
        grip:Show()
        on[frame] = true
      end
      return nil
    end)
  end
  for frame, grip in pairs(grips) do
    if not on[frame] then grip:Hide() end
  end
end
CFL.SyncSectionGrips = SyncGrips

local function LockLook()
  if not lockButton then return end
  local state = unlocked and "Unlocked-" or "Locked-"
  lockButton:SetNormalTexture(LOCK .. state .. "Up")
  lockButton:SetPushedTexture(LOCK .. state .. "Down")
end

local function SetUnlocked(on)
  unlocked = on and true or false
  if not unlocked then StopDrag() end
  LockLook()
  SyncGrips()
  if driver then driver:SetShown(unlocked) end
end
CFL.SetSectionsUnlocked = SetUnlocked
function CFL.SectionsUnlocked() return unlocked end

local function LockTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.LOCK_TITLE, 1, 1, 1)
  GameTooltip:AddLine(unlocked and L.UNLOCKED_TIP or L.LOCKED_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end

-- The sections' options: in the padlock's right-click menu, and in the friends window's own menu (its ≡ button)
local function SectionEntries(root)
  root:CreateTitle(L.LOCK_TITLE)
  root:CreateCheckbox(L.OPT_ONLINE_TOP, function() return Above("online") end,
    function() SetAbove("online", not Above("online")) end)
  root:CreateCheckbox(L.OPT_OFFLINE_TOP, function() return Above("offline") end,
    function() SetAbove("offline", not Above("offline")) end)
  root:CreateButton(unlocked and L.LOCK_SECTIONS or L.UNLOCK_SECTIONS, function() SetUnlocked(not unlocked) end)
  root:CreateButton(L.OPT_RESET, ResetOrder)
end
CFL.SectionEntries = SectionEntries

local function OptionsMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root) SectionEntries(root) end)
end

-- The padlock, on the friends page (shown with it), beside the window's X
local function MakeLock()
  local close = SocialUIFrame and SocialUIFrame.CloseButton
  if lockButton or not (socialView and close) then return end
  local lock = CreateFrame("Button", nil, socialView)
  local w, h = close:GetSize()
  lock:SetSize(w and w > 0 and w or 24, h and h > 0 and h or 24)
  lock:SetPoint("RIGHT", close, "LEFT", 0, 0)
  lock:SetFrameStrata(close:GetFrameStrata())
  lock:SetFrameLevel(close:GetFrameLevel() + 1)
  lock:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  lock:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  lock:SetScript("OnClick", function(self, button)
    if button == "RightButton" then OptionsMenu(self) return end
    Click()
    SetUnlocked(not unlocked)
    LockTip(self)
  end)
  lock:SetScript("OnEnter", LockTip)
  lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
  lockButton = lock
  CFL.lockButton = lock
  LockLook()
  -- (the grips follow the headers as the list scrolls; the dragged section follows the cursor)
  driver = CreateFrame("Frame", nil, socialView)
  driver:Hide()
  local since = 0
  driver:SetScript("OnUpdate", function(_, elapsed)
    if drag then DragStep(nil, elapsed) end
    since = since + elapsed
    if since >= 0.05 then since = 0; SyncGrips() end
  end)
  socialView:HookScript("OnHide", function() SetUnlocked(false) end)
end

function CFL.HookSocial()
  if socialView then return true end
  local view = SocialUIFrame and SocialUIFrame.FriendsList
  if not (view and view.InsertFriendsIntoDataProvider and FriendsListSocialCardMixin) then return false end
  socialView = view
  -- (in the list the game builds, before it lays it out: our sections in it, all in the player's order)
  hooksecurefunc(view, "InsertFriendsIntoDataProvider", function(self, provider)
    pcall(CFL.BnetBack, self, provider)
    Arrange(provider)
  end)
  -- (its search gave nothing at all: the game puts no friend in, and the list reaches the scroll box unarranged)
  if view.ScrollBox and type(view.ScrollBox.SetDataProvider) == "function" then
    hooksecurefunc(view.ScrollBox, "SetDataProvider", function(_, provider)
      if provider == nil or provider == arranged or not provider.GetRootNode then return end
      pcall(CFL.BnetBack, view, provider)
      Arrange(provider)
    end)
  end
  -- (our sections' fold, as the game keeps it for its own: kept here too, for the next times)
  if type(view.SaveHeaderCollapsedState) == "function" then
    hooksecurefunc(view, "SaveHeaderCollapsedState", function(_, headerType, collapsed)
      local store = SectionStore()
      if not store then return end
      for key, kind in pairs(OURS) do
        if kind == headerType then store.folded[key] = collapsed and true or nil end
      end
    end)
  end
  -- The game's card-size cache: the game fills it as it lays the list out, a pass that has read our lines (an
  -- addon's) first, so each size is put in it in the addon's name; at its next refresh the game empties it just
  -- before its friend search, and a size of ours found there then has the search refused: the list empty (black,
  -- every other time the window opened) or scrolled back up (a Battle.net friend's news). Taken out again as soon as
  -- the game has read it: the game works each size out again when it needs it (cheaply), and finds nothing of ours
  -- in it when it empties it.
  if type(view.GetTemplateExtent) == "function" and type(view.TemplateExtentCache) == "table" then
    hooksecurefunc(view, "GetTemplateExtent", function(self, name)
      local cache = self.TemplateExtentCache
      if type(cache) == "table" and name ~= nil then cache[name] = nil end
    end)
  end
  -- (each card as the game draws it: after its own drawing, ours dressed; the cards are made after this, from the
  -- game's card with this hook in it)
  hooksecurefunc(FriendsListSocialCardMixin, "Initialize", function(frame, node) SocialCard(nil, frame, node) end)
  MakeLock()
  local menus = _G.Menu -- (the game's menus: "Menu" here is the cards' own right-click menu)
  if type(menus) == "table" and menus.ModifyMenu then
    menus.ModifyMenu("MENU_SOCIAL_UI_BATTLE_NET_BAR", function(_, root)
      root:CreateDivider()
      SectionEntries(root)
    end)
  end
  return true
end

---------------------------------------------------------------------------
-- Coming and going: said in the chat as the game says it of a friend, the list redrawn
---------------------------------------------------------------------------
local wasOnline = {} -- lower-case whole name -> online when last looked
local settled = false -- (the first moments after login: the ones already online heard, not announced)
-- "No player named" lines held back a moment (see "Held back", below): Key(name) -> the line(s), the windows, when
CFL.Withheld = { lines = {}, said = {} } -- (no local of its own: the file's main chunk is at Lua's 200 locals)
local function Announce(alt, online)
  local frame = DEFAULT_CHAT_FRAME
  if not (frame and frame.AddMessage) then return end
  -- (one the server has just said not found, now online: neither line said, the two only the server's late word)
  local key = Key(alt.name)
  if online and CFL.Withheld.lines[key] then CFL.Withheld.lines[key] = nil return end
  local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
  local r, g, b = info and info.r or 1, info and info.g or 1, info and info.b or 0
  local text
  if online then
    text = (ERR_FRIEND_ONLINE_SS or "|Hplayer:%s|h[%s]|h has come online."):format(alt.name, alt.name)
  else
    text = (ERR_FRIEND_OFFLINE_S or "%s has gone offline."):format(alt.name)
  end
  -- (said a moment later: back as it was meanwhile, online then offline at once or the reverse, neither said; 3
  -- seconds, more while the server is slow)
  local said = CFL.Withheld.said
  local pending = said[key]
  if pending and pending.online ~= online then said[key] = nil return end
  pending = { online = online }
  said[key] = pending
  local wait = CFL.Wait and CFL.Wait() or 2
  C_Timer.After(math.max(CFL.Withheld.HOLD_MIN or 3, wait + 1), function()
    if said[key] ~= pending then return end
    said[key] = nil
    frame:AddMessage(text, r, g, b)
  end)
end
local function Look(announce)
  MendKnown()
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
-- ... is currently playing" (that line hidden from the chat when it answers one of our questions, however late);
-- online it says nothing for 2 seconds (longer while the server is slow: its answers' delay learned as they come); a
-- late answer still says offline, and is still hidden. A character heard in the chat by its whole name is online at
-- once. Between two players with this addon or Clara (the same messages: "ClaraFriends") that have each other in
-- their lists it is at once both ways: the question is a hello (asked of everyone at login, the first 8 at once), the
-- answer comes with its level, class and zone, and a goodbye goes at logout (not at a reload). Not asked, never
-- online (one character at a time per WoW account): the character played now and this account's other characters.
---------------------------------------------------------------------------
local PROBE_PREFIX = "ClaraFriends" -- (Clara's own: the two speak together)
local PROBE_EVERY = 1     -- seconds between two questions
local PROBE_ROUND = 10    -- seconds at least between two questions to the same character
local PROBE_ROUND_OPEN = 3 -- the same while the friends list is open
local PROBE_WAIT = 2      -- seconds without the server's "no player named": online (longer while the server is slow)
local PROBE_WAIT_MAX = 20 -- the most it waits (a server very slow to answer)
local PROBE_BURST = 8     -- questions asked at once at login, goodbyes said at once at logout
local PROBE_HIDE = 30     -- seconds the server's answer to a question is still taken for it (hidden, offline)
local PROBE_SETTLE = 3    -- seconds after the world shows before asking (answers held in a loading screen came late)
local pausedUntil = math.huge -- (no question before the world shows)
local REPLY_EVERY = 2     -- seconds at least between two answers to the same asker (its hello answered at once)
local replied = {}        -- Key(name) -> when answered last
local slowest = 0         -- seconds: the server's slowest recent answer (forgotten little by little)
local loads = 0           -- loading screens since login (an answer held in one tells nothing of the server's pace)
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

local function SetVerdict(key, online, heard)
  local p = probes[key] or {}
  probes[key] = p
  p.sent = nil
  -- (heard from: its questions answered; the ones asked just before it was heard, whose "no player named" may still
  -- come, kept a moment: that line hidden, saying nothing of it now)
  if heard and p.asked then
    local now, keep, wait = GetTime(), {}, CFL.Wait and CFL.Wait() or PROBE_WAIT -- (Wait: below)
    for _, q in ipairs(p.asked) do
      if now - q.at < wait then q.stale, q.untilAt = true, now + wait; keep[#keep + 1] = q end
    end
    p.asked = keep
  end
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
    -- (each question kept a while: its answer, however late, is ours)
    p.asked = p.asked or {}
    p.asked[#p.asked + 1] = { at = now, load = loads, ask = true }
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
    if not IsMe(alt.name) and not OnThisAccount(alt.name) then
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

-- How long a question waits for the server's answer: 2 seconds, longer while the server is slow (its slowest recent
-- answer, and the game's own latency)
local function Wait()
  local wait = PROBE_WAIT
  if slowest > 0 then wait = math.max(wait, slowest * 1.5 + 1) end
  if GetNetStats then
    local ok, _, _, home, world = pcall(GetNetStats)
    local ms = ok and math.max(tonumber(home) or 0, tonumber(world) or 0) or 0
    if ms > 0 then wait = math.max(wait, ms * 3 / 1000 + 1) end
  end
  return math.min(wait, PROBE_WAIT_MAX)
end
CFL.Wait = Wait -- (for the tests)

local lastTick
local function AskServer()
  local now = GetTime()
  -- (the server's pace forgotten little by little: half of it in two minutes)
  if lastTick and now > lastTick and slowest > 0 then slowest = slowest * 0.5 ^ ((now - lastTick) / 120) end
  lastTick = now
  local wait = Wait()
  for key, p in pairs(probes) do
    -- (questions too old for an answer: let go)
    if p.asked then CFL.Withheld.Expire(p.asked, now) end
    if p.sent and now - p.sent >= wait then SetVerdict(key, true) end -- (unanswered: online)
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
    if alt.clara and not IsMe(alt.name) and not OnThisAccount(alt.name) then
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

-- A "No player named" line, taken once whoever sees it first (the addon's events, each chat window's filter): the
-- name in it, and whether it answers one of our questions (the oldest still waiting for that name; hidden). Its
-- delay teaches the server's pace (counted from the newest question: a question to one online is never answered).
local lastLine, lastText, lastAt, lastKey, lastOurs
local function TakeAnswer(text, line)
  if issecret(text) or type(text) ~= "string" then return nil, false end
  local now = GetTime()
  local byLine = type(line) == "number" and not issecret(line) and line > 0
  if (byLine and line == lastLine) or (not byLine and text == lastText and now == lastAt) then return lastKey, lastOurs, CFL.Withheld.last end
  local key = NotFoundName(text)
  local ours, held = false, nil
  local p = key and probes[key]
  local asked = p and p.asked
  if asked then CFL.Withheld.Expire(asked, now) end
  if asked and asked[1] then
    local newest = asked[#asked]
    if newest.ask and newest.load == loads then slowest = math.max(slowest, now - newest.at) end
    ours = table.remove(asked, 1)
  end
  if key and not ours then held = CFL.Withheld.Hold(key, text, now) end
  lastLine, lastText, lastAt, lastKey, lastOurs, CFL.Withheld.last = byLine and line or nil, text, now, key, ours, held
  return key, ours, held
end

---------------------------------------------------------------------------
-- Held back: a "No player named" line that answers no whisper of ours, naming a character of the list (a whisper of
-- the player's own, or the server's word coming late or twice), hidden a moment: 3 seconds, longer while the server
-- is slow (the time the addon waits for its answers, and a second). Heard from meanwhile (it came online: the line
-- was only the server's late word), the line dropped, and its "has come online" not said either. Else the line shown
-- then, in each chat window that would have shown it, and the character offline.
---------------------------------------------------------------------------
CFL.Withheld.HOLD_MIN = 3
CFL.Withheld.REPLY_HIDE = 5 -- seconds an answer of ours waits for the server's "no player named" (one online says nothing)

-- The questions too old for an answer let go: ours, after PROBE_HIDE; an answer of ours, or one asked just before
-- the character was heard from, sooner
function CFL.Withheld.Expire(asked, now)
  for i = #asked, 1, -1 do
    local q = asked[i]
    if now > (q.untilAt or (q.at + PROBE_HIDE)) then table.remove(asked, i) end
  end
end

-- An answer of ours whispered (its level, class and zone): a "no player named" for it is ours too (hidden), and says
-- nothing of the character now (it has just been heard from)
function CFL.Withheld.Expect(name)
  if issecret(name) or type(name) ~= "string" then return end
  local key, now = Key(name), GetTime()
  local p = probes[key] or {}
  probes[key] = p
  p.asked = p.asked or {}
  p.asked[#p.asked + 1] = { at = now, load = loads, untilAt = now + math.max(CFL.Withheld.REPLY_HIDE, Wait()) }
end

function CFL.Withheld.Release(key, entry)
  if CFL.Withheld.lines[key] ~= entry then return end -- (dropped: it came online)
  CFL.Withheld.lines[key] = nil
  local p = probes[key]
  if p and p.verdict == true and (p.at or 0) > entry.at then return end -- (heard from since: the line was late)
  local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
  for frame in pairs(entry.frames) do
    if frame.AddMessage then
      for _, text in ipairs(entry.texts) do frame:AddMessage(text, info and info.r or 1, info and info.g or 1, info and info.b or 0) end
    end
  end
  local alt, own = Listed(key)
  if alt then SetVerdict(own, false) end
end

function CFL.Withheld.Hold(key, text, now)
  local alt, own = Listed(key)
  if not alt then return nil end
  local entry = CFL.Withheld.lines[own]
  if entry then
    entry.texts[#entry.texts + 1] = text
    return entry
  end
  entry = { texts = { text }, frames = {}, at = now }
  CFL.Withheld.lines[own] = entry
  local p = probes[own]
  if p then p.sent = nil end -- (the server has spoken of it: no silence taken for online)
  C_Timer.After(math.max(CFL.Withheld.HOLD_MIN, Wait() + 1), function() CFL.Withheld.Release(own, entry) end)
  return entry
end

local function HideOurs(frame, _, text, ...)
  if off then return false end
  local _, ours, held = TakeAnswer(text, (select(10, ...)))
  if held and frame then held.frames[frame] = true end
  return (ours or held) and true or false
end

local function Answer(sender)
  local level = UnitLevel and UnitLevel("player") or 0
  local _, class = UnitClass("player")
  local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
  if issecret(zone) or type(zone) ~= "string" then zone = "" end
  if Whisper(sender, ("I|%d|%s|%s"):format(tonumber(level) or 0, class or "", (zone:gsub("|", "")))) then
    CFL.Withheld.Expect(sender)
  end
  local sex = UnitSex and UnitSex("player")
  if (sex == 2 or sex == 3) and Whisper(sender, "S|" .. sex) then CFL.Withheld.Expect(sender) end
end

-- A unit's whole name ("First Surname"), as the game's own names give it
local function WholeName(unit)
  local ok, name, surname = pcall(function()
    if UnitNameUnmodified then return UnitNameUnmodified(unit) end
    return UnitName(unit)
  end)
  if not ok or issecret(name) or type(name) ~= "string" or name == "" then return nil end
  local consts = Constants and Constants.CharacterNameSeparatorConsts
  local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
  if type(sep) == "string" and not issecret(surname) and type(surname) == "string" and surname ~= ""
    and not name:find(sep, 1, true) then
    return name .. sep .. surname
  end
  return name
end

-- Its class (and level) from the game, for one seen or heard: its class color even without an addon of its own
local function KeepClass(alt, class, level)
  if issecret(class) or issecret(level) then return end
  local changed = false
  if type(class) == "string" and class ~= "" and alt.class ~= class then alt.class, changed = class, true end
  level = tonumber(level)
  if level and level > 0 and alt.level ~= level then alt.level, alt.levelAt, changed = level, time and time() or nil, true end
  if changed then CFL.Refresh() end
end

local function KeepSex(alt, own, sex)
  if sex ~= 2 and sex ~= 3 then return end
  local sexes = Sexes()
  if sexes then sexes[own] = sex end
  if alt and alt.sex ~= sex then
    alt.sex = sex
    CFL.Refresh()
  end
end

-- One seen (target, under the mouse, in the group): its sex, the game's
local function NoteUnit(unit)
  local ok, player = pcall(UnitIsPlayer, unit)
  if not ok or issecret(player) or not player then return end
  local name = WholeName(unit)
  if not name then return end
  CFL.Mend(name)
  local alt, own = Listed(Key(name))
  if not alt then return end
  local okSex, sex = pcall(UnitSex, unit)
  if okSex and not issecret(sex) then KeepSex(alt, own, sex) end
  local okClass, _, class = pcall(UnitClass, unit)
  local okLevel, level = pcall(UnitLevel, unit)
  KeepClass(alt, okClass and class or nil, okLevel and level or nil)
end

local CHAT_PRESENCE = { "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
  "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }

local probeEvents = CreateFrame("Frame")
probeEvents:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, ...)
  if event == "PLAYER_LOGOUT" then
    Goodbye()
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- A loading screen held the answers: the questions then unanswered are asked again, a moment after the world
    -- shows (everyone at once after a login or reload), not taken for online.
    for _, p in pairs(probes) do p.sent = nil end
    loads = loads + 1
    pausedUntil = GetTime() + PROBE_SETTLE
    if a1 or a2 then
      Hello()
      C_Timer.After(PROBE_SETTLE, AskAll)
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- (a question of ours answered: offline; an answer of ours, or a question asked just before it was heard from:
    -- hidden, saying nothing of it now; any other line: held back, see above)
    local key, ours = TakeAnswer(a1, (select(7, ...)))
    if not (key and ours and ours.ask and not ours.stale) then return end
    local alt, own = Listed(key)
    if alt then SetVerdict(own, false) end
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, text, channel, sender = a1, a2, a3, a4
    if prefix ~= PROBE_PREFIX or channel ~= "WHISPER" then return end
    if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    CFL.Mend(sender)
    local alt, own = Listed(Key(sender))
    if not alt then
      -- A player not in this list asking: answered all the same (its level, class and zone are what /who tells
      -- anyone), so that a friend who has this one in their list sees it, even while it has not added them back
      if text == "?" then
        local key, now = Key(sender), GetTime()
        if key and not (replied[key] and now - replied[key] < REPLY_EVERY) then
          replied[key] = now
          Answer(sender)
        end
      end
      return
    end
    Respell(alt, sender)
    alt.clara = true -- (it has the addon or Clara: greeted first, told goodbye)
    if text == "!" then SetVerdict(own, false) return end -- (its goodbye)
    SetVerdict(own, true, true)
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
      local sex = tonumber(text:match("^S|(%d)$") or "")
      if sex then KeepSex(alt, own, sex) end
    end
  elseif event == "PLAYER_LEVEL_UP" then
    KeepMe(a1)
  elseif event == "PLAYER_TARGET_CHANGED" then
    NoteUnit("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    NoteUnit("mouseover")
  elseif event == "GROUP_ROSTER_UPDATE" then
    local raid = IsInRaid and IsInRaid()
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do NoteUnit((raid and "raid" or "party") .. i) end
  else -- heard in the chat: by its whole name only (a first name alone may be anyone's)
    if issecret(a2) or type(a2) ~= "string" or a2 == "" then return end
    CFL.Mend(a2)
    local heard = Key(a2)
    local alt, own = Listed(heard)
    if alt and own == heard then
      Respell(alt, a2)
      SetVerdict(own, true, true)
      -- (its sex, from the game's word on its sender)
      local guid = select(8, ...)
      if type(guid) == "string" and not issecret(guid) and GetPlayerInfoByGUID then
        local okInfo, _, class, _, _, sex = pcall(GetPlayerInfoByGUID, guid)
        if okInfo and not issecret(sex) then KeepSex(alt, own, sex) end
        if okInfo then KeepClass(alt, class, nil) end
      end
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
  for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP" }) do
    probeEvents:RegisterEvent(event)
  end
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
-- A character's right-click menu (the target's portrait, a group's frame, a name in the chat...): Add Classic friend
-- in the game's Add Friend submenu, its whole name (first name and surname) put in the list
---------------------------------------------------------------------------
-- (the game's menus that can hold its Add Friend: those of another player)
local PLAYER_MENUS = { "TARGET", "FOCUS", "PARTY", "PLAYER", "RAID_PLAYER", "RAID", "ENEMY_PLAYER", "ARENAENEMY",
  "FRIEND", "FRIEND_OFFLINE", "CHAT_ROSTER", "GUILD", "GUILD_OFFLINE", "COMMUNITIES_MEMBER", "COMMUNITIES_WOW_MEMBER",
  "COMMUNITIES_GUILD_MEMBER", "NEIGHBORHOOD_ROSTER", "RAF_RECRUIT", "RECENT_ALLY", "RECENT_ALLY_OFFLINE",
  "PVP_SCOREBOARD", "WORLD_STATE_SCORE" }

-- Its whole name: the unit's (UnitNameUnmodified: first name and surname), else the menu's name and surname
function CFL.MenuName(contextData)
  if type(contextData) ~= "table" then return nil end
  local name
  local unit = contextData.unit
  if type(unit) == "string" and not issecret(unit) then name = WholeName(unit) end
  if name == nil then
    local first, surname = contextData.name, contextData.surname
    if type(first) ~= "string" or issecret(first) then return nil end
    name = first:match("^([^%-]+)") or first -- (a realm left out: "Name-Realm")
    if type(surname) == "string" and not issecret(surname) and surname ~= "" and not name:find(" ", 1, true) then
      name = name .. " " .. surname
    end
  end
  return Normal(name)
end

-- The game's Add Friend submenu in a menu (in it, or in one of its submenus)
local function FriendSubmenu(description, depth)
  if not (description and description.EnumerateElementDescriptions) then return nil end
  for _, child in description:EnumerateElementDescriptions() do
    if MenuUtil.GetElementText(child) == ADD_FRIEND then return child end
    if depth > 0 then
      local found = FriendSubmenu(child, depth - 1)
      if found then return found end
    end
  end
end

local function AddClassicEntry(_, root, contextData)
  if off then return end
  local name = CFL.MenuName(contextData)
  if not name or IsMe(name) then return end
  local submenu = FriendSubmenu(root, 2)
  if not submenu then return end
  local button = submenu:CreateButton(L.MENU_ADD, function() CFL.Add(name) end)
  local list = List()
  if list and list[name:lower()] and button and button.SetEnabled then button:SetEnabled(false) end -- (already in it)
end
function CFL.AddClassicEntry(owner, root, contextData) pcall(AddClassicEntry, owner, root, contextData) end

-- (at login, Clara not loaded: Clara has its own)
local menusHooked = false
function CFL.HookUnitMenus()
  local menus = _G.Menu
  if menusHooked or type(menus) ~= "table" or not menus.ModifyMenu or not (MenuUtil and MenuUtil.GetElementText)
    or not ADD_FRIEND then return end
  menusHooked = true
  for _, which in ipairs(PLAYER_MENUS) do menus.ModifyMenu("MENU_UNIT_" .. which, CFL.AddClassicEntry) end
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
  -- (this character's sex kept for the whole account: its other characters show its class's name as it is)
  local me, sexes = WholeName("player"), Sexes()
  if me and sexes and UnitSex then sexes[Key(me)] = UnitSex("player") end
  KeepMe()
  if not db then
    if type(ClassicFriendsListDB) ~= "table" then ClassicFriendsListDB = {} end
    db = ClassicFriendsListDB
  end
  List()
  Hook()
  CFL.HookUnitMenus()
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
