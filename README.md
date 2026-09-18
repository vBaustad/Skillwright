# Skillwright (WoW: Forever)

Profession leveling for WoW: Forever. Instead of a hand-written guide, Skillwright plans the route itself from
the game's own recipe data (skill-up colours, reagents, stations) and your live prices:

- **Cheapest**: the least gold per skill point, from Auctionator, TSM or its own auction house scan.
- **Fastest**: the fewest crafts per skill point.

It opens beside the profession window with the recipe to make now, how many more, your materials
(have/need, bank included), and buttons to craft, buy from the open merchant, or train at the open trainer.
Recipes you have learned from recipe items are used too. Where trainer recipes stop giving skill, it lists the
recipes that would carry you on.

`/sw` guide - `/sw cheap` / `/sw fast` - `/sw prices` - `/sw config`

## Data

`Data/Recipes.lua` and `Data/Items.lua` are generated from the datamined client by
`S:\forever-data\tools\gen_skillwright_data.py`; don't edit them by hand. `tools/test_skillwright_solver.py`
runs the route solver outside the game.

Trainers don't publish the skill a recipe needs to learn; until you've visited one, Skillwright estimates it
(conservatively) and marks it as an estimate.
