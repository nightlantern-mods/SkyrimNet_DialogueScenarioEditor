Scriptname SkyrimNet_DialogueScenarioEditorMain extends Quest
{Reads event setups from JSON files in Data/SKSE/Plugins/StorageUtilData/SkyrimNet_DialogueScenarioEditor/
and runs the first one whose participants are all near the player.

A setup has up to ten columns, run left to right. Each column holds up to three participants,
an optional narration, up to ten lines (each with its speaker, in any order, the same speaker as
often as wanted; reworded by SkyrimNet in the speaker's own voice) and an optional OStim scene
that starts after the lines. A character may appear in several columns, but joins OStim only once
per event; columns without OStim are just talk.

Keys: enabled, onlytargets, repeat, intervaldays, location (0 any, 1 indoors, 2 outdoors);
per column cN_actors, cN_lines, cN_speakers (intList: participant index per line; without it,
line i is spoken by participant i), cN_autos (intList: 1 = that line is made up when spoken),
cN_auto (1 = every line of the column is), cN_autolen (0/1/2 = 3/6/10 lines), cN_narrator,
cN_ostim, cN_tags.

The JSON files are only read, never written. Fired state lives in the save (StorageUtil).}

string Property EventFolder = "SkyrimNet_DialogueScenarioEditor" AutoReadOnly
string Property CommonFile = "SkyrimNet_DialogueScenarioEditor_Common" AutoReadOnly
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
Keyword npcKeyword
int loadCount = 0 ; bumped on every load
int runLoad = 0   ; loadCount when the current run started

; Keeping the column's cast together while it talks (see Hold).
bool holding = false
Actor[] holdCast
Actor holdAnchor
float[] holdSides
bool[] holdSettled ; per participant: close enough and standing still
bool anchorFaced = false ; an NPC anchor has turned toward the others
int holdTick = 0
string Property HeldList = "SkyrimNet_DialogueScenarioEditor:held" AutoReadOnly ; actors with SetDontMove on

; --------------------------------------------------------------------------------------------
; Setup and the periodic check (called from the player alias timer)
; --------------------------------------------------------------------------------------------

; Called on every game load (mod event registrations do not survive a load).
Function Setup()
	npcKeyword = Keyword.GetKeyword("ActorTypeNPC")
	RegisterSpeechEvents()
	loadCount += 1
	; A save made mid-talk keeps the "don't move" flag on whoever was held: give it back.
	holding = false
	FreeHeld()
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

	Actor player = Game.GetPlayer()
	If Utility.IsInMenuMode() || player.IsInCombat() || OActor.IsInOStim(player)
		Return CheckInterval
	EndIf
	Cell here = player.GetParentCell()
	If here == None
		Return CheckInterval
	EndIf

	string[] files = JsonUtil.JsonInFolder(EventFolder)
	If files.Length == 0
		Return CheckInterval
	EndIf

	bool interior = here.IsInterior()
	float range = ExteriorRange
	If interior
		range = InteriorRange
	EndIf
	Actor[] nearby = OActorUtil.GetActorsInRangeV2(player, range, true, true)

	int i = 0
	While i < files.Length
		string file = EventFolder + "/" + files[i]
		If IsReady(file, here)
			If TryStart(file, nearby, here, interior)
				Return CheckInterval
			EndIf
		EndIf
		i += 1
	EndWhile
	Return CheckInterval
EndFunction

; Enabled, not used up, past its interval, and not blocked in the cell it last fired in.
bool Function IsReady(string file, Cell here)
	If JsonUtil.GetIntValue(file, "enabled", 0) == 0
		Return false
	EndIf
	int where = JsonUtil.GetIntValue(file, "location", 0)
	If (where == 1 && !here.IsInterior()) || (where == 2 && here.IsInterior())
		Return false
	EndIf
	string id = StateKey(file)

	Form blockedCell = StorageUtil.GetFormValue(self, id + ":cell")
	If blockedCell != None
		If blockedCell != here
			StorageUtil.UnsetFormValue(self, id + ":cell")
		Else
			Return false
		EndIf
	EndIf

	float last = StorageUtil.GetFloatValue(self, id + ":last", -1.0)
	If last < 0.0
		Return true
	EndIf
	If JsonUtil.GetIntValue(file, "repeat", 0) == 0
		Return false
	EndIf
	float interval = JsonUtil.GetFloatValue(file, "intervaldays", 1.0)
	Return Utility.GetCurrentGameTime() - last >= interval
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
			Warn(file, "column " + (c + 1) + " has more than " + MaxPerColumn + " participants")
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
						Warn(file, "column " + (c + 1) + " lists " + a.GetDisplayName() + " twice")
						Return false
					EndIf
					s += 1
				EndWhile
			Else
				a = Resolve(spec, nearby, here, interior, slots)
			EndIf
			If a == None
				Return false ; someone is not here (normal, no message)
			EndIf
			If a.IsChild()
				Warn(file, "children cannot take part: " + a.GetDisplayName())
				Return false
			EndIf
			If a.IsInCombat() || OActor.IsInOStim(a)
				Return false
			EndIf
			slots[colStart + k] = a
			specs[colStart + k] = spec
			k += 1
		EndWhile
		c += 1
	EndWhile

	If JsonUtil.StringListCount(file, "c1_actors") == 0
		Warn(file, "column 1 has no participants")
		Return false
	EndIf

	; Who else is around.
	bool onlyTargets = JsonUtil.GetIntValue(file, "onlytargets", 0) != 0
	int i = 0
	While i < nearby.Length
		Actor other = nearby[i]
		If Counts(other, here, interior) && slots.Find(other) < 0
			If onlyTargets || other.IsChild()
				Return false
			EndIf
		EndIf
		i += 1
	EndWhile

	; Fire: remember it in the save before anything can fail.
	string id = StateKey(file)
	StorageUtil.SetFloatValue(self, id + ":last", Utility.GetCurrentGameTime())
	StorageUtil.SetFormValue(self, id + ":cell", here)
	running = true
	runStart = Utility.GetCurrentGameTime()
	runLoad = loadCount
	Log("start " + file)
	RunSetup(file, slots)
	running = false
	If Interrupted()
		Log("stopped " + file + " (a save made during the event was loaded)")
	Else
		Log("done " + file)
	EndIf
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

	string narration = JsonUtil.GetStringValue(file, col + "narrator", "")
	If narration != ""
		SkyrimNetApi.RegisterPersistentEvent(FillNames(narration), cast[0])
	EndIf

	Gather(cast)

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
	EndIf

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
			If madeUp
				SpeakFreely(speaker, listener, context)
			Else
				Speak(speaker, listener, FillNames(line))
			EndIf
			lastSpeaker = speaker
		EndIf
		k += 1
	EndWhile

	; Let them go before OStim places them (or back to their day once only talking).
	Release(cast)

	If JsonUtil.GetIntValue(file, col + "ostim", 1) != 0 && !Interrupted()
		StartScene(cast, JsonUtil.GetStringValue(file, col + "tags", ""))
	EndIf
EndFunction

; Brings everyone to the player (if taking part) or to the first participant, all at once:
; each one keeps a spot in front of the anchor, so they walk there and stay while talking.
; Far away (another room) they are moved there. Waits up to GatherTimeout for them to arrive,
; then goes on anyway so a stuck NPC cannot hold the event.
Function Gather(Actor[] cast)
	Actor player = Game.GetPlayer()
	Actor anchor = cast[0]
	If cast.Find(player) >= 0
		anchor = player
	EndIf
	float[] sides = new float[3]
	; The cast is held together from here until Release (see Hold). An NPC anchor has no spot of
	; its own to keep, and its daily routine would walk it (and everyone keeping their place
	; around it) away: it stands still until the talk ends.
	holdCast = cast
	holdAnchor = anchor
	holdSides = sides
	holdSettled = new bool[3]
	anchorFaced = false
	holdTick = 0
	If anchor != player && !OActor.IsInOStim(anchor)
		Pin(anchor, None) ; turned toward the first one to arrive (Hold)
	EndIf
	holding = true

	bool moved = false
	int k = 0
	int spot = 0
	While k < cast.Length
		Actor a = cast[k]
		; Someone still in an earlier column's scene stays put (they talk from the scene).
		If a != anchor && a != player && !OActor.IsInOStim(a)
			sides[k] = -60.0 + 120.0 * spot ; left, right, then further right
			spot += 1
			If a.GetDistance(anchor) > 1500.0
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
			If late != anchor && late != player && !OActor.IsInOStim(late) && late.GetDistance(anchor) > NearDistance
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
	int k = 0
	While k < holdCast.Length
		Actor a = holdCast[k]
		If a != None && a != holdAnchor && a != player && !OActor.IsInOStim(a)
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

; Walk to the spot beside the anchor (a loose spot: within 100 of it counts).
Function Approach(Actor a, int k)
	holdSettled[k] = false
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
		If cast[k] != anchor && cast[k] != Game.GetPlayer() && !OActor.IsInOStim(cast[k]) && cast[k].GetDistance(anchor) > NearDistance
			Return false
		EndIf
		k += 1
	EndWhile
	Return true
EndFunction

Function Release(Actor[] cast)
	holding = false
	FreeHeld()
	int k = 0
	While k < cast.Length
		If cast[k] != Game.GetPlayer() && !OActor.IsInOStim(cast[k])
			cast[k].ClearKeepOffsetFromActor()
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
		SkyrimNetApi.TransformDialogue(line)
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
	SkyrimNetApi.DirectNarration(direction, speaker, listener)
	If !WaitForSpeech(NpcSpeechTimeout) && !Interrupted()
		; Written but not voiced (SkyrimNet thought the speaker was out of earshot): say it again.
		Log(speaker.GetDisplayName() + "'s line was not voiced; asking again")
		Utility.Wait(SettleAfterMove)
		BeginWatch(speaker)
		SkyrimNetApi.DirectNarration(direction, speaker, listener)
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
		SkyrimNetApi.TriggerPlayerDialogue()
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
	SkyrimNetApi.DirectNarration(direction, speaker, listener)
	If !WaitForSpeech(NpcSpeechTimeout) && !Interrupted()
		Log(speaker.GetDisplayName() + "'s auto line was not voiced; asking again")
		Utility.Wait(SettleAfterMove)
		BeginWatch(speaker)
		SkyrimNetApi.DirectNarration(direction, speaker, listener)
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
EndFunction

Event OnSkyrimNetSpeechStarted(string eventName, string strArg, float numArg, Form sender)
	If watchSpeaker != None && sender == watchSpeaker
		piecesStarted += 1
	EndIf
EndEvent

Event OnSkyrimNetSpeechComplete(string eventName, string strArg, float numArg, Form sender)
	If watchSpeaker != None && sender == watchSpeaker
		replyWritten = true
	EndIf
EndEvent

Event OnSkyrimNetAudioEnded(string eventName, string strArg, float numArg, Form sender)
	If watchSpeaker != None && sender == watchSpeaker
		piecesEnded += 1
	EndIf
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
			watchSpeaker = None
			Utility.Wait(0.5)
			Return true
		EndIf
		; Every piece is announced before the reply counts as written, so written with no piece
		; (after a moment) means SkyrimNet dropped the voice.
		If replyWritten && piecesStarted == 0 && waited >= 3.0
			watchSpeaker = None
			Return false
		EndIf
		; The player's line (TransformDialogue) sends no SpeechComplete: every started piece has
		; played and a short quiet follows. Also the no-events fallback.
		If !replyWritten && piecesEnded > 0 && piecesEnded >= piecesStarted
			If SkyrimNetApi.GetTimeSinceLastAudioEnded() >= 1500 && SkyrimNetApi.GetSpeechQueueSize() == 0
				watchSpeaker = None
				Return true
			EndIf
		EndIf
	EndWhile
	Log("speech wait timed out after " + timeout + " s (pieces " + piecesEnded + "/" + piecesStarted + ", written " + replyWritten + ")")
	watchSpeaker = None
	Return true
EndFunction

; Waits until nobody has spoken for QuietMs and nothing is queued (used before a scene starts).
Function WaitForSilence(float timeout)
	float waited = 0.0
	While waited < timeout
		int since = SkyrimNetApi.GetTimeSinceLastAudioEnded()
		If (since == 0 || since >= QuietMs) && SkyrimNetApi.GetSpeechQueueSize() == 0
			Return
		EndIf
		Utility.Wait(0.5)
		waited += 0.5
		Hold()
	EndWhile
	Log("silence wait timed out after " + timeout + " s")
EndFunction

; Furniture (beds etc.) follows the player's OStim settings.
Function StartScene(Actor[] cast, string tags)
	WaitForSilence(20.0)
	StopScenesOf(cast)
	Actor[] sorted = OActorUtil.Sort(cast, OActorUtil.EmptyArray())
	string sceneId = ""
	If tags != ""
		sceneId = OLibrary.GetRandomSceneWithAnySceneTagCSV(sorted, tags)
		If sceneId == ""
			sceneId = OLibrary.GetRandomSceneWithAnyActionCSV(sorted, tags)
		EndIf
		If sceneId == ""
			Log("no scene for tags '" + tags + "' with " + sorted.Length + " actors; using any scene")
		EndIf
	EndIf
	; Alone: most solo scenes are idles and intros, so "any scene" means masturbation here.
	If sceneId == "" && sorted.Length == 1
		sceneId = OLibrary.GetRandomSceneWithAnyActionCSV(sorted, SoloActions)
	EndIf
	If sceneId == ""
		sceneId = OLibrary.GetRandomScene(sorted)
	EndIf
	If sceneId == ""
		Notify("no OStim scene fits " + sorted.Length + " actors")
		Return
	EndIf

	int builder = OThreadBuilder.Create(sorted)
	If builder < 0
		Notify("OStim refused these actors")
		Return
	EndIf
	OThreadBuilder.SetStartingAnimation(builder, sceneId)
	int thread = OThreadBuilder.Start(builder)

	; The next column waits until this scene has started.
	float waited = 0.0
	While waited < 10.0 && !OThread.IsRunning(thread)
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	Utility.Wait(1.0)
EndFunction

; Anyone still in a scene (an earlier column's, or any other) has that scene stopped first, so the
; same character can join OStim again later in the event (the user's choice). OStim cannot take
; one actor out of a scene, so everyone else in that scene leaves it too.
Function StopScenesOf(Actor[] cast)
	bool stopped = false
	int k = 0
	While k < cast.Length
		If OActor.IsInOStim(cast[k])
			int thread = OActor.GetThreadID(cast[k])
			If thread >= 0 && OThread.IsRunning(thread)
				Log("stopping scene " + thread + " for " + cast[k].GetDisplayName())
				OThread.Stop(thread)
				stopped = true
			EndIf
		EndIf
		k += 1
	EndWhile
	If !stopped
		Return
	EndIf
	float waited = 0.0
	While waited < 10.0 && AnyInOStim(cast)
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	Utility.Wait(1.5) ; let them stand up and redress before the next scene
EndFunction

bool Function AnyInOStim(Actor[] cast)
	int k = 0
	While k < cast.Length
		If OActor.IsInOStim(cast[k])
			Return true
		EndIf
		k += 1
	EndWhile
	Return false
EndFunction

; --------------------------------------------------------------------------------------------
; Helpers
; --------------------------------------------------------------------------------------------

Actor[] Function ColumnCast(Actor[] slots, int c)
	int n = 0
	While n < MaxPerColumn && slots[c * MaxPerColumn + n] != None
		n += 1
	EndWhile
	Actor[] cast = OActorUtil.CreateArray(n)
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

Function Log(string msg)
	Debug.Trace("[SkyrimNet_DialogueScenarioEditor] " + msg)
EndFunction

; Setup mistakes are shown once per save, not on every check.
Function Warn(string file, string msg)
	string text = file + ": " + msg
	If StorageUtil.StringListHas(self, "SkyrimNet_DialogueScenarioEditor:warned", text)
		Return
	EndIf
	StorageUtil.StringListAdd(self, "SkyrimNet_DialogueScenarioEditor:warned", text)
	Log(text)
	Debug.Notification("ScenarioEditor: " + text)
EndFunction

Function Notify(string msg)
	Log(msg)
	Debug.Notification("ScenarioEditor: " + msg)
EndFunction
