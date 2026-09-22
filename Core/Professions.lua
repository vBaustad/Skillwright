-- Skillwright - professions: ranks, learned recipes and the open profession window.
local ADDON, SW = ...
local P = {}
SW.Prof = P

-- Map a skill line (possibly a child tier line) to the base profession line we plan with.
local function BaseLine(id, parent)
    if SW.ALL_LINES[id] then return id end
    if parent and SW.ALL_LINES[parent] then return parent end
    return nil
end

local function RememberName(id, name)
    if id and name and name ~= "" then SW.DB().profNames[id] = name end
end

local GATHERING = { [182] = true, [186] = true, [393] = true }   -- Herbalism, Mining, Skinning
local SECONDARY = { [185] = true, [129] = true }                 -- Cooking, First Aid

-- Ranks of every profession the character has, without opening any window. Asked per skill line ID:
-- walking the skill list by index only sees lines under expanded headers, and a collapsed
-- "Professions" header would make every profession look forgotten.
function P.ScanRanks()
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return end
    local changed = false
    for id in pairs(SW.ALL_LINES) do
        local s = C_SkillInfo.GetSkillLineInfoByID(id)
        local has = s and not s.isHeader and (s.rank or 0) > 0
        if has then RememberName(id, s.name) end
        if GATHERING[id] then
            local g = SW.CharDB().gathering
            if (g[id] or false) ~= (has or false) then
                g[id] = has or nil
                changed = true
            end
        end
        if SW.PROFESSIONS[id] then
            local p = SW.CharProf(id)
            if has then
                if not p.has or p.rank ~= s.rank or p.max ~= s.maxRank then
                    p.has, p.rank, p.max = true, s.rank, s.maxRank or 0
                    changed = true
                end
            elseif p.has then
                p.has, p.rank = nil, 0      -- forgotten (unlearned at a trainer)
                changed = true
            end
        end
    end
    P.scanned = true
    if changed then SW.Fire("RANKS_CHANGED") end
end

-- The character has no crafting profession Skillwright plans (gathering ones don't count, nor do Cooking and
-- First Aid). False until the skill lines have been read once, so a slow login never flashes "choose one".
function P.NoCrafting()
    if not P.scanned then return false end
    for id in pairs(SW.PROFESSIONS) do
        if not SECONDARY[id] and SW.CharProf(id).has then return false end
    end
    return true
end

-- The character's gathering professions (skill line IDs, in a fixed order).
function P.Gathering()
    local list, g = {}, SW.CharDB().gathering
    for _, id in ipairs({ 186, 182, 393 }) do
        if g[id] then list[#list + 1] = id end
    end
    return list
end

-- Learned recipes without opening the profession window: IsPlayerSpell knows recipe spells in Forever
-- (verified in game), so the route and shopping list are right even before the window has been opened.
-- It only ever adds: the window scan (below) stays the full truth while the window is open.
function P.ScanKnownSpells()
    if not IsPlayerSpell then return end
    for id, data in pairs(SW.Data.professions) do
        local p = SW.CharDB().profs[id]
        if p and p.has then
            p.known = p.known or {}
            local added = false
            for _, r in ipairs(data[2]) do
                if not p.known[r[1]] and IsPlayerSpell(r[1]) then
                    p.known[r[1]] = true
                    added = true
                end
            end
            if added then SW.Fire("RECIPES_CHANGED", id) end
        end
    end
end

function P.Rank(id)
    return SW.CharProf(id).rank or 0
end

-- Professions this character has that Skillwright can plan, sorted by name.
function P.Mine()
    local list = {}
    for id in pairs(SW.PROFESSIONS) do
        local p = SW.CharDB().profs[id]
        if p and p.has then list[#list + 1] = id end
    end
    table.sort(list, function(a, b) return SW.ProfName(a) < SW.ProfName(b) end)
    return list
end

-- Every plannable profession: the character's own first, then the rest (for previewing).
function P.All()
    local mine, seen, list = P.Mine(), {}, {}
    for _, id in ipairs(mine) do list[#list + 1] = id; seen[id] = true end
    local rest = {}
    for id in pairs(SW.PROFESSIONS) do if not seen[id] then rest[#rest + 1] = id end end
    table.sort(rest, function(a, b) return SW.ProfName(a) < SW.ProfName(b) end)
    for _, id in ipairs(rest) do list[#list + 1] = id end
    return list
end

-- ---------------------------------------------------------------------------
-- The open profession window
-- ---------------------------------------------------------------------------
local function ViewingOwnProfession()
    local T = C_TradeSkillUI
    if not T or not T.IsTradeSkillReady or not T.IsTradeSkillReady() then return false end
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
    if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
    return true
end

-- The profession window that is open (own professions only): { id = base line, info = profession info }.
-- Read when it opens and kept until it closes, so refreshes don't keep asking the client.
-- Where it comes from: GetChildProfessionInfo(), and when that has no profession (professionID 0: Forever has
-- no expansion tiers) the info Blizzard's own window stored, ProfessionsFrame.professionInfo. Blizzard gets
-- that one from GetBaseProfessionInfo, which addon code can't call (it raises the "blocked action" dialog).
local open = nil
local windowOpen = false     -- between TRADE_SKILL_SHOW and TRADE_SKILL_CLOSE
local pendingOpen = false    -- the window opened and the guide hasn't been told yet
local retries = 0
local MAX_RETRIES = 10       -- x 0.5 s: the data can come a moment after TRADE_SKILL_SHOW

local function ReadOpen()
    if not ViewingOwnProfession() then return nil end
    local child = C_TradeSkillUI.GetChildProfessionInfo()
    if child and child.professionID and child.professionID ~= 0 then
        local id = BaseLine(child.professionID, child.parentProfessionID)
        if id then return { id = id, info = child } end
    end
    local shown = ProfessionsFrame and ProfessionsFrame.professionInfo
    if shown and shown.professionID and shown.professionID ~= 0 then
        local id = BaseLine(shown.professionID, shown.parentProfessionID)
        if id then return { id = id, info = shown } end
    end
    return nil
end

function P.OpenLine()
    if open then return open.id, open.info end
end

-- PROFESSION_OPEN once per opening of the profession window (as soon as its data is there - also when it is
-- the same profession as last time) and when it switches profession; rescans of an open window (a craft, a
-- new recipe) fire PROFESSION_UPDATED, which only refreshes - so a guide you closed stays closed.
local ScanOpen
ScanOpen = function()
    if not windowOpen then return end
    local before = open and open.id
    open = ReadOpen()
    local id, info = P.OpenLine()
    if not id then
        -- not ready yet: try again shortly while the opening is still unannounced
        if pendingOpen and retries < MAX_RETRIES then
            retries = retries + 1
            SW.Debounce("scanTrade", 0.5, ScanOpen)
        end
        return
    end
    if not SW.PROFESSIONS[id] then pendingOpen = false return end   -- a gathering profession
    RememberName(id, (info.parentProfessionName and info.parentProfessionName ~= "") and info.parentProfessionName or info.professionName)
    local p = SW.CharProf(id)
    local level, maxLevel = info.skillLevel, info.maxSkillLevel
    if not level or level == 0 then level, maxLevel = p.rank, p.max end
    local rankChanged = p.rank ~= level or p.max ~= maxLevel
    p.has = true
    p.rank, p.max = level or p.rank, maxLevel or p.max

    -- Ask the client about every recipe in the data; the window's filters can't hide any this way.
    local known, changed = {}, false
    local data = SW.Data.professions[id]
    if data then
        for _, r in ipairs(data[2]) do
            local ri = C_TradeSkillUI.GetRecipeInfo(r[1])
            if ri and ri.learned then known[r[1]] = true end
        end
    end
    for spell in pairs(known) do if not p.known[spell] then changed = true end end
    for spell in pairs(p.known) do if not known[spell] then changed = true end end
    p.known = known
    SW.dbg("scanned %s: rank %d/%d", SW.ProfName(id), p.rank, p.max)
    if changed then SW.Fire("RECIPES_CHANGED", id) end
    if rankChanged then SW.Fire("RANKS_CHANGED", id) end
    if pendingOpen or (before and id ~= before) then
        pendingOpen = false
        SW.Fire("PROFESSION_OPEN", id)
    else
        SW.Fire("PROFESSION_UPDATED", id)
    end
end

function P.IsOpen(id)
    local current = P.OpenLine()
    return current ~= nil and current == id
end

-- Learned right now? Live when that profession's window is open, else the last scan.
function P.Knows(id, spell)
    if P.IsOpen(id) then
        local ri = C_TradeSkillUI.GetRecipeInfo(spell)
        return ri and ri.learned or false
    end
    return SW.CharProf(id).known[spell] or false
end

SW.On("TRADE_SKILL_SHOW", function()
    windowOpen, pendingOpen, retries = true, true, 0
    SW.Debounce("scanTrade", 0.3, ScanOpen)
end)
SW.On("TRADE_SKILL_LIST_UPDATE", function() if windowOpen then SW.Debounce("scanTrade", 1, ScanOpen) end end)
SW.On("NEW_RECIPE_LEARNED", function()
    if windowOpen then SW.Debounce("scanTrade", 1, ScanOpen) else SW.Debounce("scanKnown", 1, P.ScanKnownSpells) end
end)
SW.On("TRADE_SKILL_CLOSE", function()
    windowOpen, pendingOpen, open = false, false, nil
    SW.Debounce("scanTrade", 0, function() end)   -- drop a scan still waiting for the closed window
    SW.Fire("PROFESSION_CLOSED")
    SW.Debounce("scanRanks", 0.5, P.ScanRanks)
end)
SW.On("SKILL_LINES_CHANGED", function() SW.Debounce("scanRanks", 0.5, P.ScanRanks) end)
SW.On("CHAT_MSG_SKILL", function() SW.Debounce("scanRanks", 0.3, P.ScanRanks) end)
SW.Listen("LOGIN", function()
    C_Timer.After(2, function()
        P.ScanRanks()
        P.ScanKnownSpells()
    end)
end)
