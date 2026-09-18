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

-- Ranks of every profession the character has, without opening any window.
function P.ScanRanks()
    local found = {}
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        for i = 1, C_SkillInfo.GetNumSkillLines() do
            local s = C_SkillInfo.GetSkillLineInfo(i)
            if s and not s.isHeader then
                local id = BaseLine(s.skillID, s.parentSkillLineID)
                if id then found[id] = { rank = s.rank, max = s.maxRank, name = s.name } end
            end
        end
    end
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            if index then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
                local id = skillLine and BaseLine(skillLine)
                if id and not found[id] then found[id] = { rank = rank, max = maxRank, name = name } end
            end
        end
    end
    local changed = false
    for id, info in pairs(found) do
        RememberName(id, info.name)
        if SW.PROFESSIONS[id] then
            local p = SW.CharProf(id)
            if p.rank ~= info.rank or p.max ~= info.max then
                p.rank, p.max = info.rank or 0, info.max or 0
                p.has = true
                changed = true
            end
            p.has = true
        end
    end
    -- Forgotten professions
    for id, p in pairs(SW.CharDB().profs) do
        if p.has and not found[id] and next(found) then
            p.has, p.rank = nil, 0
            changed = true
        end
    end
    if changed then SW.Fire("RANKS_CHANGED") end
end

function P.Rank(id)
    return SW.CharProf(id).rank or 0
end

function P.MaxRank(id)
    local m = SW.CharProf(id).max or 0
    return m > 0 and m or SW.MAX_RANK
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

-- Skill line of the profession window that is open right now (own professions only), or nil.
function P.OpenLine()
    if not ViewingOwnProfession() then return nil end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    if not info or not info.professionID or info.professionID == 0 then return nil end
    return BaseLine(info.professionID, info.parentProfessionID), info
end

local function ScanOpen()
    local id, info = P.OpenLine()
    if not id or not SW.PROFESSIONS[id] then return end
    RememberName(id, (info.parentProfessionName and info.parentProfessionName ~= "") and info.parentProfessionName or info.professionName)
    local p = SW.CharProf(id)
    local rankChanged = p.rank ~= info.skillLevel or p.max ~= info.maxSkillLevel
    p.has = true
    p.rank, p.max = info.skillLevel or p.rank, info.maxSkillLevel or p.max

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
    SW.Fire("PROFESSION_OPEN", id)
end

function P.IsOpen(id)
    local open = P.OpenLine()
    return open ~= nil and open == id
end

-- Learned right now? Live when that profession's window is open, else the last scan.
function P.Knows(id, spell)
    if P.IsOpen(id) then
        local ri = C_TradeSkillUI.GetRecipeInfo(spell)
        return ri and ri.learned or false
    end
    return SW.CharProf(id).known[spell] or false
end

SW.On("TRADE_SKILL_SHOW", function() SW.Debounce("scanTrade", 0.3, ScanOpen) end)
SW.On("TRADE_SKILL_LIST_UPDATE", function() SW.Debounce("scanTrade", 1, ScanOpen) end)
SW.On("NEW_RECIPE_LEARNED", function() SW.Debounce("scanTrade", 1, ScanOpen) end)
SW.On("TRADE_SKILL_CLOSE", function()
    SW.Fire("PROFESSION_CLOSED")
    SW.Debounce("scanRanks", 0.5, P.ScanRanks)
end)
SW.On("SKILL_LINES_CHANGED", function() SW.Debounce("scanRanks", 0.5, P.ScanRanks) end)
SW.On("CHAT_MSG_SKILL", function() SW.Debounce("scanRanks", 0.3, P.ScanRanks) end)
SW.Listen("LOGIN", function() C_Timer.After(2, P.ScanRanks) end)
