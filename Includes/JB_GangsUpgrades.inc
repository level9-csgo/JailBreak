#if defined _JB_GangsUpgrades_included
 #endinput
#endif
#define _JB_GangsUpgrades_included

/**
 * Creates a new gang upgrade.
 * 
 * @param unique             A unique name for the upgrade, used to be sorted in the database.
 * @param upgradeName        Gang upgrade name, will be shown in the gang menu.
 * @param upgradeDesc        Gang upgrade description, will be shown in the gang menu.
 *
 * @return                  Gang upgrade index.
 */
native int JB_CreateGangUpgrade(char[] unique, char[] upgradeName, char[] upgradeDesc);

/**
 * Creates a new gang upgrade level.
 * 
 * @param upgradeIndex       Gang upgrade index for the level to be added.
 * @param levelPrice         The price of the created level.
 *
 * @return					 The amount of levels for the specified upgrade index.
 * @error 					 Invalid gang upgrade index.
 */
native int JB_CreateGangUpgradeLevel(int upgradeIndex, int levelPrice);

/**
 * Gets a gang upgrade level.
 * 
 * @param gangIndex       Gang index to get the upgrade from.
 * @param upgradeIndex    Upgrade index to get the level from.
 
 * @return               Gang upgrade level.
 * @error 			     Invalid gang index/upgrade index.
 */
native int JB_GetGangUpgradeLevel(int gangIndex, int upgradeIndex);

/**
 * Finds and returns the gang upgrade index, by searching the index with the given unique.
 * 
 * @param unique             The unique name for the specified gang upgrade.
 * @return                   Gang upgrade index, or -1 if there is no gang upgrade matching the given unique.
 */
native int JB_FindGangUpgrade(char[] unique);

/**
 * Toggles a certain gang upgrade, controls whenther the upgrade will function or not.
 * 
 * @param upgradeIndex      Upgrade index to toggle.
 * @param toggleMode        Toggle mode to set the upgrade as.
 *
 * @return                 True in successful, false if a error has occurred.
 */
native bool JB_ToggleGangUpgrade(int upgradeIndex, bool toggleMode);

/**
 * Called when a client has upgraded a gang upgrade.
 * 
 * @param client       		 Client index.
 * @param upgradeIndex       Index of the upgrade.
 * @param level        		 The new upgrade's level.
 */
forward void JB_OnUpgradeUpgraded(int client, int upgradeIndex, int level);

/**
 * Called when a gang upgrade has changed his activity mode. (Change by the native 'JB_ToggleGangUpgrade')
 * 
 * @param upgradeIndex      Toggled upgrade index.
 * @param toggleMode        Toggle mode that has set to the upgrade.
 */
forward void JB_OnUpgradeToggle(int upgradeIndex, bool toggleMode);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_GangsUpgrades_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateGangUpgrade");
	MarkNativeAsOptional("JB_CreateGangUpgradeLevel");
	MarkNativeAsOptional("JB_GetGangUpgradeLevel");
	MarkNativeAsOptional("JB_FindGangUpgrade");
	MarkNativeAsOptional("JB_ToggleGangUpgrade");
}
#endif

public SharedPlugin __pl_JB_GangsUpgrades = 
{
	name = "JB_GangsUpgrades", 
	file = "JB_GangsUpgrades.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 