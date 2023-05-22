#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GuardsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

enum struct Client
{
	int iAccountID;
	
	char szName[MAX_NAME_LENGTH];
	char szAdminName[MAX_NAME_LENGTH];
	int iAdminImmunity;
	int iBanTime;
	int iExpire;
	char szReason[128];
	
	void Reset(bool resetStructure = true) {
		if (resetStructure)
		{
			this.iAccountID = 0;
			this.szName[0] = '\0';
		}
		
		this.szAdminName[0] = '\0';
		this.iAdminImmunity = 0;
		this.iBanTime = 0;
		this.iExpire = 0;
		this.szReason[0] = '\0';
	}
	
	void AddBanCT(int adminIndex, int length, const char[] reason = "") {
		if (adminIndex != -1) {
			GetClientName(adminIndex, this.szAdminName, sizeof(Client::szAdminName));
		} else {
			this.szAdminName[0] = '\0';
		}
		this.iAdminImmunity = adminIndex == -1 ? 1:GetAdminImmunityLevel(GetUserAdmin(adminIndex));
		this.iBanTime = GetTime();
		this.iExpire = GetTime() + (length * 60);
		strcopy(this.szReason, sizeof(Client::szReason), reason);
		TrimString(this.szReason);
		
	}
	
	bool CheckBan() {
		if (this.iExpire == 0) {
			return false;
		}
		else if (this.iExpire - GetTime() <= 0) {
			this.Reset(false);
			return false;
		}
		
		return true;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

Database g_Database = null;

GlobalForward g_fwdOnBanCTExecuted;

ConVar g_cvMinimumBanLength;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - CT Bans", 
	author = PLUGIN_AUTHOR, 
	description = "Provides to ban client from being a guard for a specific time, part of the guards system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null) {
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	g_cvMinimumBanLength = CreateConVar("jb_minimum_banct_length", "5", "Minimum length in minutes for ban a client from being a gurad.", _, true, 5.0, true, 30.0);
	
	AutoExecConfig(true, "CTBans", "JailBreak");
	
	LoadTranslations("common.phrases");
	
	RegAdminCmd("sm_addbanct", Command_AddBanCT, ADMFLAG_BAN, "Ban CT a client, means that client cannot join the guards team.");
	RegAdminCmd("sm_abc", Command_AddBanCT, ADMFLAG_BAN, "Ban CT a client, means that client cannot join the guards team. (An Alias)");
	RegAdminCmd("sm_banctlist", Command_BanCTList, ADMFLAG_BAN, "Access the banned ct players menu.");
	RegAdminCmd("sm_bcl", Command_BanCTList, ADMFLAG_BAN, "Access the banned ct players menu. (An Alias)");
	
	RegConsoleCmd("sm_banct", Command_BanCT, "Allows to clients check their status about their ban ct.");
}

public void OnPluginEnd()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			OnClientDisconnect(current_client);
		}
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	g_ClientsData[client].Reset();
	
	if (!IsFakeClient(client))
	{
		if (!(g_ClientsData[client].iAccountID = GetSteamAccountID(client)))
		{
			KickClient(client, "Verification error, please reconnect.");
			return;
		}
		
		GetClientName(client, g_ClientsData[client].szName, sizeof(g_ClientsData[].szName));
		
		SQL_FetchUser(client);
	}
}

public void OnClientDisconnect(int client)
{
	if (!IsFakeClient(client))
	{
		SQL_UpdateUser(client);
	}
}

//================================[ Commands ]================================//

public Action Command_AddBanCT(int client, int args)
{
	if (args < 2)
	{
		PrintToChat(client, "%s Usage: \x04/addbanct\x01 <name|#userid> <minutes> <reason>", PREFIX);
		return Plugin_Handled;
	}
	
	char szArg[MAX_NAME_LENGTH], szArg2[32], szArg3[128];
	
	GetCmdArg(1, szArg, sizeof(szArg));
	GetCmdArg(2, szArg2, sizeof(szArg2));
	
	if (args > 2) {
		GetCmdArgString(szArg3, sizeof(szArg3));
		ReplaceString(szArg3, sizeof(szArg3), szArg, "", true);
		ReplaceString(szArg3, sizeof(szArg3), szArg2, "", true);
	}
	
	int iTargetIndex = FindTarget(client, szArg, true, true);
	int iLength = StringToInt(szArg2);
	
	if (iTargetIndex == -1) {
		// Automated message
		return Plugin_Handled;
	}
	if (g_ClientsData[iTargetIndex].CheckBan()) {
		PrintToChat(client, "%s Player \x02%N\x01 is already banned from being a guard.", PREFIX, iTargetIndex);
		return Plugin_Handled;
	}
	
	if (!iLength || iLength < g_cvMinimumBanLength.IntValue) {
		PrintToChat(client, "%s You have specified an \x02invalid\x01 time, minimum ban length is \x4%d\x01 minutes.", PREFIX, g_cvMinimumBanLength.IntValue);
		return Plugin_Handled;
	}
	
	g_ClientsData[iTargetIndex].AddBanCT(client, iLength, szArg3);
	
	Call_StartForward(g_fwdOnBanCTExecuted);
	Call_PushCell(iTargetIndex);
	Call_PushCell(client);
	Call_PushCell(iLength);
	Call_PushString(szArg3);
	Call_Finish();
	
	PrintToChatAll("%s \x04%N\x01 has banned \x02%N\x01 from being a guard for \x03%d\x01 minutes.", PREFIX, client, iTargetIndex, iLength);
	PrintToChat(iTargetIndex, "%s \x02You have been banned\x01 from being a \x0Bguard\x01. Type \x04/banct\x01 to see additonal information about your ban.", PREFIX);
	
	if (GetClientTeam(iTargetIndex) == CS_TEAM_CT)
	{
		ChangeClientTeam(iTargetIndex, CS_TEAM_T);
	}
	
	return Plugin_Handled;
}

public Action Command_BanCTList(int client, int args)
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
		
		if (GetUserAdmin(iTargetIndex) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s Ban CT List menu allowed for administrators only.", PREFIX_ERROR);
		} else {
			showBanCTListMenu(iTargetIndex);
		}
	}
	else {
		showBanCTListMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Command_BanCT(int client, int args)
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
		
		showBanCTMenu(iTargetIndex, iTargetIndex);
	}
	else {
		showBanCTMenu(client, client);
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void showBanCTListMenu(int client)
{
	char szItem[MAX_NAME_LENGTH], szItemInfo[32];
	Menu menu = new Menu(Handler_BanCTList);
	menu.SetTitle("%s Ban CT List -\n ", PREFIX_MENU);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client)) {
			Format(szItem, sizeof(szItem), "%N [%s]", current_client, g_ClientsData[current_client].CheckBan() ? "BANNED":"Not Banned");
			IntToString(current_client, szItemInfo, sizeof(szItemInfo));
			menu.AddItem(szItemInfo, szItem);
		}
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_BanCTList(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iTargetIndex = StringToInt(szItem);
		showBanCTMenu(client, iTargetIndex);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void showBanCTMenu(int client, int iTargetIndex)
{
	char szItem[MAX_NAME_LENGTH], szItemInfo[32];
	Menu menu = new Menu(Handler_BanCT);
	
	FormatTime(szItem, sizeof(szItem), "%d/%m/%Y - %H:%M:%S", g_ClientsData[iTargetIndex].iExpire);
	menu.SetTitle("%s Ban CT - Viewing \"%N\"\n \n• Status: %s\n• Expire Date: %s\n• Banned By: %s\n• Ban Reason: %s%s", PREFIX_MENU, iTargetIndex, 
		g_ClientsData[iTargetIndex].CheckBan() ? "BANNED":"Not Banned", 
		g_ClientsData[iTargetIndex].CheckBan() ? szItem:"Not Banned", 
		g_ClientsData[iTargetIndex].CheckBan() ? g_ClientsData[iTargetIndex].szAdminName:"Not Banned", 
		!g_ClientsData[iTargetIndex].CheckBan() ? "Not Banned":g_ClientsData[iTargetIndex].szReason[0] == '\0' ? "No Reason Specified":g_ClientsData[iTargetIndex].szReason, 
		GetUserAdmin(client) != INVALID_ADMIN_ID ? "\n ":""
		);
	
	if (GetUserAdmin(client) != INVALID_ADMIN_ID) {
		IntToString(iTargetIndex, szItemInfo, sizeof(szItemInfo));
		Format(szItem, sizeof(szItem), "Unban Player%s", g_ClientsData[iTargetIndex].CheckBan() ? "":" [Not Banned]");
		menu.AddItem(szItemInfo, szItem, g_ClientsData[iTargetIndex].CheckBan() ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	int iItemCount = menu.ItemCount;
	for (int iCurrentItem = 0; iCurrentItem < (6 - iItemCount); iCurrentItem++) {
		menu.AddItem("", "", ITEMDRAW_NOTEXT); // Fix the back button gap.
	}
	
	menu.ExitBackButton = (GetUserAdmin(client) != INVALID_ADMIN_ID);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_BanCT(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iTargetIndex = StringToInt(szItem);
		
		if (!g_ClientsData[iTargetIndex].CheckBan())
		{
			PrintToChat(client, "%s The selected player is no logner \x02banned\x01!", PREFIX_ERROR);
			return 0;
		}
		
		if (GetAdminImmunityLevel(GetUserAdmin(client)) < g_ClientsData[iTargetIndex].iAdminImmunity) {
			PrintToChat(client, "%s The ban ct on \x04%N\x01 was unable to be removed due to being banned by a higher administrator!", PREFIX, iTargetIndex);
		} else {
			g_ClientsData[iTargetIndex].Reset(false);
			PrintToChatAll("%s Admin \x04%N\x01 has deleted \x0E%N's\x01 Ban CT.", PREFIX, client, iTargetIndex);
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		showBanCTListMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_AddBanCT", Native_AddBanCT);
	CreateNative("JB_IsClientBannedCT", Native_IsClientBannedCT);
	
	g_fwdOnBanCTExecuted = CreateGlobalForward("JB_OnBanCTExecuted", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_String);
	
	return APLRes_Success;
}

public int Native_AddBanCT(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	if (g_ClientsData[client].CheckBan()) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client \x02%N\x01 is already banned from being a guard.", client);
	}
	
	int iAdminIndex = GetNativeCell(2);
	
	if (iAdminIndex < 1 || iAdminIndex > MaxClients && iAdminIndex != -1) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid admin index (%d)", client);
	}
	if (!IsClientConnected(iAdminIndex) && iAdminIndex != -1) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Admin %d is not connected", client);
	}
	
	int iLength = GetNativeCell(3);
	
	char szReason[128];
	GetNativeString(4, szReason, sizeof(szReason));
	
	g_ClientsData[client].AddBanCT(iAdminIndex, iLength, szReason);
	
	Call_StartForward(g_fwdOnBanCTExecuted);
	Call_PushCell(client);
	Call_PushCell(iAdminIndex);
	Call_PushCell(iLength);
	Call_PushString(szReason);
	Call_Finish();
	
	return 0;
}

public int Native_IsClientBannedCT(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_ClientsData[client].CheckBan();
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `jb_ban_ct` (`account_id` INT NOT NULL, `banct_admin_name` VARCHAR(128) NOT NULL, `banct_admin_immunity` INT NOT NULL, `banct_ban_time` INT NOT NULL, `banct_expire` INT NOT NULL, `banct_reason` VARCHAR(128) NOT NULL)");
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

void SQL_FetchUser(int client)
{
	char szQuery[256];
	g_Database.Format(szQuery, sizeof(szQuery), "SELECT `banct_admin_name`, `banct_admin_immunity`, `banct_ban_time`, `banct_expire`, `banct_reason` FROM `jb_ban_ct` WHERE `account_id` = '%d'", g_ClientsData[client].iAccountID);
	g_Database.Query(SQL_FetchUser_CB, szQuery, GetClientSerial(client));
}

public void SQL_FetchUser_CB(Database db, DBResultSet results, const char[] error, any serial)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	int client = GetClientFromSerial(serial);
	
	if (!client)
	{
		return;
	}
	
	if (results.FetchRow())
	{
		results.FetchString(0, g_ClientsData[client].szAdminName, sizeof(g_ClientsData[].szAdminName));
		g_ClientsData[client].iAdminImmunity = results.FetchInt(1);
		g_ClientsData[client].iBanTime = results.FetchInt(2);
		g_ClientsData[client].iExpire = results.FetchInt(3);
		results.FetchString(4, g_ClientsData[client].szReason, sizeof(g_ClientsData[].szReason));
	}
	else
	{
		char szQuery[128];
		g_Database.Format(szQuery, sizeof(szQuery), "INSERT INTO `jb_ban_ct` (`account_id`) VALUES ('%d')", g_ClientsData[client].iAccountID);
		g_Database.Query(SQL_CheckForErrors, szQuery);
	}
}

void SQL_UpdateUser(int client)
{
	char szQuery[128];
	g_Database.Format(szQuery, sizeof(szQuery), "SELECT * FROM `jb_ban_ct` WHERE `account_id` = '%d'", g_ClientsData[client].iAccountID);
	g_Database.Query(SQL_UpdateUser_CB, szQuery, client);
}

public void SQL_UpdateUser_CB(Database db, DBResultSet results, const char[] error, int client)
{
	if (error[0])
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	if (results.FetchRow())
	{
		char szQuery[512];
		g_Database.Format(szQuery, sizeof(szQuery), "UPDATE `jb_ban_ct` SET `banct_admin_name` = '%s', `banct_admin_immunity` = %d, `banct_ban_time` = %d, `banct_expire` = %d, `banct_reason` = '%s' WHERE `account_id` = '%d'", 
			g_ClientsData[client].szAdminName, 
			g_ClientsData[client].iAdminImmunity, 
			g_ClientsData[client].iBanTime, 
			g_ClientsData[client].iExpire, 
			g_ClientsData[client].szReason, 
			g_ClientsData[client].iAccountID
			);
		g_Database.Query(SQL_CheckForErrors, szQuery);
	}
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (error[0])
	{
		LogError("Databse error, (%s)", error);
		return;
	}
}

//================================================================//