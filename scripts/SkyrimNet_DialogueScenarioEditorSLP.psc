Scriptname SkyrimNet_DialogueScenarioEditorSLP Hidden
{The mod's calls into SexLab P+ (SexLabRegistry scenes, SexLabThread). Only the main script calls
these, and only when P+ is installed: under SexLab 1.6x the types used here do not exist.
SkyrimNet_DialogueScenarioEditorSL16 holds the same function for 1.6x. Modelled on SkyrimNet Brothel's
P+ code (tested there on P+).}

; Starts a scene for the cast: one with any of the tags (tried in a random order), else for one
; person a masturbation scene, else any scene. bed: 0 SexLab chooses the place (and a bed or
; furniture by its own settings), 1 on bedRef (without bedRef, or when SexLab has no scene there for
; the tags, as 0), 2 never on furniture. excluded: scene IDs (or their beginnings) never to play.
; Returns the thread ID, or -1 when SexLab refuses or nothing fits.
Int Function StartScene(Quest api, Actor[] cast, String[] tags, Int bed, ObjectReference bedRef, String[] excluded) Global
	SexLabFramework sexLab = api as SexLabFramework
	Int furn = 1
	If bed == 2
		furn = 0
	EndIf
	String[] scenes
	If bed == 1 && bedRef
		; The tags matter more than the bed: any bed scene only when no tags were given.
		scenes = Pick(cast, tags, 2, bedRef, excluded, tags.Length == 0)
		If scenes.Length > 0
			furn = 2
		Else
			Debug.Trace("[SkyrimNet_DialogueScenarioEditor] SexLab P+: no scene on the bed for the tags")
			bedRef = None
		EndIf
	Else
		bedRef = None
	EndIf
	If furn != 2
		scenes = Pick(cast, tags, furn, None, excluded)
	EndIf
	; The scene search takes a while; an actor unloaded meanwhile is not handed on.
	If !SkyrimNet_DialogueScenarioEditorSL.AllLoaded(cast)
		Return -1
	EndIf
	If scenes.Length == 0
		Return -1
	EndIf
	SexLabThread thread = sexLab.StartSceneEx(cast, scenes, None, "", bedRef, furn, "")
	If !thread
		Return -1
	EndIf
	Return thread.GetThreadID()
EndFunction

; The scene the thread plays now ("" when there is no such thread).
String Function ActiveScene(Quest api, Int threadId) Global
	sslThreadController thread = (api as SexLabFramework).GetController(threadId)
	If !thread
		Return ""
	EndIf
	Return thread.GetActiveScene()
EndFunction

; When the cast (all of them, no one else) is already in one SexLab scene: plays a scene for the tags
; in it instead, without ending it (no standing up or redressing in between). Scenes on furniture are
; allowed, so one fits a scene already on a bed; P+ refuses those that do not fit, and the next is
; tried. Returns the scene ID; "" when they are not in one scene together or none fits.
String Function SwitchScene(Quest api, Actor[] cast, String[] tags, String[] excluded) Global
	sslThreadController thread = SkyrimNet_DialogueScenarioEditorSL.SharedThread(api, cast)
	If !thread
		Return ""
	EndIf
	Actor[] positions = thread.Positions
	String[] scenes = Pick(positions, tags, 1, None, excluded, tags.Length == 0)
	Int i = 0
	While i < scenes.Length && i < 10
		If thread.ResetScene(scenes[i])
			Return scenes[i]
		EndIf
		i += 1
	EndWhile
	Return ""
EndFunction

; Scenes for the tags, else for one person masturbation scenes, else (with anyScene) up to 60 of
; any scenes for the cast; the excluded ones left out. None when nothing is left.
String[] Function Pick(Actor[] cast, String[] tags, Int furn, ObjectReference center, String[] excluded, Bool anyScene = True) Global
	String[] scenes = SkyrimNet_DialogueScenarioEditorSL.WithoutExcluded(PickScenes(cast, tags, furn, center), excluded)
	If scenes.Length == 0 && cast.Length == 1
		String[] solo = new String[1]
		solo[0] = "Masturbation"
		scenes = SkyrimNet_DialogueScenarioEditorSL.WithoutExcluded(PickScenes(cast, solo, furn, center), excluded)
	EndIf
	If scenes.Length == 0 && anyScene
		String[] any = SkyrimNet_DialogueScenarioEditorSL.Sample(SexLabRegistry.LookupScenes(cast, "", None, furn, center), 60)
		scenes = SkyrimNet_DialogueScenarioEditorSL.WithoutExcluded(any, excluded)
	EndIf
	Return scenes
EndFunction

; Scenes for the first of the tags (in SL.TryOrder's order: what happens first, mood tags last) that SexLab has any for; none when no tag
; fits. For a man and a woman, scenes where one position takes only women and the other only men
; come first (SexLab may otherwise give the man the woman's part). furniture and center as
; SexLab's aiFurniture and akCenter.
String[] Function PickScenes(Actor[] cast, String[] tags, Int furn, ObjectReference center) Global
	String[] nothing
	If tags.Length == 0
		Return nothing
	EndIf
	String[] order = SkyrimNet_DialogueScenarioEditorSL.TryOrder(tags)
	Int i = 0
	While i < order.Length
		String tag = order[i]
		String[] picked = OneSexPositionScenes(cast, tag, furn, center)
		If picked.Length == 0
			picked = SexLabRegistry.LookupScenes(cast, tag, None, furn, center)
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
String[] Function OneSexPositionScenes(Actor[] positions, String tag, Int furn, ObjectReference center) Global
	String[] picked
	If !IsManAndWoman(positions)
		Return picked
	EndIf
	String[] found = SexLabRegistry.LookupScenes(positions, tag, None, furn, center)
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
