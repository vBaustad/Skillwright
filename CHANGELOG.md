# Skillwright for WoW: Forever

## 0.2.0-beta2

### Where things live

- **The welcome page is gone and its text is on the settings page**, at the bottom, under its own
  headings: what it does, getting started, trainers and vendors and the auction house, and good to
  know. Nothing was cut. Two of those sections were already on that page under a second "Good to
  know" heading, so they read as one block now instead of twice under the same title.

- **"Open the guide" no longer sits on top of the scrollbar** on the Options > AddOns page. It
  was pinned to the window while the page scrolled beneath it, so it covered the scroll arrow and
  anything that scrolled past. It is part of the page now, beside the title, and the title's text
  leaves room for it.

- **The YippYapp launcher bar is gone.** The one thing it still decided for Skillwright - whether
  the icon is in the shared YippYapp minimap button - is a checkbox on Skillwright's own settings
  page. The guide still opens from your profession window, the minimap and |cffffd100/skw|r.

### Tooltips

- **Nothing is added to an item tooltip unless you ask for it.** Skillwright wrote two lines
  there: the auction price, which was on, and - for an enchanter - what items like this have
  disenchanted into, which had no setting at all and could not be turned off. Both are off now,
  with a checkbox each. If you run Auctionator or TSM, the price line was repeating a number
  those addons already put on the same tooltip.

  Turning it off reaches people who are already playing, not just new installs. Anyone who had
  switched the price line off keeps it off - and nobody can have meaningfully switched it on,
  because it was on to begin with.

### The route

- **Tailoring reaches 300.** It used to stop at 255, and the reason was ours: every recipe
  needing one of Forever's workstations was dropped on the assumption that a workstation is
  somewhere you travel to. It is not - you build it, and a tailor builds a Spinning Wheel at
  140. The 74 recipes behind it are a step, not a wall. The guide now works out, per profession,
  the skill needed to build each station, and holds those recipes back to exactly that point.

- **The route tells you to build the workstation**, once, before the first step that needs it,
  the same way it tells you to make a missing tool - with its materials and what they cost.

- **The route says which workstation it is waiting on**, when one really is in the way. It used
  to blame recipes from drops nobody has mapped. That was not it: Leatherworking stops at 250
  for a Sewing Machine and Blacksmithing at 285 for a Master Forge, and both of those need 300
  in the same profession to build - the rank the route is trying to reach. It names the station,
  how many recipes are behind it, how far they would carry you, and what building one takes.

- **What you have not learned, on the Route tab**, opening on the part that can still help you.
  Four groups: what to go and learn at a trainer, what you have the skill for but need the recipe
  for, what is still out of reach, and - last and dimmed - what has gone grey and can no longer
  raise your skill at all. The first two are ordered by how much skill is left in each recipe,
  not by what it costs to learn, and each row says where it goes grey. A skill we have estimated
  is marked; visit the trainer once and the real number replaces it.

### The window

- **The window stops jumping a moment after it opens.** The "auction prices are out of date"
  strip was measured before anything had told it how wide it was, so it drew one line tall and
  grew to two a frame later, pushing everything below it down. Nothing was loading.
- **The list's rows no longer sit on each other.** They were taller than the space between them,
  so every row overlapped the next and every icon leaned into the line below - worst in the first
  second after opening, before the icons had loaded and given the eye something to lock onto.
- **Long recipe names keep their beginnings.** They were clipped from the left, so "Silver Rod"
  read as "er Rod".
- **The route folds away too**, like the groups under it, and its bar says which skills it covers
  while it is shut.
- **Each row says three things, one per column.** The skill you need to learn it, coloured the way
  the trade window colours the recipe - orange down to grey - so you can see what it is worth at a
  glance; the name in the item's own rarity colour; and the level you need to use what it makes.
- **The Route tab no longer lists the same recipes twice.** The section at the bottom offering
  recipes that would carry the route further was a short version of the list now sitting above it.
- **The list says what its columns are.** The skill you need on the left, the skill it stops
  helping at on the right, and the name in the colour the trade window gives it - all three
  named, with the rest on the hover.
- **The not-learned list opens instantly.** It used to build four hundred rows the moment you
  opened it, and ask the client for every name, icon and item quality at once, so it appeared
  wrong and settled a second later. Each group opens on its own now, and they all start shut.
- **The panel is drawn with the client's own nine-slice**, so its corners are crisp at any size
  instead of being one stretched texture.

### Fixes

- **The Route tab is readable.** Eight paragraphs of notes sat under the route; what is left is
  the total and a legend for the markers actually on screen, with the reasons on a hover.
- **Trainer steps can be read.** "Train Expert Blacksmithing (..." was cut off and had no hover,
  so there was no way to see the rest of it. It answers a hover now.

- **Training pet skills works again.** Skillwright reads what a trainer teaches, and to see the
  services your own filters hide it turns those filters on for a moment. It was doing that at
  EVERY trainer - class, pet, riding - and changing a filter from an addon makes the client refuse
  the Train button afterwards and tell you to disable your addons. It was not an error anyone
  could report, because nothing errored. It now only touches a trainer that teaches a profession
  it plans for, and only reads the rest.
## 0.2.0-beta1

### The Now tab

- **The Now tab is about now again.** It had grown a second Route tab inside it: the next four
  steps, a list of recipes for skill 285 while you stand at 97, the total for the whole route, and
  what the other mode would cost. All of that is on the Route tab, where the route lives, and the
  card is back to what to make, what it needs, what it costs and what is in your way.

### The route

- **The plan now runs the whole way to 300**, with the trainer visits in it as steps of their own -
  Journeyman at 75, Expert at 150, Artisan at 225. Before, it stopped at whatever your current rank
  cap was, so a smith at 81 saw two steps and a footnote. When the next thing to do is walk to a
  trainer, that is the step.
- **Fastest counts crafts. Nothing else.** It used to weigh materials by what a vendor pays for
  them, and had a setting letting it take 10% or 25% longer to save them. Both are gone. The vendor
  price was never the right number - no vendor sells an Iron Bar - and it was putting a Truesilver
  Skeleton Key in the Blacksmithing route where every guide puts iron. Fastest now assumes what it
  always should have: that you can buy or farm what a step needs. **Cheapest is the mode that
  spends your gold, and it is the one that asks what things cost.**
- **A recipe you have not learned no longer wins by a hair.** Going to a trainer cost the plan
  nothing at all, so at First Aid 87 it asked for nine Simple Poultice - not learned, from a trainer
  that character had never met - instead of ten Wool Bandage, which they could make where they stood.
  An unlearned recipe now has to be meaningfully better before the plan sends you walking, and more so
  when we are only guessing you can learn it yet. A recipe that genuinely halves the work still wins.
- **Steps with almost no chance of a skill-up are gone.** A recipe with under a 25% chance is no longer
  planned unless you pick it yourself. On one real Blacksmithing route that cut 175 crafts to 88.
- **Cheapest plans as far as the prices reach**, and says where that is, instead of quietly mixing
  priced and unpriced stretches.
- **Cheapest needs auction prices, and now says so.** Without them it was only ever producing the
  shortest route under a different name. If you were on Cheapest, had never scanned and have no
  Auctionator or TSM, Skillwright has moved you to Fastest - the same plan you were already getting,
  under the name that describes it - and says in chat how to switch back. If you have scanned, your
  choice is untouched.
- **When Fastest and Cheapest would make different things right here**, the card says so and says which
  to believe: they disagree because Fastest counts crafts and reads no price at all, while Cheapest
  ranks by what the auction charges. Only on a step where they really differ - never as a standing note.

### Learning recipes

- **The "learn this at a trainer" list is split** into what you can learn right now and what is for
  later. It listed four recipes at skill 95 when only one could be learned, with nothing to tell them
  apart.
- **A much better guess at when a trainer teaches a recipe.** The game does not carry that number
  for trainer recipes, so Skillwright works it out from the recipe's own skill range. Checked
  against 49 real requirements it is exactly right 31 times, against none for the old rule. It can
  still be early, so a recipe you have not learned has to beat one you have by a clear margin before
  the plan sends you walking - and **one visit to any trainer replaces every guess for that
  profession with the game's own number.**
- A guessed requirement is never shown as if it were the game's number - it says "we think", and hovering
  it explains what the guess is worth.
- A recipe you already know is never held back by a guess about learning it.
- Asking for a different recipe now wins over "go and learn this one".
- The route tab marks unlearned steps: `*` not learned yet, `*?` not learned and the skill it needs is
  our estimate.

### Money and materials

- **Materials you already own are no longer priced at a tenth on screen.** That was an internal weighting
  meant to make the planner prefer what is in your bags, and it was leaking onto the card, the tooltip
  and the shopping list - a stack of 64 Bronze Bars was quoted at 15s when the auction wanted 2s 51c
  each. What the planner pays and what you pay are separate numbers now.
- **"You already have the materials for this"** was coming from that same internal flag and was shown
  against 103 of 1450 bars. It is counted honestly now, and the card says "Still to buy" at shop prices.
- **The card says what a step really costs**: what you still have to buy, and what that comes to once
  you sell what you make. When you cannot afford it all at once, it says how short you are and that you
  can make what you can, sell, and buy the rest.
- **Item tooltips show the auction price** and where it came from - "(Auctionator)" or "(your scan, 4h
  ago)". A scan too old to plan with still shows the number, greyed out and labelled. No price, no line.
- **Auction prices are the cheapest 15% by quantity**, so a couple of listings planted far below or far
  above the market cannot move them.
- **Disenchanting shows what you actually got**, not a table we invented: which items fall in the same
  group is exact client data, what comes out of a group is not, so Skillwright counts your own results
  and says how many it has seen. No Enchanting means no line at all.

### The window

- **Clicking Mining or Fishing no longer throws the guide across the screen.** It let go of the
  profession window and went back to wherever you had last dragged it, which from your side is
  just the window jumping. It stays where it is now and says it has nothing to plan for that one.
- **It wears the profession window's own panel art** - the drawing behind the page and the
  inner frame with its lines and corner pieces - so the guide reads as part of that window
  rather than a box parked beside it. The drawing is the one for the profession you are on and
  changes with it, Mining and Fishing included. It is the client's own art, not a copy, so it
  follows whatever Blizzard does to it.
- **The tabs sit on the panel and the content sits inside it.** Now, Route and Shopping floated
  above the panel with a gap under them, the words started on the frame line, and the
  scrollbar's arrows sat on its top and bottom edges. There is room around everything now.
- **Two parts of the window had no art at all, and nothing said so.** The selected mode button
  and the rows on the Route tab were both marked with an atlas this client does not have, and a
  missing atlas draws nothing rather than complaining - which is also why the first attempt at
  the panel art was invisible. Both are drawn now, and every atlas the window asks for is
  checked before it is used.
- **Each profession is compared against the client once, not once per window.** Opening
  Blacksmithing, then Cooking, then Blacksmithing again read all two thousand recipe schematics
  three times over, and so did closing and reopening the window. The repeats never found
  anything - the log line said "grey differs 0, skill-ups differ 0, reagents differ 0" every
  time. It runs again for a profession when you learn a recipe in it, which is the one thing
  that can change the answer.

- **"Make instead" is a choice again, not a wall.** It listed every recipe that could give a
  point - two dozen at Blacksmithing 97 - so the eight worth reading were buried. It shows the
  best eight now, sorted as before by what you would still have to buy, with **Show all** at the
  bottom for the rest. A recipe you have picked yourself is always in the short list.
- **It no longer offers what cannot help you.** A grey recipe gives nothing, ever, so it is never
  listed. Nor is one whose chance is below the line the planner itself refuses to plan with -
  unless you can make it right now from what is in your bags, which is a different offer and says
  so. On the route in the screenshot that started this, nothing was actually grey; what it removes
  is the near-grey tail once your bags are empty.
- **The card says whose choice the recipe is.** A recipe you picked yourself was marked
  "(your choice)" - at the end of the sentence naming a *different* recipe, the one under
  "Make instead". So a chosen step of 158 crafts sat above a line offering 31, with the green
  marker apparently on the 31, and Fastest looked like it was recommending the long way round.
  The marker is on the headline now, next to the recipe it is about. If the guide substituted
  the recipe itself because you cannot make the route's one, it says that instead - that is not
  your choice and no longer claims to be. **Let Skillwright choose** in the same menu hands the
  step back to the route.
- **Cheapest and Fastest show which one you are on.** The selected mode was marked by a texture
  that does not exist in this client and a font one shade apart from the other - and then cleared
  outright whenever anything on the route had no price, so neither was marked at all. The one you
  are using is now filled and white; the other is grey.

- **Skillwright has a tab on the profession window.** It sits under your profession tabs, in the
  same column, and it is built from the same template the client builds those tabs from rather
  than drawn to look like one - so it matches whatever that art is, and moves down by itself when
  you pick up another profession. It is lit while the guide is open, and clicking it opens or
  closes the guide. It stays in the column on Mining and Fishing too, where pressing it opens the
  guide on a profession it can actually plan.
- **Whether you want the guide is remembered.** Two things say you do not: the X on the guide,
  and its tab. Either one keeps it shut - through profession switches, through closing and
  reopening the window, and through a reload - until you press the tab again. Nothing else
  counts: closing the *profession* window takes the guide with it and the next one brings it
  back, because that is the window going away rather than a decision about the guide.
- **Escape no longer loses the guide for good.** Pressing it over the profession window closed
  both, and the guide then stayed away until you found the tab - the addon had no way to tell
  that hide apart from you closing it, and guessed wrong. It no longer guesses.
- **It no longer appears on its own after Escape either.** Closing the profession window used to
  leave a guide you had opened yourself on screen, detached and moved to its free-floating
  position - it had not reopened, it had jumped, but there is no way to tell those apart by
  looking. None of this touches "Open with the profession window" in Settings, which is still
  the setting for "never do this on your own".
- **It keeps out of other addons' way.** If another addon has already put a panel on the right of
  the profession window, the guide takes the left instead; if both sides are taken, it stops
  attaching and stays where you last put it rather than landing on someone else's panel. The button
  does the same, stepping left along the title bar until it finds room. What counts as being in the
  way is something anchored to the profession window - which is what an addon that adds to that
  window does. A window that merely happens to be on screen is left alone, and a panel that appears
  after the guide has anchored can still overlap until the next time it anchors.

### Fixes

- **Opening Mining, Herbalism or Fishing now gets the guide out of the way.** It used to sit there
  showing the last crafting profession's route beside a window it has nothing to do with. If the
  guide opened itself alongside a profession window it now closes with one it cannot plan; if you
  opened it yourself it stays, and says so.
- **Opening a profession, or switching between two, took seconds before the right guide appeared.**
  The scan was scheduled 0.05s after the window opened - and then every update as the recipe list
  filled in cancelled it and scheduled it a full second later instead, again and again. The fast
  path had been measured and written months ago and never once ran.

- **Lines in the "learn this at a trainer" panel were drawn on top of each other.** Anything that
  wrapped to more than one line - the "where" line, the book hint, the "meanwhile you could make"
  suggestion - was measured as a single line, so the next line landed in the middle of it. The same
  fault sized the "make something else instead" line, which now wraps too.
- **When the next thing to do is walk to a trainer, that is what the card says.** It used to lead with
  the recipe's name and icon, in the same place it uses for "make this", above a panel telling you to
  go and learn it - so it read as though you already had it. The headline is now the trainer, and the
  recipe is named in the sentence under it.
- **"Make something else" is a button you can see.** It was a line of text that happened to open a
  menu, which nobody would ever have guessed. It has a panel, a highlight and a chevron now, and it
  always starts with what it does.
- **"Make about 9 more" is gone.** Nothing counts your crafts - that number is how far the skill has to
  go - so it fell while you made something else entirely, and a player making Wool Bandage watched the
  Simple Poultice counter tick down. It now says what it is: "About 9 of these takes you from skill 87
  to 95."
- The Shopping tab threw an error as soon as one material had no price, which was every route since we
  stopped guessing prices.
- A crash on the Cooking route when the step you were following had just been swapped for another
  recipe - and that swapped card could describe the recipe it replaced: wrong source, wrong tools,
  wrong trainer requirement.
- The "no prices" strip stayed on screen after a scan with the page drawn over it, and the Cheapest
  button complained about scanning even after you had scanned.
- Switching profession took up to 1.3 seconds before the guide knew which profession it was looking at,
  and could show the previous one's plan in the meantime, including its "go and learn this" panel.
- The route no longer plans a skill-up across a rank cap, and no longer plans past the last recipe that
  exists in this build.
- Training rows that were cut off now show the full text on hover.

### Data

- **Recipe data regenerated for build 1.60.1.70009** (it was two builds behind). Four tailoring recipes
  no longer need Fine Thread - Cloudy and Azure Gustwoven Trousers and Windraveled Pants - so the guide
  had been sending people to buy a reagent the recipe stopped using. New 300-330 recipes from recipe
  items, and Green and Red Winter Clothes give a different number of skill-ups.
- Nothing is said about lost settings on build 70009, where the client bug that caused them is fixed.
- Pinned to the shared YippYapp library v1.0.6.

## 0.1.0-beta8

- Updated shared YippYapp library.

## 0.1.0-beta7

- Buying from a merchant works again. The confirmation never appeared: Skillwright asked the game to
  format the price with a function Forever doesn't have, so the button errored instead of opening the
  popup. Every price shown in the guide was always fine - only the buy confirmation used it.

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
