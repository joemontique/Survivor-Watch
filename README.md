# Survivor Watch 1.6.6

Survivor Watch is a Project Zomboid Build 42 single-player digital-watch companion focused on planning, needs, XP progress and learned recommendations.

The player-facing mod is a watch, but the internal mod ID remains `SurvivorPhone` so existing character mod data continues to load.

## 1.6.6 highlights

### Progress and XP learning

- Progress now puts skills that gained XP today above skills with zero XP today.
- Within those groups, skills are ordered by XP remaining to the next level.
- Repeatable actions learn from recent matching XP samples and estimate how many similar actions remain before the next level.
- Fishing catches feed the same learning system, showing `Learning 1/3`, `Learning 2/3`, then a rolling average and estimated catches remaining.
- Running and sprinting have a dedicated Fitness model that learns from elapsed running time, distance traveled and observed Fitness XP.
- Fitness shows a provisional estimate first, then moves to a learned rate as evidence accumulates.
- Zero-XP running time is retained so long stretches before a Fitness XP award are not ignored.
- Weight and weight trend remain visible in Progress.

### Suggested Reading

- Progress includes a Suggested Reading section.
- A skill is suggested only after it earns XP during the current in-game day.
- The watch checks whether the full skill-book multiplier for the survivor's current level range is active.
- Recommendations distinguish between `Not read` and `Partially read`.
- Recommendations disappear once the full current book multiplier is active.
- Current-day XP resets on the next in-game day, so Suggested Reading follows the skills the survivor is actively training now.

### Vitals

- The compact and expanded watch use:
  - Hunger
  - Hydration
  - Rest
  - Stamina
- `Rest` replaces the older Recovery wording.
- Hunger keeps meaningful reserve below the first hunger moodle instead of dropping directly to zero.
- Rest now behaves the same way: Drowsy is a red warning state but still leaves reserve; deeper tiredness continues draining the bar and 0% is reserved for maximum fatigue.
- Hunger becomes urgent/red starting at Peckish, and Rest becomes urgent/red starting at Drowsy.
- Expanded Hunger and Rest can show the active moodle state together with the remaining percentage.

### Sleep Reset

- Sleep Reset now uses the actual in-game time-of-day instead of elapsed world time when choosing a target.
- Corrective naps are kept short enough to reduce fatigue without intentionally pushing the survivor into the next normal sleep period.
- Targets display AM/PM and explicitly indicate `today` or `tomorrow`.
- The alarm target is always forward from the current in-game time.

### Watch and vanilla alarm interaction

- Clicking the vanilla time portion of the HUD can open Survivor Watch.
- The watch hotspot is limited to the time area so the vanilla alarm area remains usable.
- While a digital-watch alarm is ringing, Survivor Watch yields the HUD interaction so the vanilla alarm can be dismissed normally.

### Notifications

- Survivor Watch popup/toast notifications are disabled.
- Planner, needs, sleep and XP-related events can still be recorded in history.
- The underlying planner and learning systems continue to operate without popup interruption.

## Tested in-game for 1.6.6

The candidate build was tested in Project Zomboid Build 42 and passed the high-risk paths used for this release:

- opening the compact and expanded Survivor Watch
- expanded-window tabs and controls
- Progress screen rendering and scrolling
- Suggested Reading, including partial book progress
- active-skill Progress sorting
- running/sprinting Fitness tracking and learned estimates
- fishing XP action estimates
- Animal Care recognition
- Mechanics recognition
- generator interaction recognition
- vanilla time versus alarm HUD interaction
- Hunger and Rest display behavior
- Sleep Reset target timing

A render-time full item scan used by the first Suggested Reading implementation caused the Progress screen to freeze during testing. That approach was removed; Suggested Reading now derives the required skill-book volume without scanning every scripted item.

## Persistence and compatibility

Persistent values remain under:

`getModData().SurvivorPhone`

The internal mod ID remains:

`SurvivorPhone`

This is intentional for save compatibility. Installation and deployment do not require editing Project Zomboid save files or base-game files.

## Installation / local deployment

The Build 42 mod payload is under the `42` directory.

For the development checkout on Windows, the included sync script can back up the installed mod, deploy the complete payload and verify file hashes:

`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\sync-local-mod.ps1`

See [tools/README.md](tools/README.md) for the sync workflow and destination setup.

## Current scope

Survivor Watch is single-player focused. Terrain-map work and battery drain/charging remain outside the current release scope.
