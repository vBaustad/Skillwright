-- Skillwright - drift: how far our datamined recipe data is from what the game actually says.
-- The open profession window is the one place the client hands us the truth for recipes the character
-- knows: the grey threshold (maxTrivialLevel), how many skill points a craft gives, and the reagents.
-- Nothing here is shown to players; it is numbers for us, printed by /skw debug, so we can decide whether
-- the data needs regenerating from a newer build.
local ADDON, SW = ...
local D = {}
SW.Drift = D

local F_SPELL, F_YELLOW, F_GREY, F_UPS, F_MATS = 1, 5, 6, 7, 10
local PER_PASS = 25          -- recipes whose reagents we read per window open: the schematic read is the slow one

local function Row(prof, spell)
    local data = SW.Data.professions[prof]
    if not data then return nil end
    D.index = D.index or {}
    local byProf = D.index[prof]
    if not byProf then
        byProf = {}
        for _, r in ipairs(data[2]) do byProf[r[F_SPELL]] = r end
        D.index[prof] = byProf
    end
    return byProf[spell]
end

-- Reagents the game lists for a recipe: { [itemID] = count }, or nil when the API won't say.
local function Reagents(spell)
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return nil end
    local ok, schematic = pcall(T.GetRecipeSchematic, spell, false)
    if not ok or not schematic or not schematic.reagentSlotSchematics then return nil end
    local out, n = {}, 0
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID then
            out[first.itemID] = (out[first.itemID] or 0) + (slot.quantityRequired or 1)
            n = n + 1
        end
    end
    if n == 0 then return nil end
    return out
end

local function SameMats(row, live)
    local ours, n = {}, 0
    local mats = row[F_MATS]
    for i = 1, #mats, 2 do
        ours[mats[i]] = mats[i + 1]
        n = n + 1
    end
    local m = 0
    for id, count in pairs(live) do
        m = m + 1
        if ours[id] ~= count then return false end
    end
    return n == m
end

-- What the game showed us about a recipe's thresholds, kept account-wide and preferred by the solver.
--   grey  = maxTrivialLevel, which the client states outright.
--   yellow = not stated, but bounded by the colour at the skill we are standing on: a recipe still shown
--            as "optimal" (orange) at skill 39 cannot turn yellow at or below 39, whatever our data says.
local function Learn(spell, row, info, rank)
    local db = SW.DB()
    db.colors = db.colors or {}
    local e = db.colors[spell] or {}
    local changed = false

    local grey = info.maxTrivialLevel
    if grey and grey > 0 and e.grey ~= grey then
        e.grey, changed = grey, true
    end

    -- Enum.TradeskillRelativeDifficulty: 0 Optimal (orange), 1 Medium (yellow), 2 Easy (green), 3 Trivial
    local diff = info.relativeDifficulty
    if diff ~= nil and rank and rank > 0 then
        local yellow = e.yellow or row[F_YELLOW]
        if diff == 0 and yellow <= rank then
            e.yellow, changed = rank + 1, true       -- still orange here: yellow must be higher
        elseif diff == 1 and yellow > rank then
            e.yellow, changed = rank, true           -- already yellow here: yellow can be no higher
        end
    end

    if changed then
        db.colors[spell] = e
        return true
    end
    return false
end

-- Compare what the open window says with what our data says, and keep the tally.
function D.Scan(prof)
    local t = debugprofilestop and debugprofilestop()
    local rank = SW.Prof.Rank(prof)
    local T = C_TradeSkillUI
    if not (prof and T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
    local ok, ids = pcall(T.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return end
    local db = SW.DB()
    db.tsDrift = db.tsDrift or { checked = 0, grey = 0, ups = 0, mats = 0, matsChecked = 0 }
    local d = db.tsDrift
    local seen, learned = 0, false
    for _, spell in ipairs(ids) do
        local row = Row(prof, spell)
        if row then
            local info = T.GetRecipeInfo(spell)
            if info and info.learned then
                d.checked = d.checked + 1
                if Learn(spell, row, info, rank) then learned = true end
                local grey = info.maxTrivialLevel
                if grey and grey > 0 and grey ~= row[F_GREY] then
                    d.grey = d.grey + 1
                    d.greyWorst = math.max(d.greyWorst or 0, math.abs(grey - row[F_GREY]))
                    d.greyExample = spell
                end
                local ups = info.numSkillUps
                if ups and ups > 0 and ups ~= row[F_UPS] then
                    d.ups = d.ups + 1
                    d.upsExample = spell
                end
                if seen < PER_PASS then
                    local live = Reagents(spell)
                    if live then
                        seen = seen + 1
                        d.matsChecked = d.matsChecked + 1
                        if not SameMats(row, live) then
                            d.mats = d.mats + 1
                            d.matsExample = spell
                        end
                    end
                end
            end
        end
    end
    if t then SW.dbg("drift scan took %.0f ms", debugprofilestop() - t) end
    D.Print(true)
    -- Better thresholds change the route, so it has to be worked out again.
    if learned then SW.Fire("COLORS_CHANGED", prof) end
end

-- The tally, for /skw debug. Quiet unless there is something to say.
function D.Print(onlyIfDebug)
    local d = SW.DB().tsDrift
    if not d or d.checked == 0 then
        if not onlyIfDebug then SW.msg("no recipes compared yet - open a profession window.") end
        return
    end
    local function pct(n) return 100 * n / math.max(1, d.checked) end
    local corrected = 0
    for _ in pairs(SW.DB().colors or {}) do corrected = corrected + 1 end
    local line = ("drift: %d recipes compared, grey differs %d (%.0f%%, worst %d), skill-ups differ %d (%.0f%%), "
        .. "reagents differ %d of %d read, %d recipes corrected from what the game showed"):format(
        d.checked, d.grey, pct(d.grey), d.greyWorst or 0, d.ups, pct(d.ups), d.mats, d.matsChecked, corrected)
    if onlyIfDebug then SW.dbg("%s", line) else SW.msg("%s", line) end
end

-- Once per profession window. It used to run on every update too, which meant a full pass (and 25
-- schematic reads) after every single craft - felt as lag while crafting.
local done
SW.Listen("PROFESSION_OPEN", function(prof)
    if done == prof then return end
    done = prof
    SW.Debounce("drift", 1, function() D.Scan(prof) end)
end)
SW.Listen("PROFESSION_CLOSED", function() done = nil end)
