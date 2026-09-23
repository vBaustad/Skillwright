-- Skillwright - where the higher trainers were in Classic. HAND-WRITTEN, not generated: the game client
-- carries no trainer names or locations at all (checked in the Forever beta data), so this is the last
-- resort, shown only when neither this character nor any other on the account has met such a trainer.
-- It is always marked as Classic knowledge, and it never gives coordinates: a place name that turns out
-- wrong costs a question to a guard, a wrong coordinate costs a walk to an empty field.
--
-- Apprentice and Journeyman are left out on purpose: any profession trainer in a capital teaches those.
-- Facts checked against a Classic trainer guide (Warcraft Tavern, SoD phase 2), wording our own.
local ADDON, SW = ...
SW.Data = SW.Data or {}

-- [skillLineID] = { [tierName] = { Alliance = { who, where }, Horde = { who, where } } }
-- `note` replaces "train with" for the ones that aren't trained from an NPC at all.
SW.Data.trainerHints = {
    -- Alchemy
    [171] = {
        Expert = {
            Alliance = { who = "Ainethil", where = "the Craftsmen's Terrace in Darnassus" },
            Horde = { who = "Doctor Herbert Halsey", where = "the Apothecarium in Undercity" },
        },
        Artisan = {
            Alliance = { who = "Kylanna Windwhisper", where = "Feathermoon Stronghold in Feralas" },
            Horde = { who = "Rogvar", where = "Stonard in the Swamp of Sorrows" },
        },
    },
    -- Blacksmithing
    [164] = {
        Expert = {
            Alliance = { who = "Bengus Deepforge", where = "the Great Forge in Ironforge" },
            Horde = { who = "Saru Steelfury", where = "the Valley of Honor in Orgrimmar" },
        },
        Artisan = {
            Alliance = { who = "Brikk Keencraft", where = "Booty Bay in Stranglethorn" },
            Horde = { who = "Brikk Keencraft", where = "Booty Bay in Stranglethorn" },
        },
    },
    -- Enchanting
    [333] = {
        Expert = {
            Alliance = { who = "Kitta Firewind", where = "the Tower of Azora in Elwynn Forest" },
            Horde = { who = "Hgarth", where = "Sun Rock Retreat in Stonetalon Mountains" },
        },
        Artisan = {
            Alliance = { who = "Annora", where = "a side chamber inside Uldaman" },
            Horde = { who = "Annora", where = "a side chamber inside Uldaman" },
        },
    },
    -- Engineering
    [202] = {
        Expert = {
            Alliance = { who = "Springspindle Fizzlegear", where = "Tinker Town in Ironforge" },
            Horde = { who = "Roxxik", where = "the Valley of Honor in Orgrimmar" },
        },
        Artisan = {
            Alliance = { who = "Buzzek Bracketswing", where = "Gadgetzan in Tanaris" },
            Horde = { who = "Buzzek Bracketswing", where = "Gadgetzan in Tanaris" },
        },
    },
    -- Leatherworking
    [165] = {
        Expert = {
            Alliance = { who = "Telonis", where = "the Craftsmen's Terrace in Darnassus" },
            Horde = { who = "Una", where = "the Middle Rise in Thunder Bluff" },
        },
        Artisan = {
            Alliance = { who = "Drakk Stonehand", where = "Aerie Peak in the Hinterlands" },
            Horde = { who = "Hahrana Ironhide", where = "Camp Mojache in Feralas" },
        },
    },
    -- Tailoring
    [197] = {
        Expert = {
            Alliance = { who = "Georgio Bolero", where = "the Mage Quarter in Stormwind" },
            Horde = { who = "Josef Gregorian", where = "the Magic Quarter in Undercity" },
        },
        Artisan = {
            Alliance = { who = "Timothy Worthington", where = "Theramore Isle in Dustwallow Marsh" },
            Horde = { who = "Daryl Stack", where = "Tarren Mill in Hillsbrad Foothills" },
        },
    },
    -- Cooking: not trained from a trainer at these ranks
    [185] = {
        Expert = {
            Alliance = { note = "the Expert Cookbook, sold by Shandrina at Silverwind Refuge in Ashenvale" },
            Horde = { note = "the Expert Cookbook, sold by Wulan at Shadowprey Village in Desolace" },
        },
        Artisan = {
            Alliance = { note = "the quest Clamlette Surprise from Dirge Quikcleave in Gadgetzan" },
            Horde = { note = "the quest Clamlette Surprise from Dirge Quikcleave in Gadgetzan" },
        },
    },
    -- First Aid: a book, then a quest
    [129] = {
        Expert = {
            Alliance = { note = "the book Expert First Aid - Under Wraps, sold by Deneb Walker at Stromgarde Keep in Arathi Highlands" },
            Horde = { note = "the book Expert First Aid - Under Wraps, sold by Balai Lok'Wein at Brackenwall Village in Dustwallow Marsh" },
        },
        Artisan = {
            Alliance = { note = "the Triage quest from Doctor Gustaf VanHowzen at Theramore Isle" },
            Horde = { note = "the Triage quest from Doctor Gregory Victor at Hammerfall in Arathi Highlands" },
        },
    },
}

-- What we can say about where to train `tier` of `prof`, or nil when we have nothing to offer.
-- Always phrased as Classic knowledge: Forever has moved and added NPCs.
function SW.TrainerHint(prof, tier)
    local byTier = SW.Data.trainerHints[prof]
    local entry = byTier and byTier[tier]
    entry = entry and entry[UnitFactionGroup and UnitFactionGroup("player") or "Alliance"]
    if not entry then return nil end
    if entry.note then
        return ("In Classic this came from %s - Forever may differ."):format(entry.note)
    end
    return ("In Classic this was taught by %s in %s - Forever may differ."):format(entry.who, entry.where)
end
