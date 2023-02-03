#if defined _JB_SpecialMods_included
 #endinput
#endif
#define _JB_SpecialMods_included

/**
 * Adds a special mod item to the core menu.
 * 
 * @param name               Name of the special mod.
 * @param description        Description of the special mod.
 *
 * @return                   Special mod index.
 */
native int JB_CreateSpecialMod(char[] name, char[] description);

/**
 * Finds and returns the special mod index, by searching the index with the given name.
 * 
 * @param name               The name for the specified special mod.
 * @return                   Special mod index, or -1 if there is no special mod matching the given name.
 */
native int JB_FindSpecialMod(char[] name);

/**
 * Returns the current running special mod index.
 * 
 * @return                   Current running special mod index, or -1 if no mod is running.
 */
native int JB_GetCurrentSpecialMod();

/**
 * Aborts the current running special mod.
 * 
 * @param execute_forward	 True to execute 'JB_OnSpecialModEnd' forward, false otherwise.
 *							 Note that if you are calling this native from the forward itself, 
 *							 this boolean must be FALSE to avoid INFINITE LOOP!
 *
 * @return 							True if the special mod has successfully aborted, false otherwise.
 */
native bool JB_AbortSpecialMod(bool execute_forward = true);

/**
 * Called once a special mod has executed by the current main guard.
 * 
 * @param client              The executer client index.
 * @param specialModId		  The executed special mod index.
 * @param bought			  True if the the main guard has bought the special mod, false if it executed by a vote.
 */
forward void JB_OnSpecialModExecute(int client, int specialModId, bool bought);

/**
 * Called once a special mod is ending.
 * 
 * @param specialModId		  The ended special mod index.
 */
forward void JB_OnSpecialModEnd(int specialModId);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_SpecialMods_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateSpecialMod");
	MarkNativeAsOptional("JB_FindSpecialMod");
	MarkNativeAsOptional("JB_GetCurrentSpecialMod");
	MarkNativeAsOptional("JB_AbortSpecialMod");
}
#endif

public SharedPlugin __pl_JB_SpecialMods = 
{
	name = "JB_SpecialMods", 
	file = "JB_SpecialMods.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 