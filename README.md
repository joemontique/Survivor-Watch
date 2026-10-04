# Survivor Watch 1.6.5

A Project Zomboid Build 42.20.4 single-player digital-watch tracker. The internal mod ID remains `SurvivorPhone` so existing character mod data keeps loading, but the player-facing flow is now a watch/tracker instead of a phone.

## This update

- Reworks the small watch face around Vitals first: Hydration, Fuel, Recovery and Stamina are the top readout after the in-game time.
- Adds a fast `Mute all notifications` control on the watch face, the Details footer and Gear. It silences popups only; tracking, XP, planner recognition, What Now and history continue.
- Keeps thirst visible in Vitals and What Now, but thirst no longer creates popup notifications at any moodle level.
- Scales the detailed drawer slightly smaller and cleans wording so it feels more like a readable fitness tracker.
- Keeps Dimmer / opacity, Dashboard size, Watch size and Watch opacity controls.

## Retained behavior

- Planner schedule times use Project Zomboid in-game time. Need forecasts display approximate IRL countdowns.
- Hunger, Thirst, Recovery and Stamina remain normalized reserves with native state labels. Hunger only shows 100% at the full/stuffed states and drops when that state ends. Recovery reaches zero at Drowsy and pulses at stronger tiredness.
- What Now recommends one action at a time using needs, current activity, schedule windows, travel/place evidence and learning history.
- Planner rows remain compact checklist items with one task Actions menu. Older completed tasks hide after the most recent completion unless history is opened.
- Auto-complete favors correctness: chicken care uses confirmed Animal Care XP or native petting action hooks, fishing requires a real caught item plus pickup XP, generator hooks use exact generator interactions, and duplicate task matches do not guess unless one matching task is already active.
- Food and water stay manual. Map work is paused. Battery drain/charging is still a late future feature.

## Persistence and compatibility

All persistent values remain under the character's `getModData().SurvivorPhone` table. Existing `dnd` settings are preserved and shown as Mute all notifications. No save files are opened or edited by installation. Original Project Zomboid game files and debug files are unchanged.

## First test after install

1. Start Project Zomboid fresh and load a test world or your current world only if you are comfortable testing the mod there.
2. Wear or carry a digital watch. Confirm the small watch face opens and puts Vitals first.
3. Toggle `Muted` / `Alerts` from the watch face or footer and confirm popups stop while tracking continues.
4. Become Slightly Thirsty or Thirsty and confirm there is no thirst popup, while Vitals still shows the condition.
5. Open Details and confirm the drawer is smaller, readable and keeps Vitals separate.

## Verification

The validation harness compiles and executes the production Lua in Lua 5.1 with simulated Build 42 objects and native game Lua fixtures. It does not launch the game and does not touch the main save.

## Deploy updates on Windows

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\sync-local-mod.ps1` from the repository
root to back up and deploy the complete `42` payload from the checked-out branch.
See [the sync workflow](tools/README.md) for initial destination setup, verification,
backup receipts and restart requirements. The script does not merge branches.
