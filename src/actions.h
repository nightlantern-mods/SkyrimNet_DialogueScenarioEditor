#pragma once

#include <string>
#include <vector>

// SkyrimNet actions that other mods define in YAML (SKSE/Plugins/SkyrimNet/external/<mod>/actions/
// and config/actions/), for a column ending in "a SkyrimNet action". Only the files of installed
// mods are there, and the Papyrus side keeps only the names SkyrimNet has registered
// (IsActionRegistered), so the page lists what can run in this game. Actions that a C++ plugin
// registers in code have no file and are not listed.
namespace Actions
{
    // Every action name found (categories and disabled ones left out). Read once, on first use.
    std::vector<std::string> Names();

    // The page's list for the given names (the registered ones), as JSON:
    // [{"n": name, "m": mod, "d": description, "p": [{"n": parameter, "d": description, "o": optional}]}]
    // where "p" holds only the parameters a caller fills in (type "dynamic").
    std::string ListJson(const std::vector<std::string>& a_names);
}
