# Skillwright (WoW: Forever)

Profession leveling for WoW: Forever. Instead of a hand-written guide, Skillwright plans the route itself from
the game's own recipe data (skill-up colours, reagents, tools, stations) and your prices:

- **Cheapest**: the least gold per skill point, from Auctionator, TSM or its own auction house scan.
- **Fastest**: the fewest crafts per skill point.

Recipes whose materials you can buy from a vendor come first, and tools like enchanting rods are planned in as
their own steps.

It opens beside the profession window with the recipe to make now, how many more, your materials (have/need,
bank included) and a Craft button, plus Route and Shopping tabs for the rest of the way. At a vendor it buys
what you're short of (with a confirmation), at a trainer it learns the recipes on your route. For enchanting
you can pick the item to enchant. Where trainer recipes stop giving skill, it lists the recipes that would
carry you on.

## Using it

- Open your profession window, or click the Skillwright icon on the minimap (grouped behind the YippYapp
  button when you use several YippYapp addons), or type `/skw` (also `/skillwright`).
- `/skw cheap` / `/skw fast` switch the route mode, `/skw prices` shows where prices come from.
- Settings: right-click the icon or `/skw config` (the guide's Settings tab), or
  Options > AddOns > YippYapp > Skillwright (`/skw options`). The minimap and launcher buttons are on the
  shared YippYapp page.

## Part of YippYapp

Skillwright works fully on its own. With **Guildhall** you can ask a guildie to craft the steps you'd rather
skip, or post the materials your route still needs.

## Data

`Data/Recipes.lua` and `Data/Items.lua` are generated from the datamined client by
`forever-data/tools/gen_skillwright_data.py`; don't edit them by hand.

Trainers don't publish the skill a recipe needs to learn; until you've visited one, Skillwright estimates it
(conservatively) and marks it as an estimate. Where recipe items drop or are sold isn't in the client data yet,
so those recipes are used only once you know them.
