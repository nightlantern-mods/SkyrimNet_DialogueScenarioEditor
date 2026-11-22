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

; Starts a scene for the cast: one with any of the tags (scene tags first, then actions), else for
; one person a masturbation scene (soloActions), else any scene. Furniture (beds etc.) follows the
; player's OStim settings. Returns the thread ID; -1 when no scene fits, -2 when OStim refuses the cast.
Int Function StartScene(Actor[] cast, String tags, String soloActions) Global
	Actor[] sorted = OActorUtil.Sort(cast, OActorUtil.EmptyArray())
	String sceneId = ""
	If tags != ""
		sceneId = OLibrary.GetRandomSceneWithAnySceneTagCSV(sorted, tags)
		If sceneId == ""
			sceneId = OLibrary.GetRandomSceneWithAnyActionCSV(sorted, tags)
		EndIf
	EndIf
	; Alone: most solo scenes are idles and intros, so "any scene" means masturbation here.
	If sceneId == "" && sorted.Length == 1
		sceneId = OLibrary.GetRandomSceneWithAnyActionCSV(sorted, soloActions)
	EndIf
	If sceneId == ""
		sceneId = OLibrary.GetRandomScene(sorted)
	EndIf
	If sceneId == ""
		Return -1
	EndIf
	Debug.Trace("[SkyrimNet_DialogueScenarioEditor] OStim scene " + sceneId)
	Int builder = OThreadBuilder.Create(sorted)
	If builder < 0
		Return -2
	EndIf
	OThreadBuilder.SetStartingAnimation(builder, sceneId)
	Return OThreadBuilder.Start(builder)
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
