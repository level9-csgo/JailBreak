#if defined _JB_CellsSystem_included
 #endinput
#endif
#define _JB_CellsSystem_included

/**
 * Opens all the cells on the current map.
 *
 * @noreturn
 */
native void JB_OpenCells();

/**
 * Closes all the cells on the current map.
 *
 * @noreturn
 */
native void JB_CloseCells();

/**
 * Checks if the current map's jail doors are opened.
 * 
 * @return          True if the cells are opened, false otherwise.
 */
native bool JB_IsCellsOpened();

/**
 * Checks if the current map's jail doors are opened.
 * 
 * @param mapName    Map name to check.
 * @return          True if the map cells are configurated, false if not.
 */
native bool JB_IsMapCellsConfigurated(char[] mapName);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_CellsSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_OpenCells");
	MarkNativeAsOptional("JB_CloseCells");
	MarkNativeAsOptional("JB_IsCellsOpened");
	MarkNativeAsOptional("JB_IsMapCellsConfigurated");
}
#endif

public SharedPlugin __pl_JB_CellsSystem = 
{
	name = "JB_CellsSystem", 
	file = "JB_CellsSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 