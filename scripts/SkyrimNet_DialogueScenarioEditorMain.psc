Scriptname SkyrimNet_DialogueScenarioEditorMain extends Quest
{Reads event setups from JSON files in Data/SKSE/Plugins/StorageUtilData/SkyrimNet_DialogueScenarioEditor/
and runs the first one whose participants are all near the player (automatic scenarios on a timer,
hotkey scenarios when the player presses the scenario hotkey).

A setup has up to ten columns, run left to right. Each column holds up to three participants,
an optional narration, up to ten lines (each with its speaker, in any order, the same speaker as
often as wanted; reworded by SkyrimNet in the speaker's own voice) and an optional OStim scene
that starts after the lines. A character may appear in several columns, but joins OStim only once
per event; columns without OStim are just talk.

Keys: enabled, trigger (0 automatic, 1 the scenario hotkey), onlytargets, repeat, intervaldays,
location (0 any, 1 indoors, 2 outdoors), cell / cellname (only in that cell; empty = anywhere);
per column cN_actors, cN_lines, cN_speakers (intList: participant index per line; without it,
line i is spoken by participant i), cN_autos (intList: 1 = that line is made up when spoken),
cN_auto (1 = every line of the column is), cN_autolen (0/1/2 = 3/6/10 lines), cN_narrator,
cN_end (what ends the column: 0 nothing, 1 OStim scene, 2 move and wait, 3 a SkyrimNet action:
cN_action, cN_actmod, cN_actwho, cN_actargs; older files: cN_ostim),
cN_tags (OStim), cN_movewho (intList of participants), cN_moveplace / cN_moveplacename (a place
from the DLL's list), cN_moveuntil (a scenario name), cN_movedays; requires (a scenario that must
have happened first).

The JSON files are only read, never written. Fired state lives in the save (StorageUtil).}

string Property EventFolder = "SkyrimNet_DialogueScenarioEditor" AutoReadOnly
string Property CommonFile = "SkyrimNet_DialogueScenarioEditor_Common" AutoReadOnly
; Scenarios the player deleted on the page (list "names", file names without .json). A deleted file
; is only emptied, so a reinstall or update of the mod brings a shipped example back: this list keeps
; it deleted. Written only by the page's Delete and Save (the UI script).
string Property DeletedFile = "SkyrimNet_DialogueScenarioEditor_Deleted" AutoReadOnly
int Property MaxColumns = 10 AutoReadOnly
int Property MaxPerColumn = 3 AutoReadOnly
int Property MaxLines = 10 AutoReadOnly
float Property CheckInterval = 3.0 AutoReadOnly
float Property InteriorRange = 10000.0 AutoReadOnly
float Property ExteriorRange = 3000.0 AutoReadOnly
float Property NpcSpeechTimeout = 45.0 AutoReadOnly
float Property PlayerSpeechTimeout = 20.0 AutoReadOnly
int Property QuietMs = 2500 AutoReadOnly
float Property WarpAfter = 8.0 AutoReadOnly
float Property SettleAfterMove = 3.0 AutoReadOnly
float Property NearDistance = 260.0 AutoReadOnly
string Property SoloActions = "femalemasturbation,malemasturbation,vaginaltoying,analtoying,rubbingclitoris" AutoReadOnly

bool running = false
float runStart = 0.0
bool dllLog = false        ; the DLL has Log: the log goes to SkyrimNet_DialogueScenarioEditor.log
string lastGlobalWhy = ""  ; why no scenario could start (player in combat etc.), logged on change
string why = ""            ; why IsReady / TryStart said no (logged per scenario on change)
float runReal = 0.0        ; real time the run started (seconds), for the timings in the log
float watchStart = 0.0     ; real time the current speech wait started
Keyword npcKeyword
int loadCount = 0 ; bumped on every load
int runLoad = 0   ; loadCount when the current run started

; Keeping the column's cast together while it talks (see Hold).
bool holding = false
Actor[] holdCast
Actor holdAnchor
float[] holdSides
bool[] holdSettled ; per participant: close enough and standing still
bool[] holdApproached ; per participant: this mod set their KeepOffsetFromActor
string Property TouchedList = "SkyrimNet_DialogueScenarioEditor:touched" AutoReadOnly ; changed by an action this run
bool anchorFaced = false ; an NPC anchor has turned toward the others
int holdTick = 0
string Property HeldList = "SkyrimNet_DialogueScenarioEditor:held" AutoReadOnly ; actors with SetDontMove on

; --------------------------------------------------------------------------------------------
; Setup and the periodic check (called from the player alias timer)
; --------------------------------------------------------------------------------------------

; Called on every game load (mod event registrations do not survive a load).
Function Setup()
	dllLog = SkyrimNet_DialogueScenarioEditorNative.Version() >= 2
	npcKeyword = Keyword.GetKeyword("ActorTypeNPC")
	RegisterSpeechEvents()
	loadCount += 1
	lastGlobalWhy = ""
	StorageUtil.ClearStringValuePrefix("DSE:why:")
	DetectFrameworks()
	LogSetupState()
	; A save made mid-talk keeps the "don't move" flag on whoever was held: give it back.
	holding = false
	FreeHeld()
	; Move-and-wait trips: the linked reference is set again.
	RestoreParked()
EndFunction

; A save made in the middle of an event brings the half-done run back with it. Its speech state
; is gone, so it stops instead of carrying on (it would otherwise jump to the next line at once).
bool Function Interrupted()
	Return runLoad != loadCount
EndFunction

; Returns the delay before the next check.
float Function Check()
	If running
		; A run lost with an old save must not lock the mod forever.
		If Utility.GetCurrentGameTime() - runStart < 0.1
			Return CheckInterval
		EndIf
		Log("an earlier run never finished; unlocking")
		running = false
	EndIf
	If npcKeyword == None
		Setup()
	EndIf
	CheckParked()

	Actor player = Game.GetPlayer()
	If Utility.IsInMenuMode()
		Return CheckInterval ; not logged: every open menu would show up
	EndIf
	If player.IsInCombat()
		GlobalWhy("the player is in combat")
		Return CheckInterval
	EndIf
	If InScene(player)
		GlobalWhy("the player is in a sex scene")
		Return CheckInterval
	EndIf
	Cell here = player.GetParentCell()
	If here == None
		GlobalWhy("the player has no cell")
		Return CheckInterval
	EndIf

	string[] files = JsonUtil.JsonInFolder(EventFolder)
	If files.Length == 0
		GlobalWhy("no scenario files in StorageUtilData/" + EventFolder)
		Return CheckInterval
	EndIf
	GlobalWhy("")

	bool interior = here.IsInterior()
	float range = ExteriorRange
	If interior
		range = InteriorRange
	EndIf
	Actor[] nearby = NearbyActors(player, range)

	int i = 0
	While i < files.Length
		string file = EventFolder + "/" + files[i]
		If IsDeleted(files[i])
			; deleted on the page: never logged again after the first time
			Because(file, "deleted on the page")
		ElseIf JsonUtil.GetIntValue(file, "trigger", 0) == 1
			Because(file, "starts only with the hotkey")
		ElseIf !IsReady(file, here)
			Because(file, why)
		ElseIf TryStart(file, nearby, here, interior)
			Return CheckInterval
		Else
			Because(file, why)
		EndIf
		i += 1
	EndWhile
	Return CheckInterval
EndFunction

; A scenario was deleted, or a new one saved (perhaps under the name of a deleted one): its run
; record in this save (last run, done, the cell it ran in) belongs to the old one and is dropped.
Function ForgetRuns(string name)
	string id = StateKey(EventFolder + "/" + name + ".json")
	bool had = StorageUtil.GetFloatValue(self, id + ":last", -1.0) >= 0.0
	StorageUtil.UnsetFloatValue(self, id + ":last")
	StorageUtil.UnsetFloatValue(self, id + ":done")
	StorageUtil.UnsetFormValue(self, id + ":cell")
	StorageUtil.UnsetStringValue(None, "DSE:why:" + EventFolder + "/" + name + ".json")
	Log("run record of " + name + " cleared (had one: " + had + ")")
EndFunction

; The scenario hotkey (MCM, handled by the UI script): starts the first scenario set to start with
; the hotkey ("trigger" 1) whose conditions are met here. Every reason it gives is logged, and the
; player is told when none could start.
Function StartByHotkey()
	Log("scenario hotkey pressed")
	If running
		Notify("a scenario is already running")
		Return
	EndIf
	If npcKeyword == None
		Setup()
	EndIf
	Actor player = Game.GetPlayer()
	If player.IsInCombat() || InScene(player)
		Notify("no scenario can start during combat or a sex scene")
		Return
	EndIf
	Cell here = player.GetParentCell()
	If here == None
		Return
	EndIf
	string[] files = JsonUtil.JsonInFolder(EventFolder)
	bool interior = here.IsInterior()
	float range = ExteriorRange
	If interior
		range = InteriorRange
	EndIf
	Actor[] nearby = NearbyActors(player, range)
	int found = 0
	int i = 0
	While i < files.Length
		string file = EventFolder + "/" + files[i]
		If !IsDeleted(files[i]) && JsonUtil.GetIntValue(file, "trigger", 0) == 1
			found += 1
			If !IsReady(file, here)
				Log("hotkey: " + ScenarioName(file) + " cannot start: " + why)
			ElseIf TryStart(file, nearby, here, interior)
				Return
			Else
				Log("hotkey: " + ScenarioName(file) + " cannot start: " + why)
			EndIf
		EndIf
		i += 1
	EndWhile
	If found == 0
		Notify("no scenario is set to start with the hotkey")
	Else
		Notify("no hotkey scenario can start here (the log says why)")
	EndIf
EndFunction

; Why a scenario does not start, logged only when it changes (the check runs every few seconds).
; Cleared on every load (Setup), so each session's log says it once.
Function Because(string file, string reason)
	string k = "DSE:why:" + file
	If reason == "" || reason == StorageUtil.GetStringValue(None, k, "")
		Return
	EndIf
	StorageUtil.SetStringValue(None, k, reason)
	Log("not starting " + ScenarioName(file) + ": " + reason)
EndFunction

Function GlobalWhy(string reason)
	If reason == lastGlobalWhy
		Return
	EndIf
	lastGlobalWhy = reason
	If reason != ""
		Log("no scenario can start: " + reason)
	Else
		Log("checking scenarios again")
	EndIf
EndFunction

; On every load: the mod's state, SkyrimNet's settings that matter here, and every scenario.
Function LogSetupState()
	Log("---- load " + loadCount + " ----")
	Log("DLL log: " + dllLog + ", DLL version " + SkyrimNet_DialogueScenarioEditorNative.Version() + ", SkyrimNet " + SkyrimNetApi.GetBuildVersion() + " (" + SkyrimNetApi.GetBuildType() + ")")
	Log("SkyrimNet: tts engine " + SkyrimNetApi.GetConfigString("game", "tts.engine", "?") + ", player voice " + SkyrimNetApi.GetConfigString("game", "player.voiceId", "?") + ", player voice input " + SkyrimNetApi.GetConfigBool("game", "player.voiceInput", false) + ", continuous mode " + SkyrimNetApi.IsContinuousModeEnabled())
	Log("running " + running + ", parked " + StorageUtil.FormListCount(self, ParkedList) + ", held " + StorageUtil.FormListCount(self, HeldList))
	string[] files = JsonUtil.JsonInFolder(EventFolder)
	Log(files.Length + " scenario file(s)")
	int i = 0
	While i < files.Length
		string file = EventFolder + "/" + files[i]
		string id = StateKey(file)
		Log("  " + ScenarioName(file) + ": enabled " + JsonUtil.GetIntValue(file, "enabled", 0) + ", deleted " + IsDeleted(files[i]) + ", trigger " + JsonUtil.GetIntValue(file, "trigger", 0) + " (0 auto, 1 hotkey), location " + JsonUtil.GetIntValue(file, "location", 0) + ", cell '" + JsonUtil.GetStringValue(file, "cellname", "") + "' " + JsonUtil.GetStringValue(file, "cell", "") + ", only participants " + JsonUtil.GetIntValue(file, "onlytargets", 0) + ", repeat " + JsonUtil.GetIntValue(file, "repeat", 0) + " every " + JsonUtil.GetFloatValue(file, "intervaldays", 1.0) + " days, requires '" + JsonUtil.GetStringValue(file, "requires", "") + "', columns " + ColumnSummary(file) + ", last run " + StorageUtil.GetFloatValue(self, id + ":last", -1.0) + ", done " + StorageUtil.GetFloatValue(self, id + ":done", -1.0))
		i += 1
	EndWhile
EndFunction

; "Lydia+player(2 lines, end 1) | Hod(auto 1, end 0)" for the log.
string Function ColumnSummary(string file)
	string s = ""
	int c = 0
	While c < MaxColumns
		string col = "c" + (c + 1) + "_"
		int n = JsonUtil.StringListCount(file, col + "actors")
		If n > 0
			string who = ""
			int k = 0
			While k < n
				If k > 0
					who += "+"
				EndIf
				who += JsonUtil.StringListGet(file, col + "actors", k)
				k += 1
			EndWhile
			string lines = JsonUtil.StringListCount(file, col + "lines") + " lines"
			If JsonUtil.GetIntValue(file, col + "auto", 0) != 0
				lines = "auto " + JsonUtil.GetIntValue(file, col + "autolen", 0)
			EndIf
			If s != ""
				s += " | "
			EndIf
			s += who + "(" + lines + ", end " + JsonUtil.GetIntValue(file, col + "end", JsonUtil.GetIntValue(file, col + "ostim", -1)) + ")"
		EndIf
		c += 1
	EndWhile
	If s == ""
		Return "(none)"
	EndIf
	Return s
EndFunction

; True when the player deleted this scenario on the page (a name from JsonInFolder, with or without .json).
bool Function IsDeleted(string name)
	int n = StringUtil.GetLength(name)
	If n > 5 && StringUtil.Substring(name, n - 5) == ".json"
		name = StringUtil.Substring(name, 0, n - 5)
	EndIf
	Return JsonUtil.StringListHas(DeletedFile, "names", name)
EndFunction

; Enabled, not used up, past its interval, and not blocked in the cell it last fired in.
bool Function IsReady(string file, Cell here)
	why = ""
	; Leaving the cell it last ran in ends the once-per-visit block, whatever else stops it now: this
	; is checked first, so a scenario set to indoors only still has its block cleared while the player
	; is outdoors (it used to be cleared only when every check before it passed, 2026-11-22).
	Form lastCell = StorageUtil.GetFormValue(self, StateKey(file) + ":cell")
	If lastCell != None && lastCell != here
		StorageUtil.UnsetFormValue(self, StateKey(file) + ":cell")
	EndIf
	If JsonUtil.GetIntValue(file, "enabled", 0) == 0
		why = "switched off"
		Return false
	EndIf
	int where = JsonUtil.GetIntValue(file, "location", 0)
	If (where == 1 && !here.IsInterior()) || (where == 2 && here.IsInterior())
		If where == 1
			why = "set to indoors only, and the player is outdoors"
		Else
			why = "set to outdoors only, and the player is indoors"
		EndIf
		Return false
	EndIf
	; A chosen cell ("cell": spec "0xLOCAL|plugin"): only there.
	string cellSpec = JsonUtil.GetStringValue(file, "cell", "")
	If cellSpec != ""
		int bar = StringUtil.Find(cellSpec, "|")
		Cell wanted = None
		If bar > 0
			wanted = Game.GetFormFromFile(ParseHex(StringUtil.Substring(cellSpec, 0, bar)), StringUtil.Substring(cellSpec, bar + 1)) as Cell
		EndIf
		If wanted == None
			why = "the chosen cell " + JsonUtil.GetStringValue(file, "cellname", cellSpec) + " (" + cellSpec + ") is not in the load order"
			Return false
		EndIf
		If wanted != here
			why = "set to the cell " + JsonUtil.GetStringValue(file, "cellname", cellSpec) + ", and the player is in " + here.GetName() + " (" + here.GetFormID() + ")"
			Return false
		EndIf
	EndIf
	string id = StateKey(file)

	; Another scenario that must have happened first ("requires": its name).
	string needed = JsonUtil.GetStringValue(file, "requires", "")
	If needed != "" && StorageUtil.GetFloatValue(self, StateKey(EventFolder + "/" + needed + ".json") + ":done", -1.0) < 0.0
		why = "needs " + needed + " to have finished first"
		Return false
	EndIf

	; The "once per visit to a cell" block keeps an automatic scenario from firing again and again
	; while the player stays; a hotkey scenario starts only when asked, so it does not have it.
	Form blockedCell = StorageUtil.GetFormValue(self, id + ":cell")
	If blockedCell != None && JsonUtil.GetIntValue(file, "trigger", 0) == 1
		blockedCell = None
	EndIf
	If blockedCell != None
		If blockedCell != here
			StorageUtil.UnsetFormValue(self, id + ":cell")
		Else
			why = "already ran in this cell (runs again here only after leaving it)"
			Return false
		EndIf
	EndIf

	float last = StorageUtil.GetFloatValue(self, id + ":last", -1.0)
	If last < 0.0
		Return true
	EndIf
	If JsonUtil.GetIntValue(file, "repeat", 0) == 0
		why = "already ran once (repeat is off)"
		Return false
	EndIf
	float interval = JsonUtil.GetFloatValue(file, "intervaldays", 1.0)
	If Utility.GetCurrentGameTime() - last < interval
		why = "repeat interval not over (" + interval + " days)"
		Return false
	EndIf
	Return true
EndFunction

; --------------------------------------------------------------------------------------------
; Matching the participants against who is here
; --------------------------------------------------------------------------------------------

bool Function TryStart(string file, Actor[] nearby, Cell here, bool interior)
	Actor player = Game.GetPlayer()
	Actor[] slots = new Actor[30]   ; MaxColumns * MaxPerColumn
	string[] specs = new string[30]

	int c = 0
	While c < MaxColumns
		string listKey = "c" + (c + 1) + "_actors"
		int n = JsonUtil.StringListCount(file, listKey)
		If n > MaxPerColumn
			why = "column " + (c + 1) + " has more than " + MaxPerColumn + " participants"
			Warn(file, why)
			Return false
		EndIf
		int colStart = c * MaxPerColumn
		int k = 0
		While k < n
			string spec = JsonUtil.StringListGet(file, listKey, k)
			; The same character in an earlier column is the same person here.
			Actor a = Reuse(spec, slots, specs, colStart)
			If a != None
				int s = colStart
				While s < colStart + k
					If slots[s] == a
						why = "column " + (c + 1) + " lists " + a.GetDisplayName() + " twice"
						Warn(file, why)
						Return false
					EndIf
					s += 1
				EndWhile
			Else
				a = Resolve(spec, nearby, here, interior, slots)
			EndIf
			If a == None
				why = "column " + (c + 1) + ": " + WhyMissing(spec, here, interior, slots) ; someone is not here (normal, no message)
				Return false
			EndIf
			If a.IsChild()
				why = "children cannot take part: " + a.GetDisplayName()
				Warn(file, why)
				Return false
			EndIf
			If a.IsInCombat()
				why = a.GetDisplayName() + " is in combat"
				Return false
			EndIf
			If slApi != None && SkyrimNet_DialogueScenarioEditorSL.InFactionOnly(slApi, a)
				Because(file, a.GetDisplayName() + " is in SexLab's animating faction with no SexLab scene (left over from a scene that did not end cleanly): not counted as in a scene")
			EndIf
			If InScene(a)
				why = a.GetDisplayName() + " is in a sex scene (" + SceneFramework(a) + ")"
				Return false
			EndIf
			slots[colStart + k] = a
			specs[colStart + k] = spec
			k += 1
		EndWhile
		c += 1
	EndWhile

	If JsonUtil.StringListCount(file, "c1_actors") == 0
		why = "column 1 has no participants"
		Warn(file, why)
		Return false
	EndIf

	; Who else is around: only matters with "only the people in it" (children nearby no longer
	; block a start, the user's choice 2026-11-22; children still cannot take part).
	If JsonUtil.GetIntValue(file, "onlytargets", 0) != 0
		int i = 0
		While i < nearby.Length
			Actor other = nearby[i]
			If Counts(other, here, interior) && slots.Find(other) < 0
				why = "set to only the participants, and " + other.GetDisplayName() + " is around (" + (other.GetDistance(player) as int) + " units away)"
				Return false
			EndIf
			i += 1
		EndWhile
	EndIf

	; Fire: remember it in the save before anything can fail.
	string id = StateKey(file)
	StorageUtil.SetFloatValue(self, id + ":last", Utility.GetCurrentGameTime())
	StorageUtil.SetFormValue(self, id + ":cell", here)
	running = true
	runStart = Utility.GetCurrentGameTime()
	runLoad = loadCount
	runReal = Utility.GetCurrentRealTime()
	StorageUtil.FormListClear(self, TouchedList)
	Log("==== start " + ScenarioName(file) + " in " + here.GetName() + " (" + LocationWord(interior) + ") ====")
	Log("file: " + MiscUtil.ReadFromFile("Data/SKSE/Plugins/StorageUtilData/" + file))
	Log("SkyrimNet now: speech queue " + SkyrimNetApi.GetSpeechQueueSize() + ", ms since audio ended " + SkyrimNetApi.GetTimeSinceLastAudioEnded() + ", continuous mode " + SkyrimNetApi.IsContinuousModeEnabled())
	int q = 0
	While q < slots.Length
		If slots[q] != None
			Log("  slot c" + (q / MaxPerColumn + 1) + "." + (q % MaxPerColumn + 1) + " '" + specs[q] + "' = " + Who(slots[q]))
		EndIf
		q += 1
	EndWhile
	; Anyone on a move-and-wait trip takes part without it for now.
	int s = 0
	While s < slots.Length
		If slots[s] != None && IsParked(slots[s])
			SuspendPark(slots[s])
		EndIf
		s += 1
	EndWhile
	RunSetup(file, slots)
	running = false
	StorageUtil.FormListClear(self, TouchedList)
	If Interrupted()
		Log("stopped " + ScenarioName(file) + " (a save made during the event was loaded)")
	Else
		Log("==== done " + ScenarioName(file) + " after " + Elapsed(runReal) + " ====")
		StorageUtil.SetFloatValue(self, id + ":done", Utility.GetCurrentGameTime())
		ReleaseWaitingFor(ScenarioName(file))
	EndIf
	; Whoever is still to wait somewhere (sent off by this scenario, or waiting for another) goes on.
	s = 0
	While s < slots.Length
		If slots[s] != None && IsParked(slots[s])
			ApplyPark(slots[s])
		EndIf
		s += 1
	EndWhile
	Return true
EndFunction

; The actor an earlier column already found for this entry (same text, or any player word).
Actor Function Reuse(string spec, Actor[] slots, string[] specs, int colStart)
	bool playerWord = IsPlayerWord(spec)
	Actor player = Game.GetPlayer()
	int j = 0
	While j < colStart
		If slots[j] != None && (specs[j] == spec || (playerWord && slots[j] == player))
			Return slots[j]
		EndIf
		j += 1
	EndWhile
	Return None
EndFunction

; For the log: why Resolve found nobody for this entry.
string Function WhyMissing(string spec, Cell here, bool interior, Actor[] taken)
	string near = "within " + (ExteriorRange as int) + " units"
	If interior
		near = "in this cell"
	EndIf
	If IsPlayerWord(spec)
		Return "'" + spec + "' is the player, who is already taken in this column"
	EndIf
	int bar = StringUtil.Find(spec, "|")
	If bar > 0
		Form f = Game.GetFormFromFile(ParseHex(StringUtil.Substring(spec, 0, bar)), StringUtil.Substring(spec, bar + 1))
		If f == None
			Return "'" + spec + "' is not in the load order (plugin missing?)"
		EndIf
		Actor a = f as Actor
		If a != None
			If a.IsDead()
				Return a.GetDisplayName() + " is dead"
			ElseIf a.IsDisabled()
				Return a.GetDisplayName() + " is disabled"
			ElseIf taken.Find(a) >= 0
				Return a.GetDisplayName() + " is already taken in this column"
			ElseIf a.GetParentCell() == None
				Return a.GetDisplayName() + " is not loaded (far away)"
			EndIf
			Return a.GetDisplayName() + " is not " + near + " (in " + a.GetParentCell().GetName() + ", " + (a.GetDistance(Game.GetPlayer()) as int) + " units away)"
		EndIf
		If f as ActorBase
			Return "nobody who is " + f.GetName() + " (" + spec + ") is " + near
		EndIf
		Return "'" + spec + "' is not a person"
	EndIf
	Return "nobody named '" + spec + "' is " + near
EndFunction

; "Lydia (00A2C94E, 123 units from the player, in Breezehome)" for the log.
string Function Who(Actor a)
	If a == None
		Return "nobody"
	EndIf
	If a == Game.GetPlayer()
		Return a.GetDisplayName() + " (player)"
	EndIf
	string cellName = "?"
	If a.GetParentCell() != None
		cellName = a.GetParentCell().GetName()
	EndIf
	Return a.GetDisplayName() + " (" + a.GetFormID() + ", " + (a.GetDistance(Game.GetPlayer()) as int) + " units from the player, in " + cellName + ")"
EndFunction

string Function LocationWord(bool interior)
	If interior
		Return "interior"
	EndIf
	Return "exterior"
EndFunction

; "12.5 s" since a real time.
string Function Elapsed(float since)
	Return (((Utility.GetCurrentRealTime() - since) * 10.0) as int) / 10.0 + " s"
EndFunction

; A player word (see IsPlayerWord), "0x1A69A|Skyrim.esm" (a reference), or a display name.
Actor Function Resolve(string spec, Actor[] nearby, Cell here, bool interior, Actor[] taken)
	Actor player = Game.GetPlayer()
	If IsPlayerWord(spec)
		If taken.Find(player) >= 0
			Return None
		EndIf
		Return player
	EndIf

	int bar = StringUtil.Find(spec, "|")
	If bar > 0
		int formId = ParseHex(StringUtil.Substring(spec, 0, bar))
		string plugin = StringUtil.Substring(spec, bar + 1)
		Form f = Game.GetFormFromFile(formId, plugin)
		Actor byId = f as Actor
		If byId != None
			If Counts(byId, here, interior) && nearby.Find(byId) >= 0 && taken.Find(byId) < 0
				Return byId
			EndIf
			Return None
		EndIf
		; A base NPC record (what the settings page stores): whoever nearby is that NPC.
		ActorBase base = f as ActorBase
		If base == None
			Return None
		EndIf
		int j = 0
		While j < nearby.Length
			Actor b = nearby[j]
			If Counts(b, here, interior) && taken.Find(b) < 0 && (b.GetActorBase() == base || b.GetLeveledActorBase() == base)
				Return b
			EndIf
			j += 1
		EndWhile
		Return None
	EndIf

	int i = 0
	While i < nearby.Length
		Actor a = nearby[i]
		If Counts(a, here, interior) && taken.Find(a) < 0 && a.GetDisplayName() == spec
			Return a
		EndIf
		i += 1
	EndWhile
	Return None
EndFunction

; A living, enabled person (not a creature) in the player's cell (interiors) or range (exteriors).
bool Function Counts(Actor a, Cell here, bool interior)
	If a == None || a.IsDead() || a.IsDisabled()
		Return false
	EndIf
	If a != Game.GetPlayer() && !a.HasKeyword(npcKeyword)
		Return false
	EndIf
	If interior && a.GetParentCell() != here
		Return false
	EndIf
	Return true
EndFunction

; --------------------------------------------------------------------------------------------
; Running a setup
; --------------------------------------------------------------------------------------------

Function RunSetup(string file, Actor[] slots)
	int c = 0
	While c < MaxColumns && !Interrupted()
		Actor[] cast = ColumnCast(slots, c)
		If cast.Length > 0
			RunColumn(file, c, cast)
		EndIf
		c += 1
	EndWhile
EndFunction

Function RunColumn(string file, int c, Actor[] cast)
	Actor player = Game.GetPlayer()
	string col = "c" + (c + 1) + "_"

	string castNames = ""
	int q = 0
	While q < cast.Length
		If q > 0
			castNames += ", "
		EndIf
		castNames += cast[q].GetDisplayName()
		q += 1
	EndWhile
	Log("-- column " + (c + 1) + " (" + castNames + ") at " + Elapsed(runReal))
	string narration = JsonUtil.GetStringValue(file, col + "narrator", "")
	If narration != ""
		int sent = SkyrimNetApi.RegisterPersistentEvent(FillNames(narration), cast[0])
		Log("narration (not spoken, background for the NPCs) -> " + sent + ": " + FillNames(narration))
	EndIf

	float gatherStart = Utility.GetCurrentRealTime()
	Gather(cast)
	Log("gathered in " + Elapsed(gatherStart))

	; From the second column on, earlier columns' scene talk must not hold this column's lines
	; back: drop what is queued (the line being spoken still finishes). Chosen by the user.
	; Auto column: every line is made up when it is spoken (short / medium / long = 3 / 6 / 10),
	; the participants taking turns.
	bool autoColumn = JsonUtil.GetIntValue(file, col + "auto", 0) != 0
	int lines = JsonUtil.StringListCount(file, col + "lines")
	If autoColumn
		lines = AutoLineCount(JsonUtil.GetIntValue(file, col + "autolen", 0))
	EndIf
	If lines > MaxLines
		lines = MaxLines
	EndIf

	If c > 0 && lines > 0
		SkyrimNetApi.PurgeDialogue(true)
		Log("purged queued dialogue from earlier columns")
	EndIf
	Log(lines + " line(s), auto column " + autoColumn)

	; Lines in their own order, each with its speaker (a participant index). Old files have no
	; speaker list: line i is then spoken by participant i. An auto line (cN_autos) has no text of
	; its own: the speaker says what fits the scene (AutoContext).
	bool haveSpeakers = JsonUtil.IntListCount(file, col + "speakers") > 0
	string context = ""
	If autoColumn || JsonUtil.IntListHas(file, col + "autos", 1)
		context = AutoContext(file, c)
	EndIf
	Actor lastSpeaker = None
	int k = 0
	While k < lines && !Interrupted()
		string line = ""
		int who = k % cast.Length
		bool madeUp = autoColumn
		If !autoColumn
			line = JsonUtil.StringListGet(file, col + "lines", k)
			If haveSpeakers
				who = JsonUtil.IntListGet(file, col + "speakers", k)
			Else
				who = k
			EndIf
			madeUp = JsonUtil.IntListGet(file, col + "autos", k) == 1
		EndIf
		If (line != "" || madeUp) && who >= 0 && who < cast.Length
			Actor speaker = cast[who]
			Actor listener = PickListener(cast, speaker, lastSpeaker)
			string kind = "fixed"
			If madeUp
				kind = "auto"
			EndIf
			Log("line " + (k + 1) + "/" + lines + " at " + Elapsed(runReal) + ": " + speaker.GetDisplayName() + " -> " + Who(listener) + " (" + kind + "): " + FillNames(line))
			float lineStart = Utility.GetCurrentRealTime()
			If madeUp
				SpeakFreely(speaker, listener, context)
			Else
				Speak(speaker, listener, FillNames(line))
			EndIf
			Log("line " + (k + 1) + " finished after " + Elapsed(lineStart))
			lastSpeaker = speaker
		Else
			Log("line " + (k + 1) + " skipped (empty, or speaker " + who + " not in a cast of " + cast.Length + ")")
		EndIf
		k += 1
	EndWhile

	; Let them go before OStim places them (or back to their day once only talking).
	Release(cast)

	; What ends the column (cN_end): 0 nothing, 1 an OStim scene, 2 move and wait. Older files
	; have only cN_ostim (1 = scene, 0 = nothing).
	int ending = JsonUtil.GetIntValue(file, col + "end", -1)
	If ending < 0
		ending = JsonUtil.GetIntValue(file, col + "ostim", 1)
	EndIf
	If Interrupted()
		Return
	EndIf
	Log("column " + (c + 1) + " ends with " + ending + " (0 nothing, 1 OStim, 2 move and wait, 3 action) at " + Elapsed(runReal))
	If ending == 1
		StartScene(cast, JsonUtil.GetStringValue(file, col + "tags", ""))
	ElseIf ending == 2
		MoveAway(file, col, cast)
	ElseIf ending == 3
		RunAction(file, col, cast)
	EndIf
EndFunction

; --------------------------------------------------------------------------------------------
; A SkyrimNet action at the end of a column (cN_end 3): cN_action (its name), cN_actmod (the mod it
; comes from, for messages), cN_actwho (who does it: a participant of the column), cN_actargs (its
; parameters as a JSON object; {player} and the like are filled in). The mod that defines it may
; have been removed since the scenario was saved: then it is skipped and the log says so.
; --------------------------------------------------------------------------------------------

Function RunAction(string file, string col, Actor[] cast)
	string name = JsonUtil.GetStringValue(file, col + "action", "")
	string fromMod = JsonUtil.GetStringValue(file, col + "actmod", "")
	If name == ""
		Log("action: none chosen")
		Return
	EndIf
	If !SkyrimNetApi.IsActionRegistered(name)
		LogAt("action " + name + " (" + fromMod + ") is not registered in SkyrimNet (its mod is not installed or not running): skipped", 1)
		Return
	EndIf
	int who = JsonUtil.GetIntValue(file, col + "actwho", 0)
	If who < 0 || who >= cast.Length
		who = 0
	EndIf
	string args = FillNames(JsonUtil.GetStringValue(file, col + "actargs", "{}"))
	If args == ""
		args = "{}"
	EndIf
	int result = SkyrimNetApi.ExecuteAction(name, cast[who], args)
	Log("action " + name + " (" + fromMod + ") by " + Who(cast[who]) + " with " + args + " -> " + result + " (0 = done)")
	; Whoever the action is about (the one doing it, and anyone of the column named in it) is left
	; alone by the later columns of this run: what the action started (a fight, a walk, a pose, a
	; package of its own) must not be undone by gathering and holding them.
	Touch(cast[who], "did the action " + name)
	int t = 0
	While t < cast.Length
		If t != who && cast[t] != Game.GetPlayer() && StringUtil.Find(args, cast[t].GetDisplayName()) >= 0
			Touch(cast[t], "named in the action " + name)
		EndIf
		t += 1
	EndWhile
	; Give what it starts a moment to begin before the next column.
	Utility.Wait(2.0)
	int k = 0
	While k < cast.Length
		Log("  after the action: " + cast[k].GetDisplayName() + " in combat " + cast[k].IsInCombat())
		k += 1
	EndWhile
EndFunction

; --------------------------------------------------------------------------------------------
; Move and wait: chosen people of the column walk to a place and wait there, until a named
; scenario has happened or some days have passed (whichever comes first).
; They walk with a vanilla package (travel to the linked reference, then hold position within
; 512), the linked reference being the inside door of the place (from the DLL). Whoever has not
; arrived an in-game hour later is moved there while out of the player's sight.
; --------------------------------------------------------------------------------------------

string Property ParkedList = "SkyrimNet_DialogueScenarioEditor:parked" AutoReadOnly

; defaultHoldPositionLinkedRef512WithTravel (Skyrim.esm)
Package Function TravelHoldPackage()
	Return Game.GetFormFromFile(0x101C01, "Skyrim.esm") as Package
EndFunction

Function MoveAway(string file, string col, Actor[] cast)
	If SkyrimNet_DialogueScenarioEditorNative.Version() == 0
		Warn(file, "move and wait needs SkyrimNet_DialogueScenarioEditor.dll")
		Return
	EndIf
	ObjectReference anchor = SkyrimNet_DialogueScenarioEditorNative.PlaceAnchor(JsonUtil.GetStringValue(file, col + "moveplace", ""))
	If anchor == None
		Warn(file, "the place to move to was not found: " + JsonUtil.GetStringValue(file, col + "moveplacename", ""))
		Return
	EndIf
	string untilName = JsonUtil.GetStringValue(file, col + "moveuntil", "")
	float days = JsonUtil.GetFloatValue(file, col + "movedays", 3.0)
	Actor player = Game.GetPlayer()
	int n = JsonUtil.IntListCount(file, col + "movewho")
	int i = 0
	While i < n
		int who = JsonUtil.IntListGet(file, col + "movewho", i)
		If who >= 0 && who < cast.Length && cast[who] != player && cast[who] != None
			Park(cast[who], anchor, untilName, days)
		EndIf
		i += 1
	EndWhile
EndFunction

Function Park(Actor a, ObjectReference anchor, string untilName, float days)
	StorageUtil.SetFormValue(a, "DSE:parkAnchor", anchor)
	StorageUtil.SetStringValue(a, "DSE:parkUntil", untilName)
	float deadline = -1.0
	If days > 0.0
		deadline = Utility.GetCurrentGameTime() + days
	EndIf
	StorageUtil.SetFloatValue(a, "DSE:parkDeadline", deadline)
	StorageUtil.SetFloatValue(a, "DSE:parkSince", Utility.GetCurrentGameTime())
	StorageUtil.FormListAdd(self, ParkedList, a, false)
	ApplyPark(a)
	If running
		Touch(a, "sent to wait at " + anchor.GetParentCell().GetName())
	EndIf
	Log(a.GetDisplayName() + " goes to " + anchor.GetParentCell().GetName() + " and waits (until " + untilName + ", " + days + " days)")
EndFunction

; (Again) sends a parked person on their way: after a load, or after a scenario they were in.
Function ApplyPark(Actor a)
	ObjectReference anchor = StorageUtil.GetFormValue(a, "DSE:parkAnchor") as ObjectReference
	Package travel = TravelHoldPackage()
	If anchor == None || travel == None
		Return
	EndIf
	PO3_SKSEFunctions.SetLinkedRef(a, anchor)
	ActorUtil.AddPackageOverride(a, travel, 100, 1)
	a.EvaluatePackage()
EndFunction

; Takes the trip off for now (a scenario with them is starting), keeping the record.
Function SuspendPark(Actor a)
	Package travel = TravelHoldPackage()
	If travel != None
		ActorUtil.RemovePackageOverride(a, travel)
	EndIf
	PO3_SKSEFunctions.SetLinkedRef(a, None)
	a.EvaluatePackage()
EndFunction

; Back to their own life.
Function Unpark(Actor a)
	SuspendPark(a)
	StorageUtil.FormListRemove(self, ParkedList, a, true)
	StorageUtil.UnsetFormValue(a, "DSE:parkAnchor")
	StorageUtil.UnsetStringValue(a, "DSE:parkUntil")
	StorageUtil.UnsetFloatValue(a, "DSE:parkDeadline")
	StorageUtil.UnsetFloatValue(a, "DSE:parkSince")
	Log(a.GetDisplayName() + " stops waiting")
EndFunction

bool Function IsParked(Actor a)
	Return StorageUtil.FormListHas(self, ParkedList, a)
EndFunction

; Every check: ends waits that ran out, and moves whoever has been on the way too long (out of
; the player's sight).
Function CheckParked()
	int i = StorageUtil.FormListCount(self, ParkedList) - 1
	If i < 0
		Return
	EndIf
	Actor player = Game.GetPlayer()
	float now = Utility.GetCurrentGameTime()
	While i >= 0
		Actor a = StorageUtil.FormListGet(self, ParkedList, i) as Actor
		If a == None || a.IsDead()
			StorageUtil.FormListRemoveAt(self, ParkedList, i)
		Else
			float deadline = StorageUtil.GetFloatValue(a, "DSE:parkDeadline", -1.0)
			ObjectReference anchor = StorageUtil.GetFormValue(a, "DSE:parkAnchor") as ObjectReference
			If (deadline > 0.0 && now >= deadline) || anchor == None
				Unpark(a)
			ElseIf a.GetParentCell() != anchor.GetParentCell() && now - StorageUtil.GetFloatValue(a, "DSE:parkSince", now) > 1.0 / 24.0
				If !InScene(a) && !a.IsInCombat() && (!a.Is3DLoaded() || !player.HasLOS(a))
					Log("moving " + a.GetDisplayName() + " to " + anchor.GetParentCell().GetName() + " (still on the way)")
					a.MoveTo(anchor)
					StorageUtil.SetFloatValue(a, "DSE:parkSince", now)
				EndIf
			EndIf
		EndIf
		i -= 1
	EndWhile
EndFunction

; A scenario has finished: whoever was waiting for it goes back to their life.
Function ReleaseWaitingFor(string scenarioName)
	int i = StorageUtil.FormListCount(self, ParkedList) - 1
	While i >= 0
		Actor a = StorageUtil.FormListGet(self, ParkedList, i) as Actor
		If a != None && StorageUtil.GetStringValue(a, "DSE:parkUntil", "") == scenarioName
			Unpark(a)
		EndIf
		i -= 1
	EndWhile
EndFunction

; Re-applies every trip after a load (the linked reference is set again).
Function RestoreParked()
	int i = StorageUtil.FormListCount(self, ParkedList) - 1
	While i >= 0
		Actor a = StorageUtil.FormListGet(self, ParkedList, i) as Actor
		If a != None
			ApplyPark(a)
		EndIf
		i -= 1
	EndWhile
EndFunction

; The file's scenario name: "SkyrimNet_DialogueScenarioEditor/event1.json" -> "event1".
string Function ScenarioName(string file)
	string s = file
	int slash = StringUtil.Find(s, "/")
	While slash >= 0
		s = StringUtil.Substring(s, slash + 1)
		slash = StringUtil.Find(s, "/")
	EndWhile
	int dot = StringUtil.Find(s, ".json")
	If dot > 0
		s = StringUtil.Substring(s, 0, dot)
	EndIf
	Return s
EndFunction

; Brings everyone to the player (if taking part) or to the first participant, all at once:
; each one keeps a spot in front of the anchor, so they walk there and stay while talking.
; Far away (another room) they are moved there. Waits up to GatherTimeout for them to arrive,
; then goes on anyway so a stuck NPC cannot hold the event.
Function Gather(Actor[] cast)
	Actor player = Game.GetPlayer()
	; The player when taking part, else the first participant the mod may hold (see LeftAlone).
	Actor anchor = cast[0]
	If cast.Find(player) >= 0
		anchor = player
	Else
		int f = 0
		While f < cast.Length && LeftAlone(cast[f]) != ""
			f += 1
		EndWhile
		If f < cast.Length
			anchor = cast[f]
		EndIf
	EndIf
	float[] sides = new float[3]
	; The cast is held together from here until Release (see Hold). An NPC anchor has no spot of
	; its own to keep, and its daily routine would walk it (and everyone keeping their place
	; around it) away: it stands still until the talk ends.
	holdCast = cast
	holdAnchor = anchor
	holdSides = sides
	holdSettled = new bool[3]
	holdApproached = new bool[3]
	anchorFaced = false
	holdTick = 0
	; Someone the mod must leave alone (fighting, in a scene, changed by an action...) gets no
	; "wait here", anchor or not.
	string anchorWhy = LeftAlone(anchor)
	If anchor != player && anchorWhy == ""
		Pin(anchor, None) ; turned toward the first one to arrive (Hold)
	ElseIf anchorWhy != ""
		Log("not holding " + anchor.GetDisplayName() + ": " + anchorWhy)
	EndIf
	holding = true

	bool moved = false
	int k = 0
	int spot = 0
	Log("gathering around " + Who(anchor))
	While k < cast.Length
		Actor a = cast[k]
		string alone = LeftAlone(a)
		If a != anchor
			Log("  " + Who(a) + ", " + (a.GetDistance(anchor) as int) + " units from " + anchor.GetDisplayName() + LeftAloneNote(alone))
		EndIf
		; Someone in a scene, fighting or changed by an action stays where they are (they talk from there).
		If a != anchor && a != player && alone == ""
			sides[k] = -60.0 + 120.0 * spot ; left, right, then further right
			spot += 1
			If a.GetDistance(anchor) > 1500.0
				Log("moving " + a.GetDisplayName() + " next to " + anchor.GetDisplayName() + " (too far to walk)")
				a.MoveTo(anchor, sides[k], 110.0, 0.0, false)
				moved = true
			EndIf
			Approach(a, k)
		EndIf
		k += 1
	EndWhile

	; Walking time is capped: whoever is not there by WarpAfter (e.g. still getting up from a
	; chair, or stuck) is moved to their spot. Whoever arrives stops (Hold).
	float waited = 0.0
	While waited < WarpAfter && !AllNear(cast, anchor)
		Utility.Wait(0.5)
		waited += 0.5
		Hold()
	EndWhile
	If waited >= WarpAfter
		k = 0
		While k < cast.Length
			Actor late = cast[k]
			If late != anchor && late != player && LeftAlone(late) == "" && late.GetDistance(anchor) > NearDistance
				Log("moving " + late.GetDisplayName() + " (did not arrive in " + WarpAfter + " s)")
				late.MoveTo(anchor, sides[k], 110.0, 0.0, false)
				moved = true
			EndIf
			k += 1
		EndWhile
	EndIf
	; SkyrimNet keeps its own copy of where everyone is and skips voicing anyone it still thinks
	; is far away. After a move, give that copy time to catch up before anyone speaks.
	If moved
		Utility.Wait(SettleAfterMove)
	EndIf
	; whoever is close by now stops here instead of shuffling for the exact spot
	holdTick = 2
	Hold()
EndFunction

; While the column talks (called from the speech waits), about every 1.5 s.
; Close enough (NearDistance) = stop: the exact spot is dropped and they stand still, so nobody
; keeps running at a chair or a table between them and their spot. Someone who ends up too far
; (the player walked off, or something pulled them away) is sent back, and stops again once close.
; Far off (walked out of the room) they are moved back.
Function Hold()
	If !holding
		Return
	EndIf
	holdTick += 1
	If holdTick < 3
		Return
	EndIf
	holdTick = 0
	Actor player = Game.GetPlayer()
	; Something that starts while they talk (a fight, a scene, another mod's package hold) is let be:
	; whoever it takes loses the "wait here" and the spot to keep.
	If holdAnchor != None && holdAnchor != player && StorageUtil.FormListHas(self, HeldList, holdAnchor)
		string anchorWhy = LeftAlone(holdAnchor)
		If anchorWhy != ""
			Log(holdAnchor.GetDisplayName() + " no longer held: " + anchorWhy)
			Unpin(holdAnchor)
			Rekick(holdAnchor)
		EndIf
	EndIf
	FreeFightersFromTalk()
	int k = 0
	While k < holdCast.Length
		Actor a = holdCast[k]
		string alone = ""
		If a != None && a != holdAnchor && a != player
			alone = LeftAlone(a)
		EndIf
		If alone != ""
			If StorageUtil.FormListHas(self, HeldList, a)
				Log(a.GetDisplayName() + " no longer held: " + alone)
				Unpin(a)
				Rekick(a)
			EndIf
			If holdApproached[k]
				a.ClearKeepOffsetFromActor() ; only the offset this mod set
				holdApproached[k] = false
			EndIf
		ElseIf a != None && a != holdAnchor && a != player
			float dist = a.GetDistance(holdAnchor)
			If dist > 900.0
				Log("moving " + a.GetDisplayName() + " back (wandered off while talking)")
				Unpin(a)
				a.MoveTo(holdAnchor, holdSides[k], 110.0, 0.0, false)
				Approach(a, k)
			ElseIf holdSettled[k]
				If dist > NearDistance + 200.0
					Unpin(a)
					Approach(a, k)
				EndIf
			ElseIf dist <= NearDistance
				a.ClearKeepOffsetFromActor()
				holdApproached[k] = false
				Pin(a, holdAnchor)
				holdSettled[k] = true
				If !anchorFaced && holdAnchor != player
					holdAnchor.SetAngle(0.0, 0.0, holdAnchor.GetAngleZ() + holdAnchor.GetHeadingAngle(a))
					anchorFaced = true
				EndIf
			EndIf
		EndIf
		k += 1
	EndWhile
EndFunction

; Why the mod must not move or hold this actor now ("" when it may): in a sex scene (either
; framework), fighting (a brawl too), changed by an action or a move-and-wait earlier in this run
; (Touch), or held by another mod through SkyrimNet's package holds (its own scene). Speaking is
; not affected: they still say their lines from where they are.
string Function LeftAlone(Actor a)
	If a == None || a == Game.GetPlayer()
		Return ""
	EndIf
	If InScene(a)
		Return "in a sex scene (" + SceneFramework(a) + ")"
	ElseIf a.IsInCombat()
		Return "fighting"
	ElseIf StorageUtil.FormListHas(self, TouchedList, a)
		Return StorageUtil.GetStringValue(a, "DSE:touched", "changed by an action")
	ElseIf SkyrimNetApi.IsHoldingPackages(a, "")
		Return "another mod holds their SkyrimNet packages"
	EndIf
	Return ""
EndFunction

string Function LeftAloneNote(string reason)
	If reason == ""
		Return ""
	EndIf
	Return ", left alone: " + reason
EndFunction

; Marks an actor as changed by this run (see LeftAlone) until the run ends.
Function Touch(Actor a, string reason)
	If a == None || a == Game.GetPlayer()
		Return
	EndIf
	StorageUtil.FormListAdd(self, TouchedList, a, false)
	StorageUtil.SetStringValue(a, "DSE:touched", reason)
	Log(a.GetDisplayName() + " is left alone for the rest of this run: " + reason)
EndFunction

; A fighter whose fight began while a "stand still" package was on them (this mod's wait, or
; SkyrimNet's talk package) may stand and take the blows even once it is gone (2026-11-22: Orgnar,
; StartCombat at 19:09:29.8, holds off at 19:09:30.4). The fight is started again against their
; current target, as SeverActions itself does for brawls that do not take ("Rekick").
Function Rekick(Actor a)
	If a == None || a == Game.GetPlayer() || !a.IsInCombat()
		Return
	EndIf
	Actor target = a.GetCombatTarget()
	a.EvaluatePackage()
	; Only a fight between people of the column: a target from outside it (the player, picked by the
	; AI's own action, 2026-11-22) is not pushed on.
	If target != None && (holdCast == None || holdCast.Find(target) < 0)
		Log(a.GetDisplayName() + " fights " + target.GetDisplayName() + ", who is not in this column: not started again")
		Return
	EndIf
	If target != None
		a.StartCombat(target)
		Log(a.GetDisplayName() + ": fight started again against " + target.GetDisplayName() + " now that nothing holds them")
	Else
		Log(a.GetDisplayName() + ": fighting with no combat target to start again against")
	EndIf
EndFunction

; While an NPC speaks, SkyrimNet holds them with its own talk package (TalkToNPC, or TalkToPlayer)
; until the reply is over, so a participant who fights while still talking stands and takes the
; blows (a brawl the AI started from the talk, 2026-11-22). Their lines stay: only that package is
; taken off anyone of the column who is fighting, through SkyrimNet's own UnregisterPackage.
Function FreeFightersFromTalk()
	If holdCast == None
		Return
	EndIf
	Actor player = Game.GetPlayer()
	int k = 0
	While k < holdCast.Length
		Actor a = holdCast[k]
		If a != None && a != player && a.IsInCombat()
			bool freed = false
			If SkyrimNetApi.HasPackage(a, "TalkToNPC") == 1
				SkyrimNetApi.UnregisterPackage(a, "TalkToNPC")
				Log(a.GetDisplayName() + " is fighting: SkyrimNet's TalkToNPC package taken off so they fight while talking")
				freed = true
			EndIf
			If SkyrimNetApi.HasPackage(a, "TalkToPlayer") == 1
				SkyrimNetApi.UnregisterPackage(a, "TalkToPlayer")
				Log(a.GetDisplayName() + " is fighting: SkyrimNet's TalkToPlayer package taken off so they fight while talking")
				freed = true
			EndIf
			If freed
				Rekick(a)
			EndIf
		EndIf
		k += 1
	EndWhile
EndFunction

; Walk to the spot beside the anchor (a loose spot: within 100 of it counts).
Function Approach(Actor a, int k)
	holdSettled[k] = false
	holdApproached[k] = true
	a.KeepOffsetFromActor(holdAnchor, holdSides[k], 110.0, 0.0, 0.0, 0.0, 180.0, 200.0, 100.0)
EndFunction

; Stand and wait, turned toward faceTo, until the talk ends (freed in Release, and on every load).
; Done the way the game's own scenes do it: a "wait here" AI package on top of the NPC's own (a
; follower would otherwise keep heading for the player). Blocking movement alone (SetDontMove)
; left them walking on the spot with their back to the others.
Function Pin(Actor a, Actor faceTo)
	Package wait = WaitPackage()
	If wait != None
		ActorUtil.AddPackageOverride(a, wait, 100, 1)
		a.EvaluatePackage()
	EndIf
	StorageUtil.FormListAdd(self, HeldList, a, false)
	If faceTo != None && faceTo != a
		a.SetAngle(0.0, 0.0, a.GetAngleZ() + a.GetHeadingAngle(faceTo))
	EndIf
EndFunction

Function Unpin(Actor a)
	Package wait = WaitPackage()
	If wait != None
		ActorUtil.RemovePackageOverride(a, wait)
		a.EvaluatePackage()
	EndIf
	StorageUtil.FormListRemove(self, HeldList, a, true)
EndFunction

; MQ201PartyDoNothing (Skyrim.esm): wait where you are, no movement, no conditions.
Package Function WaitPackage()
	Return Game.GetFormFromFile(0x0544C2, "Skyrim.esm") as Package
EndFunction

; Gives the NPCs we held back to their own AI.
Function FreeHeld()
	Package wait = WaitPackage()
	int n = StorageUtil.FormListCount(self, HeldList)
	int i = 0
	While i < n
		Actor a = StorageUtil.FormListGet(self, HeldList, i) as Actor
		If a != None
			If wait != None
				ActorUtil.RemovePackageOverride(a, wait)
			EndIf
			a.SetDontMove(false) ; held that way by an earlier build
			a.EvaluatePackage()
		EndIf
		i += 1
	EndWhile
	StorageUtil.FormListClear(self, HeldList)
EndFunction

bool Function AllNear(Actor[] cast, Actor anchor)
	int k = 0
	While k < cast.Length
		If cast[k] != anchor && cast[k] != Game.GetPlayer() && LeftAlone(cast[k]) == "" && cast[k].GetDistance(anchor) > NearDistance
			Return false
		EndIf
		k += 1
	EndWhile
	Return true
EndFunction

Function Release(Actor[] cast)
	holding = false
	FreeHeld()
	; Only the offsets this mod set are cleared: one that an action or another mod set stays.
	int k = 0
	While k < holdCast.Length && k < holdApproached.Length
		If holdApproached[k] && holdCast[k] != None
			holdCast[k].ClearKeepOffsetFromActor()
			holdApproached[k] = false
		EndIf
		k += 1
	EndWhile
EndFunction

; Who a line is addressed to: whoever spoke last (answering them), else the first other
; participant; nobody when the speaker is alone.
Actor Function PickListener(Actor[] cast, Actor speaker, Actor lastSpeaker)
	If lastSpeaker != None && lastSpeaker != speaker
		Return lastSpeaker
	EndIf
	int k = 0
	While k < cast.Length
		If cast[k] != speaker
			Return cast[k]
		EndIf
		k += 1
	EndWhile
	Return None
EndFunction

; The line is a direction, not a script: SkyrimNet rewords it in the speaker's own voice.
Function Speak(Actor speaker, Actor listener, string line)
	Actor player = Game.GetPlayer()

	; Player speech purges whatever NPCs are still saying, so make sure nobody is mid-reply.
	If speaker == player
		WaitForSilence(20.0)
		BeginWatch(player)
		int sent = SkyrimNetApi.TransformDialogue(line)
		Log("TransformDialogue (player line) -> " + sent + " (0 = accepted)")
		WaitForSpeech(PlayerSpeechTimeout)
		Return
	EndIf

	; Narration is taken as something that already happened, so the direction says the speaker is
	; ABOUT to say it (the user's point); otherwise the AI may treat the line as already spoken.
	; The wording lives in CommonFile ("speakto" / "speak") so it is not English-only.
	string direction
	If listener != None
		direction = JsonUtil.GetStringValue(CommonFile, "speakto", "{speaker} is about to say to {listener}, in their own words, something that means: \"{line}\"")
		direction = ReplaceAll(direction, "{listener}", listener.GetDisplayName())
	Else
		direction = JsonUtil.GetStringValue(CommonFile, "speak", "{speaker} is about to say, in their own words, something that means: \"{line}\"")
	EndIf
	direction = ReplaceAll(direction, "{speaker}", speaker.GetDisplayName())
	direction = ReplaceAll(direction, "{line}", line)
	BeginWatch(speaker)
	int sent = SkyrimNetApi.DirectNarration(direction, speaker, listener)
	Log("DirectNarration -> " + sent + " (0 = accepted): " + direction)
	If !WaitForSpeech(NpcSpeechTimeout) && !Interrupted()
		; Written but not voiced (SkyrimNet thought the speaker was out of earshot): say it again.
		Log(speaker.GetDisplayName() + "'s line was not voiced; asking again (" + Who(speaker) + ")")
		Utility.Wait(SettleAfterMove)
		BeginWatch(speaker)
		sent = SkyrimNetApi.DirectNarration(direction, speaker, listener)
		Log("DirectNarration (again) -> " + sent)
		WaitForSpeech(NpcSpeechTimeout)
	EndIf
EndFunction

; Lines in an auto column: short / medium / long.
int Function AutoLineCount(int size)
	If size >= 2
		Return 10
	ElseIf size == 1
		Return 6
	EndIf
	Return 3
EndFunction

; What an auto line goes by: this column's narration first, then the one before and the one
; after (where the story comes from and where it is heading). The wording is in CommonFile.
string Function AutoContext(string file, int c)
	string parts = ""
	string joiner = JsonUtil.GetStringValue(CommonFile, "autojoin", ". ")
	parts = AddPart(parts, joiner, "autoscene", NarrationOf(file, c))
	If c > 0
		parts = AddPart(parts, joiner, "autoprev", NarrationOf(file, c - 1))
	EndIf
	If c + 1 < MaxColumns
		parts = AddPart(parts, joiner, "autonext", NarrationOf(file, c + 1))
	EndIf
	If parts == ""
		Return ""
	EndIf
	Return ReplaceAll(JsonUtil.GetStringValue(CommonFile, "autowrap", " ({parts})"), "{parts}", parts)
EndFunction

string Function NarrationOf(string file, int c)
	Return FillNames(JsonUtil.GetStringValue(file, "c" + (c + 1) + "_narrator", ""))
EndFunction

string Function AddPart(string parts, string joiner, string which, string text)
	If text == ""
		Return parts
	EndIf
	string fallback = "{text}"
	If which == "autoscene"
		fallback = "Now: {text}"
	ElseIf which == "autoprev"
		fallback = "Before: {text}"
	ElseIf which == "autonext"
		fallback = "Next: {text}"
	EndIf
	string part = ReplaceAll(JsonUtil.GetStringValue(CommonFile, which, fallback), "{text}", text)
	If parts == ""
		Return part
	EndIf
	Return parts + joiner + part
EndFunction

; An auto line: no text of its own, the speaker says whatever fits the scene and the talk so far.
; NPCs: a direction like the fixed lines ("autospeakto" / "autospeak" in CommonFile). The player:
; SkyrimNet's own player dialogue, made from what is going on.
Function SpeakFreely(Actor speaker, Actor listener, string context)
	Actor player = Game.GetPlayer()
	If speaker == player
		WaitForSilence(20.0)
		BeginWatch(player)
		int sentP = SkyrimNetApi.TriggerPlayerDialogue()
		Log("TriggerPlayerDialogue (player auto line) -> " + sentP + " (0 = accepted)")
		WaitForSpeech(PlayerSpeechTimeout)
		Return
	EndIf
	string direction
	If listener != None
		direction = JsonUtil.GetStringValue(CommonFile, "autospeakto", "{speaker} is about to say something to {listener} in their own words, following how the scene is going.{context}")
		direction = ReplaceAll(direction, "{listener}", listener.GetDisplayName())
	Else
		direction = JsonUtil.GetStringValue(CommonFile, "autospeak", "{speaker} is about to say something in their own words, following how the scene is going.{context}")
	EndIf
	direction = ReplaceAll(direction, "{speaker}", speaker.GetDisplayName())
	direction = ReplaceAll(direction, "{context}", context)
	BeginWatch(speaker)
	int sent = SkyrimNetApi.DirectNarration(direction, speaker, listener)
	Log("DirectNarration (auto) -> " + sent + " (0 = accepted): " + direction)
	If !WaitForSpeech(NpcSpeechTimeout) && !Interrupted()
		Log(speaker.GetDisplayName() + "'s auto line was not voiced; asking again (" + Who(speaker) + ")")
		Utility.Wait(SettleAfterMove)
		BeginWatch(speaker)
		sent = SkyrimNetApi.DirectNarration(direction, speaker, listener)
		Log("DirectNarration (auto, again) -> " + sent)
		WaitForSpeech(NpcSpeechTimeout)
	EndIf
EndFunction

; --------------------------------------------------------------------------------------------
; Knowing when a reply is over. SkyrimNet speaks a reply in pieces: SkyrimNet_SpeechStarted per
; piece, SkyrimNet_SpeechComplete once the whole reply is written (usually before most of it is
; heard), then SkyrimNet_AudioEnded as each piece finishes playing. Sender = the speaker.
; --------------------------------------------------------------------------------------------

Actor watchSpeaker
int piecesStarted = 0
int piecesEnded = 0
bool replyWritten = false

Function RegisterSpeechEvents()
	RegisterForModEvent("SkyrimNet_SpeechStarted", "OnSkyrimNetSpeechStarted")
	RegisterForModEvent("SkyrimNet_SpeechComplete", "OnSkyrimNetSpeechComplete")
	RegisterForModEvent("SkyrimNet_AudioEnded", "OnSkyrimNetAudioEnded")
EndFunction

Function BeginWatch(Actor speaker)
	watchSpeaker = speaker
	piecesStarted = 0
	piecesEnded = 0
	replyWritten = false
	watchStart = Utility.GetCurrentRealTime()
EndFunction

; While a scenario runs, every speech event is logged, whoever sent it: a line that never counts
; as heard shows up here as events from someone else (or with no sender).
Function LogSpeechEvent(string what, string strArg, float numArg, Form sender)
	If !running
		Return
	EndIf
	string from = "none"
	If sender != None
		from = sender.GetName()
		If sender as Actor
			from = (sender as Actor).GetDisplayName()
		EndIf
	EndIf
	string mine = ""
	If watchSpeaker != None && sender == watchSpeaker
		mine = " [watched]"
	EndIf
	Log("  " + what + " from " + from + mine + " +" + Elapsed(watchStart) + " num " + numArg + ": " + strArg)
EndFunction

Event OnSkyrimNetSpeechStarted(string eventName, string strArg, float numArg, Form sender)
	If watchSpeaker != None && sender == watchSpeaker
		piecesStarted += 1
	EndIf
	LogSpeechEvent("SpeechStarted", strArg, numArg, sender)
EndEvent

Event OnSkyrimNetSpeechComplete(string eventName, string strArg, float numArg, Form sender)
	If watchSpeaker != None && sender == watchSpeaker
		replyWritten = true
	EndIf
	LogSpeechEvent("SpeechComplete", strArg, numArg, sender)
EndEvent

Event OnSkyrimNetAudioEnded(string eventName, string strArg, float numArg, Form sender)
	If watchSpeaker != None && sender == watchSpeaker
		piecesEnded += 1
	EndIf
	LogSpeechEvent("AudioEnded", strArg, numArg, sender)
EndEvent

; Done when the whole reply is written and every piece of it has played. If the events never
; come (e.g. no voice), falls back to: the speaker's audio ended and everyone stayed quiet.
; Returns false only when the reply was written but none of it is being voiced.
bool Function WaitForSpeech(float timeout)
	float waited = 0.0
	While waited < timeout
		Utility.Wait(0.5)
		waited += 0.5
		If Interrupted()
			watchSpeaker = None
			Return true
		EndIf
		Hold()
		If replyWritten && piecesStarted > 0 && piecesEnded >= piecesStarted
			Log("speech done after " + Elapsed(watchStart) + " (written, " + piecesEnded + "/" + piecesStarted + " pieces played)")
			watchSpeaker = None
			Utility.Wait(0.5)
			Return true
		EndIf
		; Every piece is announced before the reply counts as written, so written with no piece
		; (after a moment) means SkyrimNet dropped the voice.
		If replyWritten && piecesStarted == 0 && waited >= 3.0
			Log("written but not voiced after " + Elapsed(watchStart) + " (no SpeechStarted from the speaker)")
			watchSpeaker = None
			Return false
		EndIf
		; The player's line (TransformDialogue) sends no SpeechComplete: every started piece has
		; played and a short quiet follows. Also the no-events fallback.
		If !replyWritten && piecesEnded > 0 && piecesEnded >= piecesStarted
			If SkyrimNetApi.GetTimeSinceLastAudioEnded() >= 1500 && SkyrimNetApi.GetSpeechQueueSize() == 0
				Log("speech done after " + Elapsed(watchStart) + " (" + piecesEnded + "/" + piecesStarted + " pieces played, then quiet)")
				watchSpeaker = None
				Return true
			EndIf
		EndIf
	EndWhile
	Log("speech wait timed out after " + timeout + " s (pieces ended " + piecesEnded + " / started " + piecesStarted + ", written " + replyWritten + ", speech queue " + SkyrimNetApi.GetSpeechQueueSize() + ", ms since audio ended " + SkyrimNetApi.GetTimeSinceLastAudioEnded() + ")")
	watchSpeaker = None
	Return true
EndFunction

; Waits until nobody has spoken for QuietMs and nothing is queued (used before a scene starts).
Function WaitForSilence(float timeout)
	float waited = 0.0
	While waited < timeout
		int since = SkyrimNetApi.GetTimeSinceLastAudioEnded()
		If (since == 0 || since >= QuietMs) && SkyrimNetApi.GetSpeechQueueSize() == 0
			If waited > 0.0
				Log("waited " + waited + " s for silence")
			EndIf
			Return
		EndIf
		Utility.Wait(0.5)
		waited += 0.5
		Hold()
	EndWhile
	Log("silence wait timed out after " + timeout + " s (speech queue " + SkyrimNetApi.GetSpeechQueueSize() + ", ms since audio ended " + SkyrimNetApi.GetTimeSinceLastAudioEnded() + ")")
EndFunction

; --------------------------------------------------------------------------------------------
; Sex scenes: OStim Standalone or SexLab (P+ or 1.6x), whichever is installed; with both, the MCM
; choice (set by the UI script through SetFramework: 0 automatic = OStim, 1 OStim, 2 SexLab). The
; calls themselves are in SkyrimNet_DialogueScenarioEditorOS / SL / SLP / SL16, which only run when
; their framework is installed, so this script names no type of either.
; --------------------------------------------------------------------------------------------

bool hasOStim = false
Quest slApi = None
bool slLegacy = false   ; SexLab 1.6x (else P+)
int frameworkChoice = 0

Function DetectFrameworks()
	hasOStim = Game.IsPluginInstalled("OStim.esp")
	slApi = None
	slLegacy = false
	int version = 0
	If Game.IsPluginInstalled("SexLab.esm")
		slApi = SkyrimNet_DialogueScenarioEditorSL.API()
		version = SkyrimNet_DialogueScenarioEditorSL.Version()
		slLegacy = version > 0 && version < 20000
	EndIf
	Log("frameworks: OStim " + hasOStim + ", SexLab " + (slApi != None) + " (version " + version + ", 1.6x " + slLegacy + "), MCM choice " + frameworkChoice + " (0 auto, 1 OStim, 2 SexLab); scenes use " + FrameworkName())
EndFunction

Function SetFramework(int choice)
	If choice < 0 || choice > 2
		choice = 0 ; not set yet in the MCM: automatic
	EndIf
	frameworkChoice = choice
	Log("scene framework set to " + choice + " (0 auto, 1 OStim, 2 SexLab): scenes use " + FrameworkName())
EndFunction

bool Function SceneWithOStim()
	If !hasOStim
		Return false
	EndIf
	Return frameworkChoice != 2 || slApi == None
EndFunction

string Function FrameworkName()
	If SceneWithOStim()
		Return "OStim"
	ElseIf slApi == None
		Return "none"
	ElseIf slLegacy
		Return "SexLab 1.6x"
	EndIf
	Return "SexLab P+"
EndFunction

; In a scene of either framework (this mod's or another's).
bool Function InScene(Actor a)
	If a == None
		Return false
	EndIf
	If hasOStim && SkyrimNet_DialogueScenarioEditorOS.IsInScene(a)
		Return true
	EndIf
	Return slApi != None && SkyrimNet_DialogueScenarioEditorSL.IsActive(slApi, a)
EndFunction

; Which framework says the actor is in a scene, for the log.
string Function SceneFramework(Actor a)
	string s = ""
	If hasOStim && SkyrimNet_DialogueScenarioEditorOS.IsInScene(a)
		s = "OStim says so"
	EndIf
	If slApi != None && SkyrimNet_DialogueScenarioEditorSL.IsActive(slApi, a)
		If s != ""
			s += ", "
		EndIf
		s += "SexLab IsActorActive says so"
	EndIf
	Return s
EndFunction

bool Function AnyInScene(Actor[] cast)
	int k = 0
	While k < cast.Length
		If InScene(cast[k])
			Return true
		EndIf
		k += 1
	EndWhile
	Return false
EndFunction

; Everyone near center (the player too): the DLL's list of loaded actors, else OStim's search, else
; PapyrusUtil's scan of the cell.
Actor[] Function NearbyActors(ObjectReference center, float range)
	If SkyrimNet_DialogueScenarioEditorNative.Version() >= 5
		Return SkyrimNet_DialogueScenarioEditorNative.NearbyActors(center, range)
	ElseIf hasOStim
		Return SkyrimNet_DialogueScenarioEditorOS.Nearby(center, range)
	EndIf
	Return MiscUtil.ScanCellNPCs(center, range, None, false)
EndFunction

; The column's sex scene with its tags (OStim's; SexLab gets the matching SexLab tags).
Function StartScene(Actor[] cast, string tags)
	WaitForSilence(20.0)
	StopScenesOf(cast)
	If npcKeyword == None
		Setup()
	EndIf
	If SceneWithOStim()
		int thread = SkyrimNet_DialogueScenarioEditorOS.StartScene(cast, tags, SoloActions)
		If thread == -1
			Notify("no OStim scene fits " + cast.Length + " actors")
			Return
		ElseIf thread < 0
			Notify("OStim refused these actors")
			Return
		EndIf
		; The next column waits until this scene has started.
		float waited = 0.0
		While waited < 10.0 && !SkyrimNet_DialogueScenarioEditorOS.IsRunning(thread)
			Utility.Wait(0.5)
			waited += 0.5
		EndWhile
		Log("OStim: " + cast.Length + " actor(s), tags '" + tags + "', thread " + thread + " running " + SkyrimNet_DialogueScenarioEditorOS.IsRunning(thread) + " after " + waited + " s")
		Utility.Wait(1.0)
		Return
	EndIf
	If slApi == None
		Notify("no sex scene: neither OStim nor SexLab is installed")
		Return
	EndIf
	string[] slTags = SkyrimNet_DialogueScenarioEditorSL.SexLabTags(tags)
	Log(FrameworkName() + ": " + cast.Length + " actor(s), OStim tags '" + tags + "' -> SexLab tags '" + PapyrusUtil.StringJoin(slTags, ",") + "'")
	int slThread
	If slLegacy
		slThread = SkyrimNet_DialogueScenarioEditorSL16.StartScene(slApi, cast, slTags)
	Else
		slThread = SkyrimNet_DialogueScenarioEditorSLP.StartScene(slApi, cast, slTags)
	EndIf
	If slThread < 0
		Notify("SexLab refused these actors")
		Return
	EndIf
	float slWaited = 0.0
	While slWaited < 10.0 && !AnyInScene(cast)
		Utility.Wait(0.5)
		slWaited += 0.5
	EndWhile
	Log("SexLab thread " + slThread + " active " + AnyInScene(cast) + " after " + slWaited + " s")
	Utility.Wait(1.0)
EndFunction

; Anyone still in a scene (an earlier column's, or any other) has that scene stopped first, so the
; same character can take part again later in the event (the user's choice). Neither framework can
; take one actor out of a scene, so everyone else in that scene leaves it too.
Function StopScenesOf(Actor[] cast)
	bool stopped = false
	int k = 0
	While k < cast.Length
		bool one = false
		If hasOStim && SkyrimNet_DialogueScenarioEditorOS.StopSceneOf(cast[k])
			one = true
		ElseIf slApi != None && SkyrimNet_DialogueScenarioEditorSL.StopSceneOf(slApi, cast[k])
			one = true
		EndIf
		If one
			Log("stopped the scene " + cast[k].GetDisplayName() + " was in")
			stopped = true
		EndIf
		k += 1
	EndWhile
	If !stopped
		Return
	EndIf
	float waited = 0.0
	While waited < 10.0 && AnyInScene(cast)
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	Utility.Wait(1.5) ; let them stand up and redress before the next scene
EndFunction

; --------------------------------------------------------------------------------------------
; Helpers
; --------------------------------------------------------------------------------------------

Actor[] Function ColumnCast(Actor[] slots, int c)
	int n = 0
	While n < MaxPerColumn && slots[c * MaxPerColumn + n] != None
		n += 1
	EndWhile
	Actor[] cast = PapyrusUtil.ActorArray(n)
	int k = 0
	While k < n
		cast[k] = slots[c * MaxPerColumn + k]
		k += 1
	EndWhile
	Return cast
EndFunction

; Words that mean the player come from CommonFile ("playerwords"), so non-English words never sit
; in this source. Words written in braces are also replaced by the player's name inside lines.
bool Function IsPlayerWord(string spec)
	If spec == "player" || spec == "{player}"
		Return true
	EndIf
	Return JsonUtil.StringListHas(CommonFile, "playerwords", spec)
EndFunction

string Function FillNames(string text)
	string name = Game.GetPlayer().GetDisplayName()
	text = ReplaceAll(text, "{player}", name)
	int n = JsonUtil.StringListCount(CommonFile, "playerwords")
	int i = 0
	While i < n
		string word = JsonUtil.StringListGet(CommonFile, "playerwords", i)
		If StringUtil.Find(word, "{") == 0
			text = ReplaceAll(text, word, name)
		EndIf
		i += 1
	EndWhile
	Return text
EndFunction

string Function ReplaceAll(string text, string find, string with)
	int at = StringUtil.Find(text, find)
	While at >= 0
		; Substring with length 0 means "to the end", so a match at 0 needs an empty head.
		string head = ""
		If at > 0
			head = StringUtil.Substring(text, 0, at)
		EndIf
		string tail = ""
		If at + StringUtil.GetLength(find) < StringUtil.GetLength(text)
			tail = StringUtil.Substring(text, at + StringUtil.GetLength(find))
		EndIf
		text = head + with + tail
		at = StringUtil.Find(text, find, at + StringUtil.GetLength(with))
	EndWhile
	Return text
EndFunction

int Function ParseHex(string s)
	If StringUtil.Find(s, "0x") == 0
		s = StringUtil.Substring(s, 2)
	EndIf
	string digits = "0123456789ABCDEF0123456789abcdef"
	int value = 0
	int i = 0
	int len = StringUtil.GetLength(s)
	While i < len
		int d = StringUtil.Find(digits, StringUtil.GetNthChar(s, i))
		If d < 0
			Return 0
		EndIf
		value = value * 16 + (d % 16)
		i += 1
	EndWhile
	Return value
EndFunction

string Function StateKey(string file)
	Return "SkyrimNet_DialogueScenarioEditor:" + file
EndFunction

; The DLL's log (SKSE\SkyrimNet_DialogueScenarioEditor.log, no INI setting needed), and the Papyrus log.
Function Log(string msg)
	LogAt(msg, 0)
EndFunction

Function LogAt(string msg, int level)
	If dllLog
		SkyrimNet_DialogueScenarioEditorNative.Log(msg, level)
	EndIf
	Debug.Trace("[SkyrimNet_DialogueScenarioEditor] " + msg)
EndFunction

; Setup mistakes are shown once per save, not on every check.
Function Warn(string file, string msg)
	string text = file + ": " + msg
	If StorageUtil.StringListHas(self, "SkyrimNet_DialogueScenarioEditor:warned", text)
		Return
	EndIf
	StorageUtil.StringListAdd(self, "SkyrimNet_DialogueScenarioEditor:warned", text)
	LogAt(text, 1)
	Debug.Notification("ScenarioEditor: " + text)
EndFunction

Function Notify(string msg)
	LogAt(msg, 1)
	Debug.Notification("ScenarioEditor: " + msg)
EndFunction
