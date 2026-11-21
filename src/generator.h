#pragma once

#include <string>

// Scenario generation (the settings page's Generate): the scenario writer, an NPC, writes a whole
// scenario for the chosen people through SkyrimNet's LLM, on the variant dialogue_scenario_writer
// (its model is set in SkyrimNet's dashboard). One request for the plot and the outline of every
// column (dse_scenario_plan), then one per column for its narration and lines
// (dse_scenario_column). Progress and the result go to Papyrus as the mod event "DSE_Gen" (strArg:
// JSON), which hands them to the page's dseGen().
namespace Generator
{
    // kDataLoaded: finds SkyrimNet's C++ API.
    void SetUp();

    // a_request (from the page): {"writer": {"spec", "name"}, "people": [{"spec", "name"}],
    // "columns": n, "theme": text, "language": text, "tags": [{"tag", "meaning"}],
    // "solo_tags": [tag]}. False when it cannot start (the reason is sent as a DSE_Gen error).
    bool Start(const std::string& a_request);
}
