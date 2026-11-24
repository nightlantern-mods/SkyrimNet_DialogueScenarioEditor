Scriptname SkyrimNet_DialogueScenarioEditorOS Hidden
{The mod's calls into OStim Standalone. Only the main script calls these, and only when OStim.esp is
installed: without OStim the types used here do not exist, so the main script names none of them.}

Bool Function IsInScene(Actor who) Global
	Return OActor.IsInOStim(who)
EndFunction

; Everyone near center (the center too, and the player), as OStim's own search finds them.
Actor[] Function Nearby(ObjectReference center, Float range) Global
	Return OActorUtil.GetActorsInRangeV2(center, range, true, true)
EndFunction

; A scene for the cast: one with any of the tags (scene tags first, then actions), else for one
; person a masturbation scene (soloActions), else any scene; on bedRef (None: without furniture).
; The scene is looked up for that bed's own furniture type (doublebed, singlebed, bedroll), as
; SkyrimNet Brothel does. 2026-11-24: twice a scene looked up for the parent type "bed" crashed the
; game in the player's behavior graph as it started on the bed; Brothel, looking up by the bed's own
; type, has not crashed (the suspected cause, not a proven one). excluded: scene IDs (or their
; beginnings) never to pick. "" when nothing fits.
String Function ChooseScene(Actor[] cast, String tags, String soloActions, ObjectReference bedRef, String[] excluded) Global
	String furn = ""
	If bedRef
		furn = OFurniture.GetFurnitureType(bedRef)
		If furn == ""
			Return ""
		EndIf
	EndIf
	Return PickScene(OActorUtil.Sort(cast, OActorUtil.EmptyArray()), tags, soloActions, furn, excluded)
EndFunction

; The bed's furniture type as OStim knows it (for the log).
String Function FurnitureType(ObjectReference ref) Global
	Return OFurniture.GetFurnitureType(ref)
EndFunction

; Starts sceneId for the cast. bedRef: on that bed (sceneId must be a bed scene); else bed 2 never
; on furniture, otherwise furniture as the player's OStim settings. Returns the thread ID; -2 when
; OStim refuses the cast.
Int Function StartWith(Actor[] cast, String sceneId, Int bed, ObjectReference bedRef) Global
	Actor[] sorted = OActorUtil.Sort(cast, OActorUtil.EmptyArray())
	Int builder = OThreadBuilder.Create(sorted)
	If builder < 0
		Return -2
	EndIf
	If bedRef
		OThreadBuilder.SetFurniture(builder, bedRef)
	ElseIf bed == 2
		OThreadBuilder.NoFurniture(builder)
	EndIf
	OThreadBuilder.SetStartingAnimation(builder, sceneId)
	Return OThreadBuilder.Start(builder)
EndFunction

; When the cast (all of them, no one else) is already in one running OStim scene: changes that
; scene to one for the tags on the same spot and furniture, without ending it (no standing up or
; redressing in between). Returns the new scene ID; "" when they are not in one scene together or
; no scene fits there (the caller then stops it and starts a new one).
String Function SwitchScene(Actor[] cast, String tags, String soloActions, String[] excluded) Global
	If cast.Length == 0 || !OActor.IsInOStim(cast[0])
		Return ""
	EndIf
	Int thread = OActor.GetThreadID(cast[0])
	If thread < 0 || !OThread.IsRunning(thread)
		Return ""
	EndIf
	Actor[] inThread = OThread.GetActors(thread)
	If inThread.Length != cast.Length
		Return ""
	EndIf
	Int i = 0
	While i < cast.Length
		If inThread.Find(cast[i]) < 0
			Return ""
		EndIf
		i += 1
	EndWhile
	String sceneId = PickScene(inThread, tags, soloActions, OThread.GetFurnitureType(thread), excluded)
	If sceneId == ""
		Return ""
	EndIf
	OThread.WarpTo(thread, sceneId, False)
	Return sceneId
EndFunction

; The scene the thread plays now; "" while it starts up or once it has ended.
String Function SceneOf(Int thread) Global
	Return OThread.GetScene(thread)
EndFunction

; Whether the scene ID is one the player excluded: it begins with one of the entries, so
; "BillyyCcg" covers BillyyCcg-1, BillyyCcg-2 and so on.
Bool Function IsExcluded(String sceneId, String[] excluded) Global
	Int i = 0
	While i < excluded.Length
		If excluded[i] != "" && StringUtil.Find(sceneId, excluded[i]) == 0
			Return True
		EndIf
		i += 1
	EndWhile
	Return False
EndFunction

; PickOnce, picked again (OStim picks at random) while it gives an excluded scene; "" when only
; excluded scenes came up.
String Function PickScene(Actor[] sorted, String tags, String soloActions, String furn, String[] excluded) Global
	Int tries = 0
	While tries < 20
		String sceneId = PickOnce(sorted, tags, soloActions, furn)
		If sceneId == "" || !IsExcluded(sceneId, excluded)
			Return sceneId
		EndIf
		Debug.Trace("[SkyrimNet_DialogueScenarioEditor] OStim scene " + sceneId + " is excluded, picking again")
		tries += 1
	EndWhile
	Return ""
EndFunction

; Tags that only say how a scene feels, not what happens in it: a scene with one of these alone does
; not fit the column (2026-11-24: "missionary,lustful,dom" got a 69 scene tagged only "dom").
String Function MoodTags() Global
	Return "romantic,lustful,dom"
EndFunction

; The tags without the mood tags.
String Function CoreTags(String tags) Global
	String[] given = PapyrusUtil.StringSplit(tags, ",")
	String[] moods = PapyrusUtil.StringSplit(MoodTags(), ",")
	String core = ""
	Int i = 0
	While i < given.Length
		If given[i] != "" && moods.Find(given[i]) < 0
			If core != ""
				core += ","
			EndIf
			core += given[i]
		EndIf
		i += 1
	EndWhile
	Return core
EndFunction

; A scene for the tags, the closest match first: all of the tags; all of the core tags (what
; happens: positions and acts); any core tag as a scene tag, then as an action; and only with
; moodOnly, any tag at all (a mood tag alone). On furniture of type furn ("" none). "" when none.
String Function TagMatch(Actor[] sorted, String furn, String tags, Bool moodOnly) Global
	String core = CoreTags(tags)
	String sceneId = AllSceneTags(sorted, furn, tags)
	If sceneId == "" && core != "" && core != tags
		sceneId = AllSceneTags(sorted, furn, core)
	EndIf
	If sceneId == "" && core != ""
		sceneId = AnySceneTag(sorted, furn, core)
	EndIf
	If sceneId == "" && core != ""
		sceneId = AnyAction(sorted, furn, core)
	EndIf
	If sceneId == "" && (moodOnly || core == "")
		sceneId = AnySceneTag(sorted, furn, tags)
		If sceneId == ""
			sceneId = AnyAction(sorted, furn, tags)
		EndIf
	EndIf
	Return sceneId
EndFunction

String Function AllSceneTags(Actor[] sorted, String furn, String tags) Global
	If furn == ""
		Return OLibrary.GetRandomSceneWithAllSceneTagsCSV(sorted, tags)
	EndIf
	Return OLibrary.GetRandomFurnitureSceneWithAllSceneTagsCSV(sorted, furn, tags)
EndFunction

String Function AnySceneTag(Actor[] sorted, String furn, String tags) Global
	If furn == ""
		Return OLibrary.GetRandomSceneWithAnySceneTagCSV(sorted, tags)
	EndIf
	Return OLibrary.GetRandomFurnitureSceneWithAnySceneTagCSV(sorted, furn, tags)
EndFunction

String Function AnyAction(Actor[] sorted, String furn, String types) Global
	If furn == ""
		Return OLibrary.GetRandomSceneWithAnyActionCSV(sorted, types)
	EndIf
	Return OLibrary.GetRandomFurnitureSceneWithAnyActionCSV(sorted, furn, types)
EndFunction

; A scene for the sorted cast, on furniture of that type ("" none). Without furniture: tags, else
; masturbation alone, else any scene. On furniture the same, but "any scene" only when no tags were
; given and for two or more (the tags matter more than the bed: "" lets the caller try again
; without the bed).
String Function PickOnce(Actor[] sorted, String tags, String soloActions, String furn) Global
	String sceneId = ""
	If tags != ""
		; On furniture a scene that only shares a mood tag does not count (the caller tries without).
		sceneId = TagMatch(sorted, furn, tags, furn == "")
		If furn != ""
			Return sceneId
		EndIf
	EndIf
	; Alone: most solo scenes are idles and intros, so "any scene" means masturbation here.
	If sceneId == "" && sorted.Length == 1
		If furn == ""
			sceneId = OLibrary.GetRandomSceneWithAnyActionCSV(sorted, soloActions)
		Else
			sceneId = OLibrary.GetRandomFurnitureSceneWithAnyActionCSV(sorted, furn, soloActions)
		EndIf
	EndIf
	If sceneId == ""
		If furn == ""
			sceneId = OLibrary.GetRandomScene(sorted)
		ElseIf sorted.Length > 1
			sceneId = OLibrary.GetRandomFurnitureScene(sorted, furn)
		EndIf
	EndIf
	Return sceneId
EndFunction

; The nearest free bed (bedroll, single or double bed: OStim's "bed" type and its subtypes) within
; radius of center that OStim has scenes for count actors on; None when there is none.
ObjectReference Function FindBed(Int count, ObjectReference center, Float radius) Global
	ObjectReference[] found = OFurniture.FindFurniture(count, center, radius, 0.0)
	Int i = 0
	While i < found.Length
		String type = OFurniture.GetFurnitureType(found[i])
		If type == "bed" || OFurniture.IsChildOf("bed", type)
			Return found[i]
		EndIf
		i += 1
	EndWhile
	Return None
EndFunction

Bool Function IsRunning(Int thread) Global
	Return OThread.IsRunning(thread)
EndFunction

; Stops the OStim scene the actor is in (everyone in it leaves it: OStim cannot take one actor out).
; Returns whether there was one.
Bool Function StopSceneOf(Actor who) Global
	If !OActor.IsInOStim(who)
		Return False
	EndIf
	Int thread = OActor.GetThreadID(who)
	If thread >= 0 && OThread.IsRunning(thread)
		OThread.Stop(thread)
		Return True
	EndIf
	Return False
EndFunction
