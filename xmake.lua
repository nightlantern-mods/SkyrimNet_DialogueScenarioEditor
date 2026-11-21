-- set minimum xmake version
set_xmakever("3.0.0")

-- CommonLibSSE-NG: a checkout shared with the other Prisma UI plugins (override with COMMONLIB_SSE_NG)
includes(os.getenv("COMMONLIB_SSE_NG") or "C:/Modding/MotionCommander/lib/commonlibsse-ng")

local PLUGIN_NAME = "SkyrimNet_DialogueScenarioEditor"
local PLUGIN_VERSION = "0.1.0"

set_project(PLUGIN_NAME)
set_version(PLUGIN_VERSION)
set_license("MIT")

set_languages("c++23")
set_warnings("allextra")
add_defines("UNICODE", "_UNICODE")

add_rules("mode.release")

add_requires("nlohmann_json v3.12.0")

target(PLUGIN_NAME)
    add_deps("commonlibsse-ng")
    add_packages("nlohmann_json")

    add_rules("commonlibsse-ng.plugin", {
       name = PLUGIN_NAME,
       author = "nightlantern-mods",
       description = "Prisma UI host for the SkyrimNet Dialogue Scenario Editor settings page"
    })

    add_files("src/**.cpp")
    add_headerfiles("src/**.h")
    add_includedirs("src")
    set_pcxxheader("src/pch.h")
    add_cxflags("/utf-8")
