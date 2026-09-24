# Skillwright for WoW: Forever

## 0.1.0-beta6

- Updated shared YippYapp library.

## 0.1.0-beta5

- Same as beta4; CurseForge did not build that tag.

## 0.1.0-beta4

- Settings moved into the YippYapp window, recipe alternatives, a "learn this at a trainer"
  panel with locations Skillwright learns from your own trainer visits, and the cheapest/fastest
  choice now states what it costs you.

## 0.1.0-beta3

- **No crafting profession yet?** Skillwright opens a "Choose a profession" page: what each profession is good for, the gathering profession that goes with it (highlighted if you already have one), and a click to preview its route. Learn one and the planner takes over by itself.
- Camp recipes (Camp Tent, Sharpening Wheel, Fish Bowl...) are marked as taught by the "Camping 101" quest at skill 20, not by the trainer. Faction Banners show only for your faction.
- Changing settings no longer closes the Options window, which could cause an error.

## 0.1.0-beta2

- Materials you already have count in the route: with plenty of Linen Cloth, First Aid suggests bandages first. Rare and expensive materials are never used up this way. Turn it off with "Use materials I already have".
- The guide opens beside the profession window again.
- Items in the shopping list show their names instead of "item 6338".
- Settings are also under Options > AddOns > YippYapp > Skillwright.

## 0.1.0-beta1

The first beta of Skillwright for WoW: Forever. Instead of a hand-written guide, Skillwright plans your
profession's route itself, from the game's own recipe data and your prices.

**What it does**
- Plans the way from your current skill to 300 for Alchemy, Blacksmithing, Cooking, Enchanting, Engineering,
  First Aid, Leatherworking and Tailoring: which recipe to make, how many, what it takes and what it costs.
- Choose **Cheapest** (least gold per skill point) or **Fastest** (fewest crafts).
- Recipes whose materials you can buy from a vendor come first. Materials nobody sells, like enchanting
  essences, count as expensive.
- Tools get their own steps: "First: make a Runed Copper Rod", "buy a Blacksmith Hammer", and the higher rods
  when the recipes need them.
- Where trainer recipes stop giving skill, the guide lists the recipes that would carry you on.

**While you craft**
- The guide opens beside your profession window: the recipe to make now, how many more, your materials
  (bank included) and a Craft button. The Route and Shopping tabs show the rest of the way.
- A minimal window with just the next craft (the **-** button by the close button).
- **Enchanting**: pick the item to enchant in the "Optional Target" slot. Optionally the "replace enchant?"
  question is answered for you (never for gear you are wearing).

**Trainers, vendors and the auction house**
- At a trainer, Skillwright reads what skill each recipe needs, and a Train button learns the recipes on your
  route.
- At a vendor, a Buy button gets the materials you're short of - it shows the total and asks first.
- Prices come from Auctionator or TSM, or from Skillwright's own auction house scan (**Scan prices**).

**Getting around**
- Click the Skillwright icon on the minimap (grouped behind the YippYapp button if you use several YippYapp
  addons) or type `/skw` (also `/skillwright`; `/sw` is Blizzard's stopwatch).
- Right-click the icon or type `/skw config` for the settings. They are also under
  Options > AddOns > YippYapp > Skillwright.

**Good to know**
- Built from WoW: Forever beta data. Where recipe items drop or are sold isn't known yet, so routes use trainer
  recipes and the ones you already know.
- Until you've visited a trainer, the skill a trainer recipe needs is estimated (and marked as such).
- Part of YippYapp - addons for WoW: Forever that work even better together.
