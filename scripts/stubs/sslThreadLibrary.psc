Scriptname sslThreadLibrary extends Quest
{compile-only stub of SexLab P+ and 1.6x; never deployed}

ObjectReference[] Function FindBeds(ObjectReference akCenterRef, Float afRadius = 4096.0, Float afRadiusZ = 512.0) Native Global
Int Function GetBedTypeImpl(ObjectReference akReference) Native Global
Bool Function IsBed(ObjectReference akReference) Native Global
; SexLab 1.6x
Int Function GetBedType(ObjectReference BedRef)
	Return 0
EndFunction
