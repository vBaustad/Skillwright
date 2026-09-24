-- Skillwright - the self test behind /yippyapp test. It answers one question: does anything error?
-- After a cleanup round the classic bug is something deleted but still called, and that only shows when
-- the code actually runs. So this runs the parts that are safe in a live client: it reads, plans and
-- builds strings. It never crafts, buys, trains, touches trainer filters, or writes a setting.
local ADDON, SW = ...
local T = {}
SW.SelfTest = T

-- A tooltip that collects lines instead of showing them: the hover code is the least-exercised of all.
local function StubTip()
    local tip = { lines = 0 }
    function tip:AddLine() self.lines = self.lines + 1 end
    function tip:AddDoubleLine() self.lines = self.lines + 1 end
    function tip:SetOwner() end
    function tip:Show() end
    return tip
end

-- Run `fn`, name what it was if it throws.
local function Check(results, name, fn)
    local ok, err = pcall(fn)
    results[#results + 1] = { name = name, ok = ok, err = err }
    return ok
end

function T.Run()
    local results = {}
    local profs = SW.Prof.Mine()
    if #profs == 0 then profs = { SW.Prof.All()[1] } end

    Check(results, "professions and ranks", function()
        SW.Prof.ScanRanks()
        SW.Prof.All()
        SW.Prof.NoCrafting()
        SW.Prof.Gathering()
    end)

    Check(results, "prices", function()
        SW.Prices.Status()
        SW.Prices.SourceText()
        SW.Prices.Market(2589)
    end)

    for _, prof in ipairs(profs) do
        local name = SW.ProfName(prof)
        local route
        Check(results, name .. ": route", function()
            route = SW.Plan.RouteNow(prof)          -- the character's own skill, both this and the other mode
            SW.Plan.RouteNow(prof, SW.Settings().mode == "fast" and "cheap" or "fast")
        end)
        local cur
        Check(results, name .. ": plan", function()
            cur = SW.Plan.Current(prof)
            SW.Plan.Remaining(prof)
            SW.Plan.Shopping(prof)
            SW.Plan.TradeOff(prof)
            SW.Plan.TrainingDue(prof)
        end)
        Check(results, name .. ": alternatives", function()
            local rank = math.max(1, SW.Prof.Rank(prof))
            local to = (cur and cur.step and cur.step.to) or SW.MAX_RANK
            for _, o in ipairs(SW.Plan.Orange(prof, rank, to)) do
                assert(o.spell, "an alternative without a recipe")
                assert(o.crafts and o.canMake ~= nil and o.missing ~= nil, "an alternative without its numbers")
            end
        end)
        Check(results, name .. ": step lines", function()
            if not (cur and cur.step) then return end
            local tip = StubTip()
            SW.StepTooltipForTest(cur.step)(tip)
            SW.MatsTagForTest(cur.step)
            for _, s in ipairs((route and route.steps) or {}) do
                SW.StepTooltipForTest(s)(tip)
                SW.MatsTagForTest(s)
            end
            assert(tip.lines > 0, "no tooltip lines were built")
        end)
        Check(results, name .. ": where to learn", function()
            SW.Trainer.WhereIs(prof, "Expert")
            if SW.TrainerHint then SW.TrainerHint(prof, "Expert") end
        end)
    end

    Check(results, "names and money", function()
        SW.ItemName(2589)
        SW.MoneyShort(12345)
        SW.Money(12345)
    end)

    local failed = {}
    for _, r in ipairs(results) do
        if not r.ok then failed[#failed + 1] = ("%s (%s)"):format(r.name, tostring(r.err)) end
    end
    if #failed > 0 then
        return false, ("%d of %d checks failed: %s"):format(#failed, #results, table.concat(failed, "; "))
    end
    return true, ("%d checks, %d profession%s planned"):format(#results, #profs, #profs == 1 and "" or "s")
end

SW.Listen("LOGIN", function()
    local LIB = SW.LIB
    if LIB and LIB.RegisterSelfTest then LIB.RegisterSelfTest("Skillwright", T.Run) end
end)
