-- Skillwright - route solver.
-- Plans the cheapest or fastest way from the current skill to the target, from the datamined recipe table.
-- Pure Lua (no WoW API) so it can be tested outside the game: everything live comes in through `opts`.
local ADDON, SW = ...

local floor, ceil, max, min, huge = math.floor, math.ceil, math.max, math.min, math.huge

-- recipe field positions in SW.Data.professions[prof][2][i]
local F_SPELL, F_ITEM, F_QTY, F_LEARN, F_YELLOW, F_GREY, F_UPS, F_SRC, F_STATION, F_MATS, F_RITEM, F_CAMP =
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12

-- Trainers don't publish the skill a recipe needs to learn; this estimate is replaced by the real value as
-- soon as the player opens a trainer (SkillwrightDB.learnRanks). Conservative on purpose: planning a recipe
-- slightly late costs little, planning it before it can be learned breaks the route.
local LEARN_GAP = 10
local LEARN_GAP_FALLBACK = 30    -- used only where the conservative estimate leaves no recipe at all
local SWITCH_PENALTY = 3         -- switching recipe costs as much as ~3 skill points (fewer, longer steps)
local FAST_GOLD_WEIGHT = 1 / (20 * 10000) -- fast mode: 20g of mats counts as one extra craft (tie-breaker)

SW.Solver = SW.Solver or {}
local Solver = SW.Solver

local function itemFacts(id)
    return SW.Data.items and SW.Data.items[id]
end

-- Skill-up chance at `rank` (vanilla formula): orange 100%, yellow/green fall linearly to 0 at grey.
function Solver.Chance(yellow, grey, rank)
    if rank < yellow then return 1 end
    if rank >= grey then return 0 end
    return (grey - rank) / (grey - yellow)
end

function Solver.Color(yellow, grey, rank)
    if rank < yellow then return "orange" end
    if rank >= grey then return "grey" end
    if rank < floor((yellow + grey) / 2) then return "yellow" end
    return "green"
end

-- Returns learnRank, isEstimate
function Solver.LearnRank(r, opts, fallback)
    local spell = r[F_SPELL]
    local known = opts.learnRanks and opts.learnRanks[spell]
    if known then return known, false end
    if r[F_LEARN] > 0 then return r[F_LEARN], false end
    if r[F_SRC] == "a" then return 1, false end
    return max(1, r[F_YELLOW] - (fallback and LEARN_GAP_FALLBACK or LEARN_GAP)), true
end

-- Whether a recipe may be used at all (source + station rules), independent of rank.
local function usable(r, opts)
    if r[F_CAMP] and not opts.allowCamp then return false end
    if opts.exclude and opts.exclude[r[F_SPELL]] then return false end
    if opts.known and opts.known[r[F_SPELL]] then return true end
    local src = r[F_SRC]
    if src == "t" or src == "a" then return true end
    -- specialization recipes: when the player has (or plans) that specialization
    local spec = src:match("^s:(.+)$")
    if spec then return opts.spec ~= nil and opts.spec == spec end
    -- recipe items ("r") and quest rewards ("q"): only once learned, their sources aren't known yet
    return false
end

---------------------------------------------------------------------------------------------------- prices

-- Price of one unit, in copper, plus where it came from: "ah", "vendor", "craft" or "est".
-- opts.market(id) -> copper|nil is the live market price (auction scan, Auctionator, TSM ...).
function Solver.NewPricer(prof, opts)
    local cache, busy = {}, {}
    local makers = {}
    for _, r in ipairs(SW.Data.professions[prof][2]) do
        if r[F_ITEM] > 0 and usable(r, opts) and not makers[r[F_ITEM]] then makers[r[F_ITEM]] = r end
    end
    local pricer
    pricer = function(id)
        local c = cache[id]
        if c then return c[1], c[2] end
        local facts = itemFacts(id)
        local best, src = nil, nil
        local vendor = (opts.vendorPrices and opts.vendorPrices[id]) or (facts and facts[1] > 0 and facts[1])
        if vendor then best, src = vendor, "vendor" end
        local ah = opts.market and opts.market(id)
        if ah and ah > 0 and (not best or ah < best) then best, src = ah, "ah" end
        -- an intermediate this profession makes (bolts of cloth, cured leather, bars ...)
        local maker = makers[id]
        if maker and not busy[id] then
            busy[id] = true
            local sum, mats = 0, maker[F_MATS]
            for i = 1, #mats, 2 do sum = sum + mats[i + 1] * (pricer(mats[i])) end
            busy[id] = nil
            sum = sum / max(1, maker[F_QTY])
            if not best or sum < best then best, src = sum, "craft" end
        end
        if not best or src == "craft" then
            -- no market data: a rough guess from the vendor sell price (also caps chains of crafted
            -- intermediates, which multiply up quickly when their own inputs are guesses)
            local est = facts and max(1, facts[2] * 4) or 1000
            if not best or est < best then best, src = est, "est" end
        end
        cache[id] = { best, src }
        return best, src
    end
    return pricer
end

-- Mats cost of one craft minus what the product sells to a vendor for (never below 10% of the mats).
local function craftCost(r, price)
    local sum, mats = 0, r[F_MATS]
    for i = 1, #mats, 2 do sum = sum + mats[i + 1] * (price(mats[i])) end
    local facts = r[F_ITEM] > 0 and itemFacts(r[F_ITEM])
    if facts and not facts[4] then
        sum = max(sum - facts[2] * r[F_QTY], sum * 0.1)
    end
    return sum
end

-- Recipes the player can't use yet (recipe items, quests, specializations) that would carry the route past
-- `rank`: orange or yellow there and learnable by then. Cheapest per skill-up first.
function Solver.GapOptions(prof, rank, opts, price, limit)
    local list = {}
    for _, r in ipairs(SW.Data.professions[prof][2]) do
        if not usable(r, opts) and not (r[F_CAMP] and not opts.allowCamp) then
            local learn = Solver.LearnRank(r, opts, true)
            local p = Solver.Chance(r[F_YELLOW], r[F_GREY], rank)
            if learn <= rank and p >= 0.5 then
                list[#list + 1] = { spell = r[F_SPELL], item = r[F_ITEM], source = r[F_SRC], recipeItem = r[F_RITEM],
                                    yellow = r[F_YELLOW], grey = r[F_GREY], learn = learn,
                                    score = craftCost(r, price) / p }
            end
        end
    end
    table.sort(list, function(a, b) return a.score < b.score end)
    for i = (limit or 6) + 1, #list do list[i] = nil end
    return list
end

---------------------------------------------------------------------------------------------------- solve

-- opts:
--   from, to      skill range (to defaults to 300)
--   mode          "cheap" or "fast"
--   known         { [spell] = true } recipes the character has learned
--   learnRanks    { [spell] = rank } skill needed to learn, seen at trainers
--   vendorPrices  { [item] = copper } unit prices seen on merchants
--   market        function(item) -> copper|nil
--   allowCamp     include recipes that need a camp station
--   exclude       { [spell] = true } recipes the player doesn't want
-- Returns { steps = { step, ... }, crafts = n, cost = copper, gapAt = rank|nil }
-- step = { from, to, spell, item, qty, crafts, mats = { {id, count}, ... }, cost, source, learn, learnEstimated }
function Solver.Solve(prof, opts)
    local data = SW.Data.professions[prof]
    if not data then return nil end
    local from, to = opts.from or 1, opts.to or 300
    local fast = opts.mode == "fast"
    local price = Solver.NewPricer(prof, opts)

    local cands = {}
    for _, r in ipairs(data[2]) do
        if usable(r, opts) then
            cands[#cands + 1] = { r = r, cost = craftCost(r, price) }
        end
    end

    -- per-attempt cost of recipe c at rank `rank`, or nil when it can't give a skill-up there
    local function stepCost(c, rank, fallback)
        local r = c.r
        local learn = Solver.LearnRank(r, opts, fallback)
        if learn > rank then return nil end
        local p = Solver.Chance(r[F_YELLOW], r[F_GREY], rank)
        if p <= 0 then return nil end
        if fast then return (1 + c.cost * FAST_GOLD_WEIGHT) / p end
        return c.cost / p
    end

    -- f[rank][ci] = cost of reaching `to` from `rank` crafting cands[ci] now
    local f, best, bestStep, fb = {}, {}, {}, {}
    best[to], bestStep[to] = 0, 0
    for rank = to - 1, from, -1 do
        local row, b, bs = {}, huge, huge
        local usedFallback = false
        for pass = 1, 2 do
            local fallback = pass == 2
            for ci, c in ipairs(cands) do
                local sc = stepCost(c, rank, fallback)
                if sc then
                    local nxt = min(rank + max(1, c.r[F_UPS]), to)
                    local tail
                    if nxt >= to then
                        tail = 0
                    else
                        local stay = f[nxt] and f[nxt][ci]
                        local switch = best[nxt] + SWITCH_PENALTY * bestStep[nxt]
                        tail = (stay and stay < switch) and stay or switch
                    end
                    local v = sc + tail
                    row[ci] = v
                    if v < b then b = v end
                    if sc < bs then bs = sc end
                end
            end
            if b < huge then usedFallback = fallback break end
        end
        if b == huge then
            -- nothing can raise skill at this rank with what we know: plan up to the gap instead
            local res = Solver.Solve(prof, setmetatable({ to = rank }, { __index = opts }))
            if res and not res.gapAt then
                res.gapAt, res.gapOptions = rank, Solver.GapOptions(prof, rank, opts, price)
            end
            return res
        end
        f[rank], best[rank], bestStep[rank], fb[rank] = row, b, bs, usedFallback
    end

    -- walk the table forward and collapse consecutive ranks on the same recipe into steps
    local steps, total, cost = {}, 0, 0
    local rank, cur = from, nil
    while rank < to do
        local row = f[rank]
        local pick
        if cur and row[cur] and row[cur] <= best[rank] + SWITCH_PENALTY * bestStep[rank] then
            pick = cur
        else
            local bv = huge
            for ci, v in pairs(row) do if v < bv then bv, pick = v, ci end end
        end
        local c = cands[pick]
        local r = c.r
        local p = Solver.Chance(r[F_YELLOW], r[F_GREY], rank)
        local ups = max(1, r[F_UPS])
        local step = steps[#steps]
        if pick ~= cur or not step then
            local learn, est = Solver.LearnRank(r, opts, fb[rank])
            step = { from = rank, to = rank, spell = r[F_SPELL], item = r[F_ITEM], qty = r[F_QTY],
                     yellow = r[F_YELLOW], grey = r[F_GREY], source = r[F_SRC], recipeItem = r[F_RITEM],
                     station = r[F_STATION], learn = learn, learnEstimated = est,
                     attempts = 0, costEach = c.cost }
            steps[#steps + 1] = step
        end
        step.attempts = step.attempts + 1 / p
        rank = min(rank + ups, to)
        step.to = rank
        cur = pick
    end

    for _, s in ipairs(steps) do
        s.crafts = ceil(s.attempts - 1e-6)
        s.cost = s.crafts * s.costEach
        s.mats = {}
        local r
        for _, c in ipairs(cands) do if c.r[F_SPELL] == s.spell then r = c.r break end end
        local mats = r[F_MATS]
        for i = 1, #mats, 2 do
            local id = mats[i]
            local unit, src = price(id)
            s.mats[#s.mats + 1] = { id = id, count = mats[i + 1] * s.crafts, per = mats[i + 1], unit = unit, priceSource = src }
        end
        total = total + s.crafts
        cost = cost + s.cost
    end
    return { steps = steps, crafts = total, cost = cost, from = from, to = to, mode = opts.mode }
end
