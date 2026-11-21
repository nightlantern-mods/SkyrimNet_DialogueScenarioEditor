Scriptname SkyrimNet_DialogueScenarioEditorNative Hidden
{Natives of SKSE\Plugins\SkyrimNet_DialogueScenarioEditor.dll. Without the DLL every function returns 0 / false.

The Prisma UI host of the settings page: the page's calls window.dse_*(text) arrive as mod events
"DSE_Prisma_dse_*" (strArg = text). Scenario generation: progress and the result arrive as the mod
event "DSE_Gen" (strArg = JSON for the page's dseGen).}

; 1 or more when the DLL is loaded, 0 without it.
int Function Version() global native

; Bit 1: Magelight UI is loaded. Bit 2: the Prisma UI page is ready (only when Magelight UI is not).
int Function Host() global native

; Shows the page and gives it the input (the game pauses). False: no page, or another Prisma UI view has the input.
bool Function Open() global native

Function Close() global native

bool Function IsOpen() global native

; Runs JavaScript in the page.
Function Eval(string script) global native

; Every unique, named adult person of the load order as a JSON array of [formID, plugin, name]
; (the page's NPC picker; what OnPageNpcs scans in Papyrus, in well under a second).
string Function NpcList() global native

; The page's Generate request (JSON). False: it did not start (a DSE_Gen error says why).
bool Function Generate(string request) global native
