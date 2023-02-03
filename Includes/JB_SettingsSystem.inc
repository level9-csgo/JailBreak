#if defined _JB_SettingsSystem_included
 #endinput
#endif
#define _JB_SettingsSystem_included

enum SettingType
{
	Setting_Int = 0, 
	Setting_Float, 
	Setting_Bool
}

/**
 * Creates a settings category to the core menu.
 * 
 * @param name               Name of the category.
 * @param description        Description of the category.
 * @param menuPosition       Item position in the menu, -1 will push the item into the end of the menu.
 *
 * @return                  Category index.
 */
native void JB_CreateSettingCategory(char[] name, char[] description, int menuPosition = -1);

/**
 * Creates a settings to a specific category inside the core menu.
 * 
 * @param cookieName         The setting's cookie name, max cookie name length is 32.
 * @param cookieDesc         The setting's cookie description, max cookie description length is 100.
 * @param displayName        A display name that will be shown on the settings menu.
 * @param categoryName       Associated category name, or empty to display the setting inside the main menu.
 * @param type               Setting value type, integer/boolean/float. See the enum above.
 * @param maxValue       	 Maximum value available to be set, ignored if the setting type is boolean.
 * @param defaultValue       Default value to be set once the cookie is cached.
 * 
 * @return                  Setting index.
 * @error                  Invalid cookie name/description length.
 */
native int JB_CreateSetting(char[] cookieName, char[] cookieDesc, char[] displayName, char[] categoryName, SettingType type, any maxValue, char[] defaultValue = "");

/**
 * Finds and returns the setting category index, by searching the index with the given name.
 * 
 * @param name               The name for the specified setting category.
 * @return                  Setting category index, or -1 if there is no setting category matching the given name.
 */
native int JB_FindSettingCategory(char[] name);

/**
 * Finds and returns the setting index, by searching the index with the given cookie name.
 * 
 * @param cookieName         The cookie name for the setting.
 * @return                  Setting index, or -1 if there is no setting matching the given cookie name.
 */
native int JB_FindSetting(char[] cookieName);

/**
 * Gets a client's setting value.
 * 
 * @param client             Client index.
 * @param settingId          Setting index to get the value from.
 * @param buffer     		 Destination string buffer.
 * @param maxlen	     	 Maximum length of output string buffer.
 * @error                  If the client is not connected/specified invalid setting index, an error will be thrown.
 */
native void JB_GetClientSetting(int client, int settingId, char[] buffer, int maxlen);

/**
 * Sets a client's setting value.
 * 
 * @param client             Client index.
 * @param settingId          Setting index to set the value.
 * @param value              The new setting value to be change to.
 * @error                   If the client is not connected/specified invalid setting index, an error will be thrown.
 */
native void JB_SetClientSetting(int client, int settingId, char[] value);

/**
 * Called when a client setting's value has changed.
 * 
 * @param client              Client index.
 * @param settingId           The setting index that's being changed.
 * @param oldValue            The old setting value.
 * @param newValue            The new (current) setting value.
 * @param firstLoad			  True if this is the first load. (value from the database)
 *
 * @return					Plugin_Handled or higher to block the change.
 */
forward Action JB_OnClientSettingChange(int client, int settingId, const char[] oldValue, char[] newValue, bool firstLoad);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_SettingsSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateSettingCategory");
	MarkNativeAsOptional("JB_CreateSetting");
	MarkNativeAsOptional("JB_FindSettingCategory");
	MarkNativeAsOptional("JB_FindSetting");
	MarkNativeAsOptional("JB_GetClientSetting");
	MarkNativeAsOptional("JB_SetClientSetting");
}
#endif

public SharedPlugin __pl_JB_SettingsSystem = 
{
	name = "JB_SettingsSystem", 
	file = "JB_SettingsSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
};
