# PASTE_ORDER: Steal a Fish island, lighting, props, rod

Ready-to-paste Luau for the world. Files are in `studio/world/`. Your Plot1-Plot8, spawn and gameplay
scripts are never edited: every script **finds** them (`WorldConfig`) and builds around them.

Two kinds of files:
- **Command Bar scripts** (run once in edit mode): open View > Command Bar, paste the whole file, press Enter.
  Don't keep them as Scripts. Each is wrapped so re-running is safe (it clears its own output first).
- **Scripts / LocalScripts** (kept in the place): create the object at the location given, paste the code in.

## Order

| # | File | Kind | Location | What it does |
|---|---|---|---|---|
| 1 | `WorldConfig.luau` | ModuleScript | ReplicatedStorage > **World** (Folder) > WorldConfig | Finds your plots/spawn, exposes island settings. Everything below requires it. |
| 2 | `TerrainBuilder.luau` | Command Bar | View > Command Bar | Deletes the Baseplate, writes the island (beach, sea, coves, hills, plot pads, plaza, paths). 20-60 s. |
| 3 | `LightingSetup.luau` | Command Bar | View > Command Bar | Future lighting, golden hour, Atmosphere, Sky, Bloom, ColorCorrection, SunRays, DepthOfField, water. |
| 4 | `PropBuilder.luau` | Command Bar | View > Command Bar | Nipa huts, bamboo fences, palms, rocks, lanterns, pier into `workspace.WorldProps` (about 1,100 parts). |
| 5 | `RodBuilder.luau` | Command Bar | View > Command Bar | Builds the FishingRod Tool (24 parts) into StarterPack and ServerStorage.Tools. |
| 6 | `RodClient.client.luau` | LocalScript | StarterPack > FishingRod > **RodClient** (and the same inside ServerStorage > Tools > FishingRod) | Cast animation, line, bobber, fires your cast remote. |
| 7 | `DayNightCycle.client.luau` | LocalScript | StarterPlayer > StarterPlayerScripts > **DayNightCycle** | Synced slow day/night that pauses during world events. |
| 8 | `AmbientSound.server.luau` | Script | ServerScriptService > **World** (Folder) > AmbientSound | SoundService setup, waves/wind/seagulls. Paste sound ids at the top. |
| 9 | `PerformanceSetup.luau` | Command Bar | View > Command Bar, **last** | StreamingEnabled, persistent plots, anchoring, shadows off, box collisions. |

Then File > Save / Publish. Play-test with the Device Emulator (phone) once.

## Before you start (2 minutes)

1. Your plots must be named `Plot1` ... `Plot8` (Models or Parts), anywhere in Workspace (a `Plots` folder is
   fine). Your SpawnLocation marks the plaza. If names differ, rename them or edit `WorldConfig.FindPlot`.
2. In `RodBuilder.luau` (or on the finished tool's attributes) set `CastRemotePath` to your cast RemoteEvent,
   default `ReplicatedStorage/Remotes/Cast`. The rod fires it with **no arguments**; your server logic is unchanged.
3. Take a copy of the place first (File > Save As). TerrainBuilder and PropBuilder set undo waypoints, but a backup
   is cheaper than Ctrl+Z on 500 studs of terrain.

## Settings you may want to change

`WorldConfig.SETTINGS`: `SEA_LEVEL_OFFSET` (-7: sea surface 7 studs below the plots), `ISLAND_MARGIN` (95 studs
of island beyond the farthest plot), `HILL_HEIGHT` (26), `PIER_LENGTH` (70), `PIER_DIRECTION` (nil = away from the
plots' centroid, through the spawn). Re-run TerrainBuilder then PropBuilder after changing them.

`AmbientSound.server.luau` top: `SOUND_IDS.waves / seagulls / wind` = free Creator Store audio ids (search "ocean
waves loop", "seagulls", "wind loop", filter by "free to use"). With 0 you get Roblox's built-in swim/whoosh loops as
quiet stand-ins (seagulls stay silent).

`DayNightCycle.client.luau`: `CYCLE_MINUTES = 24` (0 freezes golden hour).

## How the pieces fit the existing systems

- **Mutation event skies**: `EventAtmosphere` (mutation system) snapshots Lighting when an event starts and tweens
  back when it ends. `DayNightCycle` only touches ClockTime/Brightness while `EventState.EventId` is empty and waits
  4.5 s after an event ends, so they never fight. `LightingSetup` names its effects `SAF_*`; EventAtmosphere adds its
  own temporary `SAF_Event*` effects next to them.
- **Fishing rod**: `RodClient` fires your cast RemoteEvent on release, then waits for either
  `ReplicatedStorage.Items.Remotes.FishPopup` (sent by `MutationService.CreateCaughtFish`), your remote firing back to
  the client, or a 25 s timeout, then reels in (with a tug when a fish came). The local cooldown reads
  `EconomyBalance.CastSeconds(player:GetAttribute("EquippedNet"))`; set that attribute on the server when a player
  equips a net, or leave it (10 s Basic Net). The server's own cooldown is still the real one.
- **Pier cast spot**: `workspace.WorldProps.Pier.EndDeck.CastSpot` attachment marks deep water 10 studs past the end
  of the pier, in case you want a "best fishing spot" bonus later.
- **Streaming**: Plot models, SpawnLocation and the pier are Persistent/Atomic so WaitForChild in your scripts still works.

## What I could not do here

No Studio in this sandbox, so none of this was run in Roblox. All 9 files pass `luau-analyze` with Roblox
globals declared. Things to eyeball on first run: the island radius vs. your plot spread (ISLAND_MARGIN), the
pier landing on the beach (PIER_DIRECTION), hut positions (they sit on the side of each plot away from the plaza),
and the rod's Grip offset (edit `GRIP_IDLE`/`tool.Grip` if the rod sits oddly in the hand for your rig).
