# Publishing Survivor Watch to Steam Workshop

Survivor Watch 1.6.6 is ready to package for the Project Zomboid Steam Workshop.

The first upload should stay **Unlisted** until the Workshop-downloaded copy passes one clean-install smoke test. After that, change the Workshop item visibility to **Public**.

## Requirements

- Project Zomboid Build 42 installed through Steam.
- A Steam account that owns Project Zomboid.
- The finished Survivor Watch repository.
- A `preview.png` that is exactly **256 x 256 pixels**, PNG format, and no larger than **1000 KB**.
- Project Zomboid should be closed while assembling or replacing the Workshop staging folder.

The Workshop item ID assigned by Steam is separate from the mod ID. The mod ID must remain:

`SurvivorPhone`

## Workshop package layout

The packaging script produces:

```text
SurvivorWatchWorkshop/
├─ preview.png
├─ workshop.txt
└─ Contents/
   └─ mods/
      └─ SurvivorPhone/
         ├─ mod.info
         ├─ common/
         │  └─ mod.info
         └─ 42/
            ├─ mod.info
            └─ media/
```

The uploader-validating copy is `common/mod.info`. The root copy is retained for compatibility, while the tested Build 42 gameplay payload remains unchanged in `42/`.

## Build the package

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-workshop-package.ps1 -PreviewPath 'C:\path\to\preview.png'
```

By default this creates:

`dist\SurvivorWatchWorkshop`

The script validates the preview dimensions and file size, validates Survivor Watch metadata, places a verified `common/mod.info` where the current Build 42 Workshop validator expects metadata, copies the complete `42` payload, and SHA-256 verifies the packaged Build 42 files against the repository source.

To build directly into Project Zomboid's Workshop authoring folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-workshop-package.ps1 `
  -PreviewPath 'C:\path\to\preview.png' `
  -OutputPath "$env:USERPROFILE\Zomboid\Workshop\SurvivorWatch"
```

The script will not overwrite an arbitrary existing directory. A directory must either be new or have been created previously by this script.

If Steam has already assigned an `id=<WorkshopID>` line in the generated `workshop.txt`, rebuilding the same script-managed output directory preserves that ID.

## First Workshop upload

1. Build or copy the package to:
   `%USERPROFILE%\Zomboid\Workshop\SurvivorWatch`
2. Launch Project Zomboid.
3. Open **Workshop** from the main menu.
4. Choose **Create and Update Items**.
5. Select **Survivor Watch [B42]**.
6. Confirm the preview, title, description, and tags.
7. Keep visibility **Unlisted** for the first upload.
8. Create a new Workshop item and let Steam assign its Workshop ID.

Recommended tags:

- Build 42
- Interface
- QoL
- Skills

## Clean-install smoke test

After the first upload:

1. Close Project Zomboid.
2. Avoid loading both the local development copy and Workshop copy with the same mod ID at the same time.
3. Subscribe to the unlisted Workshop item.
4. Let Steam download it.
5. Launch Project Zomboid and enable Survivor Watch from the Workshop copy.
6. Confirm:
   - the mod appears as Survivor Watch 1.6.6;
   - a carried/worn digital watch opens the compact Survivor Watch;
   - the expanded panel opens;
   - Today / Planner / Progress / Travel / Settings render;
   - Rest/Hunger bars display;
   - no startup Lua errors appear.

This is only a packaging/install smoke test. The 1.6.6 gameplay feature set was already validated before merge.

## Publish publicly

Once the Workshop copy passes the smoke test, edit the Workshop item and change visibility from **Unlisted** to **Public**.

Suggested short description:

> Survivor Watch turns Project Zomboid's digital watch into a compact survival companion with vitals, planning, XP progress, learned action estimates, Suggested Reading, Fitness tracking, and Sleep Reset guidance.

## Updating later versions

For future releases:

1. Finish and test the new version in Git first.
2. Update `42/mod.info`, runtime version text, README, and Workshop description as needed.
3. Re-run `build-workshop-package.ps1` against the same script-managed Workshop output path.
4. Confirm the existing Workshop ID was preserved.
5. Use Project Zomboid's **Create and Update Items** screen to upload the update.
6. Add concise Steam change notes.

Do not change the internal mod ID from `SurvivorPhone`; it is intentionally retained for save compatibility.
