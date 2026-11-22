Scriptname SexLabUtil
{compile-only stub of SexLab P+ and 1.6x; never deployed}

SexLabFramework Function GetAPI() Global
	Return None
EndFunction

; 1.6x returns its own version (16601 for 1.66b); P+ returns its SKSE plugin's version.
Int Function GetVersion() Global
	Return 0
EndFunction
