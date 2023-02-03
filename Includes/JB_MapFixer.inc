#if defined _JB_MapFixer_included
 #endinput
#endif
#define _JB_MapFixer_included

enum FixerType
{
	Fixer_Int = 0, 
	Fixer_Float, 
	Fixer_Bool
}

/**
 * Creates a map fixer setting to the core menu.
 * 
 * @param unique             A unique text for the map fixer.
 * @param name               Name of the map fixer, will be displayed inside the admin menu.
 * @param type       		 Map fixer value type, integer/boolean/float. See the enum above.
 * @param flag     			 Allowed admin flag to change the map fixer's value.
 * @param minValue       	 Minimum value available to be set, ignored if the fixer type is boolean.
 * @param maxValue       	 Maximum value available to be set, ignored if the fixer type is boolean.
 * @param defaultValue       Default value to be set once the fixer is created.
 *
 * @return                   Map fixer index.
 */
native int JB_CreateMapFixer(char[] unique, char[] name, FixerType type, AdminFlag flag, any minValue, any maxValue, any defaultValue = 0);

/**
 * Gets a map fixer setting value.
 * 
 * @param settingId          Map fixer index to get the value from.
 * @error                   Invalid given setting index.
 * @return  				Map fixer value.
 */
native any JB_GetMapFixer(int settingId);

/**
 * Finds and returns the map fixer index, by searching the index with the given unique.
 * 
 * @param unique        	 The unique for the map fixer.
 * @return                  Map fixer index, or -1 if there is no fixer matching the given unique.
 */
native int JB_FindMapFixer(char[] unique);

/**
 * Called when an administrator has changed a map fixer setting value.
 * 
 * @param client              Changer Client index.
 * @param settingId           The setting index that's being changed.
 * @param oldValue            The old setting value.
 * @param newValue            The new (current) setting value.
 *
 * @return					  Plugin_Handled or higher to block the change.
 */
forward Action JB_OnMapFixerChange(int client, int settingId, any &oldValue, any &newValue);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_MapFixer_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateMapFixer");
	MarkNativeAsOptional("JB_GetMapFixer");
	MarkNativeAsOptional("JB_FindMapFixer");
}
#endif

public SharedPlugin __pl_JB_MapFixer = 
{
	name = "JB_MapFixer", 
	file = "JB_MapFixer.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
}; 