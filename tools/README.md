# Sync the local Project Zomboid mod

From the repository root, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\sync-local-mod.ps1
```

The script defaults to the **currently checked-out branch and commit**. It does
not fetch, switch branches, merge, or modify Git history. Before deploying an
update, fetch and check out the intended branch. If updating an existing branch,
use `git pull --ff-only` only after confirming your local work is clean.

On the first run it identifies a unique installed mod by `42/mod.info` containing
`name=Survivor Watch` and `id=SurvivorPhone`. For a custom user directory or an
ambiguous installation, pass the verified destination explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\sync-local-mod.ps1 -ModPath 'C:\Users\YOUR_USER\Zomboid\mods\SurvivorPhone'
```

The successful destination is remembered in the ignored
`tools/.sync-local-mod.json` and revalidated on every run. Backups go under the
same Zomboid user directory's `ModBackups/SurvivorPhone`, outside the live mod.
Each deployment backs up the **whole installed mod**, verifies that backup,
stages the complete repository `42` payload, and replaces only the live `42`
directory. Root-level installed files remain in place. Old payload files are
removed by the directory swap; no stale Lua files are left behind.

Every payload file is checked by relative filename and SHA-256, including
`WatchPanelUI.lua` and `ClockHotspot.lua`. A `deployment.json` receipt beside the
backup records branch, commit, destination, process status and hashes. Failure
returns exit code 1; a failed swap attempts to restore the original `42` and
preserves the failed payload for investigation. No save or base-game paths are
opened, changed or deleted. Linked paths are rejected.

The script requires Git on PATH and Windows PowerShell 5.1 or PowerShell 7. It
rejects uncommitted changes in `42`; changes outside the game payload are never
discarded. It leaves Project Zomboid running if open and reports that a restart
is required for the new Lua to load. Sync again with the same command for each
future selected update. In-game testing is still required; a successful hash
check confirms deployment, not gameplay behavior.
