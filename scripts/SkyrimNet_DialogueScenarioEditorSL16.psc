Scriptname SkyrimNet_DialogueScenarioEditorSL16 Hidden
{The mod's calls into SexLab 1.6x (sslBaseAnimation lists, StartSex). Only the main script calls
these, and only when 1.6x is installed; SkyrimNet_DialogueScenarioEditorSLP holds the same function
for P+. Modelled on SkyrimNet Brothel's 1.6x code, written against SexLab 1.66b's sources; not tried
in game on 1.6x.}

; Starts a scene for the cast with up to 10 animations for the first of the tags (in SL.TryOrder's order) that has any, else for one person masturbation, else any animation SexLab finds; excluded
; animations (registry name or name beginning with an entry of excluded) left out. Returns the
; thread ID, or -1 when SexLab refuses or nothing is left. bed: 0 a bed as SexLab's own settings,
; 1 centred on bedRef (without one, as 0), 2 no bed.
Int Function StartScene(Quest api, Actor[] cast, String[] tags, Int bed, ObjectReference bedRef, String[] excluded) Global
	SexLabFramework sexLab = api as SexLabFramework
	sslBaseAnimation[] anims = Gather(sexLab, cast, tags, excluded, True)
	; The animation search takes a while; an actor unloaded meanwhile is not handed on.
	If anims.Length == 0 || !SkyrimNet_DialogueScenarioEditorSL.AllLoaded(cast)
		Return -1
	EndIf
	If bed != 1
		bedRef = None
	EndIf
	Return sexLab.StartSex(cast, anims, None, bedRef, bed != 2, "")
EndFunction

; When the cast (all of them, no one else) is already in one SexLab scene: gives it animations for
; the tags (as StartScene picks them) and plays one of them from its first stage, without ending the
; scene. Returns whether it did; False when they are not in one scene together or nothing fits the
; tags. Written against 1.66b's sources (as SkyrimNet SexLab switches animations); not tried in game.
Bool Function SwitchScene(Quest api, Actor[] cast, String[] tags, String[] excluded) Global
	SexLabFramework sexLab = api as SexLabFramework
	sslThreadController thread = SkyrimNet_DialogueScenarioEditorSL.SharedThread(api, cast)
	If !thread
		Return False
	EndIf
	sslBaseAnimation[] anims = Gather(sexLab, thread.Positions, tags, excluded, tags.Length == 0)
	If anims.Length == 0
		Return False
	EndIf
	sslBaseAnimation[] forced = thread.GetForcedAnimations()
	If forced && forced.Length > 0
		thread.SetForcedAnimations(anims)
	Else
		thread.SetAnimations(anims)
	EndIf
	; SetAnimation keeps the stage number (clamped to the new animation's last): start from stage 1.
	If thread.Stage > 1
		thread.GoToStage(1)
	EndIf
	thread.SetAnimation(-1)
	Return True
EndFunction

; The animation the thread plays now, by its registry name ("" when there is no such thread).
String Function ActiveScene(Quest api, Int threadId) Global
	sslThreadController thread = (api as SexLabFramework).GetController(threadId)
	If !thread || !thread.Animation
		Return ""
	EndIf
	Return thread.Animation.Registry
EndFunction

; The same for the thread the actor is in.
String Function ActiveSceneOf(Quest api, Actor who) Global
	sslThreadController thread = (api as SexLabFramework).GetActorController(who)
	If !thread || !thread.Animation
		Return ""
	EndIf
	Return thread.Animation.Registry
EndFunction

; Up to 10 animations for the first of the tags (in SL.TryOrder's order: what happens first, mood tags last) that has any, else for one
; person masturbation, else (with anyScene) any; none when nothing is left.
sslBaseAnimation[] Function Gather(SexLabFramework sexLab, Actor[] positions, String[] tags, String[] excluded, Bool anyScene) Global
	sslBaseAnimation[] found = new sslBaseAnimation[10]
	Int count = 0
	String[] order = SkyrimNet_DialogueScenarioEditorSL.TryOrder(tags)
	Int i = 0
	While i < order.Length && count == 0
		count = Collect(sexLab, positions, order[i], found, 10, 200, excluded)
		i += 1
	EndWhile
	If count == 0 && positions.Length == 1
		count = Collect(sexLab, positions, "Masturbation", found, 10, 200, excluded)
	EndIf
	If count == 0 && anyScene
		count = Collect(sexLab, positions, "", found, 10, 200, excluded)
	EndIf
	sslBaseAnimation[] anims = sslUtility.AnimationArray(count)
	Int k = 0
	While k < count
		anims[k] = found[k]
		k += 1
	EndWhile
	Return anims
EndFunction

; Fills into with up to limit of SexLab's animations for the cast, checked from a random start and
; at most maxChecks of them (0 for all); returns how many. An animation qualifies when it has the
; tag, is not aggressive, needs no special furniture, is not excluded and, for humans, has as many
; male and female positions as the cast has men and women (1.6x positions each take one sex).
Int Function Collect(SexLabFramework sexLab, Actor[] positions, String tag, sslBaseAnimation[] into, Int limit, Int maxChecks, String[] excluded) Global
	Int males = 0
	Int females = 0
	Int i = 0
	While i < positions.Length
		Int gender = sexLab.GetGender(positions[i])
		If gender == 0
			males += 1
		ElseIf gender == 1
			females += 1
		EndIf
		i += 1
	EndWhile
	Bool humans = males + females == positions.Length

	sslBaseAnimation[] found
	If tag == ""
		found = sexLab.GetAnimationsByType(positions.Length, -1, -1, -1, False, True)
	Else
		found = sexLab.GetAnimationsByTags(positions.Length, tag, "Aggressive")
	EndIf
	If !found || found.Length == 0
		Return 0
	EndIf
	Int checks = found.Length
	If maxChecks > 0 && checks > maxChecks
		checks = maxChecks
	EndIf
	Int count = 0
	Int index = Utility.RandomInt(0, found.Length - 1)
	While checks > 0 && count < limit
		sslBaseAnimation anim = found[index]
		If anim && !anim.HasTag("Aggressive") && !anim.HasTag("Furniture") \
				&& (!humans || (anim.MaleCount() == males && anim.FemaleCount() == females)) \
				&& !SkyrimNet_DialogueScenarioEditorSL.IsExcluded(anim.Registry, excluded) \
				&& !SkyrimNet_DialogueScenarioEditorSL.IsExcluded(anim.Name, excluded)
			into[count] = anim
			count += 1
		EndIf
		index = (index + 1) % found.Length
		checks -= 1
	EndWhile
	Return count
EndFunction
