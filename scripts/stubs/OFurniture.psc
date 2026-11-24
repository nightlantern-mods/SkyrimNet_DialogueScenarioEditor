ScriptName OFurniture
{compile-only stub of OStim Standalone; never deployed}

string Function GetFurnitureType(ObjectReference FurnitureRef) Global Native
bool Function IsChildOf(string SuperType, string SubType) Global Native
ObjectReference[] Function FindFurniture(int ActorCount, ObjectReference CenterRef, float Radius, float SameFloor = 0.0) Global Native
