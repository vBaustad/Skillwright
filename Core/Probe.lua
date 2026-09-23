-- Skillwright - /skw debug passives: a research probe, hidden from the help text. Lists what the game says the
-- character's professions give (passive spells in the spellbook, profession spell lists) and flags helpful
-- auras whose text mentions a stat or a percentage, so a profession passive that only shows as an aura is
-- caught too. Printed and saved to SkillwrightDB.debug.passives[character] (read it from WTF after logout).
-- Out of combat only: in combat every aura is secret.
local ADDON, SW = ...
local Probe = {}
SW.Probe = Probe

local STAT_WORDS = { "stamina", "strength", "agility", "intellect", "spirit", "%%" }

local function Flagged(text)
    local t = (text or ""):lower()
    for _, w in ipairs(STAT_WORDS) do
        if t:find(w) then return true end
    end
    return false
end

local function Desc(spellID)
    if not spellID then return "" end
    if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
    local ok, d = pcall(C_Spell.GetSpellDescription, spellID)
    return ok and d or ""
end

local function Oneline(s)
    return (s or ""):gsub("[\r\n]+", " ")
end

-- Every spellbook item in the player bank, with the tab it's under.
local function Spellbook(out)
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then
        out.notes[#out.notes + 1] = "C_SpellBook skill-line API missing"
        return
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for line = 1, SB.GetNumSpellBookSkillLines() or 0 do
        local info = SB.GetSpellBookSkillLineInfo(line)
        if info then
            local offset, n = info.itemIndexOffset or 0, info.numSpellBookItems or 0
            for slot = offset + 1, offset + n do
                local ok, item = pcall(SB.GetSpellBookItemInfo, slot, bank)
                if ok and item and item.spellID then
                    local d = Desc(item.spellID)
                    out.spellbook[#out.spellbook + 1] = {
                        tab = info.name, spell = item.spellID, name = item.name, sub = item.subName,
                        passive = item.isPassive and true or false, desc = Oneline(d), flag = Flagged(d) or nil,
                    }
                end
            end
        end
    end
end

-- The profession entries (GetProfessions / GetProfessionInfo) and the spells listed under each.
local function Professions(out)
    if not (GetProfessions and GetProfessionInfo) then
        out.notes[#out.notes + 1] = "GetProfessions missing"
        return
    end
    local ok, a, b, c, d, e = pcall(GetProfessions)
    if not ok then
        out.notes[#out.notes + 1] = "GetProfessions failed: " .. tostring(a)
        return
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for _, index in ipairs({ a, b, c, d, e }) do
        if index then
            local ok2, name, _, rank, maxRank, numSpells, spellOffset, skillLine = pcall(GetProfessionInfo, index)
            if ok2 and name then
                local p = { name = name, rank = rank, max = maxRank, skillLine = skillLine, spells = {} }
                for slot = (spellOffset or 0) + 1, (spellOffset or 0) + (numSpells or 0) do
                    local ok3, item = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                    if ok3 and item and item.spellID then
                        local dsc = Desc(item.spellID)
                        p.spells[#p.spells + 1] = { spell = item.spellID, name = item.name,
                            passive = item.isPassive and true or false, desc = Oneline(dsc), flag = Flagged(dsc) or nil }
                    end
                end
                out.professions[#out.professions + 1] = p
            end
        end
    end
end

-- Helpful auras, with their tooltip text (which has the real numbers) and the spell description.
local function Auras(out)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        out.notes[#out.notes + 1] = "C_UnitAuras missing"
        return
    end
    for i = 1, 80 do
        if C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret and C_Secrets.ShouldUnitAuraIndexBeSecret("player", i, "HELPFUL") then
            out.notes[#out.notes + 1] = "aura " .. i .. " is secret - stopped"
            break
        end
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local tip = {}
        if C_TooltipInfo and C_TooltipInfo.GetUnitBuff then
            local ok, data = pcall(C_TooltipInfo.GetUnitBuff, "player", i)
            if ok and data and data.lines then
                for _, l in ipairs(data.lines) do
                    if l.leftText and l.leftText ~= "" then tip[#tip + 1] = l.leftText end
                end
            end
        end
        local d = Desc(aura.spellId)
        local text = table.concat(tip, " / ")
        out.auras[#out.auras + 1] = {
            spell = aura.spellId, name = aura.name, duration = aura.duration, permanent = (aura.duration or 0) == 0 or nil,
            tooltip = Oneline(text), desc = Oneline(d), flag = (Flagged(text) or Flagged(d)) or nil,
        }
    end
end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    return v
end

-- Max health against what Stamina accounts for, to catch a hidden "+x% health" aura: compare the implied
-- base between two characters of the same race, class and level, with and without the profession.
-- Stamina rule used (vanilla): the first 20 give 1 health each, the rest 10. If Forever scales Stamina
-- differently the implied base is off by the same amount on both characters, so the comparison still holds.
local function Health(out)
    local h = { max = Plain(UnitHealthMax("player")) }
    local ok, base, stat, pos, neg = pcall(UnitStat, "player", 3)
    if ok then h.stamina = { base = Plain(base), effective = Plain(stat), pos = Plain(pos), neg = Plain(neg) } end
    if GetUnitMaxHealthModifier then
        local ok2, m = pcall(GetUnitMaxHealthModifier, "player")
        if ok2 then h.modifier = Plain(m) end
    end
    if type(h.max) == "number" and h.stamina and type(h.stamina.effective) == "number" then
        local sta = h.stamina.effective
        h.fromStamina = math.min(sta, 20) + math.max(sta - 20, 0) * 10
        h.impliedBase = h.max - h.fromStamina
        if type(h.modifier) == "number" and h.modifier > 0 then
            h.impliedBaseNoMod = math.floor(h.max / h.modifier + 0.5) - h.fromStamina
        end
    end
    out.health = h
end

-- Resistances (Herbalism's announced "Natural Talent" is resistance to all schools, rising with skill).
local SCHOOLS = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
local function Resists(out)
    if not UnitResistance then return end
    out.resist = {}
    for i, name in ipairs(SCHOOLS) do
        local ok, base, total, bonus, minus = pcall(UnitResistance, "player", i)
        if ok then out.resist[name] = { base = Plain(base), total = Plain(total), bonus = Plain(bonus), minus = Plain(minus) } end
    end
end

local MAX_ROWS = 200      -- rows kept per list in the saved dump
local MAX_CHARS = 3       -- characters kept in the saved dump

local function Cap(list, n)
    for i = #list, n + 1, -1 do list[i] = nil end
end

-- Keep the newest few characters only.
local function Prune(saved)
    local names = {}
    for name in pairs(saved) do names[#names + 1] = name end
    if #names <= MAX_CHARS then return end
    table.sort(names, function(a, b) return (saved[a].time or "") > (saved[b].time or "") end)
    for i = MAX_CHARS + 1, #names do saved[names[i]] = nil end
end

-- Known spell IDs to confirm with IsPlayerSpell (the camp passives found in the data).
local CANDIDATES = { 1278062, 1278067, 1278068 }

function Probe.Passives(quiet)
    if InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
        SW.msg("leave combat first - auras can't be read in combat.")
        return
    end
    local _, build = GetBuildInfo()
    local out = {
        time = date("%Y-%m-%d %H:%M:%S"), build = build, char = UnitName("player") .. "-" .. (GetNormalizedRealmName() or ""),
        class = select(2, UnitClass("player")), race = select(2, UnitRace("player")), level = UnitLevel("player"),
        ranks = {},
        spellbook = {}, professions = {}, auras = {}, candidates = {}, notes = {},
    }
    for _, id in ipairs(CANDIDATES) do out.candidates[id] = IsPlayerSpell and IsPlayerSpell(id) or false end
    -- every profession rank the character has (C_SkillInfo, gathering included)
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        for id in pairs(SW.ALL_LINES) do
            local s = C_SkillInfo.GetSkillLineInfoByID(id)
            if s and (s.rank or 0) > 0 then out.ranks[id] = { name = s.name, rank = s.rank, max = s.maxRank } end
        end
    end
    for _, step in ipairs({ Spellbook, Professions, Auras, Health, Resists }) do
        local ok, err = pcall(step, out)
        if not ok then out.notes[#out.notes + 1] = "error: " .. tostring(err) end
    end
    -- A research dump, so it is capped on both ends: a few entries per list, a few characters in all.
    Cap(out.spellbook, MAX_ROWS)
    Cap(out.auras, MAX_ROWS)
    Cap(out.notes, MAX_ROWS)
    for _, p in ipairs(out.professions) do Cap(p.spells, MAX_ROWS) end
    local db = SW.DB()
    db.debug = db.debug or {}
    db.debug.passives = db.debug.passives or {}
    db.debug.passives[out.char] = out
    Prune(db.debug.passives)
    if quiet then return out end

    SW.msg("passives probe (%s, %s %s level %s, build %s):", out.char, tostring(out.race), tostring(out.class),
        tostring(out.level), tostring(build))
    local rk = {}
    for _, r in pairs(out.ranks) do rk[#rk + 1] = ("%s %d/%d"):format(r.name or "?", r.rank or 0, r.max or 0) end
    table.sort(rk)
    SW.msg("  |cffffd100Professions|r %s", #rk > 0 and table.concat(rk, ", ") or "none")
    local h = out.health
    if h then
        local sta = h.stamina or {}
        SW.msg("  |cffffd100Health|r max %s, Stamina %s (base %s, +%s, -%s) = %s health, implied base %s, max-health modifier %s",
            tostring(h.max), tostring(sta.effective), tostring(sta.base), tostring(sta.pos), tostring(sta.neg),
            tostring(h.fromStamina), tostring(h.impliedBase), tostring(h.modifier or "n/a"))
        if type(h.modifier) == "number" and math.abs(h.modifier - 1) > 0.001 then
            SW.msg("  |cffff8000[stat]|r max health is multiplied by %.3f - a hidden health bonus (profession or other)", h.modifier)
        end
    end
    if out.resist then
        local parts = {}
        for _, name in ipairs(SCHOOLS) do
            local r = out.resist[name]
            if r then parts[#parts + 1] = ("%s %s (base %s)"):format(name, tostring(r.total), tostring(r.base)) end
        end
        SW.msg("  |cffffd100Resistances|r %s", table.concat(parts, ", "))
    end
    for _, p in ipairs(out.professions) do
        SW.msg("  |cffffd100%s|r %s/%s (line %s): %d spells", p.name, tostring(p.rank), tostring(p.max), tostring(p.skillLine), #p.spells)
        for _, s in ipairs(p.spells) do
            if s.passive or s.flag then
                SW.msg("    %s%s %d %s: %s", s.passive and "[passive]" or "", s.flag and "|cffff8000[stat]|r" or "", s.spell, s.name or "?", s.desc)
            end
        end
    end
    local passives = 0
    for _, s in ipairs(out.spellbook) do
        if s.passive then
            passives = passives + 1
            if s.flag then SW.msg("  |cffff8000[stat]|r spellbook passive %d %s (%s): %s", s.spell, s.name or "?", s.tab or "?", s.desc) end
        end
    end
    SW.msg("  spellbook: %d spells, %d passive", #out.spellbook, passives)
    for _, a in ipairs(out.auras) do
        if a.flag then
            SW.msg("  |cffff8000[stat]|r aura %d %s%s: %s", a.spell or 0, a.name or "?", a.permanent and " (permanent)" or "",
                a.tooltip ~= "" and a.tooltip or a.desc)
        end
    end
    SW.msg("  auras: %d helpful. Camp passives known: %s/%s/%s", #out.auras,
        tostring(out.candidates[1278062]), tostring(out.candidates[1278067]), tostring(out.candidates[1278068]))
    for _, n in ipairs(out.notes) do SW.msg("  note: %s", n) end
    SW.msg("  saved to SkillwrightDB.debug.passives - log out (or /reload) to write it to WTF.")
    return out
end

-- Spell descriptions load on demand: run twice, the second time (1 s later) with the text filled in.
function Probe.Run()
    Probe.Passives(true)
    C_Timer.After(1, function() Probe.Passives() end)
end
