Scriptname SkyrimNet_DialogueScenarioEditorNative Hidden
{Natives of SKSE\Plugins\SkyrimNet_DialogueScenarioEditor.dll. Without the DLL every function returns 0 / false.

The Prisma UI host of the settings page: the page's calls window.dse_*(text) arrive as mod events
"DSE_Prisma_dse_*" (strArg = text). Scenario generation: progress and the result arrive as the mod
event "DSE_Gen" (strArg = JSON for the page's dseGen).}

; 1 or more when the DLL is loaded, 0 without it (2: Log exists, 3: HereCell exists).
int Function Version() global native

; Writes a line to the DLL's log, Documents\My Games\Skyrim Special Edition\SKSE\SkyrimNet_DialogueScenarioEditor.log
; (made new at every game start; no INI setting needed). level: 0 info, 1 warning, 2 error.
Function Log(string text, int level = 0) global native

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

; Named interior places (each reached by a load door) as a JSON array of [spec, name, editorID],
; for the page's place picker ("move and wait" at the end of a column).
string Function PlaceList() global native

; The player's cell as a JSON array [spec, name, interior] ("" if none), for a scenario's cell condition.
string Function HereCell() global native

; The inside door of a place (its spec from PlaceList): where "move and wait" sends people. None if unknown.
ObjectReference Function PlaceAnchor(string spec) global native

; The page's Generate request (JSON). False: it did not start (a DSE_Gen error says why).
bool Function Generate(string request) global native
