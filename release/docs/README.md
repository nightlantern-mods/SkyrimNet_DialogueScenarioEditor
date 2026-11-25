# SkyrimNet Dialogue Scenario Editor 0.3.4

> [!CAUTION]
> **Adult content.** Scenarios can end in sex scenes (OStim or SexLab). For adults only.

Write short scenarios that real NPCs play out when you meet them: who takes part, what the situation is, who says what, and whether a sex scene follows. Or let an NPC write the whole scenario for you. SkyrimNet's AI speaks every line in the speaker's own voice, so the same scenario fits any character.

A Japanese README is in `README_ja.md`.

## What it does

- **Scenarios in columns.** A scenario has up to 10 columns, played from left to right. Each column has 1 to 3 people (the player too), a narration that sets the situation, up to 10 lines in any order (anyone may speak several times), and what ends the column: nothing (talk only), a sex scene with the tags you pick (OStim, or SexLab P+ / 1.6x; the MCM sets which when both are installed), on a nearby bed if you like, **end the scene** the people are in, **move and wait** (chosen people walk to an interior and wait there until another scenario has happened or some days have passed), or **a SkyrimNet action** that one of the people does (only the actions of mods you have installed are offered, for example SeverActions). The same person may appear in several columns; a column with one person can be a masturbation scene.
- **Lines in the speaker's own voice.** A line is not read out word for word: SkyrimNet is told that the speaker is about to say something that means it, and the AI words it the way that character would. Your own lines are spoken by your character through SkyrimNet.
- **Auto lines.** Switch a single line to **Auto**, or a whole column (Short 3, Medium 6, Long 10 lines): the AI makes those lines up when they are spoken, from the column's narration, the columns before and after, and the talk so far.
- **Generate.** Pick a scenario writer (an NPC), 2 to 10 people (NPCs and you), the number of columns and, if you like, a theme. The writer writes every column in their own style: the people of each column, the narration, the lines with their speakers, and where a sex scene fits, with tags. It draws on the people's bios, memories, recent events and latest diary entries, and on the relationship maps of [SN Sexual Memories](https://github.com/nightlantern-mods/SN_SexualMemories) when there are any. The result goes into the editor, where you check it, change what you like and save. **Generate (auto lines)** writes only the people, narration and sex scenes (tags) of each column and sets the lines to Auto (Medium), made up in the game as it plays.
- **When it starts.** A scenario starts by itself, or when you press the scenario hotkey (set in the MCM; your choice per scenario), when everyone in it is near you: in the same interior, or close to you outdoors. You choose whether others may be around or only the people in it, whether it may happen indoors, outdoors or anywhere, or only in one cell (an interior from the list, or the cell you are in), whether it happens once or again every few days (0 days: every time you come back to the place), and whether another scenario must have finished first.
- **How a column plays.** The people walk over to you (or to the first person, when you are not in the column); anyone who is not there after a few seconds is moved over. They stay together while they talk. Then the column's end (a sex scene, ending the scene, move and wait, or an action) follows, and the next column begins as soon as whoever is talking has finished (up to 20 seconds; what is still queued after that is dropped). If you leave the place while a scenario plays (into another cell, or far away outdoors), it stops and counts as not having happened, so it can start again later.
- **Sex scenes.** The scene that fits the tags best is chosen: one with all of them first, then one with the tags that say what happens (positions and acts), and a scene that only shares a mood tag (romantic, lustful, dom) last. With **On a bed**, the scene is played on the nearest free bed if there is one; when you take part, everyone is moved onto the bed just before it starts. When exactly the same people are still in a scene from an earlier column, that scene goes on and only the animation changes (no standing up and dressing in between); otherwise it is stopped before the new one starts (it ends for everyone in it).

## Requirements

- [SKSE64](https://skse.silverlock.org/) and [Address Library for SKSE Plugins](https://www.nexusmods.com/skyrimspecialedition/mods/32444)
- [SkyrimNet](https://www.nexusmods.com/skyrimspecialedition/mods/198346)
- For sex scenes: [OStim Standalone](https://www.nexusmods.com/skyrimspecialedition/mods/98163) or [SexLab P+](https://www.loverslab.com/files/file/31574-sexlab-p/) / SexLab 1.6x (either one; without them, scenarios still play their talk, move and wait, and actions)
- [PapyrusUtil SE](https://www.nexusmods.com/skyrimspecialedition/mods/13048)
- [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854)
- [MCM Helper](https://www.nexusmods.com/skyrimspecialedition/mods/53000) and [SkyUI](https://www.nexusmods.com/skyrimspecialedition/mods/12604)
- For the settings page: [Magelight UI](https://www.nexusmods.com/skyrimspecialedition/mods/193303) or [Prisma UI](https://www.nexusmods.com/skyrimspecialedition/mods/148718). When both are installed, Magelight UI is used. Tested with Magelight UI; the Prisma UI page has not been tested in game yet.

Optional: [SN Sexual Memories](https://github.com/nightlantern-mods/SN_SexualMemories) (its relationship maps are used by Generate).

Tested with Skyrim SE 1.6.1170, SkyrimNet (Nexus build of 2026-11-16), OStim Standalone 7.5.1, SexLab P+, PapyrusUtil 4.6, powerofthree's Papyrus Extender 6.5.2, MCM Helper 1.6.2, SkyUI 6.11 and Magelight UI 16.

## Installing

Install the archive with Mod Organizer 2 or Vortex. The installer asks for the language of the settings menu and the settings page (English or Japanese); the mod itself works with any game language. Without a mod manager, copy the contents of `core/en` (or `core/ja`) into `Data`.

## Using it

1. In the MCM (**SkyrimNet Dialogue Scenario Editor**), set **Key that opens the settings page**. No key is set at first.
2. Press the key. Choose **New event**, give it a name (letters, digits, `_` and `-`), and fill in the columns, or use **Generate**.
3. Press **Save**. The switch next to each event in the list turns it on or off at once.
4. Walk up to the people of a scenario that is on: it starts when they are all near you (a hotkey scenario starts when you press **Key that starts a hotkey scenario**, set in the MCM).

**Page size** at the top of the page makes the whole page larger or smaller (70 to 200 %): drag the slider or press − / +. The size is kept for the next time the page opens.

A disabled example scenario, `example_riverwood`, is included. A scenario you delete stays deleted, also after the mod is updated.

The list marks a scenario that has run in this save with **Ran**. The editor shows when it started, whether it finished, and the cell it will not start in again until you leave; **Clear the run record** (press it twice) makes it count as never run.

### Excluded scenes

**Excluded scenes** (below **New event**) lists sex scenes never to pick, for every scenario: one scene ID per line, and every scene whose ID begins with it is left out (`BillyyCcg` leaves out BillyyCcg-1, BillyyCcg-2 and so on). The list is empty at first. The log names each scene just before it starts (`OStim scene ...`; for SexLab, `scene ...` once it has started), so a scene that breaks can be found there and added.

### Generate and its AI model

Generate sends one request for the plot and one for each column to SkyrimNet's AI, on its own model setting: in SkyrimNet's dashboard, **AI > Models**, `dialogue_scenario_writer`. Left empty, SkyrimNet's default model is used. The answers are JSON, so a model that follows JSON instructions well works best.

### Where scenarios are kept

Each scenario is a JSON file in `Data/SKSE/Plugins/StorageUtilData/SkyrimNet_DialogueScenarioEditor/` (with Mod Organizer 2, new files go to the overwrite folder). They are the same for every save. Whether a scenario has already happened is kept in the save.

### When something goes wrong: the log

The mod writes what it does to `Documents\My Games\Skyrim Special Edition\SKSE\SkyrimNet_DialogueScenarioEditor.log` (no INI setting needed): on every load, your scenarios and SkyrimNet's voice settings; why a scenario is not starting (once each time the reason changes); and while one runs, every line, who said it, SkyrimNet's speech events and how long each wait took. The file is made new at every game start, so copy it (with `SKSE\SkyrimNet.log`) right after the problem, before starting the game again.

## Known limits

- An NPC sitting in a chair does not always stand up to walk over; after a few seconds they are moved over.
- Prisma UI: supported, not tested in game yet.
- SexLab: the bed choice and changing the animation of a scene that goes on into the next column have been tested in game with OStim only.
- SkyrimNet itself can pick actions (a brawl, giving items, following...) from what the narration and lines say, apart from the actions set at the end of a column; auto lines make this more likely. To have an action happen exactly where you put it, let the narration and lines lead up to it (an argument, not the punch) and let the column-end action start it.

## License and credits

- This mod (scripts, plugin, settings page, prompts, texts) is © 2026 takafumi under the **MIT License** (THIRD_PARTY_NOTICES.txt, section 1). The two SkyrimNet prompts (`dse_scenario_plan`, `dse_scenario_column`) were written for this mod; they call SkyrimNet's own template functions and its event history component, which are not included.
- **SKSE/Plugins/SkyrimNet_DialogueScenarioEditor.dll** statically links CommonLibSSE NG (GPL-3.0-or-later with a Modding Exception and a GPL-3.0 Linking Exception), so the DLL is distributed under the **GNU General Public License, version 3 or later** (COPYING.txt). Its complete source code and build files are included in `Source/SKSE/SkyrimNet_DialogueScenarioEditor/`; the Papyrus sources are in `Source/Scripts/`.
- The DLL also contains SkyrimNet's plugin API headers (MIT, © Fateless.Ai), the Prisma UI API header, JSON for Modern C++, spdlog, DirectXMath, DirectX Tool Kit and rapidcsv, each under its own license: see **THIRD_PARTY_NOTICES.txt**.
- SkyrimNet, OStim, SexLab, PapyrusUtil, powerofthree's Papyrus Extender, MCM Helper, SkyUI, Magelight UI, Prisma UI and SN Sexual Memories are separate mods by their authors and are not included.
- This is an unofficial fan-made mod. It is not made, endorsed or supported by Bethesda Softworks, ZeniMax Media, Fateless.Ai or the authors of the mods above. The Elder Scrolls and Skyrim are trademarks of ZeniMax Media Inc.
