# SkyrimNet Dialogue Scenario Editor 0.1.0

> [!CAUTION]
> **Adult content.** Scenarios can end in sex scenes (OStim). For adults only.

Write short scenarios that real NPCs play out when you meet them: who takes part, what the situation is, who says what, and whether a sex scene follows. Or let an NPC write the whole scenario for you. SkyrimNet's AI speaks every line in the speaker's own voice, so the same scenario fits any character.

A Japanese README is in [README_ja.md](README_ja.md).

## Download

[Latest release](https://github.com/nightlantern-mods/SkyrimNet_DialogueScenarioEditor/releases/latest): `SkyrimNet_DialogueScenarioEditor_<version>.zip`, a FOMOD installer for Mod Organizer 2 and Vortex.

## What it does

- **Scenarios in columns.** A scenario has up to 10 columns, played from left to right. Each column has 1 to 3 people (the player too), a narration that sets the situation, up to 10 lines in any order (anyone may speak several times), and, if you like, an OStim scene after the lines with the tags you pick. The same person may appear in several columns; a column with one person can be a masturbation scene.
- **Lines in the speaker's own voice.** A line is not read out word for word: SkyrimNet is told that the speaker is about to say something that means it, and the AI words it the way that character would. Your own lines are spoken by your character through SkyrimNet.
- **Auto lines.** Switch a single line to **Auto**, or a whole column (Short 3, Medium 6, Long 10 lines): the AI makes those lines up when they are spoken, from the column's narration, the columns before and after, and the talk so far.
- **Generate.** Pick a scenario writer (an NPC), 2 to 10 people (NPCs and you), the number of columns and, if you like, a theme. The writer writes every column in their own style: the people of each column, the narration, the lines with their speakers, and where an OStim scene fits, with tags. It draws on the people's bios, memories, recent events and latest diary entries, and on the relationship maps of [SN Sexual Memories](https://github.com/nightlantern-mods/SN_SexualMemories) when there are any. The result goes into the editor, where you check it, change what you like and save.
- **When it starts.** A scenario starts by itself when everyone in it is near you: in the same interior, or close to you outdoors. You choose whether others may be around (it never starts with a child nearby) or only the people in it, whether it may happen indoors, outdoors or anywhere, and whether it happens once or again every few days (0 days: every time you come back to the place).
- **How a column plays.** The people walk over to you (or to the first person, when you are not in the column); anyone who is not there after a few seconds is moved over. They stay together while they talk. Then the OStim scene starts, and the next column begins at once. Someone still in an earlier column's scene is taken out of it before their next scene (that scene ends for everyone in it).

## Requirements

- [SKSE64](https://skse.silverlock.org/) and [Address Library for SKSE Plugins](https://www.nexusmods.com/skyrimspecialedition/mods/32444)
- [SkyrimNet](https://www.nexusmods.com/skyrimspecialedition/mods/198346)
- [OStim Standalone](https://www.nexusmods.com/skyrimspecialedition/mods/98163)
- [PapyrusUtil SE](https://www.nexusmods.com/skyrimspecialedition/mods/13048)
- [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854)
- [MCM Helper](https://www.nexusmods.com/skyrimspecialedition/mods/53000) and [SkyUI](https://www.nexusmods.com/skyrimspecialedition/mods/12604)
- For the settings page: [Magelight UI](https://www.nexusmods.com/skyrimspecialedition/mods/193303) or [Prisma UI](https://www.nexusmods.com/skyrimspecialedition/mods/148718). When both are installed, Magelight UI is used. Tested with Magelight UI; the Prisma UI page has not been tested in game yet.

Optional: [SN Sexual Memories](https://github.com/nightlantern-mods/SN_SexualMemories) (its relationship maps are used by Generate).

Tested with Skyrim SE 1.6.1170, SkyrimNet (Nexus build of 2026-11-16), OStim Standalone 7.5.1, PapyrusUtil 4.6, powerofthree's Papyrus Extender 6.5.2, MCM Helper 1.6.2, SkyUI 6.11 and Magelight UI 16.

## Installing

Install the archive with Mod Organizer 2 or Vortex. The installer asks for the language of the settings menu and the settings page (English or Japanese); the mod itself works with any game language. Without a mod manager, copy the contents of `core/en` (or `core/ja`) into `Data`.

## Using it

1. In the MCM (**SkyrimNet Dialogue Scenario Editor**), set **Key that opens the settings page**. No key is set at first.
2. Press the key. Choose **New event**, give it a name (letters, digits, `_` and `-`), and fill in the columns, or use **Generate**.
3. Press **Save**. The switch next to each event in the list turns it on or off at once.
4. Walk up to the people of a scenario that is on: it starts when they are all near you.

A disabled example scenario, `example_riverwood`, is included.

### Generate and its AI model

Generate sends one request for the plot and one for each column to SkyrimNet's AI, on its own model setting: in SkyrimNet's dashboard, **AI > Models**, `dialogue_scenario_writer`. Left empty, SkyrimNet's default model is used. The answers are JSON, so a model that follows JSON instructions well works best.

### Where scenarios are kept

Each scenario is a JSON file in `Data/SKSE/Plugins/StorageUtilData/SkyrimNet_DialogueScenarioEditor/` (with Mod Organizer 2, new files go to the overwrite folder). They are the same for every save. Whether a scenario has already happened is kept in the save.

## Known limits

- An NPC sitting in a chair does not always stand up to walk over; after a few seconds they are moved over.
- Prisma UI: supported, not tested in game yet.

## Building

The repository holds everything the release archive is made from:

| Folder | What |
| --- | --- |
| `src/`, `xmake.lua` | The SKSE plugin (DLL): the Prisma UI host of the settings page, the Papyrus natives, the NPC list and Generate. |
| `scripts/` | The Papyrus scripts. `scripts/stubs/` holds compile-only declarations of the OStim, powerofthree's Papyrus Extender and MCM Helper functions used (never shipped). |
| `plugin/` | The ESP in text form (Mutagen YAML). |
| `assets/` | The files that go into `Data` as they are: the Japanese settings page, MCM config, SkyrimNet prompts and model setting, line wording and example scenario. |
| `release/` | `tools/build_fomod.ps1` (the FOMOD archive), `tools/make_en_page.py` (the English page, made from the Japanese one), `tools/make_strings.py` (MCM texts for all ten game languages), the English files and the docs. |

- **DLL:** Visual Studio 2022 and xmake 3.0 or later. Clone [CommonLibSSE NG 7.5.4](https://github.com/alandtse/CommonLibSSE-NG/tree/v7.5.4), set `COMMONLIB_SSE_NG` to it, then `xmake f -m release -y` and `xmake build -y`.
- **Scripts:** compile `scripts/*.psc` with the Creation Kit's PapyrusCompiler, with `scripts/stubs` and the Papyrus sources of SkyrimNet, PapyrusUtil SE and Magelight UI on the import path.
- **Archive:** `release/tools/build_fomod.ps1`. Its default paths are those of the author's machine; pass `-Project` and `-Dll` for yours.

## License and credits

- This mod (scripts, plugin, settings page, prompts, texts) is © 2026 takafumi under the **MIT License** (THIRD_PARTY_NOTICES.txt, section 1). The two SkyrimNet prompts (`dse_scenario_plan`, `dse_scenario_column`) were written for this mod; they call SkyrimNet's own template functions and its event history component, which are not included.
- **SKSE/Plugins/SkyrimNet_DialogueScenarioEditor.dll** statically links CommonLibSSE NG (GPL-3.0-or-later with a Modding Exception and a GPL-3.0 Linking Exception), so the DLL is distributed under the **GNU General Public License, version 3 or later** (COPYING.txt). Its complete source code is in this repository (and in `Source/` of the release archive).
- The DLL also contains SkyrimNet's plugin API headers (MIT, © Fateless.Ai), the Prisma UI API header, JSON for Modern C++, spdlog, DirectXMath, DirectX Tool Kit and rapidcsv, each under its own license: see **THIRD_PARTY_NOTICES.txt**.
- SkyrimNet, OStim, PapyrusUtil, powerofthree's Papyrus Extender, MCM Helper, SkyUI, Magelight UI, Prisma UI and SN Sexual Memories are separate mods by their authors and are not included.
- This is an unofficial fan-made mod. It is not made, endorsed or supported by Bethesda Softworks, ZeniMax Media, Fateless.Ai or the authors of the mods above. The Elder Scrolls and Skyrim are trademarks of ZeniMax Media Inc.
