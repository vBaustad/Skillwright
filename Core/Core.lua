-- Skillwright - core: namespace, saved variables, events and slash commands.
-- Everything cross-file hangs off the SW table (the addon's second vararg).
local ADDON, SW = ...
_G.Skillwright = SW

local LIB = LibStub("LibForever-1.0")
SW.LIB = LIB

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
SW.VERSION = (getMeta and getMeta(ADDON, "Version")) or "0.0.0"

SW.CREAM = "ffebdec2"
SW.GOLD = "ffe6b34d"
SW.GRAY = "ff8a8a8a"

-- Crafting professions Skillwright plans, by skill line ID (the IDs the data and the client share).
SW.PROFESSIONS = {
    [171] = { name = "Alchemy", icon = "Interface\\Icons\\Trade_Alchemy" },
    [164] = { name = "Blacksmithing", icon = "Interface\\Icons\\Trade_BlackSmithing" },
    [185] = { name = "Cooking", icon = "Interface\\Icons\\INV_Misc_Food_15" },
    [333] = { name = "Enchanting", icon = "Interface\\Icons\\Trade_Engraving" },
    [202] = { name = "Engineering", icon = "Interface\\Icons\\Trade_Engineering",
              specs = { "Gnomish", "Goblin" } },
    [129] = { name = "First Aid", icon = "Interface\\Icons\\INV_Misc_Bandage_08" },
    [165] = { name = "Leatherworking", icon = "Interface\\Icons\\Trade_LeatherWorking",
              specs = { "Dragonscale", "Elemental", "Tribal" } },
    [197] = { name = "Tailoring", icon = "Interface\\Icons\\Trade_Tailoring" },
}
-- Every profession line, so ranks of gathering professions don't get mistaken for crafting ones.
SW.ALL_LINES = { [164] = true, [165] = true, [171] = true, [182] = true, [185] = true, [186] = true,
                 [197] = true, [202] = true, [333] = true, [356] = true, [393] = true, [129] = true }

-- Vanilla trainer tiers: the rank cap each one lifts and the skill needed to learn it.
SW.TIERS = {
    { cap = 75, name = "Apprentice", need = 1 },
    { cap = 150, name = "Journeyman", need = 50 },
    { cap = 225, name = "Expert", need = 125 },
    { cap = 300, name = "Artisan", need = 200 },
}
SW.MAX_RANK = 300

function SW.ProfName(id)
    local db = SW.DB()
    return (db.profNames and db.profNames[id]) or (SW.PROFESSIONS[id] and SW.PROFESSIONS[id].name) or ("Profession " .. tostring(id))
end
function SW.ProfIcon(id)
    return SW.PROFESSIONS[id] and SW.PROFESSIONS[id].icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function SW.msg(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    print("|cffe6b34dSkillwright|r: " .. text)
end

function SW.dbg(fmt, ...)
    if SW.debug then SW.msg("|cff888888" .. fmt .. "|r", ...) end
end

function SW.Now() return GetServerTime() end

function SW.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg %ds %dc"):format(copper / 10000, (copper / 100) % 100, copper % 100)
end

-- Short money text for tight rows: "12g", "4s 20c", "35c".
function SW.MoneyShort(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g >= 100 then return ("|cffffd100%dg|r"):format(g) end
    if g > 0 then return ("|cffffd100%dg|r |cffc7c7cf%ds|r"):format(g, s) end
    if s > 0 then return ("|cffc7c7cf%ds|r |cffeda55f%dc|r"):format(s, c) end
    return ("|cffeda55f%dc|r"):format(c)
end

-- ---------------------------------------------------------------------------
-- Events and internal callbacks (thin wrappers over LibForever)
-- ---------------------------------------------------------------------------
SW.On = LIB.On
SW.Debounce = LIB.Debounce

local listeners = {}
function SW.Listen(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
end
function SW.Fire(name, ...)
    local list = listeners[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then SW.dbg("%s: %s", name, tostring(err)) end
    end
end

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------
-- Account-wide: settings plus facts learned from the game, shared by every character.
local DEFAULTS = {
    settings = {
        mode = "cheap",          -- "cheap" or "fast"
        allowCamp = false,       -- plan recipes that need a Forever camp station
        attach = true,           -- open beside the profession window
        autoOpen = true,         -- open with the profession window
        hideMinimap = false,
        minimapAngle = 215,
        maxPriceAge = 3,         -- days before an auction price counts as stale
    },
    learnRanks = {},             -- [recipeSpellID] = skill needed, read off trainers
    trainerSeen = {},            -- [recipeSpellID] = true when a trainer offers it
    specReq = {},                -- [recipeSpellID] = specialization name a trainer asked for
    vendor = {},                 -- [itemID] = unit price seen on a merchant
    ah = {},                     -- [itemID] = { unitPrice, scannedAt }
    ahScanned = 0,
    profNames = {},              -- [skillLineID] = localized name
}

function SW.DB()
    SkillwrightDB = SkillwrightDB or {}
    local db = SkillwrightDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = (type(v) == "table") and CopyTable(v) or v end
    end
    for k, v in pairs(DEFAULTS.settings) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    return db
end

function SW.Settings() return SW.DB().settings end

-- Per character: profession ranks, learned recipes, chosen specialization, excluded recipes.
function SW.CharDB()
    SkillwrightCharDB = SkillwrightCharDB or {}
    local c = SkillwrightCharDB
    c.profs = c.profs or {}      -- [skillLineID] = { rank, max, known = { [spell] = true }, spec, exclude = {} }
    return c
end

function SW.CharProf(id)
    local profs = SW.CharDB().profs
    local p = profs[id]
    if not p then
        p = { rank = 0, max = 0, known = {}, exclude = {} }
        profs[id] = p
    end
    p.known = p.known or {}
    p.exclude = p.exclude or {}
    return p
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
SW.On("PLAYER_LOGIN", function()
    if not C_Weather then
        SW.msg("|cffff6060made for WoW: Forever - it won't work properly in this version of the game.|r")
    end
    SW.DB()
    SW.CharDB()
    SW.Fire("LOGIN")
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_SKILLWRIGHT1 = "/skillwright"
SLASH_SKILLWRIGHT2 = "/sw"
SlashCmdList.SKILLWRIGHT = function(input)
    local cmd, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        SW.ToggleWindow()
    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        SW.ShowWindow(nil, "settings")
    elseif cmd == "cheap" or cmd == "fast" then
        SW.SetMode(cmd)
    elseif cmd == "prices" then
        SW.Prices.PrintStatus()
    elseif cmd == "debug" then
        SW.debug = not SW.debug
        SW.msg("debug %s", SW.debug and "on" or "off")
    else
        SW.msg("|cffffd100/sw|r guide, |cffffd100/sw cheap|r or |cffffd100/sw fast|r route mode, "
            .. "|cffffd100/sw prices|r price sources, |cffffd100/sw config|r settings")
    end
end
