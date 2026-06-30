# Changelog

## 1.1.3

- **Train prompt** on the Now tab — when the next recipe isn't learned yet, the guide tells you
  to go visit your trainer. Open the trainer and a **Train** button appears (with a count) to
  learn the path's available recipes in one click.
- Fixed a "tried to call the protected function `SpellStopCasting()`" error from the craft
  auto-stop. It now cancels the remaining repeats the instant you hit the target; the one craft
  already mid-cast finishes on its own (so you may end up a single craft over).

## 1.1.2

- Removed the GuildFoundMarket guild-price integration (the "Check guild prices" button, the
  cost estimate, the price tooltips, and the side panel). Out of respect for GuildFoundMarket's
  author, Skillwright no longer queries its market channel. Buying mats from vendors and
  training recipes are unchanged.

## 1.1.1

- Fixed `Bindings.xml` being listed in the .toc, which spammed XML warnings on load and stopped
  the key bindings from registering. They now load correctly (Esc → Key Bindings → Skillwright).

## 1.1.0

**Guild Market (GuildFoundMarket integration)** — for realms without an Auction House.

- **Check guild prices** button on the Now tab queries GuildFoundMarket for what guildmates
  are selling the step's farmed mats for.
- A **side panel** lists each seller, their quantity and price; click a seller to open a
  pre-filled whisper and arrange the trade.
- Cheapest guild price also shows in each material's tooltip (Now and Shopping tabs).
- **Estimate cost to 300** on the Shopping tab totals the farmed mats by their cheapest guild
  price (asks a few at a time, on click, so it's easy on the channel).
- Skips vendor-bought mats (thread/dye/salt) — you just buy those from a supplier.
- Prompts you to install or connect GuildFoundMarket when it isn't set up.

**Dashboard**

- Shows **all 12 professions in two columns**; ones you haven't learned are greyed but still
  open, so you can preview and plan any profession.
- Hover a profession for an effort summary (steps · crafts · total mats to 300).
- Unlearned professions get a proper **overview** on the Now tab instead of a fake "current step".

**Accuracy & crafting**

- Reads the game's **actual recipe reagents** when the trade window is open, so material counts
  always match the recipe (and any data slip self-corrects).
- Shows the **bare-minimum mats** next to the recommended amount, so you don't over-farm.
- New `/sw verify` command audits our path data against the game's recipes.
- _Work in progress:_ **auto-stop crafting at the step's skill target.** When you craft via
  Skillwright's button it tries to stop the repeat once you hit the target, and is scoped to
  only the leveling recipe you started (it won't interrupt anything else). Still being
  verified — please report if it stops too early, too late, or not at all.

**Also**

- **Key bindings** for toggling the dashboard and the guide (Esc → Key Bindings → Skillwright).
- Optional **LibDataBroker** launcher — if another addon provides the library, Titan Panel /
  ChocolateBar users get a Skillwright launcher (Skillwright itself stays dependency-free).

**Fixes**

- Minimap button sits cleanly on the ring at the right size, with a hover glow.
- The vendor **Buy** button now buys for **every crafting profession you have**, not just the
  active one (mats several professions share are summed).
- Buy button now appears whenever a vendor stocks supplier mats you need (it no longer waited
  until you had the farmed mats first); it shows both in the guide and on the merchant window.
- Corrected several dye item IDs.
- Closing a vendor also closes the guide docked to it.
- Buy and Check-guild-prices buttons share a row to save space.
- Opening the settings panel no longer force-opens the guide window — a "Show guide window"
  button previews appearance changes on demand instead.

## 1.0.0

First public release.

- Optimal craft paths to 300 for Alchemy, Blacksmithing, Cooking, Enchanting,
  Engineering, First Aid, Leatherworking and Tailoring.
- Zone-by-zone gathering routes for Herbalism, Mining, Skinning and Fishing.
- **Now / Steps / Shopping** views with live have / need material counts.
- One-click **Buy** at vendors (buys the mats it stocks that your next steps need) and
  **Train** at trainers (learns the recipes your path calls for).
- Shift-click any material or recipe to link it in chat.
- Window **attaches to and follows your profession window**, or floats freely.
- Dashboard listing every profession on the character, a minimap button, and a settings
  panel (opacity, scale, atmospheric background, and more).
