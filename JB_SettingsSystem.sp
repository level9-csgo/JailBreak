#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <JailBreak>
#include <JB_SettingsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define ABORT_SYMBOL "-1"

#define MAX_COOKIE_NAME_LENGTH 30
#define MAX_COOKIE_DESC_LENGTH 100

//====================//

enum struct Category
{
	char szName[64];
	char szDesc[256];
	int iPosition;
}

enum struct Setting
{
	char szCookieName[MAX_COOKIE_NAME_LENGTH];
	char szDisplayName[64];
	char szCategory[64];
	Cookie cCookie;
	SettingType iSettingType;
	any aMaxValue;
	char szDefaultValue[16];
}

enum struct Client
{
	bool bIsWrite;
	int iLookingSettingId;
	
	void Reset() {
		this.bIsWrite = false;
		this.iLookingSettingId = -1;
	}
	
	void Set(bool isWrite, int settingId) {
		this.bIsWrite = isWrite;
		this.iLookingSettingId = settingId;
	}
}

Client g_esClientsData[MAXPLAYERS + 1];

ArrayList g_arCategoriesData;
ArrayList g_arSettingsData;

GlobalForward g_fwdOnClientSettingChange;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Settings System", 
	author = PLUGIN_AUTHOR, 
	description = "Provides a settings system, sorted with custom categories and different setting types.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_arCategoriesData = new ArrayList(sizeof(Category));
	g_arSettingsData = new ArrayList(sizeof(Setting));
	
	RegConsoleCmd("sm_settings", Command_Settings, "Access the settings main menu.");
	RegConsoleCmd("sm_s", Command_Settings, "Access the settings main menu. (An Alias)");
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	g_esClientsData[client].Reset();
}

public void OnClientCookiesCached(int client)
{
	char szCookieValue[16];
	Setting CurrentSettingData;
	
	for (int iCurrentSetting = 0; iCurrentSetting < g_arSettingsData.Length; iCurrentSetting++)
	{
		CurrentSettingData = GetSettingByIndex(iCurrentSetting);
		CurrentSettingData.cCookie.Get(client, szCookieValue, sizeof(szCookieValue));
		
		if (!szCookieValue[0])
		{
			SetSettingValue(client, iCurrentSetting, CurrentSettingData.szDefaultValue, true);
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (!g_esClientsData[client].bIsWrite || g_esClientsData[client].iLookingSettingId == -1) {
		return Plugin_Continue;
	}
	
	if (StrEqual(szArgs, ABORT_SYMBOL)) {
		PrintToChat(client, "%s Operation has \x02aborted\x01.", PREFIX);
		g_esClientsData[client].Reset();
		return Plugin_Handled;
	}
	
	char szNewValue[16];
	Setting SettingData; SettingData = GetSettingByIndex(g_esClientsData[client].iLookingSettingId);
	
	switch (SettingData.iSettingType)
	{
		case Setting_Int:
		{
			if (!IsStringNumric(szArgs)) {
				PrintToChat(client, "%s You have specifed an invalid \x0Csettings\x01 value! [\x02%s\x01]", PREFIX_ERROR, szArgs);
				g_esClientsData[client].Reset();
				return Plugin_Handled;
			}
			
			int iValue = StringToInt(szArgs);
			if (iValue < 0) {
				PrintToChat(client, "%s Minimum \x0Csettings\x01 value is \x040\x01! [\x02%d\x01]", PREFIX_ERROR, iValue);
				g_esClientsData[client].Reset();
				return Plugin_Handled;
			}
			
			if (iValue > SettingData.aMaxValue) {
				PrintToChat(client, "%s Maximum \x0Csetting\x01 value is \x4%d\x01 [\x02%d\x01]", PREFIX_ERROR, SettingData.aMaxValue, iValue);
				g_esClientsData[client].Reset();
				return Plugin_Handled;
			}
			
			IntToString(iValue, szNewValue, sizeof(szNewValue));
		}
		case Setting_Float:
		{
			if (!IsStringFloat(szArgs)) {
				PrintToChat(client, "%s You have specifed an invalid \x0Csettings\x01 value! [\x02%s\x01]", PREFIX, szArgs);
				g_esClientsData[client].Reset();
				return Plugin_Handled;
			}
			
			float fValue = StringToFloat(szArgs);
			if (fValue < 0.0) {
				PrintToChat(client, "%s Minimum \x0Csettings\x01 value is \x040.0\x01! [\x02%.2f\x01]", PREFIX_ERROR, fValue);
				g_esClientsData[client].Reset();
				return Plugin_Handled;
			}
			
			if (fValue > SettingData.aMaxValue) {
				PrintToChat(client, "%s Maximum \x0Csetting\x01 value is \x4%.2f\x01 [\x02%.2f\x01]", PREFIX_ERROR, SettingData.aMaxValue, fValue);
				g_esClientsData[client].Reset();
				return Plugin_Handled;
			}
			
			Format(szNewValue, sizeof(szNewValue), "%.2f", fValue);
		}
	}
	
	if (SetSettingValue(client, g_esClientsData[client].iLookingSettingId, szNewValue))
	{
		PrintToChat(client, "%s Value \x04%s\x01 successfully set to setting \x0C%s\x01!", PREFIX, szNewValue, SettingData.szDisplayName);
	}
	
	if (SettingData.szCategory[0]) {
		showSettingsMenu(client, GetCategoryByName(SettingData.szCategory));
	} else {
		showSettingsMainMenu(client);
	}
	
	g_esClientsData[client].Reset();
	return Plugin_Handled;
}

//================================[ Commands ]================================//

public Action Command_Settings(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1) {
			/* Automated message from SourceMod. */
			return Plugin_Handled;
		}
		
		showSettingsMainMenu(iTargetIndex);
	}
	else {
		RequestFrame(RF_ShowMenu, client);
	}
	
	return Plugin_Handled;
}

void RF_ShowMenu(int client)
{
	showSettingsMainMenu(client);
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_CreateSettingCategory", Native_CreateSettingCategory);
	CreateNative("JB_CreateSetting", Native_CreateSetting);
	CreateNative("JB_FindSettingCategory", Native_FindSettingCategory);
	CreateNative("JB_FindSetting", Native_FindSetting);
	CreateNative("JB_GetClientSetting", Native_GetClientSetting);
	CreateNative("JB_SetClientSetting", Native_SetClientSetting);
	
	g_fwdOnClientSettingChange = new GlobalForward("JB_OnClientSettingChange", ET_Event, Param_Cell, Param_Cell, Param_String, Param_String, Param_Cell);
	
	RegPluginLibrary("JB_SettingsSystem");
	return APLRes_Success;
}

public int Native_CreateSettingCategory(Handle plugin, int numParams)
{
	Category CategoryData;
	GetNativeString(1, CategoryData.szName, sizeof(CategoryData.szName));
	
	if (GetCategoryByName(CategoryData.szName) != -1) {
		return;
	}
	
	GetNativeString(2, CategoryData.szDesc, sizeof(CategoryData.szDesc));
	CategoryData.iPosition = GetNativeCell(3);
	
	g_arCategoriesData.PushArray(CategoryData, sizeof(CategoryData));
	g_arCategoriesData.SortCustom(SortCategoriesADTA);
}

public int Native_CreateSetting(Handle plugin, int numParams)
{
	int iStringLength;
	GetNativeStringLength(1, iStringLength);
	
	if (iStringLength >= MAX_COOKIE_NAME_LENGTH) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid cookie name length (Got: %d, Max: %d)", iStringLength, MAX_COOKIE_NAME_LENGTH);
	}
	
	Setting SettingData;
	GetNativeString(1, SettingData.szCookieName, sizeof(SettingData.szCookieName));
	
	if (GetSettingByCookieName(SettingData.szCookieName) != -1) {
		return GetSettingByCookieName(SettingData.szCookieName);
	}
	
	GetNativeStringLength(2, iStringLength);
	if (iStringLength >= MAX_COOKIE_DESC_LENGTH) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid cookie description length (Got: %d, Max: %d)", iStringLength, MAX_COOKIE_DESC_LENGTH);
	}
	
	char szCookieDesc[MAX_COOKIE_DESC_LENGTH];
	GetNativeString(2, szCookieDesc, sizeof(szCookieDesc));
	
	SettingData.cCookie = new Cookie(SettingData.szCookieName, szCookieDesc, CookieAccess_Private); // Creates the setting's cookie
	
	GetNativeString(3, SettingData.szDisplayName, sizeof(SettingData.szDisplayName));
	
	GetNativeString(4, SettingData.szCategory, sizeof(SettingData.szCategory));
	
	SettingData.iSettingType = view_as<SettingType>(GetNativeCell(5));
	
	SettingData.aMaxValue = GetNativeCell(6);
	
	GetNativeString(7, SettingData.szDefaultValue, sizeof(SettingData.szDefaultValue));
	
	int iSettingId = g_arSettingsData.PushArray(SettingData, sizeof(SettingData));
	
	char szSettingValue[16];
	if (SettingData.szDefaultValue[0])
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				SettingData.cCookie.Get(iCurrentClient, szSettingValue, sizeof(szSettingValue));
				
				if (!szSettingValue[0])
				{
					SetSettingValue(iCurrentClient, iSettingId, SettingData.szDefaultValue, true);
				}
			}
		}
	}
	
	return iSettingId;
}

public int Native_FindSettingCategory(Handle plugin, int numParams)
{
	char szName[64];
	GetNativeString(1, szName, sizeof(szName));
	return GetCategoryByName(szName);
}

public int Native_FindSetting(Handle plugin, int numParams)
{
	char szCookieName[MAX_COOKIE_NAME_LENGTH];
	GetNativeString(1, szCookieName, sizeof(szCookieName));
	return GetSettingByCookieName(szCookieName);
}

public int Native_GetClientSetting(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int iSettingId = GetNativeCell(2);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	if (!(0 <= iSettingId < g_arSettingsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid setting index (Got: %d, Max: %d)", iSettingId, g_arSettingsData.Length);
	}
	
	char szCookieValue[16];
	GetSettingByIndex(iSettingId).cCookie.Get(client, szCookieValue, sizeof(szCookieValue));
	SetNativeString(3, szCookieValue, GetNativeCell(4));
	
	return 0;
}

public int Native_SetClientSetting(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int iSettingId = GetNativeCell(2);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	if (!(0 <= iSettingId < g_arSettingsData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid setting index (Got: %d, Max: %d)", iSettingId, g_arSettingsData.Length);
	}
	
	char szNewValue[16];
	GetNativeString(3, szNewValue, sizeof(szNewValue));
	
	if (StringToInt(szNewValue) < 0) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid specified value (%s)", szNewValue);
	}
	
	SetSettingValue(client, iSettingId, szNewValue);
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	JB_WriteLogLine("Setting \"%s\" has changed to player \"%L\" to value %s by plugin %s.", GetSettingByIndex(iSettingId).szDisplayName, client, szNewValue, szFileName);
	
	return 0;
}

//================================[ Menus ]================================//

void showSettingsMainMenu(int client)
{
	char szItem[128], szItemInfo[8];
	Menu menu = new Menu(Handler_SettingsMain);
	menu.SetTitle("%s Settings System - Main Menu\n ", PREFIX_MENU);
	
	for (int iCurrentCategory = 0; iCurrentCategory < g_arCategoriesData.Length; iCurrentCategory++)
	{
		Format(szItemInfo, sizeof(szItemInfo), "%d:%d", iCurrentCategory, 1);
		Format(szItem, sizeof(szItem), "[C] %s", GetCategoryByIndex(iCurrentCategory).szName);
		menu.AddItem(szItemInfo, szItem);
	}
	
	Setting CurrentSettingData;
	
	for (int iCurrentSetting = 0; iCurrentSetting < g_arSettingsData.Length; iCurrentSetting++)
	{
		CurrentSettingData = GetSettingByIndex(iCurrentSetting);
		if (CurrentSettingData.szCategory[0]) {
			continue;
		}
		
		// Adds a spacer to separate categories and settings.
		if (menu.ItemCount == g_arCategoriesData.Length && g_arCategoriesData.Length) {
			menu.AddItem("", "", ITEMDRAW_SPACER);
		}
		
		Format(szItemInfo, sizeof(szItemInfo), "%d:%d", iCurrentSetting, 0);
		switch (CurrentSettingData.iSettingType)
		{
			case Setting_Int:Format(szItem, sizeof(szItem), "%d", GetCookieValue(client, iCurrentSetting));
			case Setting_Float:Format(szItem, sizeof(szItem), "%.2f", GetCookieValue(client, iCurrentSetting));
			case Setting_Bool:Format(szItem, sizeof(szItem), "%s", GetCookieValue(client, iCurrentSetting) == 1 ? "ON":"OFF");
		}
		
		Format(szItem, sizeof(szItem), "%s - %s", CurrentSettingData.szDisplayName, szItem);
		menu.AddItem(szItemInfo, szItem);
	}
	
	if (!menu.ItemCount) {
		menu.AddItem("", "No setting or category was found.", ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_SettingsMain(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[16];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		
		char szData[2][32];
		ExplodeString(szItem, ":", szData, sizeof(szData), sizeof(szData[]));
		
		int iItemIndex = StringToInt(szData[0]);
		bool bIsCategory = StringToInt(szData[1]) == 1;
		
		if (bIsCategory) {
			showSettingsMenu(client, iItemIndex);
		} else {
			ChangeSettingValue(client, iItemIndex);
		}
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

/* Sort Custom cretead by LuqS */

public int SortCategoriesADTA(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList arSort = view_as<ArrayList>(array);
	
	Category Struct1; arSort.GetArray(index1, Struct1, sizeof(Struct1));
	Category Struct2; arSort.GetArray(index2, Struct2, sizeof(Struct2));
	
	int iReturn;
	if (Struct1.iPosition == -1) {
		iReturn = (Struct2.iPosition == -1) ? 0 : 1;
	}
	else {
		iReturn = (Struct2.iPosition > Struct1.iPosition || Struct2.iPosition == -1) ? -1 : 1;
	}
	
	return iReturn;
}

void showSettingsMenu(int client, int iCategoryId)
{
	char szItem[128], szItemInfo[16];
	Menu menu = new Menu(Handler_Settings);
	
	Category CategoryData; CategoryData = GetCategoryByIndex(iCategoryId);
	menu.SetTitle("%s Settings System - Viewing Category \"%s\"\n• %s\n\n ", PREFIX_MENU, CategoryData.szName, CategoryData.szDesc);
	
	Setting CurrentSettingData;
	for (int iCurrentSetting = 0; iCurrentSetting < g_arSettingsData.Length; iCurrentSetting++)
	{
		CurrentSettingData = GetSettingByIndex(iCurrentSetting);
		if (GetCategoryByName(CurrentSettingData.szCategory) != iCategoryId) {
			continue;
		}
		
		IntToString(iCurrentSetting, szItemInfo, sizeof(szItemInfo));
		switch (CurrentSettingData.iSettingType)
		{
			case Setting_Int:Format(szItem, sizeof(szItem), "%d", GetCookieValue(client, iCurrentSetting));
			case Setting_Float:Format(szItem, sizeof(szItem), "%.2f", GetCookieValue(client, iCurrentSetting));
			case Setting_Bool:Format(szItem, sizeof(szItem), "%s", GetCookieValue(client, iCurrentSetting) == 1 ? "ON":"OFF");
		}
		
		Format(szItem, sizeof(szItem), "%s - %s", CurrentSettingData.szDisplayName, szItem);
		menu.AddItem(szItemInfo, szItem);
	}
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Settings(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[16];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		ChangeSettingValue(client, StringToInt(szItem));
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		showSettingsMainMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

//================================[ Functions ]================================//

int GetCategoryByName(const char[] name)
{
	return g_arCategoriesData.FindString(name);
}

any[] GetCategoryByIndex(int index)
{
	Category CategoryData;
	g_arCategoriesData.GetArray(index, CategoryData, sizeof(CategoryData));
	return CategoryData;
}

int GetSettingByCookieName(const char[] name)
{
	return g_arSettingsData.FindString(name);
}

any[] GetSettingByIndex(int index)
{
	Setting SettingData;
	g_arSettingsData.GetArray(index, SettingData, sizeof(SettingData));
	return SettingData;
}

void ChangeSettingValue(int client, int settingId)
{
	Setting SettingData; SettingData = GetSettingByIndex(settingId);
	
	switch (SettingData.iSettingType)
	{
		case Setting_Bool:
		{
			SetSettingValue(client, settingId, GetCookieValue(client, settingId) == 1 ? "0":"1");
			
			if (SettingData.szCategory[0]) {
				showSettingsMenu(client, GetCategoryByName(SettingData.szCategory));
			} else {
				showSettingsMainMenu(client);
			}
		}
		default:
		{
			PrintToChat(client, "%s Write your desired \x0Csetting\x01 value, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			g_esClientsData[client].Set(true, settingId);
		}
	}
}

bool SetSettingValue(int client, int settingId, const char[] newValue, bool firstLoad = false)
{
	Call_StartForward(g_fwdOnClientSettingChange);
	
	Call_PushCell(client); // int client
	Call_PushCell(settingId); // int settingId
	
	Setting SettingData; SettingData = GetSettingByIndex(settingId);
	
	// const char[] oldValue
	char szOldValue[16];
	SettingData.cCookie.Get(client, szOldValue, sizeof(szOldValue));
	Call_PushString(szOldValue);
	
	char szNewValue[16];
	strcopy(szNewValue, sizeof(szNewValue), newValue);
	Call_PushStringEx(szNewValue, 16, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK); // char[] newValue
	
	Call_PushCell(firstLoad); // bool firstLoad
	
	Action fwdReturn; // Forward action return
	
	int iErrors = Call_Finish(fwdReturn);
	if (iErrors != SP_ERROR_NONE)
	{
		ThrowNativeError(iErrors, "Global Forward Failed - Error: %d", iErrors);
		return false;
	}
	
	if (fwdReturn >= Plugin_Handled)
	{
		return false;
	}
	
	// Apply Setting
	SettingData.cCookie.Set(client, szNewValue);
	
	if (firstLoad) {
		JB_WriteLogLine("Setting \"%s\" value has changed to \"%s\" for player \"%L\" by first loading.", SettingData.szDisplayName, SettingData.iSettingType == Setting_Bool ? GetCookieValue(client, settingId) == 1 ? "True":"False":szNewValue, client);
	}
	else {
		JB_WriteLogLine("Player \"%L\" has changed \"%s\" setting value to \"%s\".", client, SettingData.szDisplayName, SettingData.iSettingType == Setting_Bool ? GetCookieValue(client, settingId) == 1 ? "True":"False":szNewValue);
	}
	
	return true;
}

bool IsStringNumric(const char[] string)
{
	for (int iCurrentChar = 0; iCurrentChar < strlen(string); iCurrentChar++)
	{
		if (!IsCharNumeric(string[iCurrentChar])) {
			return false;
		}
	}
	return true;
}

bool IsStringFloat(const char[] string)
{
	bool bDotChecked = false;
	for (int iCurrentChar = 0; iCurrentChar < strlen(string); iCurrentChar++)
	{
		if (string[iCurrentChar] == '.') {
			if (bDotChecked) {
				return false;
			}
			bDotChecked = true;
		}
		if (!IsCharNumeric(string[iCurrentChar]) && string[iCurrentChar] != '.') {
			return false;
		}
	}
	return true;
}

any GetCookieValue(int client, int iSettingId)
{
	char szCookieValue[16];
	Setting SettingData; SettingData = GetSettingByIndex(iSettingId);
	SettingData.cCookie.Get(client, szCookieValue, sizeof(szCookieValue));
	
	switch (SettingData.iSettingType)
	{
		case Setting_Float:return StringToFloat(szCookieValue);
		default:return StringToInt(szCookieValue);
	}
}

//================================================================//