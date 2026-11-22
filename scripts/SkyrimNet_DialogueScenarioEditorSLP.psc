Scriptname SkyrimNet_DialogueScenarioEditorSLP Hidden
{The mod's calls into SexLab P+ (SexLabRegistry scenes, SexLabThread). Only the main script calls
these, and only when P+ is installed: under SexLab 1.6x the types used here do not exist.
SkyrimNet_DialogueScenarioEditorSL16 holds the same function for 1.6x. Modelled on SkyrimNet Brothel's
P+ code (tested there on P+).}

; Starts a scene for the cast: one with any of the tags (tried in a random order), else for one
; person a masturbation scene, else any scene. SexLab chooses the place (and a bed or furniture by
; its own settings). Returns the thread ID, or -1 when SexLab refuses or nothing fits.
Int Function StartScene(Quest api, Actor[] cast, String[] tags) Global
	SexLabFramework sexLab = api as SexLabFramework
	String[] scenes = PickScenes(cast, tags)
	If scenes.Length == 0 && cast.Length == 1
		String[] solo = new String[1]
		solo[0] = "Masturbation"
		scenes = PickScenes(cast, solo)
	EndIf
	; The scene search takes a while; an actor unloaded meanwhile is not handed on.
	If !SkyrimNet_DialogueScenarioEditorSL.AllLoaded(cast)
		Return -1
	EndIf
	SexLabThread thread
	If scenes.Length > 0
		thread = sexLab.StartSceneEx(cast, scenes, None, "", None, 1, "")
	Else
		thread = sexLab.StartScene(cast, "", None, None, 1, "")
	EndIf
	If !thread
		Return -1
	EndIf
	Return thread.GetThreadID()
EndFunction

; Scenes for the first of the tags (from a random one on) that SexLab has any for; none when no tag
; fits. For a man and a woman, scenes where one position takes only women and the other only men
; come first (SexLab may otherwise give the man the woman's part).
String[] Function PickScenes(Actor[] cast, String[] tags) Global
	String[] nothing
	If tags.Length == 0
		Return nothing
	EndIf
	Int start = Utility.RandomInt(0, tags.Length - 1)
	Int i = 0
	While i < tags.Length
		String tag = tags[(start + i) % tags.Length]
		String[] picked = OneSexPositionScenes(cast, tag)
		If picked.Length == 0
			picked = SexLabRegistry.LookupScenes(cast, tag, None, 1, None)
		EndIf
		If picked.Length > 0
			Debug.Trace("[SkyrimNet_DialogueScenarioEditor] SexLab P+: " + picked.Length + " scene(s) for tag " + tag)
			Return picked
		EndIf
		i += 1
	EndWhile
	Return nothing
EndFunction

Bool Function IsManAndWoman(Actor[] positions) Global
	If positions.Length != 2
		Return False
	EndIf
	Int sexA = SexLabRegistry.GetSex(positions[0], False)
	Int sexB = SexLabRegistry.GetSex(positions[1], False)
	Return (sexA == 0 && sexB == 1) || (sexA == 1 && sexB == 0)
EndFunction

; Up to 10 scenes with the tag, out of at most 80 checked from a random start, in which one position
; takes only women and the other only men; none for other casts or when no such scene is found.
String[] Function OneSexPositionScenes(Actor[] positions, String tag) Global
	String[] picked
	If !IsManAndWoman(positions)
		Return picked
	EndIf
	String[] found = SexLabRegistry.LookupScenes(positions, tag, None, 1, None)
	If found.Length == 0
		Return picked
	EndIf
	picked = new String[10]
	Int count = 0
	Int checks = found.Length
	If checks > 80
		checks = 80
	EndIf
	Int index = Utility.RandomInt(0, found.Length - 1)
	While checks > 0 && count < 10
		Int[] sexes = SexLabRegistry.GetPositionSexA(found[index])
		If sexes.Length == 2
			Int a = Math.LogicalAnd(sexes[0], 0x3)
			Int b = Math.LogicalAnd(sexes[1], 0x3)
			If (a == 0x1 && b == 0x2) || (a == 0x2 && b == 0x1)
				picked[count] = found[index]
				count += 1
			EndIf
		EndIf
		index = (index + 1) % found.Length
		checks -= 1
	EndWhile
	Return Utility.ResizeStringArray(picked, count)
EndFunction
