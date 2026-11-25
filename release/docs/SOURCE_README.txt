SkyrimNet Dialogue Scenario Editor 0.3.4 - source of SkyrimNet_DialogueScenarioEditor.dll
==========================================================================================

This folder is the complete source of the DLL shipped in SKSE/Plugins (GPL-3.0-or-later, see
COPYING.txt and THIRD_PARTY_NOTICES.txt in the mod folder).

  src/main.cpp        the Prisma UI host of the settings page, the Papyrus natives
                      (SkyrimNet_DialogueScenarioEditorNative) and the NPC list
  src/generator.cpp   Generate: SkyrimNet's LLM through its C++ API (dse_scenario_plan, then
                      dse_scenario_column per column, on the variant dialogue_scenario_writer)
  src/skyrimnet/      SkyrimNet's plugin API headers (MIT, Fateless.Ai)
  src/PrismaUI_API.h  Prisma UI's API header
  xmake.lua           the build

Building (Windows, Visual Studio 2022, xmake 3.0 or later):

  1. Get CommonLibSSE NG 7.5.4: git clone --branch v7.5.4 https://github.com/alandtse/CommonLibSSE-NG
  2. set COMMONLIB_SSE_NG=<that folder>
  3. xmake f -m release -y
  4. xmake build -y

The DLL is written to build/windows/x64/release/. xmake fetches nlohmann_json 3.12.0 and the
libraries CommonLibSSE NG needs (spdlog 1.16.0, DirectXMath 2024.02, DirectX Tool Kit 24.2.0,
rapidcsv 8.92).

The Papyrus sources of the mod are in Source/Scripts.
