Scriptname SexLabFramework extends Quest
{compile-only stub of SexLab P+ and 1.6x; never deployed}

SexLabThread Function StartScene(Actor[] akPositions, String asTags, Actor akSubmissive = none, ObjectReference akCenter = none, int aiFurniture = 1, String asHook = "")
	Return None
EndFunction

ObjectReference Function FindBed(ObjectReference CenterRef, Float Radius = 1000.0, Bool IgnoreUsed = True, ObjectReference IgnoreRef1 = None, ObjectReference IgnoreRef2 = None)
	Return None
EndFunction

Bool Function IsBedAvailable(ObjectReference BedRef)
	Return False
EndFunction

Bool Function IsActorActive(Actor ActorRef)
	Return False
EndFunction

SexLabThread Function StartSceneEx(Actor[] akPositions, String[] asScenes, Actor akSubmissive = none, String asContext = "", ObjectReference akCenter = none, int aiFurniture = 1, String asHook = "")
	Return None
EndFunction

; SexLab 1.6x API, kept by P+ for older mods; only skyrimnet_BrothelSL16 calls these.
sslThreadLibrary Property ThreadLib Auto

Int Function StartSex(Actor[] Positions, sslBaseAnimation[] Anims, Actor Victim = none, ObjectReference CenterOn = none, Bool AllowBed = true, String Hook = "")
	Return -1
EndFunction

sslBaseAnimation[] Function GetAnimationsByTags(Int ActorCount, String Tags, String TagSuppress = "", Bool RequireAll = true)
	Return None
EndFunction

sslBaseAnimation[] Function GetAnimationsByType(Int ActorCount, Int Males = -1, Int Females = -1, Int StageCount = -1, Bool Aggressive = false, Bool Sexual = true)
	Return None
EndFunction

Int Function GetGender(Actor ActorRef)
	Return 0
EndFunction

; Both SexLab P+ and 1.6x.
sslThreadController Function GetActorController(Actor ActorRef)
	Return None
EndFunction

sslThreadController Function GetController(Int tid)
	Return None
EndFunction
