Scriptname SkyrimNet_DialogueScenarioEditorSL16 Hidden
{The mod's calls into SexLab 1.6x (sslBaseAnimation lists, StartSex). Only the main script calls
these, and only when 1.6x is installed; SkyrimNet_DialogueScenarioEditorSLP holds the same function
for P+. Modelled on SkyrimNet Brothel's 1.6x code, written against SexLab 1.66b's sources; not tried
in game on 1.6x.}

; Starts a scene for the cast with up to 10 animations for the first of the tags (from a random one
; on) that has any, else for one person masturbation, else any animation SexLab finds. Returns the
; thread ID, or -1 when SexLab refuses.
Int Function StartScene(Quest api, Actor[] cast, String[] tags) Global
	SexLabFramework sexLab = api as SexLabFramework
	sslBaseAnimation[] found = new sslBaseAnimation[10]
	Int count = 0
	If tags.Length > 0
		Int start = Utility.RandomInt(0, tags.Length - 1)
		Int i = 0
		While i < tags.Length && count == 0
			count = Collect(sexLab, cast, tags[(start + i) % tags.Length], found, 10, 200)
			i += 1
		EndWhile
	EndIf
	If count == 0 && cast.Length == 1
		count = Collect(sexLab, cast, "Masturbation", found, 10, 200)
	EndIf
	If count == 0
		count = Collect(sexLab, cast, "", found, 10, 200)
	EndIf
	; The animation search takes a while; an actor unloaded meanwhile is not handed on.
	If !SkyrimNet_DialogueScenarioEditorSL.AllLoaded(cast)
		Return -1
	EndIf
	sslBaseAnimation[] anims = sslUtility.AnimationArray(count)
	Int k = 0
	While k < count
		anims[k] = found[k]
		k += 1
	EndWhile
	Return sexLab.StartSex(cast, anims, None, None, True, "")
EndFunction

; Fills into with up to limit of SexLab's animations for the cast, checked from a random start and
; at most maxChecks of them (0 for all); returns how many. An animation qualifies when it has the
; tag, is not aggressive, needs no special furniture and, for humans, has as many male and female
; positions as the cast has men and women (1.6x positions each take one sex).
Int Function Collect(SexLabFramework sexLab, Actor[] positions, String tag, sslBaseAnimation[] into, Int limit, Int maxChecks) Global
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
				&& (!humans || (anim.MaleCount() == males && anim.FemaleCount() == females))
			into[count] = anim
			count += 1
		EndIf
		index = (index + 1) % found.Length
		checks -= 1
	EndWhile
	Return count
EndFunction
