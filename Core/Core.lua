-- Skillwright - core: namespace, saved variables, events and slash commands.
-- Everything cross-file hangs off the SW table (the addon's second vararg).
local ADDON, SW = ...
_G.Skillwright = SW

local LIB = LibStub("LibForever-1.0")
SW.LIB = LIB

SW.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0.0"

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

-- The four vanilla trainer tiers: the rank cap each one lifts to and the skill needed to learn it.
-- WoW: Forever adds a FIFTH rank above Artisan - every profession has a child skill line at
-- ParentTierIndex 4 with four rank spells of its own - and its cap is not in the client data. Nothing
-- here may pretend to know it.
SW.TIERS = {
    { cap = 75, name = "Apprentice", need = 1 },
    { cap = 150, name = "Journeyman", need = 50 },
    { cap = 225, name = "Expert", need = 125 },
    { cap = 300, name = "Artisan", need = 200 },
}

-- 300 is the end of a profession, and this is not an assumption carried over from Classic - it is what
-- this build's own data says. Of the recipes we ship, the highest skill any of them needs to be LEARNED
-- is 300, and not one needs more. 520 of them have a grey rank above 300, which is the ordinary Classic
-- shape of a top recipe: it stays yellow all the way to the cap instead of going grey before it. Grey is
-- not reach. Forever's data also carries a fifth skill line per profession (a child line at
-- ParentTierIndex 4 with four rank spells), but those lines have no abilities at all, so it is the retail
-- data model coming along with the code, not content. SkillTiers, which would state a tier's maximum
-- rank outright, is in none of the four builds we have.
SW.MAX_RANK = 300

-- How far the recipes themselves reach: the highest rank at which any of them can still give a point.
-- Not a planning target - a grey rank above 300 only means a top recipe stays yellow all the way to the
-- cap - but it is a real ceiling, because no plan can go past its last recipe whatever the game allows.
local reach = {}
function SW.DataReach(prof)
    local known = reach[prof]
    if known then return known end
    local top, data = 0, SW.Data and SW.Data.professions and SW.Data.professions[prof]
    for _, r in ipairs(data and data[2] or {}) do
        if (r[6] or 0) > top then top = r[6] end        -- r[6] is the grey rank
    end
    reach[prof] = top > 0 and top or SW.MAX_RANK
    return reach[prof]
end

-- How far to plan: 300, unless a real character has stood higher, and never past the last recipe.
-- The floor is 300 because the data says so; the override is SW.CapSeen because if Forever ever turns
-- the fifth rank on, a maxRank above 300 is the first place it will show, and we would rather follow the
-- game than our own table. A canary, not a source.
function SW.Ceiling(prof)
    local seen = SW.CapSeen(prof) or 0
    return math.min(SW.DataReach(prof), seen > SW.MAX_RANK and seen or SW.MAX_RANK)
end

-- The highest maxRank any character on this account has reached in a profession, recorded as we see it
-- (Professions.ScanRanks). It exists to catch the day the answer above stops being true: nothing in the
-- client data would tell us, so the game itself has to.
function SW.CapSeen(prof)
    return (SW.DB().caps or {})[prof]
end

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

-- Item names come from the client's item cache, which may not have them yet. Ask for the data and say how
-- many times we've had to wait, so the UI can show "Loading..." and then give up gracefully.
local nameWaits, nameCache = {}, {}
function SW.ItemName(id)
    if not id or id == 0 then return nil, 0 end
    local cached = nameCache[id]
    if cached then return cached, 0 end
    local name = C_Item.GetItemNameByID(id) or C_Item.GetItemInfo(id)
    if name then
        nameWaits[id], nameCache[id] = nil, name
        return name, 0
    end
    nameWaits[id] = (nameWaits[id] or 0) + 1
    C_Item.RequestLoadItemDataByID(id)
    return nil, nameWaits[id]
end

-- Recipe items (a "Pattern: ..." on a vendor) to the recipe they teach. Built on first use: it is only
-- needed when a merchant is open.
local recipeItems
function SW.RecipeByItem(id)
    if not id then return nil end
    if not recipeItems then
        recipeItems = {}
        for prof, data in pairs(SW.Data.professions) do
            for _, r in ipairs(data[2]) do
                if (r[11] or 0) > 0 then recipeItems[r[11]] = { prof = prof, spell = r[1] } end
            end
        end
    end
    return recipeItems[id]
end

-- Where we have seen a recipe sold, learned by opening merchants. Account-wide, like the trainers.
function SW.RecipeSource(spell)
    local db = SW.DB()
    return db.sources and db.sources[spell]
end

-- Crafting, buying and training don't work in combat: say so instead of failing silently.
function SW.CombatBlocked(action)
    if not InCombatLockdown() then return false end
    SW.msg("|cffff6060can't %s in combat|r - try again when the fight is over.", action)
    return true
end

-- Money with the coin icons. GetCoinTextureString is NOT a global in Forever - it lives in
-- C_CurrencyInfo - and calling the bare global broke the vendor buy confirmation (found by the self test
-- the day it shipped). Resolve it once, call it through pcall, and write plain text if neither exists.
local CoinText = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
function SW.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    if CoinText then
        local ok, text = pcall(CoinText, copper)
        if ok and text then return text end
    end
    return SW.MoneyPlain(copper)
end

-- The same amount in plain words, for when the client can't draw the coins.
function SW.MoneyPlain(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
    if s > 0 then return ("%ds %dc"):format(s, c) end
    return ("%dc"):format(c)
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

-- Run at most once per window: later calls while one is pending are folded into it.
local coalesced = {}
function SW.Coalesce(key, delay, fn)
    if coalesced[key] then return end
    coalesced[key] = C_Timer.NewTimer(delay, function()
        coalesced[key] = nil
        fn()
    end)
end

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
        -- Fastest is the guide: the same route for everyone, from the recipe data alone, with no
        -- price anywhere in it. Cheapest is the extra that needs an auction scan. Only new
        -- installs land here - a mode already saved is a choice we do not overrule.
        mode = "fast",           -- "cheap" or "fast"
        attach = true,           -- open beside the profession window
        autoOpen = true,         -- open with the profession window
        minimal = false,         -- small window: step, materials, Craft
        -- Whether the guide is wanted at all. Set by the X on it and by its tab on the
        -- profession window, and by nothing else: closing the profession window, or Escape, is
        -- the window going away rather than a decision about the guide.
        guideClosed = false,
        trainableOpen = false,   -- the "what a trainer teaches" list on the Route page
        maxPriceAge = 3,         -- days before our own auction scan counts as stale (and is ignored)
        preferVendor = true,     -- favour recipes whose materials all come from a vendor
        useOwned = true,         -- count materials already in the bags or bank as (nearly) free
        autoReplaceEnchant = false, -- accept "replace enchant?" for enchants Skillwright started
        deepTrainerScan = true,  -- read a trainer's hidden services once per visit (the list blinks once)
        tooltipPrice = true,     -- one line on item tooltips: the auction price, and where it came from
    },
    learnRanks = {},             -- [recipeSpellID] = skill needed, read off trainers
    trainerSeen = {},            -- [recipeSpellID] = true when a trainer offers it
    specReq = {},                -- [recipeSpellID] = specialization name a trainer asked for
    vendor = {},                 -- [itemID] = unit price seen on a merchant
    ah = {},                     -- [itemID] = { unitPrice, scannedAt }
    ahScanned = 0,
    profNames = {},              -- [skillLineID] = localized name
    caps = {},                   -- [skillLineID] = the highest maxRank any character here has reached
    migrations = {},             -- one-off fixes to saved data, by name, so each runs at most once
}

-- Defaults are filled in once per saved table (not on every call: this runs in sort comparators).
local merged
function SW.DB()
    local db = SkillwrightDB
    if db and db == merged then return db end
    db = db or {}
    SkillwrightDB = db
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = (type(v) == "table") and CopyTable(v) or v end
    end
    for k, v in pairs(DEFAULTS.settings) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    merged = db
    return db
end

function SW.Settings() return SW.DB().settings end

-- WoW: Forever used to fail to load saved variables. Everything we know - prices, the skill each
-- trainer recipe needs, the colours we learned, which recipe you were following - then started empty, and
-- the guide would silently look as if the player had never used it. We say so instead, once.
-- Nothing an addon can do preserves the file: the client rewrites it at logout either way.
-- Client build 70009 fixed it. On a client that can no longer lose them, an empty store means a first
-- install - saying anything about lost data there would be a lie to every new player. The library owns
-- that judgement (LIB.SavedVariablesBugPossible); we never read the build ourselves, and an older
-- embedded library without the check keeps behaving as before.
SW.dataLost = false
SW.Listen("LOGIN", function()
    local LIB = SW.LIB
    if not (LIB and LIB.Listen) then return end
    -- Our two stores join the library's check: it compares several addons' tables before it decides, and
    -- ours are the ones that matter to this guide.
    if LIB.RegisterSavedTable then
        LIB.RegisterSavedTable(SW.DB())
        LIB.RegisterSavedTable(SW.CharDB())
    end
    LIB.Listen("SAVED_VARIABLES_EMPTY", function()
        if LIB.SavedVariablesBugPossible and not LIB.SavedVariablesBugPossible() then return end
        SW.dataLost = true
        SW.Fire("DATA_LOST")
    end)
end)

-- Cheapest used to be the default, and until today it silently planned the shortest route whenever a
-- single material had no price - which, without an auction scan, is always. So an account sitting on
-- Cheapest with no prices has never seen a cheapest route: the button said one thing and did another.
-- Those accounts move to Fastest, which is what they were getting anyway; the only thing that changes
-- is that the label stops lying. Anyone who has scanned, or who picked a mode themselves, is left
-- alone - a default is ours to change, a choice is not.
-- Runs at most once (SkillwrightDB.migrations), and does nothing at all on a second pass.
local function MigrateDefaultMode()
    local db = SW.DB()
    if db.migrations.modeToFast then return false end
    db.migrations.modeToFast = true
    local s = SW.Settings()
    local hasPrices = (db.ahScanned or 0) > 0 or (Auctionator and Auctionator.API) or TSM_API
    if s.mode ~= "cheap" or s.modeChosen or hasPrices then return false end
    s.mode = "fast"
    return true
end

SW.Listen("LOGIN", function()
    if MigrateDefaultMode() then
        SW.msg("|cffffd100Cheapest needs auction prices|r, and without them it was only ever showing the "
            .. "shortest route. You are on |cffffd100Fastest|r now, which is the same plan under its own "
            .. "name. Scan at the auction house and Cheapest becomes a real choice - /skw cheap.")
    end
end)

-- Per character: profession ranks, learned recipes and the chosen specialization.
function SW.CharDB()
    SkillwrightCharDB = SkillwrightCharDB or {}
    local c = SkillwrightCharDB
    c.profs = c.profs or {}      -- [skillLineID] = { rank, max, known = { [spell] = true }, spec }
    c.gathering = c.gathering or {}   -- [skillLineID] = true for Herbalism, Mining, Skinning
    return c
end

function SW.CharProf(id)
    local profs = SW.CharDB().profs
    local p = profs[id]
    if not p then
        p = { rank = 0, max = 0, known = {} }
        profs[id] = p
    end
    p.known = p.known or {}
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
SLASH_SKILLWRIGHT2 = "/skw"      -- not /sw: that is Blizzard's stopwatch
SlashCmdList.SKILLWRIGHT = function(input)
    local cmd = (strtrim(input or ""):match("^(%S*)") or ""):lower()
    if cmd == "" then
        SW.ToggleWindow()
    elseif cmd == "config" or cmd == "settings" then
        SW.OpenSettings()
    elseif cmd == "options" then
        SW.OpenBlizzardOptions()
    elseif cmd == "cheap" or cmd == "fast" then
        SW.SetMode(cmd)
    elseif cmd == "prices" then
        SW.Prices.PrintStatus()
    elseif cmd == "de" or cmd == "disenchant" then
        SW.Disenchant.Print()
    elseif cmd == "debug" and strtrim(input or ""):lower():match("^debug%s+drift") then
        SW.Drift.Print(false)
    elseif cmd == "debug" then
        SW.debug = not SW.debug
        SW.msg("debug %s", SW.debug and "on" or "off")
    else
        SW.msg("|cffffd100/skw|r guide, |cffffd100/skw cheap|r or |cffffd100/skw fast|r route mode, "
            .. "|cffffd100/skw prices|r price sources, |cffffd100/skw config|r settings (also under Options > AddOns > "
            .. "Skillwright, or |cffffd100/skw options|r)")
    end
end
