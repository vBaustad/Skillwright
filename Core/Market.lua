-- Skillwright - guild-market price bridge (GuildFoundMarket interop).
--
-- There is no Auction House in the event this is built for, but many guilds run
-- GuildFoundMarket (GFM), a query-based marketplace. GFM never stores other players'
-- prices anywhere (not in SavedVariables, not on disk) - a listing exists only for a few
-- seconds in GFM's own private memory right after a search. So the only way to learn a
-- price is to ask on GFM's channel and collect the whispered replies, exactly like GFM's
-- Buy tab does.
--
-- This module is a READ-ONLY consumer of that same conversation: it asks and listens, it
-- never answers queries or posts offers, and it does not modify GuildFoundMarket. We match
-- GFM's wire format by hand, so if GFM changes the protocol these constants must be updated:
--
--   channel : a temporary channel named "GFM"<hex> that GFM has already joined on this
--             client (Config.lua derives it from a guild-info secret). We reuse its slot.
--   query   : SendChatMessage("GFMqp1:" .. "Q~<qid>~<itemID>~<ver>", "CHANNEL", nil, idx)
--   reply   : addon message, prefix "GFMarket", type WHISPER,
--             body "R~<qid>~<itemID>~<qty>~<price>~<loc>~<suffix>"   (price is copper/unit)
--   settle  : sellers answer within ~5s; we collect for that long.
--
-- Channel broadcasts must ride a hardware event, so Query() has to be called from a click
-- or slash command - never a timer. (That is a WoW/Classic-Era restriction, not ours.)

local ADDON, SW = ...

local CHAT_TAG  = "GFMqp1:"     -- GFM Core.lua CHAT_TAG
local PREFIX    = "GFMarket"    -- GFM Transport.lua PREFIX (addon-message prefix)
local SETTLE    = 5             -- GFM QUERY_SETTLE: seconds to gather replies
local CACHE_TTL = 600           -- a cached price is "fresh" for 10 minutes
local MAX_PER_CLICK = 6         -- channel messages we'll fire from a single click (throttle-safe)

SW.GuildMarket = SW.GuildMarket or {}
local M = SW.GuildMarket

-- results[itemID] = { qs = queryStart, t = lastUpdate, offers = { [sellerKey] = offer } }
--   offer = { seller, qty, price (copper/unit), loc, suffix }
local results = {}
-- [qid] = { id = itemID, start = GetTime() } for queries still inside their settle window
local active = {}
local seq = 0

-- Debug override for previewing the UI states (set via /swgp none|off|real):
--   nil = use the real state, "none" = pretend GFM isn't installed, "off" = installed but
--   not connected to a marketplace channel.
local forced

-- Optional callback the UI sets to refresh itself when fresh prices land.
M.onUpdate = nil
local function fireUpdate() if M.onUpdate then pcall(M.onUpdate) end end

-- The GFM marketplace channel shows up in our own channel list as "GFM"<hex> once GFM joins
-- it. Find its index so we can broadcast on the same slot; nil if GFM isn't connected.
local function channelIndex()
    local list = { GetChannelList() }   -- flat: id1, name1, disabled1, id2, name2, ...
    for i = 2, #list, 3 do
        local name = list[i]
        if type(name) == "string" and name:match("^GFM%x+$") then
            local idx = GetChannelName(name)
            if idx and idx > 0 then return idx, name end
        end
    end
end

-- Send GFM's actual version in our query so we don't pollute its peer-version gossip.
local function gfmVersion()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (meta and meta("GuildFoundMarket", "Version")) or "0.0.0"
end

-- All current offers for an item, cheapest first.
local function offerList(itemID)
    local r = results[itemID]
    if not r then return {} end
    local out = {}
    for _, o in pairs(r.offers) do out[#out + 1] = o end
    table.sort(out, function(a, b) return a.price < b.price end)
    return out
end

-- True if GuildFoundMarket is installed and loaded (the bridge can't work without it).
function M.Installed()
    if forced == "none" then return false end
    if forced then return true end
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return loaded and loaded("GuildFoundMarket") and true or false
end

-- True if a guild marketplace channel is reachable right now (GFM installed AND connected).
function M.Available()
    if forced then return false end
    return channelIndex() ~= nil
end

-- Cheapest offer for an item: price(copper/unit), qty, seller, loc, ageSeconds. nil if none.
function M.Get(itemID)
    local o = offerList(itemID)[1]
    if not o then return nil end
    local r = results[itemID]
    return o.price, o.qty, o.seller, o.loc, (r and (GetTime() - (r.t or 0))) or 0
end

-- Every offer for an item, cheapest first: { {seller, qty, price, loc, suffix}, ... }.
function M.GetAll(itemID) return offerList(itemID) end

-- Has anything for this item been seen recently enough to show without re-asking?
function M.IsFresh(itemID)
    local r = results[itemID]
    return (r and next(r.offers) and (GetTime() - (r.t or 0)) <= CACHE_TTL) and true or false
end

-- Ask the guild market for one or more item IDs. MUST be called from a hardware event.
-- Returns ok(boolean), and either the number of queries sent or an error string.
function M.Query(itemIDs)
    local idx = channelIndex()
    if not idx then return false, "no marketplace channel (is GuildFoundMarket connected to your guild?)" end
    if type(itemIDs) == "number" then itemIDs = { itemIDs } end
    local ver, me = gfmVersion(), UnitName("player")
    local seen, sent = {}, 0
    for _, id in ipairs(itemIDs) do
        id = tonumber(id)
        if id and not seen[id] and sent < MAX_PER_CLICK then
            seen[id] = true
            seq = seq + 1
            local qid = me .. "#SW" .. seq          -- our own qid namespace; GFM ignores these
            active[qid] = { id = id, start = GetTime() }
            SendChatMessage(CHAT_TAG .. ("Q~%s~%d~%s"):format(qid, id, ver), "CHANNEL", nil, idx)
            sent = sent + 1
        end
    end
    C_Timer.After(SETTLE + 0.5, function()
        local now = GetTime()
        for qid, q in pairs(active) do if now - q.start > SETTLE then active[qid] = nil end end
        fireUpdate()
    end)
    return true, sent
end

-- Receive replies. Both GFM and Skillwright register the prefix; GFM ignores our qids and we
-- ignore everything that isn't a reply to a query we sent, so the two never collide.
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end
local rx = CreateFrame("Frame")
rx:RegisterEvent("CHAT_MSG_ADDON")
rx:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
    if prefix ~= PREFIX or not text then return end
    local cmd, qid, id, qty, price, loc, suffix = strsplit("~", text)
    if cmd ~= "R" then return end
    local q = active[qid]
    if not q then return end
    id, price, qty = tonumber(id), tonumber(price), tonumber(qty)
    -- Safety net against a future GFM protocol change: the reply must echo the exact item we
    -- asked about and carry sane numbers. If a format shift moved fields around, the itemID
    -- won't match q.id and we drop the reply - so the feature can only ever go quiet, never
    -- surface a wrong price. (Re-verify the wire format at the top of this file if that happens.)
    if id ~= q.id then return end
    if not (price and price > 0 and qty and qty >= 0) then return end
    local r = results[id]
    -- First reply of a new query window starts a fresh listing; later replies accumulate.
    if (not r) or r.qs ~= q.start then r = { qs = q.start, offers = {} }; results[id] = r end
    local who = Ambiguate(sender, "short")
    r.offers[who .. "#" .. (suffix or "0")] = {
        seller = who, qty = qty or 0, price = price,
        loc = (loc and loc ~= "" and loc) or nil, suffix = tonumber(suffix) or 0,
    }
    r.t = GetTime()
    fireUpdate()
end)

-- Quick in-game check that the bridge actually reaches your guild market:
--   /swgp 2318      (run while you're logged in with GuildFoundMarket connected)
SLASH_SWGUILDPRICE1 = "/swgp"
SlashCmdList["SWGUILDPRICE"] = function(input)
    local arg = (input or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
    -- Debug: preview the three UI states without disabling the addon.
    if arg == "none" or arg == "off" then
        forced = arg
        SW.msg(("debug: simulating GuildFoundMarket = |cffffd100%s|r. Open a craft step's Now tab to see it; |cffffd100/swgp real|r to clear."):format(
            arg == "none" and "not installed" or "installed but disconnected"))
        if SW.Refresh then SW.Refresh() end
        return
    elseif arg == "real" or arg == "clear" or arg == "on" then
        forced = nil
        SW.msg("debug: cleared - using the real GuildFoundMarket state again.")
        if SW.Refresh then SW.Refresh() end
        return
    end
    local id = tonumber(arg:match("%d+"))
    if not id then SW.msg("usage: |cffffd100/swgp <itemID>|r to query a price, or |cffffd100/swgp none|off|real|r to preview the install prompts."); return end
    if not M.Available() then SW.msg("no marketplace channel found - is GuildFoundMarket installed and connected?"); return end
    M.onUpdate = function()
        for _, o in ipairs(M.GetAll(id)) do
            SW.msg(("guild market: |cffffffff%dx %s|r @ %s from |cff66ccff%s|r%s"):format(
                o.qty or 0, GetItemInfo(id) or ("item:" .. id),
                GetCoinTextureString and GetCoinTextureString(o.price) or (o.price .. "c"),
                o.seller or "?", o.loc and (" |cff888888(" .. o.loc .. ")|r") or ""))
        end
    end
    local ok, info = M.Query(id)
    if ok then
        SW.msg(("asked the guild market for %s - waiting %ds for replies..."):format(GetItemInfo(id) or ("item:" .. id), SETTLE))
    else
        SW.msg("couldn't ask: " .. tostring(info))
    end
end
