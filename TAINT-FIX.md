# Open this pull request

One-click compare (then click **Create pull request**):

https://github.com/vBaustad/Skillwright/compare/main...ballzac81:fix-trainer-taint-pet?expand=1

If GitHub says the branch is behind, first open https://github.com/ballzac81/Skillwright and click **Sync fork**.

## Suggested title

Fix ADDON_ACTION_FORBIDDEN on BuyTrainerService (blocks pet training)

## Suggested body

Hi — this stops Skillwright tainting the shared trainer frame, which currently blocks the default Train button (including hunter pet training).

### Bug

```
[ADDON_ACTION_FORBIDDEN] AddOn 'Skillwright' tried to call the protected function 'BuyTrainerService()'.
[C]: in function 'BuyTrainerService'
[Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua]:887
```

`ClassTrainerFrame` is reused for profession trainers **and** pet/class/riding trainers. Two things in `Core/Trainer.lua` taint that frame:

1. Replacing `_G.ClassTrainerFrame_Update` while scanning filters.
2. Calling protected `BuyTrainerService()` from the addon's own Train button.

Once that taint is on the frame, Blizzard's Train button fails for the rest of the session.

### Fix

In `Core/Trainer.lua`:

- Ignore non-profession trainers (`IsTradeskillTrainer()`).
- Do not wrap/replace `ClassTrainerFrame_Update`.
- Do not call `BuyTrainerService()`. The game only accepts a click on Blizzard's own Train button; Skillwright's button now says so instead of poisoning the frame.

Profession recipe scanning is unchanged. After this lands, `/reload` once to clear any taint already in the current session.

Reproduced on Forever with Skillwright 0.2.0-beta1 while training a hunter pet.
