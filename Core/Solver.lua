-- Skillwright - route solver.
-- Plans the cheapest or fastest way from the current skill to the target, from the datamined recipe table.
-- Pure Lua (no WoW API) so it can be tested outside the game: everything live comes in through `opts`.
local ADDON, SW = ...

local floor, ceil, max, min, huge = math.floor, math.ceil, math.max, math.min, math.huge

-- recipe field positions in SW.Data.professions[prof][2][i]
local F_SPELL, F_ITEM, F_QTY, F_LEARN, F_YELLOW, F_GREY, F_UPS, F_SRC, F_STATION, F_MATS, F_RITEM, F_CAMP, F_TOOLS =
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13

-- Trainers don't publish the skill a recipe needs to learn; this estimate is replaced by the real value as
-- soon as the player opens a trainer (SkillwrightDB.learnRanks). Conservative on purpose: planning a recipe
-- slightly late costs little, planning it before it can be learned puts a step in the route that cannot
-- be done at all.
--
-- The gap is measured, and the measurement is worth keeping because the obvious calibration is wrong.
--
-- Of the 2163 recipes we ship, the 1621 that carry a real learn rank are ALL recipe items ("r"). Not one
-- trainer recipe has one - 394 of 394 are blank, which is why the estimate exists at all. So calibrating
-- against "every recipe whose requirement we know" measures drop and vendor recipes and applies the
-- answer to trainer recipes: a different population, and usable() only plans an "r" once the player
-- already knows it, where this estimate is never consulted.
--
-- Against 45 REAL trainer observations (learn ranks this account has read off trainers), yellow sits
-- this far above the true learn rank: nine at +0, two at +5, then a long cluster at +30 and +40, max +55.
--     yellow - 10   too early for 11 of 45, never by more than 10 points; too late by 30 (median)
--     yellow - 5    too early for  9 of 45, never by more than  5 points; too late by 30
--     yellow        too early for  0 of 45;                               too late by 30, up to 55
-- Being late is not free: a trainer recipe is learned while it is still orange and stays orange for
-- another 30-40 points, so estimating `yellow` holds a recipe back for that whole band and the route
-- grinds a nearly-grey one instead. Measured on a real scan, moving to `yellow` turned a 159-craft
-- route into a 254-craft one, including 44 crafts of a recipe four points from grey.
-- Ten points early, self-corrected the moment they open a trainer, beats thirty points late.
-- How far below yellow a trainer teaches a recipe. A flat 10 was a guess that read 20 skill LATE
-- more often than not; the width of the recipe's own orange band is not a guess at all. Scored against
-- the 45 requirements this addon has recorded from real trainers, `yellow - (grey - yellow)` is exact
-- 31 times with a mean error of 5, where the flat 10 was exact 0 times with a mean error of 21. The
-- same rule over the 1629 recipes whose requirement IS in the client data - a population it was never
-- derived from - is exact 788 times, mean error 8. See DECISIONS.md. LEARN_GAP survives for recipes
-- with no usable grey, and the fallback stays the escape hatch for when nothing else is learnable.
-- WHEN A TRAINER TEACHES A RECIPE, before we have met that trainer. The game carries no such number
-- for trainer recipes, so this is ours: yellow minus the recipe's own orange band, capped at 40.
--
-- This was settled three times in one day, and the trail is worth keeping because the two obvious
-- answers are wrong in opposite directions. What we can check is 49 EXACT requirements (45 read off
-- Blacksmithing trainers by this addon, 4 from wowhead's Forever First Aid tables) and 91 UPPER
-- BOUNDS - a recipe that a Forever beta levelling guide has you making at rank N must be learnable
-- at or below N - across all seven crafting professions:
--
--     rule              exact     mean error   EARLY             provably LATE
--     yellow              12/49        25.1     none              64 of 91, by up to 54
--     yellow - 10          0/49        20.4     14, up to 10      38 of 91
--     band, capped 40     31/49         7.3     15, up to 40       2 of 91
--
-- `yellow` is the only rule that is never early, and for half a day it was what we shipped. The 91
-- bounds are what settled it: it holds a recipe back in 64 of 91 steps a real player was making, by
-- up to 54 skill, which makes the plan worse for everyone who has not yet opened a trainer.
--
-- The band rule's early cases have one shape: every recipe it gets early is one whose requirement is
-- EXACTLY yellow. A requirement is either yellow or roughly yellow-30, and nothing in the data
-- separates the two populations - not band width, not profession. So there is no rule here that is
-- both accurate and never early, only a choice of which way to be wrong.
--
-- We choose accuracy, because being early no longer costs what it did: an unlearned recipe is charged
-- UNLEARNED_MARKUP, and GUESSED_MARKUP when the requirement is a guess, so the route will not send
-- anyone walking for a small gain, and the card never states a guess as a fact. 40 is the widest band
-- the exact measurements cover; past that we stop extrapolating. LEARN_GAP is the escape hatch below
-- it, for a rank where nothing else can raise skill at all.
--
-- All of it evaporates on the first trainer visit, which records the real number for every recipe
-- that trainer lists, and the game's own GetTrainerServiceSkillReq always wins.
local LEARN_BAND_MAX = 40
local LEARN_GAP = 10
local LEARN_GAP_FALLBACK = 30    -- the escape hatch: only where the safe estimate leaves no recipe at all,
                                 -- and always flagged to the player as an estimate
local YIELD_EVERY = 20        -- ranks between breaks when solving in the background
local SWITCH_PENALTY = 3         -- switching recipe costs as much as ~3 skill points (fewer, longer steps)
-- What a recipe you have not learned has to beat a recipe you have BY, before we send you to a
-- trainer. Charging nothing for the trip let nine crafts of something unlearned beat ten crafts of
-- something in the spellbook - and the player had not even met that trainer. A margin, not a ban: a
-- recipe that genuinely halves the work still wins, and for a character who knows nothing yet every
-- candidate carries the same markup, so it changes no route there.
local UNLEARNED_MARKUP = 0.15    -- a trip to a trainer
local GUESSED_MARKUP = 0.40      -- ...and we are only GUESSING you can learn it yet
-- FASTEST COUNTS CRAFTS. Nothing else. It weighs no materials, reads no prices, and asks nothing
-- about the player's gold: the standing assumption, hardcoded and not computed, is that whatever a
-- step needs can be bought at the auction house or farmed. Higher-tier materials cost more - that is
-- simply true and needs no arithmetic here. Cheapest is the mode that spends the player's money, and
-- it is the one that asks what things cost.
--
-- What this replaced: a weighting by VENDOR SELL VALUE, which does not mean what it looks like. No
-- vendor sells an Iron Bar, so its sell price says nothing about getting one. It also produced a
-- Truesilver Skeleton Key step - 26 bars at 500 each ranked "lighter" than 372 Iron Bars at 150 -
-- which no player would agree with, next to a Blacksmithing guide that puts iron there.
--
-- Recipes that are interchangeable for the plan (same skill to learn, same yellow, same grey, same
-- skill-ups, same tools and station) still need ONE of them picked, and that choice is made in the
-- grouping below. That is a choice between recipes of the same tier doing the same job, not a
-- judgement about the route.
-- "Prefer vendor materials": materials you have to farm or buy at auction count this many times their price,
-- and in fast mode each craft that needs them counts as this many extra crafts.
local VENDOR_BIAS = 2.5

-- Below this chance a recipe stops being something you make and becomes something you throw materials
-- at. With real prices, a nearly-grey recipe with cheap reagents wins on gold per skill point every
-- time - 34 crafts of a 7.5% Rough Grinding Stone for two points was the cheapest thing on a real
-- player's route - and no guide should recommend that. So the plan does not use one, unless a rank has
-- nothing else at all: the floor is the first of three passes, and the others catch what it excludes.
-- A judgement, not a measurement. The skill-up recording will say whether a quarter is the right line;
-- until then it is set where "one in four" stops feeling like crafting.
local CHANCE_FLOOR = 0.25
-- A material with no vendor price and no auction price has no price here either: nothing is guessed from
-- its sell price. A route that needs one cannot be costed, so "cheapest" has nothing to compare and the
-- guide shows the shortest route instead until the player scans.

-- Materials already in your bags or bank (opts.haveMats) count this fraction of their price: not free, so a
-- small pile can't win a step that needs hundreds, but enough that using what you have wins a close call.
local HAVE_DISCOUNT = 0.1

SW.Solver = SW.Solver or {}
local Solver = SW.Solver
-- Read by the UI: a menu that offers what the planner would refuse is the guide arguing with itself.
Solver.CHANCE_FLOOR = CHANCE_FLOOR

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
-- The rank at which this profession could build the station a recipe needs, when it needs one.
-- Six of the nine stations need 300 in the profession that uses them, so this is also what keeps
-- their recipes out of a levelling route - no flag, just the rank.
local function stationRank(r, opts)
    if not r[F_CAMP] then return nil end
    return opts and opts.stationRank and opts.stationRank[r[F_STATION]]
end
Solver.StationRank = stationRank

local function baseLearnRank(r, opts, fallback)
    local spell = r[F_SPELL]
    local known = opts.learnRanks and opts.learnRanks[spell]
    if known then return known, false end
    -- You cannot need to learn what you already know. Without this a recipe in the player's own
    -- spellbook could be locked out of the route by our ESTIMATE of when a trainer teaches it.
    if opts.known and opts.known[spell] then return 1, false end
    if r[F_LEARN] > 0 then return r[F_LEARN], false end
    if r[F_SRC] == "a" then return 1, false end
    local yellow, grey = r[F_YELLOW], r[F_GREY] or 0
    local guess = grey > yellow and (yellow - min(grey - yellow, LEARN_BAND_MAX)) or (yellow - LEARN_GAP)
    -- the escape hatch has to go LOWER than the ordinary guess, whichever way the band falls
    if fallback then guess = min(guess, yellow - LEARN_GAP_FALLBACK) end
    return max(1, guess), true
end

--- When the recipe can first be used. A recipe needing a workstation cannot be used before the
--- player can BUILD that station, however early the trainer teaches the recipe itself - and knowing
--- the recipe already does not change that either, which is why the gate sits outside every return.
function Solver.LearnRank(r, opts, fallback)
    local rank, est = baseLearnRank(r, opts, fallback)
    local station = stationRank(r, opts)
    if station and station > rank then return station, est end
    return rank, est
end

-- Recipes only one faction can learn (the data lists both as trainer recipes).
local FACTION_ONLY = { [1229504] = "Horde", [1263425] = "Alliance" }   -- Faction Banner

-- Whether a recipe may be used at all (source + station rules), independent of rank.
local function usable(r, opts)
    -- Not "this needs a station, so no". You build the station; the only recipes genuinely out of
    -- reach are the ones whose station this profession has no recipe for. LearnRank holds the rest
    -- back to the rank where the station can be made.
    if r[F_CAMP] and not stationRank(r, opts) then return false end
    if opts.known and opts.known[r[F_SPELL]] then return true end
    local only = FACTION_ONLY[r[F_SPELL]]
    if only and opts.faction and opts.faction ~= only then return false end
    local src = r[F_SRC]
    -- "c": the tier-1 camp recipe, from the quest "Camping 101" at skill 20 (open to everyone)
    if src == "t" or src == "a" or src == "c" then return true end
    -- specialization recipes: when the player has (or plans) that specialization
    local spec = src:match("^s:(.+)$")
    if spec then return opts.spec ~= nil and opts.spec == spec end
    -- recipe items ("r") and quest rewards ("q"): only once learned, their sources aren't known yet
    return false
end

---------------------------------------------------------------------------------------------------- prices

-- Price of one unit, in copper, plus where it came from: "ah", "vendor", "craft" or "unknown".
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
            local sum, mats, ok = 0, maker[F_MATS], true
            for i = 1, #mats, 2 do
                local u, usrc = pricer(mats[i])
                if usrc == "unknown" or not u then ok = false break end
                sum = sum + mats[i + 1] * u
            end
            busy[id] = nil
            if not ok then sum = nil end
            if sum then
                sum = sum / max(1, maker[F_QTY])
                if not best or sum < best then best, src = sum, "craft" end
            end
        end
        if not best then src = "unknown" end     -- no vendor, no auction, not craftable: we do not know
        -- already in the bags or bank (Plan decides what counts: enough of it, and not valuable or rare)
        if opts.haveMats and opts.haveMats[id] and best then
            best, src = best * HAVE_DISCOUNT, "have"
        end
        cache[id] = { best, src }
        return best, src
    end
    return pricer
end

-- What one craft costs, when we can say. Materials we have no price for (no vendor, no auction scan)
-- make the whole answer unknown: `sum` and `weighted` come back nil rather than invented. Also returns
-- whether every material comes from a vendor, and how many materials have no price at all.
local function craftCost(r, price, preferVendor)
    local sum, vendorSum, weighted, mats = 0, 0, 0, r[F_MATS]
    local haveAll, unpriced = #mats > 0, 0
    for i = 1, #mats, 2 do
        local unit, src = price(mats[i])
        if src == "unknown" or not unit then
            unpriced = unpriced + 1
            haveAll = false
        else
            local c = mats[i + 1] * unit
            sum = sum + c
            if src ~= "have" then haveAll = false end
            if src == "vendor" or src == "have" then
                vendorSum = vendorSum + c
                weighted = weighted + c
            else
                weighted = weighted + c * (preferVendor and VENDOR_BIAS or 1)
            end
        end
    end
    local vendorOnly = unpriced == 0 and vendorSum >= sum
    local facts = r[F_ITEM] > 0 and itemFacts(r[F_ITEM])
    if facts and not facts[4] then
        local resale = facts[2] * r[F_QTY]
        sum = max(sum - resale, sum * 0.1)
        weighted = max(weighted - resale, weighted * 0.1)
    end
    if unpriced > 0 then return nil, vendorOnly, nil, haveAll, unpriced end
    return sum, vendorOnly, weighted, haveAll, 0
end

---------------------------------------------------------------------------- how heavy the materials are

-- What a recipe's materials weigh, with no prices involved at all: the vendor sell value of the raw
-- materials, after resolving anything Mining smelts back to the ore it came from. Static, the same on
-- every server, straight out of the client data - which is what the Fastest guide needs, because a
-- guide that changes with the auction house is not a guide.
--
-- Two other measures were tried first and both rank wrongly, so do not bring them back:
--   * chain depth (ore is 0, a bar is 1, bronze is 2). Says a copper belt beats bronze leggings. Wrong:
--     Smelt Bronze makes TWO bars, so a bronze bar costs half a copper ore plus half a tin ore.
--   * raw unit count after expansion. Says the same bronze bar and copper bar are equal - one ore each -
--     so 6 bronze (6 ore) beats 12 copper (12 ore). Also wrong: tin is not copper. Tin ore sells for 25c
--     against copper's 5c and is mined a whole tier later.
-- Sell value gets it right because the game already ranks materials that way: 6 bronze bars expand to
-- 3 copper + 3 tin ore = 90c, against 12 copper bars = 60c. Bronze is half again dearer, not half price.
local weightCache = {}
local function rawValue(id, depth)
    local cached = weightCache[id]
    if cached then return cached end
    local made = SW.Data.smelting and SW.Data.smelting[id]
    local value
    if made and (depth or 0) < 6 then
        local qty, mats = made[1], made[2]
        local sum = 0
        for i = 1, #mats, 2 do
            sum = sum + mats[i + 1] * rawValue(mats[i], (depth or 0) + 1)
        end
        value = sum / max(1, qty)
    else
        local facts = itemFacts(id)
        value = (facts and facts[2] or 0)
    end
    weightCache[id] = value
    return value
end

--- Does a vendor stock every material? Static: the datamined vendor price, not an auction or a scan.
--- Only 35 of the 513 materials recipes use have one, so this separates few recipes - but when it does,
--- "walk to a shop" really is easier than "go and mine it", and that is worth a nudge.
function Solver.AllFromVendor(r)
    local mats = r[F_MATS]
    if #mats == 0 then return false end
    for i = 1, #mats, 2 do
        local facts = itemFacts(mats[i])
        if not (facts and (facts[1] or 0) > 0) then return false end
    end
    return true
end

--- The static weight of one craft, plus how many different materials it needs.
function Solver.StaticWeight(r)
    local mats, sum, kinds = r[F_MATS], 0, 0
    for i = 1, #mats, 2 do
        sum = sum + mats[i + 1] * rawValue(mats[i], 0)
        kinds = kinds + 1
    end
    return sum, kinds
end

---------------------------------------------------------------------------------------------------- tools

-- Pure-arithmetic bitwise AND for the (small, positive) tool masks: WoW's Lua has no & operator.
local function band(a, b)
    local r, bit = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + bit end
        a, b, bit = floor(a / 2), floor(b / 2), bit * 2
    end
    return r
end

local toolItemCache = {}
-- Items that count as tool category `cat`, lowest tier first (a Runed Silver Rod counts for copper-rod recipes).
-- Known recipes that still give skill at `rank`, orange ones marked as guaranteed. The guide offers these
-- as alternatives to the step, so the player can make what they actually hold materials for.
function Solver.Interchangeable(prof, rank, opts)
    local data = SW.Data.professions[prof]
    if not (data and opts and opts.known) then return {} end
    local price = Solver.NewPricer(prof, opts)
    local out = {}
    for _, r in ipairs(data[2]) do
        if opts.known[r[F_SPELL]] and not (r[F_CAMP] and not stationRank(r, opts)) then
            local seen = opts.colors and opts.colors[r[F_SPELL]]
            local yellow = (seen and seen.yellow) or r[F_YELLOW]
            local grey = (seen and seen.grey) or r[F_GREY]
            if Solver.Chance(yellow, grey, rank) > 0 then
                local toolsOK = true
                for _, cat in ipairs(r[F_TOOLS] or {}) do
                    if not Solver.HasTool(cat, opts.owned or {}) then toolsOK = false break end
                end
                if toolsOK then
                    local cost, vendorOnly, _, haveAll = craftCost(r, price, opts.preferVendor)
                    -- per-craft only: how many crafts this would take depends on where the player is,
                    -- so `count` is filled in by whoever turns this into a step (Plan.Current)
                    local priced = {}
                    for i = 1, #r[F_MATS], 2 do
                        local unit, src = price(r[F_MATS][i])
                        priced[#priced + 1] = { id = r[F_MATS][i], per = r[F_MATS][i + 1], unit = unit,
                                                full = (src == "have") and (unit / HAVE_DISCOUNT) or unit,
                                                priceSource = src }
                    end
                    local learn, learnEst = Solver.LearnRank(r, opts)
                    out[#out + 1] = { spell = r[F_SPELL], item = r[F_ITEM], qty = r[F_QTY], mats = r[F_MATS],
                                      cost = cost, ups = max(1, r[F_UPS]), vendorOnly = vendorOnly,
                                      yellow = yellow, grey = grey, guaranteed = rank < yellow or nil,
                                      priced = priced, haveMats = haveAll,
                                      -- what it IS, so a card showing it does not describe the recipe
                                      -- it replaced: where it comes from, what it needs, what it uses
                                      source = r[F_SRC], recipeItem = r[F_RITEM], station = r[F_STATION],
                                      tools = r[F_TOOLS], learn = learn, learnEstimated = learnEst }
                end
            end
        end
    end
    return out
end

function Solver.ToolItems(cat)
    local cached = toolItemCache[cat]
    if cached then return cached end
    local list = {}
    local req = SW.Data.tools and SW.Data.tools[cat]
    if req and req[2] > 0 then
        for _, t in pairs(SW.Data.tools) do
            if t[1] == req[1] and t[2] > 0 and band(t[2], req[2]) == req[2] then
                for _, id in ipairs(t[3]) do list[#list + 1] = { id = id, mask = t[2] } end
            end
        end
        table.sort(list, function(a, b) return a.mask < b.mask end)
    end
    toolItemCache[cat] = list
    return list
end

local function hasTool(cat, owned)
    for _, t in ipairs(Solver.ToolItems(cat)) do
        if owned[t.id] then return true end
    end
    return false
end
Solver.HasTool = hasTool

--- Whether a step's prerequisite is already met. Tools are answered by the bags; a station is an
--- item too, but placing one may consume it and nothing reports a placed object, so having built it
--- once counts. Not HasTool for both: a station prereq has no category, and HasTool(nil, ...) errors
--- on the cache write before it can return anything.
function Solver.PrereqDone(t, owned)
    owned = owned or {}
    if t.station then
        return owned[t.item] == true or (SW.StationBuilt and SW.StationBuilt(t.station) or false)
    end
    return hasTool(t.category, owned)
end

-- How a tool category can be had at `rank`: "owned", { maker = recipe, id } or { buy = itemID, price }, or nil.
local function toolHow(cat, rank, ctx, depth)
    if hasTool(cat, ctx.owned) then return "owned" end
    depth = depth or 0
    if depth > 3 then return nil end
    for _, t in ipairs(Solver.ToolItems(cat)) do
        local maker = ctx.makers[t.id]
        if maker and Solver.LearnRank(maker, ctx.opts) <= rank then
            local ok = true
            for _, sub in ipairs(maker[F_TOOLS] or {}) do
                if not toolHow(sub, rank, ctx, depth + 1) then ok = false break end
            end
            if ok then return { maker = maker, id = t.id } end
        end
    end
    for _, t in ipairs(Solver.ToolItems(cat)) do
        local facts = itemFacts(t.id)
        local vendor = (ctx.opts.vendorPrices and ctx.opts.vendorPrices[t.id]) or (facts and facts[1] > 0 and facts[1])
        if vendor then return { buy = t.id, price = vendor } end
    end
    return nil
end

-- Recipes the player can't use yet (recipe items, quests, specializations) that would carry the route past
-- `rank`: orange or yellow there and learnable by then. Cheapest per skill-up first.
function Solver.GapOptions(prof, rank, opts, price, limit)
    local list = {}
    for _, r in ipairs(SW.Data.professions[prof][2]) do
        if not usable(r, opts) and not (r[F_CAMP] and not stationRank(r, opts)) then
            local learn = Solver.LearnRank(r, opts, true)
            local p = Solver.Chance(r[F_YELLOW], r[F_GREY], rank)
            if learn <= rank and p >= 0.5 then
                list[#list + 1] = { spell = r[F_SPELL], item = r[F_ITEM], source = r[F_SRC], recipeItem = r[F_RITEM],
                                    yellow = r[F_YELLOW], grey = r[F_GREY], learn = learn,
                                    -- no price for its materials: rank it by crafts, not by a guess
                                    score = ((craftCost(r, price)) or 0) / p, cost = (craftCost(r, price)) }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.spell < b.spell
    end)
    for i = (limit or 6) + 1, #list do list[i] = nil end
    return list
end

---------------------------------------------------------------------------------------------------- solve

-- A step's materials, in the one shape everything downstream expects:
--   { id, per (one craft), count (the whole step), unit (copper each), priceSource }
-- Anything that builds this table by hand must fill in all five - a missing `count` used to throw in the
-- route tooltip, which only runs on hover, so nothing caught it until a player did.
local function matsOf(r, crafts, price)
    local out, mats = {}, r[F_MATS]
    for i = 1, #mats, 2 do
        local unit, src = price(mats[i])
        -- `unit` is what the SOLVER paid (materials in the bags count as nearly free, which is right for
        -- choosing between recipes); `full` is what the shop would charge, for anything shown to a player.
        out[#out + 1] = { id = mats[i], count = mats[i + 1] * crafts, per = mats[i + 1], unit = unit,
                          full = (src == "have") and unit and (unit / HAVE_DISCOUNT) or unit,
                          priceSource = src }
    end
    return out
end

-- opts:
--   from, to      skill range (to defaults to 300)
--   mode          "cheap" or "fast"
--   preferVendor  favour recipes whose materials all come from a vendor
--   known         { [spell] = true } recipes the character has learned
--   learnRanks    { [spell] = rank } skill needed to learn, seen at trainers
--   vendorPrices  { [item] = copper } unit prices seen on merchants
--   market        function(item) -> copper|nil
--   haveMats      { [item] = true } materials already in the bags or bank, worth counting as good as owned
--   owned         { [item] = true } tools the character already has
--   breaks        { [rank] = true } ranks no step may run through (trainer visits)
--   stationRank   { [station] = rank } the rank this profession can BUILD each workstation at
-- Returns { steps = { step, ... }, crafts = n, cost = copper, gapAt = rank|nil }
-- step = { from, to, spell, item, qty, crafts, mats = { {id, count, per, unit, priceSource}, ... }, cost, source,
--          learn, learnEstimated, vendorOnly, prereqs = { tool, ... } }
-- tool = { tool = true, category, item, cost, and either spell/qty/mats/source/learn (craft it) or buy = true }
function Solver.Solve(prof, opts)
    local data = SW.Data.professions[prof]
    if not data then return nil end
    local from, to = opts.from or 1, opts.to or 300
    local fast = opts.mode == "fast"
    local pricesUnknown = false
    local preferVendor = opts.preferVendor
    local price = Solver.NewPricer(prof, opts)

    local cands, bySpell, makers = {}, {}, {}
    for _, r in ipairs(data[2]) do
        if usable(r, opts) then
            local cost, vendorOnly, weighted, haveAll, unpriced = craftCost(r, price, preferVendor)
            -- the skill each recipe needs and gives, worked out once: the rank loop below runs 300 times
            local learn = Solver.LearnRank(r, opts, false)
            local learnFB = Solver.LearnRank(r, opts, true)
            -- Thresholds the game itself showed us beat our datamined ones (Forever moved some)
            local seen = opts.colors and opts.colors[r[F_SPELL]]
            local yellow = (seen and seen.yellow) or r[F_YELLOW]
            local grey = (seen and seen.grey) or r[F_GREY]
            -- only guard numbers we learned in game: the datamined pairs may legitimately be equal
            if seen and grey <= yellow then grey = yellow + 1 end
            local _, learnIsGuess = Solver.LearnRank(r, opts, false)
            local unlearned = not (opts.known and opts.known[r[F_SPELL]])
            local markup = unlearned and (learnIsGuess and GUESSED_MARKUP or UNLEARNED_MARKUP) or 0
            local staticWeight, kinds = Solver.StaticWeight(r)
            local c = { r = r, cost = cost, vendorOnly = vendorOnly, weight = weighted, haveMats = haveAll,
                        unpriced = unpriced, staticWeight = staticWeight, kinds = kinds,
                        learn = learn, learnFB = learnFB, first = learn < learnFB and learn or learnFB,
                        markup = markup,
                        yellow = yellow, grey = grey, ups = max(1, r[F_UPS]) }
            cands[#cands + 1] = c
            bySpell[r[F_SPELL]] = c
            if r[F_ITEM] > 0 and not makers[r[F_ITEM]] then makers[r[F_ITEM]] = r end
        end
    end
    -- Recipes that behave the same in the plan - same skill to learn, same yellow/grey, same skill-ups and
    -- tools - differ only in price, and the dearer one can never win, neither as the next craft nor as the one
    -- to stay on. Keeping just the cheapest of each group is what makes a full route fast enough for one frame.
    -- Interchangeable recipes: same skill to learn, same yellow/grey, same skill-ups, tools and station.
    -- Only one of each group can ever win (the cheapest, or the one the player asked for), but the others
    -- are kept on it as alternatives, so the guide can offer "or make this instead".
    do
        local prefer = opts.prefer or {}
        local groups, kept = {}, {}
        for _, c in ipairs(cands) do
            local r = c.r
            local tools = r[F_TOOLS]
            local key = ("%d:%d:%d:%d:%d:%s:%s"):format(c.learn, c.learnFB, c.yellow, c.grey, c.ups,
                tools and #tools > 0 and table.concat(tools, ",") or "-", r[F_STATION])
            c.score = fast and (c.staticWeight + c.kinds * 0.01 + (Solver.AllFromVendor(r) and 0 or 0.001))
                or (c.weight or math.huge)
            local g = groups[key]
            if not g then
                g = { members = {} }
                groups[key] = g
            end
            g.members[#g.members + 1] = c
            local wanted = prefer[r[F_SPELL]]
            if wanted and not g.chosenByPlayer then
                g.best, g.chosenByPlayer = c, true
            elseif not g.chosenByPlayer and (not g.best or c.score < g.best.score) then
                g.best = c
            end
        end
        for _, g in pairs(groups) do
            local best = g.best
            if #g.members > 1 then
                best.alts = {}
                for _, c in ipairs(g.members) do
                    if c ~= best then
                        -- yellow/grey travel with it: whoever offers this to the player has to be
                        -- able to ask whether it is grey for them, and the group's own thresholds
                        -- are not the answer when the player is above them.
                        best.alts[#best.alts + 1] = { spell = c.r[F_SPELL], item = c.r[F_ITEM],
                                                      cost = c.cost, yellow = c.yellow, grey = c.grey }
                    end
                end
                -- a cost we do not know sorts last rather than throwing
                table.sort(best.alts, function(a, b)
                    if a.cost and b.cost then return a.cost < b.cost end
                    if a.cost then return true end
                    if b.cost then return false end
                    return a.spell < b.spell
                end)
                best.chosenByPlayer = g.chosenByPlayer or nil
            end
            kept[#kept + 1] = best
        end
        cands = kept
    end
    -- Can we price THIS stretch? Only recipes that could be used before `to` matter: an endgame
    -- reagent nobody can price says nothing about a route that ends at 150, and asking about the whole
    -- profession is what used to turn Cheapest off for everyone.
    -- priceHorizon is the first rank where that stops being true - the lowest rank at which a recipe we
    -- cannot price could be reached. Below it, "cheapest" compares real prices; above it, it would be
    -- comparing against a hole.
    local priceHorizon
    for _, c in ipairs(cands) do
        if (c.unpriced or 0) > 0 and c.first < to then
            pricesUnknown = true
            if not priceHorizon or c.first < priceHorizon then priceHorizon = c.first end
        end
    end
    -- Cheapest as far as the prices reach, then fewest crafts: two objectives that cannot share one
    -- table (copper and crafts do not add up), so they are two solves joined at the horizon. The break
    -- machinery already keeps a step from running through that rank.
    if opts.mode == "cheap" and not opts.oneObjective and priceHorizon
       and priceHorizon > from and priceHorizon < to then
        local under = { to = priceHorizon, oneObjective = true }
        local over = { from = priceHorizon, mode = "fast", oneObjective = true }
        local a = Solver.Solve(prof, setmetatable(under, { __index = opts }))
        local b = Solver.Solve(prof, setmetatable(over, { __index = opts }))
        if a and b then return Solver.Join(a, b, priceHorizon) end
        return a or b
    end
    if pricesUnknown then fast = true end


    -- lowest skill needed first, so the loop can stop where the rest are still out of reach
    table.sort(cands, function(a, b)
        if a.first ~= b.first then return a.first < b.first end
        return a.r[F_SPELL] < b.r[F_SPELL]
    end)
    local ctx = { owned = opts.owned or {}, makers = makers, opts = opts }

    -- can every tool the recipe needs be had by `rank`? (memoised per category and rank)
    local toolMemo = {}
    local function toolsOK(r, rank)
        local tools = r[F_TOOLS]
        if not tools or #tools == 0 then return true end
        for _, cat in ipairs(tools) do
            local key = cat * 1000 + rank
            local ok = toolMemo[key]
            if ok == nil then
                ok = toolHow(cat, rank, ctx) ~= nil
                toolMemo[key] = ok
            end
            if not ok then return false end
        end
        return true
    end

    -- per-attempt cost of recipe c at rank `rank`, or nil when it can't give a skill-up there
    local function stepCost(c, rank, fallback, floorOn)
        if rank >= c.grey then return nil end                 -- grey: no skill from it
        if (fallback and c.learnFB or c.learn) > rank then return nil end
        local r = c.r
        local p = Solver.Chance(c.yellow, c.grey, rank)
        if p <= 0 then return nil end
        -- unless they asked for this one: the floor decides what we RECOMMEND, never what a
        -- player is allowed to make. A choice outranks our judgement about the odds.
        if floorOn and p < CHANCE_FLOOR and not c.chosenByPlayer then return nil end
        if not toolsOK(r, rank) then return nil end
        if fast then
            -- one craft. The markup is not a material cost - it is what a trip to a trainer is worth.
            return (1 + (c.markup or 0)) / p
        end
        -- Ranking by gold, and this one has no gold figure: it can never be the cheapest answer, because
        -- we do not know what it costs. Not a guess at its price - a refusal to rank it against real ones.
        -- The range is chosen so this cannot normally happen (see priceHorizon); this is the floor under it.
        if not c.weight then return huge end
        return c.weight * (1 + (c.markup or 0)) / p
    end

    -- f[rank][ci] = cost of reaching `to` from `rank` crafting cands[ci] now
    local f, best, bestStep, fb = {}, {}, {}, {}
    best[to], bestStep[to] = 0, 0
    -- the rank drops every round, so recipes needing more skill than this can be left out from here on
    local last = #cands
    -- opts.yield (set when the plan is solved in the background) is called every so often so a long route
    -- can be spread over several frames instead of freezing one.
    local yield, sinceYield = opts.yield, 0
    -- Ranks a step may not run through: the trainer visits. A run of one recipe that spans 75 would put
    -- "70-90 Rough Grinding Stone" on the page with the visit hidden somewhere inside it. Ending the run
    -- at the cap costs one switch and makes the list readable in the order you do it. nextBreak[rank] is
    -- the first cap above that rank, so a craft that jumps over one (three skill points from 74 to 77)
    -- still ends its run there.
    local breaksAt = opts.breaks or {}
    local nextBreak = {}
    do
        local caps = {}
        for rank in pairs(opts.breaks or {}) do caps[#caps + 1] = rank end
        table.sort(caps)
        local i = 1
        for rank = 0, to do
            while caps[i] and caps[i] <= rank do i = i + 1 end
            nextBreak[rank] = caps[i]
        end
    end
    for rank = to - 1, from, -1 do
        if yield then
            sinceYield = sinceYield + 1
            if sinceYield >= YIELD_EVERY then
                sinceYield = 0
                yield()
            end
        end
        while last > 0 and cands[last].first > rank do last = last - 1 end
        local row, b, bs = {}, huge, huge
        local usedFallback = false
        for pass = 1, 3 do
            local fallback = pass == 3
            local floorOn = pass == 1
            for ci = 1, last do
                local c = cands[ci]
                local sc = stepCost(c, rank, fallback, floorOn)
                if sc then
                    local cap = nextBreak[rank]
                    local nxt = min(rank + c.ups, cap or to, to)
                    local tail
                    if nxt >= to then
                        tail = 0
                    else
                        -- at a cap the run is over, whatever continuing would have cost
                        local stay = not (cap and nxt >= cap) and f[nxt] and f[nxt][ci]
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
        local p = Solver.Chance(c.yellow, c.grey, rank)
        local ups = c.ups
        local step = steps[#steps]
        if pick ~= cur or not step or breaksAt[rank] then
            local learn, est = Solver.LearnRank(r, opts, fb[rank])
            step = { from = rank, to = rank, spell = r[F_SPELL], item = r[F_ITEM], qty = r[F_QTY],
                     yellow = c.yellow, grey = c.grey, source = r[F_SRC], recipeItem = r[F_RITEM],
                     station = r[F_STATION], learn = learn, learnEstimated = est, vendorOnly = c.vendorOnly,
                     haveMats = c.haveMats,
                     attempts = 0, costEach = c.cost, tools = r[F_TOOLS],
                     alts = c.alts, chosenByPlayer = c.chosenByPlayer }
            steps[#steps + 1] = step
        end
        step.attempts = step.attempts + 1 / p
        rank = min(rank + ups, nextBreak[rank] or to, to)
        step.to = rank
        cur = pick
    end

    -- Tools: before the first step that needs one the player doesn't have, add "make/buy this first".
    local planned = {}
    for id in pairs(ctx.owned) do planned[id] = true end
    local plannedCtx = { owned = planned, makers = makers, opts = opts }
    local function addTool(list, cat, atRank, depth)
        depth = depth or 0
        if hasTool(cat, planned) or depth > 3 then return end
        local how = toolHow(cat, atRank, plannedCtx)
        if type(how) ~= "table" then return end
        if how.maker then
            for _, sub in ipairs(how.maker[F_TOOLS] or {}) do addTool(list, sub, atRank, depth + 1) end
            local mr = how.maker
            local learn, est = Solver.LearnRank(mr, opts)
            local tc = bySpell[mr[F_SPELL]]
            list[#list + 1] = { tool = true, category = cat, item = how.id, spell = mr[F_SPELL], qty = mr[F_QTY],
                                source = mr[F_SRC], learn = learn, learnEstimated = est,
                                yellow = mr[F_YELLOW], grey = mr[F_GREY],
                                mats = matsOf(mr, 1, price), cost = tc and tc.cost or (craftCost(mr, price)) }
            planned[how.id] = true
        else
            list[#list + 1] = { tool = true, buy = true, category = cat, item = how.buy, cost = how.price, mats = {} }
            planned[how.buy] = true
        end
    end

    local costKnown = true
    -- Station crafts come from the raw rows, not from bySpell: they are made from plans, so they
    -- are not usable candidates and never entered it. Looking there found nothing, which is how
    -- the route came to use 74 Spinning Wheel recipes without ever naming a Spinning Wheel.
    local stationOf, stationRow = {}, {}
    for st, made in pairs(SW.STATION_CRAFT or {}) do stationOf[made[1]] = st end
    for _, r in ipairs(data[2]) do
        local st = stationOf[r[F_SPELL]]
        if st then stationRow[st] = r end
    end
    local builtStation = {}
    for _, s in ipairs(steps) do
        s.crafts = ceil(s.attempts - 1e-6)
        s.cost = s.costEach and s.crafts * s.costEach or nil
        s.mats = matsOf(bySpell[s.spell].r, s.crafts, price)
        s.prereqs = {}
        for _, cat in ipairs(s.tools or {}) do addTool(s.prereqs, cat, s.from) end
        -- The station a step needs, once, before the first step that needs it. Without this the
        -- Tailoring route reached 300 through 74 Spinning Wheel crafts and never mentioned a wheel.
        local mr = s.station and stationRow[s.station]
        if mr and not builtStation[s.station] then
            builtStation[s.station] = true
            local learn, est = Solver.LearnRank(mr, opts)
            s.prereqs[#s.prereqs + 1] = { station = s.station, item = mr[F_ITEM], spell = mr[F_SPELL],
                                          qty = mr[F_QTY], source = mr[F_SRC], learn = learn,
                                          learnEstimated = est, yellow = mr[F_YELLOW], grey = mr[F_GREY],
                                          mats = matsOf(mr, 1, price), cost = craftCost(mr, price) }
        end
        total = total + s.crafts
        if s.cost then cost = cost + s.cost else costKnown = false end
        for _, t in ipairs(s.prereqs) do cost = cost + (t.cost or 0) end
    end
    -- `cost` covers only what we could price; pricesUnknown says the rest exists and was not invented
    local staticWeight = 0
    for _, s in ipairs(steps) do
        staticWeight = staticWeight + s.crafts * (Solver.StaticWeight(bySpell[s.spell].r))
    end
    return { steps = steps, crafts = total, weight = staticWeight,
             cost = costKnown and cost or nil, knownCost = cost,
             pricesUnknown = pricesUnknown or not costKnown, from = from, to = to, mode = opts.mode,
             -- how far this plan could be costed at all, for the page to say out loud
             pricedTo = (not fast and not pricesUnknown) and to or nil }
end

--- Two halves of one route: cheapest as far as the prices reach, fewest crafts after that.
--- Everything the page reads has to survive the join, and the gold total may only cover the half we
--- could actually price - saying that is the whole point of splitting rather than quietly picking one.
function Solver.Join(a, b, horizon)
    local steps = {}
    for _, s in ipairs(a.steps) do steps[#steps + 1] = s end
    for _, s in ipairs(b.steps) do steps[#steps + 1] = s end
    return {
        steps = steps,
        crafts = a.crafts + b.crafts,
        cost = nil,                                  -- only half of it is known; knownCost carries that
        knownCost = (a.knownCost or 0) + (b.knownCost or 0),
        pricesUnknown = true,
        from = a.from, to = b.to, mode = "cheap",
        pricedTo = horizon,
        gapAt = a.gapAt or b.gapAt,
        gapOptions = a.gapOptions or b.gapOptions,
    }
end
