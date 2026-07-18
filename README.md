# Flammable Oils Continued

An unofficial continuation of **Flammable Oils_QUICKFIX** by Fr_Dae and contributors, updated for Factorio 2.1.

Fluid-filled infrastructure can rupture, explode, and spread fire when destroyed. Optional solid-item fires also allow combustible materials to ignite on belts, on the ground, and inside destroyed cargo containers.

## Features

- Detects flammable fluids and calculates reactions from the combined energy stored across an entity's fluidboxes.
- Supports pipes, underground pipes, storage tanks, fluid wagons, production machines, pumps, and other fluid-handling entities.
- Provides configurable ignition chances by damage type, ignition delay, explosion scaling, pollution, fire spread, fluid filters, and per-tick processing limits.
- Includes persistent remote-interface controls for modded fluid flammability, gas classification, and energy values.
- Optionally burns wood, coal, solid fuel, rocket fuel, filled fluid barrels, and flamethrower ammunition.
- Burns items at their actual positions on belts or the ground and reacts to supported cargo inside destroyed chests and cargo wagons.
- Uses bounded processing queues to keep large chain reactions from overwhelming a single game tick.

## Solid-item behavior

| Item | Behavior |
| --- | --- |
| Wood | Ignites readily and burns quickly. |
| Coal | Ignites more slowly and produces more pollution than wood. |
| Solid fuel | Burns as a petroleum fire without detonating. |
| Rocket fuel | Burns violently and can cause damaging explosions. |
| Filled fluid barrels | Inherit the flammability and energy of their contained fluid. Empty barrels remain inert. |
| Flamethrower ammunition | Produces an intense fire and a small explosion. |

The solid-item system is disabled by default. Its individual item and location settings are enabled behind the master switch, and burner fuel inventories are never scanned.

## Compatibility

- Factorio 2.1, with or without Space Age.
- Cannot be enabled at the same time as `Flammable_Oils` or `Flammable_Oils_QUICKFIX` because they provide overlapping prototypes and behavior.
- Retains optional load-order compatibility with KS Power, Factorio Tiberium, Water Turret Revived, and Lily's Incendiaries.

## Credits and license

Maintained by cciacona. Based on [Flammable Oils_QUICKFIX](https://mods.factorio.com/mod/Flammable_Oils_QUICKFIX) by Fr_Dae and contributors, which continues the original [Flammable Oils](https://github.com/Klonan/Flammable_Oils) by Klonan and OwnlyMe. This is an unofficial continuation and is not affiliated with the original maintainers.

This continuation is distributed under the [MIT License](LICENSE), Copyright (c) 2026 cciacona.

Material inherited from Flammable Oils_QUICKFIX was distributed under the Beerware license and remains under those original terms.
