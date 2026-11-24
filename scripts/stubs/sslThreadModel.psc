Scriptname sslThreadModel extends Quest Hidden
{compile-only stub of SexLab P+ and 1.6x; never deployed}

; Both P+ and 1.6x.
Actor[] Property Positions Auto
Int Property Stage Auto

; SexLab P+: the scene playing now.
String Function GetActiveScene()
	Return ""
EndFunction

; SexLab 1.6x: the animation playing now.
sslBaseAnimation Property Animation Auto

; SexLab P+: plays the scene instead of the active one; False when it does not fit these actors.
Bool Function ResetScene(String asScene)
	Return False
EndFunction

; SexLab 1.6x
Function SetAnimations(sslBaseAnimation[] AnimationList)
EndFunction

Function SetForcedAnimations(sslBaseAnimation[] AnimationList)
EndFunction

sslBaseAnimation[] Function GetForcedAnimations()
	Return None
EndFunction
