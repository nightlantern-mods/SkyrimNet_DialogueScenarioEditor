Scriptname SkyrimNet_DialogueScenarioEditorSL Hidden
{The mod's SexLab calls that P+ and 1.6x share (SkyrimNet_DialogueScenarioEditorSLP / SL16 hold the
rest). Only the main script calls these, and only when SexLab.esm is installed: without SexLab the
types used here do not exist, so the main script names none of them and keeps the API as a Quest.}

Quest Function API() Global
	Return SexLabUtil.GetAPI()
EndFunction

; 1.6x returns its own version (16601 for 1.66b); P+ the version of its SKSE plugin, a far larger
; number (or 0 without the plugin, still P+).
Int Function Version() Global
	Return SexLabUtil.GetVersion()
EndFunction

; In a SexLab scene: SexLab's IsActorActive only checks its animating faction, which an actor can
; keep after a scene that did not end cleanly (2026-11-22: Faendal, standing idle, counted as in a
; scene). So a thread of theirs must exist too.
Bool Function IsActive(Quest api, Actor who) Global
	SexLabFramework sexLab = api as SexLabFramework
	Return sexLab.IsActorActive(who) && sexLab.GetActorController(who) != None
EndFunction

; Only the faction (for the log: a leftover from a scene that did not end cleanly).
Bool Function InFactionOnly(Quest api, Actor who) Global
	SexLabFramework sexLab = api as SexLabFramework
	Return sexLab.IsActorActive(who) && sexLab.GetActorController(who) == None
EndFunction

; Ends the SexLab scene the actor is in (everyone in it leaves it). Returns whether there was one.
Bool Function StopSceneOf(Quest api, Actor who) Global
	SexLabFramework sexLab = api as SexLabFramework
	If !sexLab.IsActorActive(who)
		Return False
	EndIf
	sslThreadController thread = sexLab.GetActorController(who)
	If !thread
		Return False
	EndIf
	thread.EndAnimation(False)
	Return True
EndFunction

; SexLab tags that only say how a scene feels (from the OStim mood tags romantic, lustful, dom): tried
; only after the tags that say what happens, so a mood tag alone does not pick the scene.
Bool Function IsMoodTag(String tag) Global
	Return tag == "Loving" || tag == "Romance" || tag == "Rough" || tag == "Dirty" || tag == "Dominant"
EndFunction

; The order to try the tags in: from a random one on, those that say what happens first, the mood
; tags after them.
String[] Function TryOrder(String[] tags) Global
	String[] out = Utility.CreateStringArray(0)
	If tags.Length == 0
		Return out
	EndIf
	Int start = Utility.RandomInt(0, tags.Length - 1)
	Int pass = 0
	While pass < 2
		Int i = 0
		While i < tags.Length
			String tag = tags[(start + i) % tags.Length]
			If IsMoodTag(tag) == (pass == 1)
				out = PapyrusUtil.PushString(out, tag)
			EndIf
			i += 1
		EndWhile
		pass += 1
	EndWhile
	Return out
EndFunction

; Whether the scene ID (P+) or animation registry name / name (1.6x) begins with one of the
; excluded entries.
Bool Function IsExcluded(String id, String[] excluded) Global
	If id == ""
		Return False
	EndIf
	Int i = 0
	While i < excluded.Length
		If excluded[i] != "" && StringUtil.Find(id, excluded[i]) == 0
			Return True
		EndIf
		i += 1
	EndWhile
	Return False
EndFunction

; Up to count of the scenes, in order from a random start (wrapping around).
String[] Function Sample(String[] scenes, Int count) Global
	If scenes.Length <= count
		Return scenes
	EndIf
	String[] out = Utility.CreateStringArray(count)
	Int start = Utility.RandomInt(0, scenes.Length - 1)
	Int i = 0
	While i < count
		out[i] = scenes[(start + i) % scenes.Length]
		i += 1
	EndWhile
	Return out
EndFunction

; The scenes that are not excluded, in the same order.
String[] Function WithoutExcluded(String[] scenes, String[] excluded) Global
	If excluded.Length == 0 || scenes.Length == 0
		Return scenes
	EndIf
	String[] kept = Utility.CreateStringArray(0)
	Int i = 0
	While i < scenes.Length
		If !IsExcluded(scenes[i], excluded)
			kept = PapyrusUtil.PushString(kept, scenes[i])
		EndIf
		i += 1
	EndWhile
	If kept.Length < scenes.Length
		Debug.Trace("[SkyrimNet_DialogueScenarioEditor] SexLab: " + (scenes.Length - kept.Length) + " excluded scene(s) left out")
	EndIf
	Return kept
EndFunction

; The SexLab scene the whole cast is in together, with no one else in it; None otherwise.
sslThreadController Function SharedThread(Quest api, Actor[] cast) Global
	SexLabFramework sexLab = api as SexLabFramework
	If cast.Length == 0 || !IsActive(api, cast[0])
		Return None
	EndIf
	sslThreadController thread = sexLab.GetActorController(cast[0])
	Actor[] inThread = thread.Positions
	If !inThread || inThread.Length != cast.Length
		Return None
	EndIf
	Int i = 0
	While i < cast.Length
		If inThread.Find(cast[i]) < 0 || sexLab.GetActorController(cast[i]) != thread
			Return None
		EndIf
		i += 1
	EndWhile
	Return thread
EndFunction

; The nearest free bed SexLab knows within radius of center; None when there is none.
ObjectReference Function FindBed(Quest api, ObjectReference center, Float radius) Global
	SexLabFramework sexLab = api as SexLabFramework
	Return sexLab.FindBed(center, radius, True, None, None)
EndFunction

; Whether every actor is enabled and loaded: the scene search takes a while, and one unloaded
; meanwhile is not handed to SexLab.
Bool Function AllLoaded(Actor[] actors) Global
	Int i = 0
	While i < actors.Length
		If !actors[i] || actors[i].IsDisabled() || !actors[i].Is3DLoaded()
			Return False
		EndIf
		i += 1
	EndWhile
	Return True
EndFunction

; The scenario's tags are OStim's (scene tags and actions, comma separated). SexLab names its tags
; differently: each OStim tag becomes the SexLab tags that mean the same, to be tried one by one
; (SexLab finds a scene for any one of them). Tags it does not know are passed on as they are, so a
; SexLab tag typed into the scenario works too. Empty: no tags (any scene).
String[] Function SexLabTags(String ostimTags) Global
	String[] given = PapyrusUtil.StringSplit(ostimTags, ",")
	String[] out = Utility.CreateStringArray(0)
	Int i = 0
	While i < given.Length
		String tag = given[i]
		String mapped = MapTag(tag)
		If mapped == ""
			mapped = tag
		EndIf
		String[] parts = PapyrusUtil.StringSplit(mapped, "|")
		Int k = 0
		While k < parts.Length
			If parts[k] != "" && out.Find(parts[k]) < 0
				out = PapyrusUtil.PushString(out, parts[k])
			EndIf
			k += 1
		EndWhile
		i += 1
	EndWhile
	Return out
EndFunction

; One OStim tag -> SexLab tags ("|" between them), "" when there is no counterpart to map to.
String Function MapTag(String tag) Global
	If tag == "vaginalsex"
		Return "Vaginal"
	ElseIf tag == "analsex" || tag == "anal"
		Return "Anal"
	ElseIf tag == "oral"
		Return "Oral"
	ElseIf tag == "blowjob"
		Return "Blowjob|Oral"
	ElseIf tag == "cunnilingus"
		Return "Cunnilingus|Oral"
	ElseIf tag == "handjob"
		Return "Handjob"
	ElseIf tag == "boobjob"
		Return "Boobjob"
	ElseIf tag == "footjob"
		Return "Footjob"
	ElseIf tag == "missionary"
		Return "Missionary"
	ElseIf tag == "doggystyle"
		Return "Doggy|Doggystyle"
	ElseIf tag == "cowgirl"
		Return "Cowgirl"
	ElseIf tag == "reversecowgirl"
		Return "ReverseCowgirl|Cowgirl"
	ElseIf tag == "standing"
		Return "Standing"
	ElseIf tag == "spooning"
		Return "Spooning"
	ElseIf tag == "prone"
		Return "Prone|Doggy"
	ElseIf tag == "matingpress"
		Return "MatingPress|Missionary"
	ElseIf tag == "lap"
		Return "Lap|Sitting"
	ElseIf tag == "carry"
		Return "Holding|Standing"
	ElseIf tag == "butterfly"
		Return "Butterfly|Missionary"
	ElseIf tag == "sixtynine"
		Return "69"
	ElseIf tag == "facesitting"
		Return "Facesitting"
	ElseIf tag == "spitroast"
		Return "Spitroast"
	ElseIf tag == "romantic"
		Return "Loving|Romance"
	ElseIf tag == "lustful"
		Return "Rough|Dirty"
	ElseIf tag == "dom"
		Return "Dominant|Rough"
	ElseIf tag == "femdom"
		Return "Femdom|Cowgirl"
	ElseIf tag == "foreplay"
		Return "Foreplay"
	ElseIf tag == "kissing"
		Return "Kissing"
	ElseIf tag == "hug"
		Return "Hugging|Cuddling"
	ElseIf tag == "dp"
		Return "DP|DoublePenetration"
	ElseIf tag == "femalemasturbation" || tag == "malemasturbation"
		Return "Masturbation"
	ElseIf tag == "vaginaltoying" || tag == "analtoying"
		Return "Dildo|Masturbation"
	EndIf
	Return ""
EndFunction
