Scriptname SkyrimNet_DialogueScenarioEditorUI extends MCM_ConfigBase
{The settings page and the MCM (MCM Helper). The page runs on Magelight UI (its Papyrus tier) when
that is installed, otherwise on Prisma UI through SKSE\Plugins\SkyrimNet_DialogueScenarioEditor.dll
(SkyrimNet_DialogueScenarioEditorNative); the same index.html serves both. The key that opens the page
is chosen in the MCM and is unassigned until the player picks one. The page edits the setup files
in StorageUtilData/SkyrimNet_DialogueScenarioEditor/; files are written only when the player presses Save or
Delete on the page.

Papyrus -> page: Magelight.Eval with a script built here (setup files are JSON, so they are
embedded as object literals; other strings are escaped). Page -> Papyrus: listeners dse_*.}

string Property ModId = "SkyrimNet_DialogueScenarioEditor" AutoReadOnly
string Property ViewName = "main" AutoReadOnly
string Property SetupFolder = "SkyrimNet_DialogueScenarioEditor" AutoReadOnly
string Property SetupDisk = "Data/SKSE/Plugins/StorageUtilData/SkyrimNet_DialogueScenarioEditor/" AutoReadOnly
string Property DeletedFile = "SkyrimNet_DialogueScenarioEditor_Deleted" AutoReadOnly ; same as the main script's
int Property ChunkChars = 3000 AutoReadOnly

int boundKey = 0
int triggerKey = 0 ; the scenario hotkey (starts hotkey scenarios)
bool sendingNpcs = false
bool usePrisma = false
int pageView = 0 ; the Magelight view last shown (generation answers come later)

; --------------------------------------------------------------------------------------------
; Load-time setup (called from the player alias)
; --------------------------------------------------------------------------------------------

Function Setup()
	BindHotkey()
	PushFramework()
	RegisterForModEvent("Magelight_ViewDomReady", "OnViewDomReady")
	RegisterForModEvent("Magelight_UIModeExited", "OnUIModeExited")
	; The same page calls arrive from either host: Magelight UI (numArg = view) or the DLL's
	; Prisma UI host (numArg = 0).
	RegisterForModEvent("Magelight_JS_dse_ready", "OnPageReady")
	RegisterForModEvent("Magelight_JS_dse_close", "OnPageClose")
	RegisterForModEvent("Magelight_JS_dse_save", "OnPageSave")
	RegisterForModEvent("Magelight_JS_dse_delete", "OnPageDelete")
	RegisterForModEvent("Magelight_JS_dse_npcs", "OnPageNpcs")
	RegisterForModEvent("DSE_Prisma_dse_ready", "OnPageReady")
	RegisterForModEvent("DSE_Prisma_dse_close", "OnPageClose")
	RegisterForModEvent("DSE_Prisma_dse_save", "OnPageSave")
	RegisterForModEvent("DSE_Prisma_dse_delete", "OnPageDelete")
	RegisterForModEvent("DSE_Prisma_dse_npcs", "OnPageNpcs")
	RegisterForModEvent("Magelight_JS_dse_places", "OnPagePlaces")
	RegisterForModEvent("DSE_Prisma_dse_places", "OnPagePlaces")
	RegisterForModEvent("Magelight_JS_dse_generate", "OnPageGenerate")
	RegisterForModEvent("DSE_Prisma_dse_generate", "OnPageGenerate")
	RegisterForModEvent("Magelight_JS_dse_here", "OnPageHere")
	RegisterForModEvent("DSE_Prisma_dse_here", "OnPageHere")
	RegisterForModEvent("Magelight_JS_dse_actions", "OnPageActions")
	RegisterForModEvent("DSE_Prisma_dse_actions", "OnPageActions")
	RegisterForModEvent("DSE_Gen", "OnGen")
	sendingNpcs = false
	usePrisma = UsePrisma()
EndFunction

; Magelight UI when it is installed (or when the DLL is missing: then nothing else could work);
; Prisma UI through the DLL otherwise.
bool Function UsePrisma()
	int host = SkyrimNet_DialogueScenarioEditorNative.Host()
	Return Math.LogicalAnd(host, 1) == 0 && Math.LogicalAnd(host, 2) != 0
EndFunction

; Runs JavaScript in the page, on whichever host shows it.
Function Js(int view, string script)
	If usePrisma
		SkyrimNet_DialogueScenarioEditorNative.Eval(script)
	Else
		Magelight.Eval(view, script)
	EndIf
EndFunction

; The MCM keymap; -1 (or 0) = no key.
int Function Hotkey()
	Return GetModSettingInt("iHotkey:General")
EndFunction

; The MCM's scene framework choice (0 automatic, 1 OStim, 2 SexLab) for the main script.
Function PushFramework()
	((self as Quest) as SkyrimNet_DialogueScenarioEditorMain).SetFramework(GetModSettingInt("iFramework:General"))
EndFunction

Function BindHotkey()
	UnregisterForAllKeys()
	boundKey = Hotkey()
	If boundKey > 0
		RegisterForKey(boundKey)
	EndIf
	triggerKey = GetModSettingInt("iTriggerKey:General")
	If triggerKey > 0 && triggerKey != boundKey
		RegisterForKey(triggerKey)
	EndIf
EndFunction

Event OnSettingChange(String a_ID)
	If a_ID == "iHotkey:General" || a_ID == "iTriggerKey:General"
		BindHotkey()
	ElseIf a_ID == "iFramework:General"
		PushFramework()
	EndIf
EndEvent

Event OnKeyDown(int keyCode)
	If Utility.IsInMenuMode()
		Return
	EndIf
	If triggerKey > 0 && keyCode == triggerKey && keyCode != boundKey
		((self as Quest) as SkyrimNet_DialogueScenarioEditorMain).StartByHotkey() ; both scripts are on the same quest
		Return
	EndIf
	If boundKey <= 0 || keyCode != boundKey
		Return
	EndIf
	usePrisma = UsePrisma()
	If usePrisma
		If !SkyrimNet_DialogueScenarioEditorNative.IsOpen()
			OpenPrisma()
		EndIf
	ElseIf !Magelight.IsUIModeActive()
		Open()
	EndIf
EndEvent

; --------------------------------------------------------------------------------------------
; Opening and closing
; --------------------------------------------------------------------------------------------

; The DLL made the view at game start; the page asks for its data with dse_ready once loaded,
; and gets it again on every open.
Function OpenPrisma()
	If !SkyrimNet_DialogueScenarioEditorNative.Open()
		Debug.Notification("ScenarioEditor: could not open the page (Prisma UI is busy)")
		Log("could not open the page: Prisma UI is busy")
		Return
	EndIf
	Log("page opened (Prisma UI)")
	SendAll(0)
EndFunction

Function Open()
	If Magelight.GetVersion() == 0 || !Magelight.IsReady()
		Debug.Notification("ScenarioEditor: Magelight UI or Prisma UI is required")
		Log("could not open the page: Magelight version " + Magelight.GetVersion() + ", host " + SkyrimNet_DialogueScenarioEditorNative.Host())
		Return
	EndIf
	Magelight.RegisterMod(ModId, "SkyrimNet Dialogue Scenario Editor")
	int view = Magelight.FindView(ModId, ViewName)
	bool fresh = false
	If view == 0
		view = Magelight.CreateView(ModId, ViewName, "views/index.html", 0, 0, 0, 0, "panel", "top-left", false, false)
		fresh = true
	EndIf
	If view == 0
		Debug.Notification("ScenarioEditor: could not open the page (" + Magelight.GetLastError(ModId) + ")")
		Log("could not open the page: " + Magelight.GetLastError(ModId))
		Return
	EndIf
	Log("page opened (Magelight UI " + Magelight.GetVersion() + ", new view " + fresh + ")")
	Magelight.ShowView(view, true)
	Magelight.RequestUIMode(view, true)
	If !fresh
		; Already loaded this session: no DomReady will come, so refresh now.
		RegisterListeners(view)
		SendAll(view)
	EndIf
EndFunction

Event OnViewDomReady(string eventName, string strArg, float numArg, Form sender)
	If strArg != ModId
		Return
	EndIf
	int view = numArg as int
	RegisterListeners(view)
	; The page also asks with dse_ready once its script is set up; DomReady covers reloads.
EndEvent

Function RegisterListeners(int view)
	Magelight.RegisterListener(view, "dse_ready")
	Magelight.RegisterListener(view, "dse_close")
	Magelight.RegisterListener(view, "dse_save")
	Magelight.RegisterListener(view, "dse_delete")
	Magelight.RegisterListener(view, "dse_npcs")
	Magelight.RegisterListener(view, "dse_generate")
	Magelight.RegisterListener(view, "dse_places")
	Magelight.RegisterListener(view, "dse_here")
	Magelight.RegisterListener(view, "dse_actions")
EndFunction

; The places "move and wait" can send people to (from the DLL), for the page's place picker.
; Without the DLL the page gets null and says so.
Event OnPagePlaces(string eventName, string strArg, float numArg, Form sender)
	int view = numArg as int
	If view != 0
		pageView = view
	EndIf
	If SkyrimNet_DialogueScenarioEditorNative.Version() == 0
		Js(pageView, "dsePlaces(null)")
		Return
	EndIf
	Js(pageView, "dsePlaces(" + SkyrimNet_DialogueScenarioEditorNative.PlaceList() + ")")
EndEvent

; The SkyrimNet actions a column can end with: those in the installed mods' action files that
; SkyrimNet has registered in this game (the rest are blanked out, and the DLL skips them).
Event OnPageActions(string eventName, string strArg, float numArg, Form sender)
	int view = numArg as int
	If view != 0
		pageView = view
	EndIf
	If SkyrimNet_DialogueScenarioEditorNative.Version() < 4
		Js(pageView, "dseActions(null)")
		Return
	EndIf
	string[] names = SkyrimNet_DialogueScenarioEditorNative.ActionNames()
	int kept = 0
	int i = 0
	While i < names.Length
		If SkyrimNetApi.IsActionRegistered(names[i])
			kept += 1
		Else
			names[i] = ""
		EndIf
		i += 1
	EndWhile
	Log("actions: " + kept + " of " + names.Length + " registered")
	Js(pageView, "dseActions(" + SkyrimNet_DialogueScenarioEditorNative.ActionList(names) + ")")
EndEvent

; The player's cell, for a scenario's cell condition ("this cell" on the page).
Event OnPageHere(string eventName, string strArg, float numArg, Form sender)
	int view = numArg as int
	If view != 0
		pageView = view
	EndIf
	string here = ""
	If SkyrimNet_DialogueScenarioEditorNative.Version() >= 3
		here = SkyrimNet_DialogueScenarioEditorNative.HereCell()
	EndIf
	If here == ""
		here = "null"
	EndIf
	Log("this cell: " + here)
	Js(pageView, "dseHere(" + here + ")")
EndEvent

; --------------------------------------------------------------------------------------------
; Scenario generation (the DLL asks SkyrimNet's AI; this only passes messages along)
; --------------------------------------------------------------------------------------------

; Payload: the request JSON (see the DLL's generator.h).
Event OnPageGenerate(string eventName, string strArg, float numArg, Form sender)
	If numArg != 0.0
		pageView = numArg as int
	EndIf
	If SkyrimNet_DialogueScenarioEditorNative.Version() == 0
		Js(pageView, "dseGen({\"type\":\"error\",\"code\":\"nodll\"})")
		Return
	EndIf
	Log("generate requested")
	SkyrimNet_DialogueScenarioEditorNative.Generate(strArg) ; a failure to start arrives as DSE_Gen
EndEvent

; From the DLL: progress, the result or an error, for the page.
Event OnGen(string eventName, string strArg, float numArg, Form sender)
	Js(pageView, "dseGen(" + strArg + ")")
EndEvent

Event OnPageReady(string eventName, string strArg, float numArg, Form sender)
	SendAll(numArg as int)
EndEvent

Event OnPageClose(string eventName, string strArg, float numArg, Form sender)
	Close(numArg as int)
EndEvent

Event OnUIModeExited(string eventName, string strArg, float numArg, Form sender)
	If strArg == ModId
		Close(numArg as int)
	EndIf
EndEvent

Function Close(int view)
	If usePrisma
		SkyrimNet_DialogueScenarioEditorNative.Close()
		Return
	EndIf
	If view == 0
		view = Magelight.FindView(ModId, ViewName)
	EndIf
	Magelight.ReleaseUIMode(ModId)
	If view != 0
		Magelight.ShowView(view, false)
	EndIf
EndFunction

; --------------------------------------------------------------------------------------------
; Sending data to the page
; --------------------------------------------------------------------------------------------

Function SendAll(int view)
	If view != 0
		pageView = view
	EndIf
	; The second argument: the DLL can list every NPC at once, so the page loads the list by itself.
	Js(view, "dseBegin(\"" + Esc(Game.GetPlayer().GetDisplayName()) + "\"," + ((SkyrimNet_DialogueScenarioEditorNative.Version() > 0) as int) + ")")
	SendSetups(view)
	SendNearby(view)
	Js(view, "dseEnd()")
EndFunction

Function SendSetups(int view)
	string[] files = JsonUtil.JsonInFolder(SetupFolder)
	int i = 0
	While i < files.Length
		string name = files[i]
		If StringUtil.Find(name, ".json") < 0
			name += ".json"
		EndIf
		string text = MiscUtil.ReadFromFile(SetupDisk + name)
		string base = StringUtil.Substring(name, 0, StringUtil.GetLength(name) - 5)
		If IsSafeName(base) && StringUtil.Find(text, "{") >= 0 && !JsonUtil.StringListHas(DeletedFile, "names", base)
			Js(view, "dseSetup(\"" + base + "\"," + text + ")")
		EndIf
		i += 1
	EndWhile
EndFunction

; NPCs around the player, for quick picking: [baseId, plugin, name].
Function SendNearby(int view)
	Actor player = Game.GetPlayer()
	Actor[] near = ((self as Quest) as SkyrimNet_DialogueScenarioEditorMain).NearbyActors(player, 4000.0)
	Keyword npcKw = Keyword.GetKeyword("ActorTypeNPC")
	string js = "dseNearby(["
	bool first = true
	int i = 0
	While i < near.Length
		Actor a = near[i]
		If a != None && a != player && !a.IsDead() && !a.IsChild() && a.HasKeyword(npcKw)
			ActorBase b = a.GetActorBase()
			If !first
				js += ","
			EndIf
			js += NpcEntry(b, a.GetDisplayName())
			first = false
		EndIf
		i += 1
	EndWhile
	Js(view, js + "])")
EndFunction

; Every unique adult person in the load order, sent in chunks. Slow (seconds), so only on request.
Event OnPageNpcs(string eventName, string strArg, float numArg, Form sender)
	If sendingNpcs
		Return
	EndIf
	sendingNpcs = true
	int view = numArg as int
	; With the DLL: the whole list at once (well under a second).
	If SkyrimNet_DialogueScenarioEditorNative.Version() > 0
		Js(view, "dseNpcs(" + SkyrimNet_DialogueScenarioEditorNative.NpcList() + ",1,1)")
		Js(view, "dseNpcsDone(-1)")
		sendingNpcs = false
		Return
	EndIf
	; Without it: Papyrus goes through every form (minutes).
	Keyword npcKw = Keyword.GetKeyword("ActorTypeNPC")
	Form[] all = PO3_SKSEFunctions.GetAllForms(43)
	string js = ""
	int count = 0
	int i = 0
	While i < all.Length
		ActorBase b = all[i] as ActorBase
		If b != None && b.IsUnique()
			string name = b.GetName()
			Race r = b.GetRace()
			If name != "" && r != None && r.HasKeyword(npcKw) && !r.IsRaceFlagSet(4)
				If js != ""
					js += ","
				EndIf
				js += NpcEntry(b, name)
				count += 1
				If StringUtil.GetLength(js) > ChunkChars
					Js(view, "dseNpcs([" + js + "]," + i + "," + all.Length + ")")
					js = ""
				EndIf
			EndIf
		EndIf
		i += 1
		; Let the page's other calls (Close, Esc, Save) through while this runs for minutes: without
		; this pause they waited until the whole scan was over.
		If i % 300 == 0
			Utility.WaitMenuMode(0.05)
		EndIf
	EndWhile
	Js(view, "dseNpcs([" + js + "]," + all.Length + "," + all.Length + ")")
	Js(view, "dseNpcsDone(" + count + ")")
	sendingNpcs = false
EndEvent

string Function NpcEntry(ActorBase b, string name)
	Return "[" + b.GetFormID() + ",\"" + Esc(PO3_SKSEFunctions.GetFormModName(b, false)) + "\",\"" + Esc(name) + "\"]"
EndFunction

; --------------------------------------------------------------------------------------------
; Writing (only on the player's action in the page)
; --------------------------------------------------------------------------------------------

; Payload: "<name>\n<json text>"
Event OnPageSave(string eventName, string strArg, float numArg, Form sender)
	int view = numArg as int
	int nl = StringUtil.Find(strArg, "\n")
	If nl <= 0
		Return
	EndIf
	string name = StringUtil.Substring(strArg, 0, nl)
	string text = StringUtil.Substring(strArg, nl + 1)
	If !IsSafeName(name) || StringUtil.Find(text, "{") < 0
		Js(view, "dseSaved(\"\",false)")
		Return
	EndIf
	; A new scenario (no file yet, or an emptied / deleted one): any run record under this name is
	; an old scenario's, and must not keep the new one from starting.
	string oldText = MiscUtil.ReadFromFile(SetupDisk + name + ".json")
	bool isNew = StringUtil.Find(oldText, "{") < 0 || JsonUtil.StringListHas(DeletedFile, "names", name)
	; A scenario whose content changed (not just its on/off switch, which the list saves the same
	; way) is a new scenario to try: its run record goes too, so it can start again after an edit.
	bool changed = !isNew && WithoutSwitch(oldText) != WithoutSwitch(text)
	bool ok = MiscUtil.WriteToFile(SetupDisk + name + ".json", text, false, false)
	JsonUtil.Unload(SetupFolder + "/" + name, false)
	If ok && (isNew || changed)
		((self as Quest) as SkyrimNet_DialogueScenarioEditorMain).ForgetRuns(name)
	EndIf
	Log("saved " + name + " (" + StringUtil.GetLength(text) + " chars, ok " + ok + ")")
	If ok && JsonUtil.StringListHas(DeletedFile, "names", name)
		; saved again under a deleted name: it is a scenario again
		JsonUtil.StringListRemove(DeletedFile, "names", name, true)
		JsonUtil.Save(DeletedFile, false)
	EndIf
	Js(view, "dseSaved(\"" + name + "\"," + (ok as int) + ")")
EndEvent

; The file text with its "enabled" value left out, so a change of the list switch alone does not
; count as a changed scenario.
string Function WithoutSwitch(string text)
	text = Swap(text, "\"enabled\": 1", "\"enabled\": x")
	Return Swap(text, "\"enabled\": 0", "\"enabled\": x")
EndFunction
; Payload: "<name>". The file is emptied (PapyrusUtil cannot delete); empty files are ignored.
; The name also goes into the deleted list, so a shipped example the mod's files bring back on a
; reinstall or update stays deleted.
Event OnPageDelete(string eventName, string strArg, float numArg, Form sender)
	int view = numArg as int
	If !IsSafeName(strArg)
		Return
	EndIf
	MiscUtil.WriteToFile(SetupDisk + strArg + ".json", "", false, false)
	JsonUtil.Unload(SetupFolder + "/" + strArg, false)
	JsonUtil.StringListAdd(DeletedFile, "names", strArg, false)
	JsonUtil.Save(DeletedFile, false)
	((self as Quest) as SkyrimNet_DialogueScenarioEditorMain).ForgetRuns(strArg)
	Log("deleted " + strArg)
	Js(view, "dseDeleted(\"" + strArg + "\")")
EndEvent

; The DLL's log (see the main script's Log).
Function Log(string msg)
	If SkyrimNet_DialogueScenarioEditorNative.Version() >= 2
		SkyrimNet_DialogueScenarioEditorNative.Log("page: " + msg, 0)
	EndIf
	Debug.Trace("[SkyrimNet_DialogueScenarioEditor] page: " + msg)
EndFunction

; --------------------------------------------------------------------------------------------
; Helpers
; --------------------------------------------------------------------------------------------

; Letters, digits, _ and - only (it becomes a file name and sits inside generated scripts).
bool Function IsSafeName(string s)
	int len = StringUtil.GetLength(s)
	If len == 0 || len > 40
		Return false
	EndIf
	string ok = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	int i = 0
	While i < len
		If StringUtil.Find(ok, StringUtil.GetNthChar(s, i)) < 0
			Return false
		EndIf
		i += 1
	EndWhile
	Return true
EndFunction

; Escapes a string for a JS double-quoted literal.
string Function Esc(string s)
	s = Swap(s, "\\", "\\\\")
	s = Swap(s, "\"", "\\\"")
	s = Swap(s, "\n", "\\n")
	Return s
EndFunction

string Function Swap(string text, string find, string with)
	int at = StringUtil.Find(text, find)
	While at >= 0
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
