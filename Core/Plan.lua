-- Skillwright - plan: runs the route solver for a character's profession and keeps the result
-- until something that changes the answer happens (mode, learned recipes, prices, trainer facts).
local ADDON, SW = ...
local Plan = {}
SW.Plan = Plan

local cache = {}    -- [prof][mode] = route: both modes are kept, so the guide can say what the choice costs
local jobs = {}     -- ["prof:mode"] = { prof, mode, co = coroutine, rank = the rank it was started from }

local stale = {}      -- [prof][mode] = the route we were showing before a re-plan started

local function Cached(prof, mode)
    local byMode = cache[prof]
    return byMode and byMode[mode or SW.Settings().mode]
end

-- The route we had before the current re-plan. Opening a profession window scans it, which changes the
-- known recipes and the ranks, which invalidates the plan - so the guide would blank to "working out
-- your route..." for a few frames every single time. Showing the previous plan until the new one lands
-- is both calmer and no less true: it is what we said a moment ago, and it is replaced the instant the
-- real answer arrives.
local function Stale(prof, mode)
    local byMode = stale[prof]
    return byMode and byMode[mode or SW.Settings().mode]
end

local function Keep(prof, mode, route)
    cache[prof] = cache[prof] or {}
    cache[prof][mode] = route
end
local runner        -- the frame that drives the background solving
local Stop          -- takes that frame's OnUpdate away again (defined below)
local SLICE_MS = 6  -- time per frame given to solving: enough to be quick, small enough not to be seen
local SYNC_SPAN = 20 -- ranks still to go that are quick enough (about 8 ms) to work out on the spot

function Plan.Count(id, withBank)
    return C_Item.GetItemCount(id, withBank) or 0
end

function Plan.Invalidate(prof)
    Plan.ForgetShopping(prof)
    Plan.ForgetOrange(prof)
    if prof then
        if cache[prof] then stale[prof] = cache[prof] end
        cache[prof] = nil
        for key, job in pairs(jobs) do
            if job.prof == prof then jobs[key] = nil end
        end
    else
        for p, byMode in pairs(cache) do stale[p] = byMode end
        wipe(cache)
        wipe(jobs)
    end
    if not next(jobs) then Stop() end
    SW.Fire("PLAN_CHANGED", prof)
end

-- True while a route is still being worked out (the guide says so instead of showing nothing).
function Plan.Solving(prof, mode)
    if prof then return jobs[("%d:%s"):format(prof, mode or SW.Settings().mode)] ~= nil end
    return next(jobs) ~= nil
end

-- Runs the solving coroutines a few milliseconds per frame. Nothing to solve: the handler goes away again.
function Stop()
    if runner then
        runner:SetScript("OnUpdate", nil)
        runner:Hide()
    end
end

local function Drive()
    if not next(jobs) then return Stop() end
    local started = debugprofilestop and debugprofilestop()
    for key, job in pairs(jobs) do
        local prof, mode = job.prof, job.mode
        while true do
            local ok, res = coroutine.resume(job.co)
            if not ok then
                SW.dbg("route for %s failed: %s", SW.ProfName(prof), tostring(res))
                jobs[key] = nil
                break
            end
            if coroutine.status(job.co) == "dead" then
                jobs[key] = nil
                if res then
                    Keep(prof, mode, res)
                    if stale[prof] then stale[prof][mode] = nil end
                    if job.t then SW.dbg("solved %s (%s) from %d in %.0f ms", SW.ProfName(prof), mode, job.rank,
                        debugprofilestop() - job.t) end
                end
                SW.Fire("PLAN_CHANGED", prof)
                break
            end
            if not started or debugprofilestop() - started >= SLICE_MS then return end
        end
        if not started or debugprofilestop() - started >= SLICE_MS then return end
    end
    if not next(jobs) then Stop() end
end

local function StartJob(prof, rank, mode)
    mode = mode or SW.Settings().mode
    local key = ("%d:%s"):format(prof, mode)
    if jobs[key] then return end
    local opts = Plan.Options(prof, rank)
    opts.mode = mode
    opts.yield = coroutine.yield
    jobs[key] = {
        prof = prof, mode = mode, rank = rank,
        t = debugprofilestop and debugprofilestop(),
        co = coroutine.create(function() return SW.Solver.Solve(prof, opts) end),
    }
    if not runner then runner = CreateFrame("Frame") end
    runner:SetScript("OnUpdate", Drive)
    runner:Show()
end

function SW.SetMode(mode)
    if mode ~= "cheap" and mode ~= "fast" then return end
    -- every caller of this is a person: the settings page, the buttons on the guide, /skw cheap|fast
    SW.Settings().modeChosen = true
    if SW.Settings().mode == mode then return end
    SW.Settings().mode = mode
    -- both routes stay cached, so switching back and forth is instant and nothing is re-solved
    Plan.ForgetShopping()
    SW.Fire("PLAN_CHANGED")
    SW.msg("route mode: %s", mode == "cheap" and "|cffffd100cheapest|r" or "|cffffd100fastest|r")
end

-- The specialization key the data uses ("Dragonscale", "Goblin" ...) for a character's profession.
function Plan.Spec(prof)
    local cp = SW.CharProf(prof)
    if cp.spec then return cp.spec end
    local specs = SW.PROFESSIONS[prof] and SW.PROFESSIONS[prof].specs
    if specs and cp.specName then
        for _, key in ipairs(specs) do
            if cp.specName:find(key, 1, true) then return key end
        end
    end
end

function Plan.Options(prof, from)
    local db, cp = SW.DB(), SW.CharProf(prof)
    local s = SW.Settings()
    -- Plan the whole profession. The route used to stop at the character's current cap, which read as
    -- "this is where Blacksmithing ends" to someone at 81/150 - and the trainer visit that lifts the cap
    -- is part of the road, not a footnote beside it (Plan.Boundaries puts it in the list).
    -- A step must not run through a trainer visit: it would hide the visit inside a range.
    local breaks = {}
    for _, b in ipairs(Plan.Boundaries(prof)) do breaks[b.at] = true end
    return {
        from = math.max(1, from or cp.rank or 1),
        to = SW.Ceiling(prof),
        breaks = breaks,
        colors = db.colors,
        -- no real market data: the cheapest route should not be decided to the copper on invented prices
        pricesAreGuesses = SW.Prices.Status() == "none" or SW.Prices.Status() == "stale",
        mode = s.mode,
        -- only Fastest trades crafts for lighter materials; Cheapest has real prices and uses them
        known = cp.known,
        learnRanks = db.learnRanks,
        vendorPrices = db.vendor,
        market = SW.Prices.Market,
        allowCamp = false,       -- recipes that need a camp station (Tanning Rack, Master Forge ...) stay out
        preferVendor = s.preferVendor,
        owned = Plan.OwnedTools(),
        haveMats = s.useOwned ~= false and Plan.HaveMats(prof) or nil,
        spec = Plan.Spec(prof),
        prefer = SW.CharProf(prof).prefer,
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }
end

-- Materials this profession's recipes use, worked out once per profession.
local matsOf = {}
local function ProfessionMats(prof)
    local set = matsOf[prof]
    if set then return set end
    set = {}
    for _, r in ipairs(SW.Data.professions[prof][2]) do
        local mats = r[10]
        for i = 1, #mats, 2 do set[mats[i]] = true end
    end
    matsOf[prof] = set
    return set
end

-- Materials you already have enough of to be worth using: at least MIN_HAVE in the bags or bank, and not
-- something you'd regret burning - nothing worth more than HAVE_MAX_VALUE each, nothing rare or better.
local MIN_HAVE = 10
local HAVE_MAX_VALUE = 10000     -- 1g per unit
local haveSig = {}

local haveCache = {}
function Plan.HaveMats(prof)
    -- One client call per material of the whole profession: far too heavy to repeat per redraw, and the
    -- answer only changes when the bags do.
    local c = haveCache[prof]
    if c and c.bags == (Plan.bagSig or 0) then
        haveSig[prof] = c.sig
        return c.have
    end
    local have, sig = {}, {}
    for id in pairs(ProfessionMats(prof)) do
        local count = Plan.Count(id, true)
        if count >= MIN_HAVE then
            local quality = C_Item.GetItemQualityByID(id)
            local facts = SW.Data.items[id]
            local unit = SW.Prices.Market(id)
                or (facts and facts[1] > 0 and facts[1])
                or (facts and facts[2] * 4)
                or 0
            if (not quality or quality < 3) and unit <= HAVE_MAX_VALUE then
                have[id] = true
                sig[#sig + 1] = id
            end
        end
    end
    table.sort(sig)
    haveSig[prof] = table.concat(sig, ",")
    haveCache[prof] = { bags = Plan.bagSig or 0, have = have, sig = haveSig[prof] }
    return have
end

-- Tools the character has (bags or bank): rods, hammers, spanners ...
local ownedSig
local ownedCache
function Plan.OwnedTools()
    -- Counting every tool in the bags is a client call per item, and this runs several times per redraw:
    -- the answer only changes when the bags do.
    if ownedCache and ownedCache.bags == (Plan.bagSig or 0) then return ownedCache.owned, ownedCache.sig end
    local owned, sig = {}, {}
    for _, t in pairs(SW.Data.tools or {}) do
        for _, id in ipairs(t[3]) do
            if Plan.Count(id, true) > 0 then
                owned[id] = true
                sig[#sig + 1] = id
            end
        end
    end
    table.sort(sig)
    local text = table.concat(sig, ",")
    ownedCache = { bags = Plan.bagSig or 0, owned = owned, sig = text }
    return owned, text
end

-- The first tool a step still needs, live (it disappears the moment the tool is in your bags).
function Plan.PendingTool(step, owned)
    owned = owned or Plan.OwnedTools()
    for _, t in ipairs(step.prereqs or {}) do
        if not SW.Solver.HasTool(t.category, owned) then return t end
    end
end

-- The route for a profession from the character's current rank. Solved from rank 1 for professions
-- the character doesn't have (preview). Re-solved when the rank leaves the cached route.
function Plan.Route(prof, mode)
    mode = mode or SW.Settings().mode
    local rank = math.max(1, SW.Prof.Rank(prof))
    local r = Cached(prof, mode)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then
        Plan.WantOther(prof, rank, mode)
        return r
    end
    if r and rank >= r.to and not r.gapAt and r.to >= SW.Ceiling(prof) then return r end
    -- The last stretch is short enough to work out on the spot, so the guide stays instant where it is
    -- used most. A longer route takes tens of milliseconds - a visible stutter - so that one is solved in
    -- the background, a few milliseconds per frame, while the guide says it is working.
    if SW.Ceiling(prof) - rank <= SYNC_SPAN then return Plan.RouteNow(prof, mode) end
    StartJob(prof, rank, mode)
    -- rather than blanking the page for the few frames the new plan takes
    local previous = Stale(prof, mode)
    if previous and rank >= previous.from and (rank < previous.to or previous.to >= SW.Ceiling(prof)) then
        return previous
    end
    return nil
end

-- With the shown route ready, the other mode is worked out in the background too, so the guide can say
-- what the choice costs instead of asking the player to guess.
function Plan.WantOther(prof, rank, mode)
    local other = mode == "fast" and "cheap" or "fast"
    local r = Cached(prof, other)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then return end
    -- Not while the player is crafting: the profession window is the one place where a spare solve is
    -- felt. It is only needed for the "what would the other mode cost" line.
    if SW.Prof.IsOpen(prof) or (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
    if next(jobs) then return end                     -- one route at a time
    SW.Debounce("wantOther", 2, function()
        if SW.Prof.IsOpen(prof) or (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
        StartJob(prof, rank, other)
    end)
end

-- What switching would cost, in one line: nil while the other route is still being worked out.
-- "cheap" is the route with the lower gold cost, "fast" the one with fewer crafts - which is not always
-- how they come out, so the wording follows the numbers rather than the names.
function Plan.TradeOff(prof)
    local cheap, fast = Plan.Compare(prof)
    if not (cheap and fast) then return nil end
    local mode = SW.Settings().mode
    local here, there = (mode == "fast") and fast or cheap, (mode == "fast") and cheap or fast
    local crafts, cost = here.crafts - there.crafts, there.cost - here.cost
    if crafts == 0 and math.abs(cost) < 100 then
        return (mode == "cheap") and "Nothing cheaper exists here - the shortest route is also the cheapest."
            or "Both routes come out the same from here."
    end
    local other = (mode == "fast") and "Cheapest" or "Fastest"
    local parts = {}
    if crafts > 0 then
        parts[#parts + 1] = ("%d fewer crafts"):format(crafts)
    elseif crafts < 0 then
        parts[#parts + 1] = ("%d more crafts"):format(-crafts)
    end
    if cost > 0 then
        parts[#parts + 1] = ("%s more"):format(SW.MoneyShort(cost))
    elseif cost < 0 then
        parts[#parts + 1] = ("%s less"):format(SW.MoneyShort(-cost))
    end
    return ("%s: %s"):format(other, table.concat(parts, ", "))
end

-- Crafts and cost still to go in each mode, once they are known. Returns cheap, fast (either may be nil).
function Plan.Compare(prof)
    local rank = math.max(1, SW.Prof.Rank(prof))
    local function totals(mode)
        local r = Cached(prof, mode)
        -- the same freshness rule the guide uses: a route solved from an older rank describes a different
        -- journey, and a number that doesn't start where the player stands is worse than no number
        if not (r and (r.from == rank or (rank >= r.from and rank < r.to))) then return nil end
        local crafts, cost = 0, 0
        for _, s in ipairs(r.steps) do
            if s.to > rank then
                local n = Plan.CraftsLeft(s, rank)
                crafts = crafts + n
                cost = cost + n * Plan.StepCost(s)
            end
        end
        return { crafts = crafts, cost = cost, to = r.to }
    end
    return totals("cheap"), totals("fast")
end

-- Is the route we are showing planned without prices? True when any material has no vendor price and
-- no auction price, which is most of them until the player scans.
--- What the materials already in your bags are worth in skill, for recipes you know. This answers the
--- question a player asks the guide silently: "I have forty Rough Stone left - should I just use them
--- up and hope?" The guide used to say nothing, so they had to guess, and guessing against the plan
--- feels like the plan missed something. It did not: forty Rough Stone at skill 82 is twenty crafts at
--- 7.5%, which is one or two points. That is not advice, it is the number - and with it in front of
--- them the choice is theirs and the guide has stopped hiding.
--- Returns a list, best first: { spell, crafts, chance, points }.
function Plan.Leftovers(prof, exceptSpell)
    local rank = math.max(1, SW.Prof.Rank(prof))
    local cur = Plan.Current(prof)
    local to = (cur and cur.step and cur.step.to) or SW.Ceiling(prof)
    local out = {}
    for _, o in ipairs(Plan.Orange(prof, rank, to)) do
        local can = o.canMake or 0
        if can > 0 and o.spell ~= exceptSpell then
            local p = SW.Solver.Chance(o.yellow, o.grey, rank)
            if p > 0 then
                -- where it lands you, craft by craft: the odds fall as the rank climbs, so walking it
                -- is the only honest way to say "this takes you to 91".
                local at, left = rank, can
                while left > 0 do
                    local step = SW.Solver.Chance(o.yellow, o.grey, at)
                    if step <= 0 then break end
                    at = at + step            -- expected points from one craft
                    left = left - 1
                end
                out[#out + 1] = { spell = o.spell, crafts = can, chance = p,
                                  points = at - rank, reaches = math.floor(at) }
            end
        end
    end
    table.sort(out, function(a, b) return a.points > b.points end)
    return out
end

--- How far the gold in your pocket takes you along the route. Every material is bought - that is the
--- model, and what you already carry is simply gold you do not have to spend again - so "the rest costs
--- 16g" is only useful next to what you have. Walks the route spending as it goes and stops where the
--- purse does, counting a part-finished step for the skill it would actually buy.
--- Returns the rank your money reaches, and the cost of the whole rest, or nil when we cannot price it.
function Plan.GoldReach(prof)
    local route = Plan.Route(prof)
    if not route or not GetMoney then return nil end
    local purse = GetMoney() or 0
    local rank = math.max(1, SW.Prof.Rank(prof))
    local left, reach, total = purse, rank, 0
    for _, s in ipairs(route.steps) do
        if rank < s.to then
            local crafts = rank > s.from and Plan.CraftsLeft(s, rank) or s.crafts
            local each, known = Plan.StepCost(s)
            if not known or each == nil then return nil end        -- a step we cannot price: no answer
            local cost = each * crafts
            total = total + cost
            if left >= cost then
                left = left - cost
                reach = s.to
            elseif cost > 0 and left > 0 then
                -- part of the way: the skill the remaining gold would actually buy
                local span = s.to - math.max(rank, s.from)
                reach = math.max(reach, math.floor(math.max(rank, s.from) + span * (left / cost)))
                left = 0
            end
        end
    end
    return reach, total, purse
end

--- What this step asks you to spend that you do not have. A plan you cannot pay for is not a plan:
--- "buy 300 Bronze Bars for 16g" reads as an instruction until you notice you have two gold, and then
--- it reads as the addon not paying attention. Returns the shortfall, or nil when it is affordable or
--- when we cannot price it anyway.
function Plan.Shortfall(cur)
    if not (cur and (cur.missingCost or 0) > 0) then return nil end
    if not GetMoney then return nil end
    local purse = GetMoney() or 0
    if cur.missingCost <= purse then return nil end
    return cur.missingCost - purse, purse
end

--- What a vendor pays for what this step makes, for the whole step. Half the reason a step with dear
--- materials can still be the cheapest one: 318 bronze bars looks ruinous until you see that the
--- leggings sell back for most of it. The solver already counts this; the page did not say it.
function Plan.Resale(step, crafts)
    if not (step and step.item and step.item > 0) then return nil end
    local facts = SW.Data.items and SW.Data.items[step.item]
    local sell = facts and facts[2] or 0
    if sell <= 0 then return nil end
    return sell * (step.qty or 1) * (crafts or 1)
end

--- How far the cheapest route could be costed: nil when nothing could be, the route's own end when
--- everything could. Between the two, the plan is cheapest up to here and shortest after.
function Plan.PricedTo(prof)
    local route = Plan.Route(prof)
    return route and route.pricedTo or nil
end

function Plan.PricesUnknown(prof)
    local r = Plan.RouteIfReady(prof)
    if not r then return false end
    if (r.pricedTo or 0) > r.from then return false end   -- part of it really was planned on price
    return r.pricesUnknown == true
end

--- How far Cheapest can go for this profession, and whether we actually know yet. The question is
--- about the OTHER button, so it asks the cheap route even while Fastest is on screen - and when that
--- route has not been worked out, it says so rather than letting the caller assume the worst.
--- Returns: reach (nil when it cannot rank anything), known (false when there is no cheap route yet).
function Plan.CheapReach(prof)
    local r = Plan.RouteIfReady(prof, "cheap")
    if not r then return nil, false end
    if (r.pricedTo or 0) > r.from then return r.pricedTo, true end
    return nil, true
end

-- The route we already have, or nil. Never starts a solve: for callers that are only asking a question,
-- such as another addon wondering whether an item matters.
function Plan.RouteIfReady(prof, mode)
    local rank = math.max(1, SW.Prof.Rank(prof))
    local r = Cached(prof, mode or SW.Settings().mode)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then return r end
    return nil
end

-- The route, solved here and now (no waiting). Used by anything that can't come back for the answer.
function Plan.RouteNow(prof, mode)
    mode = mode or SW.Settings().mode
    local rank = math.max(1, SW.Prof.Rank(prof))
    local r = Cached(prof, mode)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then return r end
    local opts = Plan.Options(prof, rank)
    opts.mode = mode
    r = SW.Solver.Solve(prof, opts)
    if r then Keep(prof, mode, r) end
    return r
end

--- The two modes naming DIFFERENT recipes for the step the player is standing on. That is the only
--- moment the difference between them is worth a sentence: a player who sees Fastest say grinding
--- stones and Cheapest say bronze does not want to know which weighting method this is, they want to
--- know which to believe.
--- Returns the recipe the OTHER mode would make here, or nothing at all - which is the usual answer,
--- because the two modes agree on most steps.
--- Only ever answers with real auction prices behind it: with none, Cheapest is Fastest under another
--- name and there is nothing to disagree about; with a stale scan we have no business recommending
--- either. It never starts a solve of its own - if the other route is not worked out yet, no line.
function Plan.Divergence(prof, spell)
    local status = SW.Prices.Status()
    if status ~= "addon" and status ~= "scan" then return nil end
    local mode = SW.Settings().mode
    local other = mode == "fast" and "cheap" or "fast"
    local r = Plan.RouteIfReady(prof, other)
    if not (r and spell) then return nil end
    local step = r.steps[Plan.StepIndex(r, math.max(1, SW.Prof.Rank(prof)))]
    if not step or step.spell == spell then return nil end
    return step.spell
end

-- Which of several interchangeable recipes the player would rather make. Remembered per character and
-- profession; nil means "whichever is cheapest".
function Plan.Prefer(prof, spell)
    local cp = SW.CharProf(prof)
    cp.prefer = cp.prefer or {}
    wipe(cp.prefer)                      -- one choice per group, and groups can't overlap
    if spell then cp.prefer[spell] = true end
    -- and it becomes the step being followed, until it goes grey or its target is reached
    if spell then
        local route = Cached(prof, SW.Settings().mode)
        local rank = math.max(1, SW.Prof.Rank(prof))
        local to
        for _, st in ipairs(route and route.steps or {}) do
            if rank < st.to then to = st.to break end
        end
        Plan.SetActive(prof, spell, to)
    else
        Plan.SetActive(prof, nil)
    end
    Plan.Invalidate(prof)
end

function Plan.Preferred(prof, spell)
    local cp = SW.CharProf(prof)
    return cp.prefer ~= nil and cp.prefer[spell] == true
end

-- Of several recipes that all give a guaranteed skill-up, the one that costs least to FINISH from here:
-- materials already in the bags or bank are paid for, so only what is still missing counts. That is the
-- user's rule - "number of materials against cost to craft, lowest wins" - and it falls out naturally:
-- a recipe you have the materials for costs nothing more, however dear it would be to buy.
local orangeCache = {}

function Plan.ForgetOrange(prof)
    if prof then orangeCache[prof] = nil else wipe(orangeCache) end
end

-- crafts you could do right now from what you hold, and what the rest would cost to buy
local function Affordability(opt, crafts)
    local canMake, missing, unpriced = nil, 0, 0
    for i = 1, #opt.mats, 2 do
        local id, per = opt.mats[i], opt.mats[i + 1]
        local have = Plan.Count(id, true)
        local possible = math.floor(have / math.max(1, per))
        canMake = (canMake == nil or possible < canMake) and possible or canMake
        local short = math.max(0, per * crafts - have)
        if short > 0 then
            -- a real price or none: a vendor price and an auction scan are facts, anything else is not
            local unit = SW.Prices.Market(id) or SW.DB().vendor[id]
            if unit then missing = missing + short * unit else unpriced = unpriced + 1 end
        end
    end
    return canMake or 0, missing, unpriced
end

-- The alternatives for the step the player is on, best first. Worked out once per profession, rank and
-- bag state, so it can't shuffle while they craft.
function Plan.Orange(prof, rank, to)
    local sig = ("%d:%d"):format(rank, to)
    local cached = orangeCache[prof]
    if cached and cached.sig == sig and cached.bags == Plan.bagSig then return cached.list end
    local opts = Plan.Options(prof, rank)
    local list = SW.Solver.Interchangeable(prof, rank, opts)
    for _, o in ipairs(list) do
        -- what THIS recipe would take to carry the player to the same skill: an orange one needs fewer
        -- crafts than a yellow one, which is half of why the choice matters
        o.crafts = math.max(1, Plan.CraftsLeft({ from = rank, to = to, yellow = o.yellow, grey = o.grey }, rank))
        o.canMake, o.missing, o.unpriced = Affordability(o, o.crafts)
        o.total = o.cost and o.cost * o.crafts or nil
        o.chosen = Plan.Preferred(prof, o.spell) or nil
    end
    table.sort(list, function(a, b)
        if (a.chosen or false) ~= (b.chosen or false) then return a.chosen end
        -- what we would still have to buy, when we know it; an unknown price never pretends to be cheap
        if (a.unpriced or 0) ~= (b.unpriced or 0) then return (a.unpriced or 0) < (b.unpriced or 0) end
        if a.missing ~= b.missing then return a.missing < b.missing end
        if (a.cost or 0) ~= (b.cost or 0) then return (a.cost or 0) < (b.cost or 0) end
        return a.spell < b.spell
    end)
    orangeCache[prof] = { sig = sig, bags = Plan.bagSig, list = list }
    return list
end

-- WHAT A TRAINER WILL TEACH YOU, in the three groups the class trainer uses: what you can learn
-- standing there, what is close, and what is a long way off. Recipes you already know are left
-- out - the player said it plainly: "jeg bryr meg ikke om det jeg allerede har laert."
--
-- Nothing is scanned for this. The requirement comes from db.learnRanks when a trainer has been
-- visited, from the recipe data when it carries one, and otherwise from Solver.LearnRank, which is
-- our estimate and is marked as one.
-- EVERYTHING YOU HAVE NOT LEARNED, split at the one question that decides what you can do about
-- it: do you have the skill for it. That is the shape of the list the user asked for.
--
-- Having the skill is not the whole story for most of Forever's recipes - they come from a drop or
-- a vendor, so you can meet the requirement and still not be able to learn it. Rather than invent
-- a third group, each row carries where it comes from and the ones that need a recipe say so.
-- "Learnable now" has to mean what it says.
local LEARN_SOURCE = {
    t = nil,                            -- a trainer: nothing to add, this is the plain case
    a = "automatic",
    r = "needs the recipe",
    q = "from a quest",
    c = "from a quest",
}

function Plan.Trainable(prof)
    local data = SW.Data.professions[prof]
    if not data then return nil end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local opts = Plan.Options(prof, rank)
    local db = SW.DB()
    local now, recipe, soon, dead = {}, {}, {}, {}
    for _, r in ipairs(data[2]) do
        local spell = r[1]
        if not SW.Prof.Knows(prof, spell) then
            local need, estimated = db.learnRanks[spell], false
            if not need or need <= 0 then
                need, estimated = SW.Solver.LearnRank(r, opts)
            end
            local src = r[8]
            local row = {
                spell = spell, item = r[2], need = need, estimated = estimated or nil,
                colour = SW.Solver.Color(r[5], r[6], rank),
                source = src,
                note = LEARN_SOURCE[src] or (type(src) == "string" and src:match("^s:(.+)$")
                    and ("%s only"):format(src:match("^s:(.+)$"))) or nil,
            }
            -- WHAT CAN THIS RECIPE STILL DO FOR ME. A recipe whose grey is at or below the
            -- player's skill is finished: learning it can never raise the skill again, and a list
            -- that opens with seventy of those is a list nobody reads. They go last, counted.
            --
            -- Everything else is one of three errands - go to a trainer, go and find the recipe,
            -- or come back when you are better.
            row.grey = r[6]
            local reach = need <= rank
            local fromTrainer = src == "t" or src == "a"
            local into = (r[6] <= rank and dead)
                or (not reach and soon)
                or (fromTrainer and now)
                or recipe
            into[#into + 1] = row
        end
    end
    -- The live groups are sorted by how much skill is LEFT in them, not by what they cost to
    -- learn: the recipe that stays useful longest is the one worth walking for. The ones you
    -- cannot reach yet are sorted by what they need, because there the question is "what is next".
    local function byHeadroom(a, b)
        if a.grey ~= b.grey then return a.grey > b.grey end
        return a.spell < b.spell
    end
    local function bySkill(a, b)
        if a.need ~= b.need then return a.need < b.need end
        return a.spell < b.spell
    end
    table.sort(now, byHeadroom)
    table.sort(recipe, byHeadroom)
    table.sort(soon, bySkill)
    table.sort(dead, bySkill)
    return { now = now, recipe = recipe, soon = soon, dead = dead, rank = rank }
end

-- The step the player is following, remembered per character and profession (so it survives a /reload).
-- A guide that changes its mind while you follow it is worse than one that is slightly suboptimal, so a
-- step is only given up when it stops giving skill, when it is finished, or when the player says so.
-- Running out of materials is NOT a reason: the guide says what is missing instead.
function Plan.Active(prof)
    return SW.CharProf(prof).active
end

function Plan.SetActive(prof, spell, to)
    local cp = SW.CharProf(prof)
    if not spell then
        cp.active = nil
        return
    end
    local a = cp.active
    if a and a.spell == spell and a.to == to then return end
    cp.active = { spell = spell, to = to }
end

-- Is the recipe we are following still worth following at this skill?
local function StillGood(prof, spell, rank)
    local data = SW.Data.professions[prof]
    if not data then return nil end
    local cp = SW.CharProf(prof)
    if not SW.Prof.Knows(prof, spell) then return nil end
    for _, r in ipairs(data[2]) do
        if r[1] == spell then
            local colors = SW.DB().colors and SW.DB().colors[spell]
            local yellow = (colors and colors.yellow) or r[5]
            local grey = (colors and colors.grey) or r[6]
            if SW.Solver.Chance(yellow, grey, rank) <= 0 then return nil end   -- grey: no skill left in it
            return r, yellow, grey
        end
    end
end

-- Index of the step the rank falls in (#steps + 1 when past the route).
function Plan.StepIndex(route, rank)
    for i, s in ipairs(route.steps) do
        if rank < s.to then return i end
    end
    return #route.steps + 1
end

local Count = function(...) return Plan.Count(...) end

-- Expected crafts left in a step from `rank` (the solver's numbers, re-summed from where you are now).
function Plan.CraftsLeft(step, rank)
    local sum, r = 0, math.max(rank, step.from)
    local ups = 1
    while r < step.to do
        local p = SW.Solver.Chance(step.yellow, step.grey, r)
        if p <= 0 then break end
        sum = sum + 1 / p
        r = r + ups
    end
    return math.ceil(sum - 1e-6)
end

-- Everything the guide shows about the step you're on.
function Plan.Current(prof)
    local route = Plan.Route(prof)
    if not route then return nil end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local idx = Plan.StepIndex(route, rank)
    -- The recipe being followed wins wherever this route also uses it here: that is what keeps the guide
    -- still across a mode switch, a re-plan, or a reload.
    local active = Plan.Active(prof)
    if active then
        for i, s in ipairs(route.steps) do
            if s.spell == active.spell and rank >= s.from and rank < s.to then idx = i break end
        end
    end
    local step = route.steps[idx]
    if not step then return { route = route, done = true, rank = rank } end
    local left = math.max(1, Plan.CraftsLeft(step, rank))

    -- What the character can actually make here: every recipe they KNOW that still gives skill, the
    -- orange ones marked as guaranteed. The one to suggest is the one that costs least to finish from
    -- here, with what is already in the bags counting as paid for; a guaranteed one wins a tie, because
    --3 certain crafts beat 11 hopeful ones. Once one is being followed it stays: only losing its
    -- skill-ups, reaching its target, or the player choosing changes it.
    -- The route's own step may not be among them - it can be a recipe they have not learned yet - and
    -- when that happens the card has to say so rather than quietly grinding something else.
    -- Can the player simply go and learn what the route wants? Then that is the answer, and the card
    -- must say so: substituting a grind for a recipe they could train right now hides the cheaper step.
    -- Only when it is genuinely out of reach (needs more skill, or a rank they have not trained) does a
    -- substitute become the honest suggestion.
    local learnable
    if not SW.Prof.Knows(prof, step.spell) and step.source ~= "r" then
        local needs = step.learn or 1
        local capOK = (SW.CharProf(prof).max or 0) <= 0 or needs <= (SW.CharProf(prof).max or 0)
        learnable = rank >= needs and capOK
    end

    local alts, swapped, meanwhile = nil, nil, nil
    do
        alts = Plan.Orange(prof, rank, step.to)
        local active = Plan.Active(prof)
        if active and (rank >= (active.to or step.to) or not StillGood(prof, active.spell, rank)) then
            Plan.SetActive(prof, nil)                 -- finished, or it has gone grey
            active = nil
        end
        local pick
        -- An automatic substitution also lands in `active`, and that one must not outrank "go and
        -- learn this". A recipe the PLAYER picked must: they asked for it, and the answer to a
        -- request cannot be a different recipe.
        local chosen = active and Plan.Preferred(prof, active.spell)
        if learnable and not chosen then
            -- keep the route's step as the headline so the "go and learn this" panel fires; offer the
            -- best thing they can make meanwhile as a second line, never as the instruction
            pick = nil
            local best
            for _, o in ipairs(alts) do
                if o.spell ~= step.spell and (not best or o.missing < best.missing) then best = o end
            end
            meanwhile = best
        elseif active then
            for _, o in ipairs(alts) do
                if o.spell == active.spell then pick = o break end
            end
            -- it may be out of the "orange" list only because we have no price for it: keep it anyway
            if not pick and StillGood(prof, active.spell, rank) then pick = { spell = active.spell } end
        elseif #alts > 0 and not SW.Prof.Knows(prof, step.spell) then
            -- THE ROUTE IS THE GUIDE. It already weighed price against the number of crafts, over the
            -- whole way to 300; second-guessing it per step on "what would I still have to buy" is how
            -- the card came to suggest 180 green Heavy Linen Bandages over 45 Wool Bandages - and to
            -- claim they would carry the player to 115, when that recipe goes grey at 100.
            -- So nothing is substituted while the route's own recipe can be made. When it cannot, the
            -- best thing they CAN make is offered: guaranteed skill first, then fewest crafts, then what
            -- they already hold the materials for.
            local function worse(a, b)
                if (a.guaranteed and 1 or 0) ~= (b.guaranteed and 1 or 0) then return not a.guaranteed end
                if (a.crafts or 0) ~= (b.crafts or 0) then return (a.crafts or 0) > (b.crafts or 0) end
                return a.missing > b.missing
            end
            local best = alts[1]
            for _, o in ipairs(alts) do
                if worse(best, o) then best = o end
            end
            pick = best
            Plan.SetActive(prof, pick.spell, step.to)
        end
        if pick and pick.spell ~= step.spell then
            if not pick.mats then                     -- kept without a price: fill it in from the data
                for _, o in ipairs(Plan.Orange(prof, rank, left)) do
                    if o.spell == pick.spell then pick = o break end
                end
            end
            if pick.mats then
                -- a copy: the route itself is left alone, only what the guide shows changes
                local copy = {}
                for k, v in pairs(step) do copy[k] = v end
                copy.spell, copy.item, copy.qty = pick.spell, pick.item, pick.qty
                copy.costEach, copy.yellow, copy.grey = pick.cost, pick.yellow, pick.grey
                -- the alternatives carry per-craft prices; a step's materials also need `count`
                copy.mats = {}
                for _, m in ipairs(pick.priced or {}) do
                    copy.mats[#copy.mats + 1] = { id = m.id, per = m.per, count = m.per * left,
                                                  unit = m.unit, full = m.full or m.unit,
                                                  priceSource = m.priceSource }
                end
                copy.vendorOnly, copy.haveMats = pick.vendorOnly, pick.haveMats
                -- and how it is described: these belonged to the recipe being replaced
                copy.source, copy.recipeItem = pick.source or copy.source, pick.recipeItem
                copy.station, copy.tools = pick.station, pick.tools or copy.tools
                copy.learn, copy.learnEstimated = pick.learn or copy.learn, pick.learnEstimated
                copy.alts, copy.chosenByPlayer = nil, Plan.Preferred(prof, pick.spell) or nil
                -- what the route wanted here, and whether the player could learn it now
                if not SW.Prof.Knows(prof, step.spell) then
                    copy.blockedBy = { spell = step.spell, learn = step.learn, source = step.source,
                                       learnEstimated = step.learnEstimated, crafts = step.crafts }
                end
                -- A substitute can only carry them as far as its own grey. Keeping the route's target
                -- here promised "80 to 115" from a recipe that dies at 100.
                copy.to = math.min(step.to, pick.grey or step.to)
                -- Its own count, over its own range: the route's belonged to the recipe it replaced.
                -- Leaving this nil put a hole in a table everything else treats as a route step, and
                -- Plan.Remaining hit it the day a swap happened at exactly the step's first rank.
                copy.crafts = Plan.CraftsLeft(copy, copy.from)
                step, swapped = copy, true
                left = math.max(1, Plan.CraftsLeft(step, rank))
            end
        end
    end
    -- Whatever ends up on the card - the route's own recipe or a substitute - is what the player is
    -- following, and it stays theirs until it goes grey, finishes, or they pick another.
    if not tool and step.spell then Plan.SetActive(prof, step.spell, step.to) end

    -- A tool still to make (or buy) comes first: the step can't be crafted without it.
    local tool = Plan.PendingTool(step)
    local srcMats = step.mats
    if tool then
        left = 1
        srcMats = tool.mats
    end
    local mats, craftable = {}, nil
    for _, m in ipairs(srcMats) do
        local need = m.per * left
        local have = Count(m.id, true)
        local bags = Count(m.id, false)
        mats[#mats + 1] = { id = m.id, per = m.per, need = need, have = have, bank = math.max(0, have - bags),
                            short = math.max(0, need - have), unit = m.unit, full = m.full or m.unit,
                            priceSource = m.priceSource }
        local can = math.floor(bags / m.per)
        craftable = craftable and math.min(craftable, can) or can
    end
    -- Is this grind actually preparation? A step's product can be a material of a later one.
    local feeds
    if step.item and step.item > 0 and route then
        for i = (idx or 1) + 1, #route.steps do
            local later = route.steps[i]
            for _, m in ipairs(later.mats or {}) do
                if m.id == step.item then feeds = later.spell break end
            end
            if feeds then break end
        end
    end

    -- What the player still has to buy, at real prices - the solver's own cost counts materials they
    -- already hold as nearly free, which is right for choosing a recipe and wrong for a number on screen.
    local enough, missingCost, unpricedMats = true, 0, 0
    for _, m in ipairs(mats) do
        if m.short > 0 then
            enough = false
            local unit = m.full or m.unit
            if unit then missingCost = missingCost + m.short * unit else unpricedMats = unpricedMats + 1 end
        end
    end

    local craftSpell = tool and tool.spell or step.spell
    return {
        route = route, idx = idx, step = step, rank = rank, left = left, mats = mats, tool = tool,
        orange = alts, swapped = swapped, blockedBy = step.blockedBy, feeds = feeds,
        enough = enough, missingCost = missingCost, unpricedMats = unpricedMats,
        learnable = learnable, meanwhile = meanwhile,
        craftable = math.min(craftable or (tool and 1 or 0), left),
        known = craftSpell and SW.Prof.Knows(prof, craftSpell) or false,
        color = tool and tool.yellow and SW.Solver.Color(tool.yellow, tool.grey, rank)
            or SW.Solver.Color(step.yellow, step.grey, rank),
    }
end

-- Materials for the rest of the route, grouped by trainer tier. Current step counted from the rank.
-- The answer only changes with the route, the rank or what's in the bags, so it is kept until then.
local shopCache = {}
function Plan.ForgetShopping(prof)
    if prof then shopCache[prof] = nil else wipe(shopCache) end
end

-- What you have of each material is read fresh every time, cached list or not.
local function CountThem(groups)
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.order) do
            e.have = Count(e.id, true)
            e.short = math.max(0, e.need - e.have)
        end
    end
    return groups
end

function Plan.Shopping(prof)
    local route = Plan.Route(prof)
    if not route then return {} end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local cached = shopCache[prof]
    if cached and cached.route == route and cached.rank == rank then return CountThem(cached.groups) end
    local owned = Plan.OwnedTools()
    local groups, byTier = {}, {}
    for _, s in ipairs(route.steps) do
        if rank < s.to then
            local tier
            for _, t in ipairs(SW.TIERS) do
                if s.from < t.cap then tier = t break end
            end
            tier = tier or SW.TIERS[#SW.TIERS]
            local g = byTier[tier.cap]
            if not g then
                g = { tier = tier, mats = {}, order = {}, cost = 0 }
                byTier[tier.cap] = g
                groups[#groups + 1] = g
            end
            local crafts = rank >= s.from and Plan.CraftsLeft(s, rank) or s.crafts
            local function add(id, qty, unit, src)
                local e = g.mats[id]
                if not e then
                    e = { id = id, need = 0, unit = unit, priceSource = src }
                    g.mats[id] = e
                    g.order[#g.order + 1] = e
                end
                e.need = e.need + qty
                -- only what we can actually price counts towards the total; the rest is listed, not guessed
                if unit then g.cost = g.cost + qty * unit else g.unpriced = (g.unpriced or 0) + 1 end
            end
            for _, t in ipairs(s.prereqs or {}) do
                if not SW.Solver.HasTool(t.category, owned) then
                    if t.buy then
                        add(t.item, 1, t.cost or 0, "vendor")
                    else
                        for _, m in ipairs(t.mats) do add(m.id, m.per, m.full or m.unit, m.priceSource) end
                    end
                end
            end
            for _, m in ipairs(s.mats) do add(m.id, m.per * crafts, m.full or m.unit, m.priceSource) end
        end
    end
    shopCache[prof] = { route = route, rank = rank, groups = groups }
    return CountThem(groups)
end

-- Totals for the rest of the route: crafts and gold still to spend.
-- Shop price of one craft of a step, from the same materials the card lists.
-- Shop price of one craft, plus whether every material in it had a price at all.
function Plan.StepCost(step)
    if not (step and step.mats) then return 0, true end
    local sum, known = 0, true
    for _, m in ipairs(step.mats) do
        local unit = m.full or m.unit
        if unit then sum = sum + (m.per or 0) * unit else known = false end
    end
    return sum, known
end

function Plan.Remaining(prof)
    local route = Plan.Route(prof)
    if not route then return 0, 0 end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local owned = Plan.OwnedTools()
    local crafts, cost, priced = 0, 0, true
    -- The step the guide is actually showing can differ from the route's own (a recipe they chose, or one
    -- they can make while the route's is unlearned). Counting the route's version here made the card say
    -- 180 crafts while the total said 98.
    local cur = Plan.Current(prof)
    local shown = cur and not cur.done and cur.step or nil
    for i, s in ipairs(route.steps) do
        if rank < s.to then
            if shown and i == cur.idx then s = shown end
            local n = rank >= s.from and Plan.CraftsLeft(s, rank) or s.crafts
            crafts = crafts + n
            local each, known = Plan.StepCost(s)
            cost = cost + n * each
            if not known then priced = false end
            for _, t in ipairs(s.prereqs or {}) do
                if not SW.Solver.HasTool(t.category, owned) then cost = cost + (t.cost or 0) end
            end
        end
    end
    return crafts, cost, priced
end

--- Where the route has to stop for a trainer: each rank cap it crosses, with the rank that lifts it.
--- The fifth entry has no name - Forever's rank above Artisan is in the client data as a skill line
--- and four rank spells, but nothing there says what it is called or where it ends, so we say
--- "the next rank" rather than invent one.
function Plan.Boundaries(prof)
    local out, ceiling = {}, SW.Ceiling(prof)
    for i, t in ipairs(SW.TIERS) do
        local nextTier = SW.TIERS[i + 1]
        if t.cap < ceiling then
            out[#out + 1] = { at = t.cap, name = nextTier and nextTier.name, need = nextTier and nextTier.need }
        end
    end
    return out
end

--- The route as the Route tab reads it: the crafting steps with the trainer visits in their place.
--- A cap the character has already lifted is not a step; it is history.
function Plan.Rows(prof)
    local route = Plan.Route(prof)
    if not route then return nil end
    local trained = SW.CharProf(prof).max or 0
    local rows, bounds, bi = {}, Plan.Boundaries(prof), 1
    local function trainRowsUpTo(rank)
        while bounds[bi] and bounds[bi].at <= rank do
            local b = bounds[bi]
            if b.at >= trained and b.at >= route.from then rows[#rows + 1] = { train = b } end
            bi = bi + 1
        end
    end
    for _, s in ipairs(route.steps) do
        trainRowsUpTo(s.from)
        rows[#rows + 1] = { step = s }
    end
    trainRowsUpTo(route.to)
    return rows, route
end

-- The next trainer tier to learn, when the rank is close to (or at) the current cap.
function Plan.TrainingDue(prof)
    local cp = SW.CharProf(prof)
    local rank, max = cp.rank or 0, cp.max or 0
    if max <= 0 or max >= SW.Ceiling(prof) then return nil end
    for _, t in ipairs(SW.TIERS) do
        if t.cap > max then
            if rank >= t.need and rank >= max - 10 then return t end
            return nil
        end
    end
end

for _, ev in ipairs({ "RECIPES_CHANGED", "TRAINER_FACTS", "PRICES_CHANGED", "COLORS_CHANGED" }) do
    SW.Listen(ev, function(prof)
        if type(prof) == "number" then Plan.Invalidate(prof) else Plan.Invalidate() end
    end)
end
-- A tool arriving in (or leaving) the bags changes which recipes are possible.
-- Picking things up shouldn't re-plan constantly: only when the set of tools, or of materials we have
-- enough of, actually changes - and then at most once every few seconds.
SW.On("BAG_UPDATE_DELAYED", function()
    SW.Coalesce("bagsChanged", 3, function()
        -- what is in the bags decides which guaranteed recipe is cheapest to finish: let that list go
        -- stale on a timer, never mid-craft
        Plan.bagSig = (Plan.bagSig or 0) + 1
        Plan.ForgetOrange()
        wipe(haveCache)
        local _, sig = Plan.OwnedTools()
        local changed = ownedSig and sig ~= ownedSig
        ownedSig = sig
        if SW.Settings().useOwned ~= false then
            for prof in pairs(cache) do
                local before = haveSig[prof]
                Plan.HaveMats(prof)
                if before and haveSig[prof] ~= before then changed = true end
            end
        end
        if changed then Plan.Invalidate() end
    end)
end)
-- Vendor prices change the plan only a little; re-plan when the merchant closes.
SW.Listen("MERCHANT_CHANGED", function()
    if not (MerchantFrame and MerchantFrame:IsShown()) then SW.Debounce("replanVendor", 1, function() Plan.Invalidate() end) end
end)
