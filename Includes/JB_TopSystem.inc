#if defined _JB_TopSystem_included
 #endinput
#endif
#define _JB_TopSystem_included

/**
 * Creates a new top category to the core.
 * 
 * @param unique             Unique name of the top, used to be stored for the database.
 * @param name               Name of the top.
 * @param description        Description of the top, will be shown on the top detail.
 * @param counter            Points counter name, will be shown after the top points number.
 * @param defaultValue       An initial value for the category points to be set.
 * @return                  Top index.
 */
native int JB_CreateTopCategory(char[] unique, char[] name, char[] description, char[] counter, int defaultValue = 0);

/**
 * Finds and returns the top category index, by searching the index with the given unique.
 * 
 * @param unique              The unique for the specified top category.
 * @return                   Top category index, or -1 if there is no top category matching the given unique.
 */
native int JB_FindTopCategory(char[] unique);

/**
 * Gets a client points from a specific top category.
 * 
 * @param client             Client Index.
 * @param topId              Top categoty index to get the points from.
 * @return                  Client Points.
 * @error                  Invalid client index.
 */
native int JB_GetTopPoints(int client, int topId);

/**
 * Adds a points for a specific client.
 * 
 * @param client             Client Index.
 * @param topId              Top categoty index to add the points.
 * @param points             Points to be added.
 * @param broadcast          Print a chat message to the client, true by default.
 * @error                   Invalid client index, or invalid points amount.
 */
native void JB_AddTopPoints(int client, int topId, int points, bool broadcast = true);

/**
 * Removes a points for a specific client.
 * .
 * @param client             Client Index.
 * @param topId              Top categoty index to remove the points.
 * @param points             Points to be removed.
 * @param broadcast          Print a chat message to the client, true by default.
 * @error                   Invalid client index.
 */
native void JB_TakeTopPoints(int client, int topId, int points, bool broadcast = true);

/**
 * Shows to a certain client the top category menu by the given top index.
 * 
 * @param client             Client Index.
 * @param topId              Top categoty index to display the menu from.
 * @error                  Invalid client index.
 */
native void JB_ShowTopCategoryMenu(int client, int topId);

/**
 * Called when the top statistics has reset.
 * 
 * @param topId              Top category index.
 */
forward void JB_OnTopCategoryReset(int topId);

/**
 * Called when a client is accessing the top menu.
 *
 * @param client	Client index.
 * @param menu		Service menu handle.
 */
forward void JB_OnTopMenu(int client, Menu menu);

/**
 * Called when a client had selected a vehicles garage service.
 *
 * @param client	Client index.
 * @param item_pos	Selected menu item position index.
 * @param menu		Service menu handle.
 */
forward void JB_OnTopMenuSelect(int client, int item_pos, Menu menu);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_TopSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateTopCategory");
	MarkNativeAsOptional("JB_FindTopCategory");
	MarkNativeAsOptional("JB_GetTopPoints");
	MarkNativeAsOptional("JB_AddTopPoints");
	MarkNativeAsOptional("JB_TakeTopPoints");
	MarkNativeAsOptional("JB_ShowTopCategoryMenu");
}
#endif

public SharedPlugin __pl_JB_TopSystem = 
{
	name = "JB_TopSystem", 
	file = "JB_TopSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
}; 