# MUTATION_MANIFEST: Steal a Fish (stars, mutations, world events)

This extends the item system in `ITEMS_MANIFEST.md` / `studio/items/`. Existing modules are extended, not
rewritten. New Luau lives in `studio/mutations/`, and each file's header comment says where it goes in Studio.

## Status

| Phase | Status |
|---|---|
| 1. Plan | done |
| 2. Data modules (StarConfig, MutationData, FishDisplay) | done; EconomyBalance extended (stars and mutations optional args) |
| 3. Event scheduler (EventSchedule, EventAuthority, EventServer) | done: 31 Luau tests pass |
| 4. Roller, stacking, DataStore schema (MutationRoller, FishSchema, MutationService) | done: 94 Luau tests pass |
| 5. UI (countdown panel, banners, popups, fish visuals, atmosphere) | done: 8 client files, luau-analyze clean; not run in Studio |
| 6. Economy + tests | pending |
| 7. Manifest + final report | pending |

## Plan

1. **Stars** (`StarConfig`): each catch rolls a size fraction. Quality is the average of weight fraction and size fraction, and quality maps to 1-5 stars. The thresholds are derived from configured odds, so the odds stay exact. Each star has a value multiplier.
2. **Mutations** (`MutationData`): 8 config entries, each covering the event, the mutation, its tint and its sky preset. Stacking is config-driven (additive with a hard cap by default).
3. **Scheduler** (`EventSchedule`): a pure function of `workspace:GetServerTimeNow()` plus a fixed seed. Time is cut into fixed slots, and a 32-bit hash of (seed, slot) picks each slot's event by weight. Every server computes the same answer without MessagingService. `EventServer` publishes the state as attributes for clients.
4. **Server rolls** (`MutationRoller` + `MutationService`): stars and mutations roll only on the server, on catch and on steal. They only roll for the event the server says is active. Records follow a versioned DataStore schema (`FishSchema`, v2).
5. **UI** (LocalScript + child ModuleScripts): built entirely in code, phone-first, with UIScale, safe-area insets and TweenService.
6. **Economy**: `EconomyBalance` gains star and mutation multipliers plus event uptime. A Luau simulation of 40 players runs on the *real* modules, checks the 10-hour curve, and prints the value table.

## Decisions log

_Filled during the run._

## Failures and retries

_Filled during the run._
