#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_CellsSystem>
#include <JB_SettingsSystem>
#include <JB_SpecialDays>
#include <JB_LrSystem>
#include <Misc_Ghost>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define INFO_UPDATE_DELAY 1.0

#define STARTLR_SOUND "lastrequest_activated.mp3"

#define COUNTDOWN_END_SOUND "ui/beep07"

#define DEFAULT_HEALTH 100

//====================//

enum struct LastRequest
{
	char szName[64];
	bool bWeaponPickup;
	bool bWeaponDrop;
	bool bActivateBeacons;
	bool bIncludeRandom;
}

GlobalForward g_fwdOnLrSelected;
GlobalForward g_fwdOnRandomLrSelected;
GlobalForward g_fwdOnLrStart;
GlobalForward g_fwdOnLrEnd;
GlobalForward g_fwdOnClientGiveLr;
GlobalForward g_fwdOnShowLrInfoMenu;

Handle g_hLrInfoTimer = INVALID_HANDLE;
Handle g_hBeaconTimer = INVALID_HANDLE;
Handle g_hCountdownTimer = INVALID_HANDLE;

ConVar g_cvStartLrCountdownTime;
ConVar g_cvCountdownSoundStartAt;

ArrayList g_arLrsData;

char g_szLrWeapon[64];

bool g_bContinueGame;
bool g_bIsLrRunning;
bool g_bIsLrPeriod;
bool g_bLastRequestGiven;

int g_iLrPlayers[Part_Max];

int g_iInfoMenuSettingId = -1;
int g_iSoundsSettingId = -1;
int g_iCountdownTime;
int g_iCurrentLr = -1;

int g_iBeamSprite = -1;
int g_iHaloSprite = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Last Request System", 
	author = PLUGIN_AUTHOR, 
	description = "Last request system for prisoners.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_arLrsData = new ArrayList(sizeof(LastRequest));
	
	g_cvStartLrCountdownTime = CreateConVar("jb_start_lr_countdown_time", "30", "Time in seconds for the last request countdown timer.", _, true, 30.0, true, 60.0);
	g_cvCountdownSoundStartAt = CreateConVar("jb_lr_countdown_sound_start_at", "5", "The time left for the lr countdown for the sound effect to be function, 0 to disable.", _, true, 0.0, true, g_cvStartLrCountdownTime.FloatValue);
	
	AutoExecConfig(true, "LrSystem", "JailBreak");
	
	LoadTranslations("common.phrases");
	
	RegConsoleCmd("sm_lastrequest", Command_LastRequest, "Access the last requests list menu.");
	RegConsoleCmd("sm_lr", Command_LastRequest, "Access the last requests list menu. (An Alias)");
	RegConsoleCmd("sm_givelr", Command_GiveLr, "Give to a prisoner the abillity to last request instead of you.");
	
	RegAdminCmd("sm_abortlr", Command_AbortLr, ADMFLAG_BAN, "Aborts the currect activeted last request.");
	RegAdminCmd("sm_delaylr", Command_DelayLr, ADMFLAG_BAN, "Delays the last request countdown timer.");
	
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
}

public void OnPluginEnd()
{
	ResetValues(false, false);
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SettingsSystem"))
	{
		JB_CreateSettingCategory("Global Settings", "This category is associated with settings that do not belong to certain things.", 1);
		g_iInfoMenuSettingId = JB_CreateSetting("setting_hide_lr_info", "Hide last request infomation menu to clients. (Bool setting)", "Hide Last Request Info", "Global Settings", Setting_Bool, 1);
		
		JB_CreateSettingCategory("Sound Settings", "This category is associated with sound in general, as well as music settings.");
		g_iSoundsSettingId = JB_CreateSetting("setting_lr_general_sounds", "Controls the last request general sounds volume. (Float setting)", "Last Request General Sounds", "Sound Settings", Setting_Float, 1.0, "0.5");
	}
}

public void OnMapStart()
{
	ResetValues(false, false);
	
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
}

public void OnClientDisconnect(int client)
{
	if (g_bIsLrRunning && (client == g_iLrPlayers[Part_Prisoner] || client == g_iLrPlayers[Part_Guard]))
	{
		ResetValues(false, false);
		PrintToChatAll("%s\x01 %N has disconnected, lr has \x02aborted\x01!", client == g_iLrPlayers[Part_Prisoner] ? " \x10Prisoner" : " \x0CGuard", client);
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int iVictimIndex = GetClientOfUserId(userid);
	
	if (g_bIsLrRunning && (iVictimIndex == g_iLrPlayers[Part_Prisoner] || iVictimIndex == g_iLrPlayers[Part_Guard]))
	{
		int iAttackerIndex = GetClientOfUserId(event.GetInt("attacker"));
		int iWinnerIndex = iAttackerIndex;
		
		if (iVictimIndex == iAttackerIndex)
		{
			iWinnerIndex = iVictimIndex == g_iLrPlayers[Part_Prisoner] ? g_iLrPlayers[Part_Guard]:g_iLrPlayers[Part_Prisoner];
			event.BroadcastDisabled = true;
		}
		
		if (!g_bContinueGame)
		{
			ResetValues(false, false, !iWinnerIndex ? INVALID_LR_WINNER:iWinnerIndex, iVictimIndex);
		}
		
		if (iVictimIndex == iAttackerIndex)
		{
			Event newEvent = CreateEvent("player_death");
			newEvent.SetInt("userid", GetClientUserId(iVictimIndex));
			newEvent.SetInt("attacker", GetClientUserId(iWinnerIndex == -1 ? iVictimIndex : iWinnerIndex));
			newEvent.SetString("weapon", g_szLrWeapon);
			newEvent.Fire();
			
			if (!g_bContinueGame)
			{
				g_szLrWeapon[0] = '\0';
			}
		}
	}
	
	RequestFrame(RF_GhostVerify, userid);
	
	return Plugin_Continue;
}

void RF_GhostVerify(int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client || JB_IsClientGhost(client))
	{
		return;
	}
	
	if (g_bIsLrPeriod)
	{
		DeleteAllTimers();
		PrintCenterTextAll("");
		g_bIsLrPeriod = false;
	}
	
	int iLastPrisonerAlive = GetLastPrisonerAlive();
	
	if (!g_bIsLrRunning && GetOnlineTeamCount(CS_TEAM_CT) >= 1 && GetOnlineTeamCount(CS_TEAM_T) == 1 && iLastPrisonerAlive != -1)
	{
		if (GetClientTeam(client) == CS_TEAM_T && !g_bLastRequestGiven)
		{
			PrintToChatAll(" \x04%N\x01 is the last \x10prisoner\x01 alive! Time for last request!", iLastPrisonerAlive);
		}
		
		if (!g_bContinueGame)
		{
			showLastRequestMenu(iLastPrisonerAlive);
			PerformCountdown();
		}
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(RF_CheckForSpawn, event.GetInt("userid"));
}

void RF_CheckForSpawn(int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client || JB_IsClientGhost(client))
	{
		return;
	}
	
	if (g_bIsLrPeriod && GetOnlineTeamCount(CS_TEAM_CT) >= 1 && GetOnlineTeamCount(CS_TEAM_T) > 1)
	{
		int iLastPrisonerAlive = -1;
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T && iCurrentClient != client)
			{
				iLastPrisonerAlive = iCurrentClient;
			}
		}
		
		if (iLastPrisonerAlive == -1)
		{
			return;
		}
		
		if (GetClientMenu(iLastPrisonerAlive) != MenuSource_None)
		{
			CancelClientMenu(iLastPrisonerAlive);
		}
		
		DeleteAllTimers();
		PrintCenterTextAll("");
		g_bIsLrPeriod = false;
		PrintToChatAll("%s Last Request period has disabled due to \x10prisoner\x01 spawn.", PREFIX);
	}
	
	if (g_bIsLrRunning && GetOnlineTeamCount(CS_TEAM_CT) >= 1 && GetOnlineTeamCount(CS_TEAM_T) > 1)
	{
		ResetValues(false, false);
		PrintToChatAll("%s Last Request has disabled due to \x10prisoner\x01 spawn.", PREFIX);
	}
}

Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bIsLrRunning)
	{
		ResetValues(false, false);
	}
	
	if (g_bIsLrPeriod)
	{
		DeleteAllTimers();
		PrintCenterTextAll("");
		g_bIsLrPeriod = false;
	}
	
	return Plugin_Continue;
}

Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bIsLrRunning)
	{
		ResetValues(false, false);
		return Plugin_Continue;
	}
	
	int iLastPrisonerAlive = GetLastPrisonerAlive();
	
	if (GetOnlineTeamCount(CS_TEAM_CT) >= 1 && GetOnlineTeamCount(CS_TEAM_T) == 1 && iLastPrisonerAlive != -1)
	{
		PrintToChatAll(" \x04%N\x01 is the last \x10prisoner\x01 alive! Time for last request!", iLastPrisonerAlive);
		showLastRequestMenu(iLastPrisonerAlive);
		PerformCountdown();
	}
	
	g_bLastRequestGiven = false;
	
	return Plugin_Continue;
}

Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bIsLrRunning)
	{
		ResetValues(false, false);
	}
	
	return Plugin_Continue;
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
	if (g_bIsLrRunning)
	{
		if (!GetLrByIndex(g_iCurrentLr).bWeaponDrop && (client == g_iLrPlayers[Part_Prisoner] || client == g_iLrPlayers[Part_Guard]))
		{
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnWeaponCanUse(int client, int weapon)
{
	if (g_bIsLrRunning && (client == g_iLrPlayers[Part_Prisoner] || client == g_iLrPlayers[Part_Guard])) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

//================================[ Commands ]================================//

public Action Command_LastRequest(int client, int args)
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
			// Automated message from SourceMod.
			return Plugin_Handled;
		}
		
		if (!IsLrAvailable(iTargetIndex, client))
		{
			return Plugin_Handled;
		}
		
		showLastRequestMenu(iTargetIndex);
	}
	else
	{
		if (!IsLrAvailable(client, client))
		{
			return Plugin_Handled;
		}
		
		showLastRequestMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Command_GiveLr(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID)
		{
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1)
		{
			// Automated message from SourceMod. 
			return Plugin_Handled;
		}
		
		if (!IsPlayerAlive(iTargetIndex) || GetClientTeam(iTargetIndex) != CS_TEAM_T)
		{
			PrintToChat(client, "%s Giving Last Request allowed to \x04alive\x01 prisoner only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		if (GetOnlineTeamCount(CS_TEAM_T) > 1 || GetOnlineTeamCount(CS_TEAM_CT) < 1)
		{
			PrintToChat(iTargetIndex, "%s Giving Last Request allowed only when there is \x041\x01 prisoner alive and atleast \x041\x01 guard alive.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		if (g_bIsLrRunning)
		{
			PrintToChat(client, "%s There is another Last Request game running!", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		if (g_bLastRequestGiven) {
			PrintToChat(client, "%s Last request already given, wait for the next game!", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		showGiveLrMenu(iTargetIndex);
	}
	else
	{
		if (!IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T) {
			PrintToChat(client, "%s Giving Last Request allowed to \x04alive\x01 prisoner only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		if (GetOnlineTeamCount(CS_TEAM_T) > 1 || GetOnlineTeamCount(CS_TEAM_CT) < 1) {
			PrintToChat(client, "%s Giving Last Request allowed only when there is \x041\x01 prisoner alive and atleast \x041\x01 guard alive.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		if (g_bIsLrRunning) {
			PrintToChat(client, "%s You are in a middle of another Last Request game!", PREFIX_ERROR);
			return Plugin_Handled;
		}
		if (g_bLastRequestGiven) {
			PrintToChat(client, "%s Last request already given, wait for the next game!", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		showGiveLrMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Command_AbortLr(int client, int args)
{
	if (!g_bIsLrRunning) {
		PrintToChat(client, "%s There is no last request game activated!", PREFIX);
		return Plugin_Handled;
	}
	
	ResetValues(true, true);
	
	int iLastPrisonerAlive = GetLastPrisonerAlive();
	if (iLastPrisonerAlive != -1) {
		showLastRequestMenu(iLastPrisonerAlive);
	}
	
	PrintToChatAll("%s Admin \x04%N\x01 has aborted the current activated last request!", PREFIX, client);
	
	if (GetOnlineTeamCount(CS_TEAM_T) == 1 && GetOnlineTeamCount(CS_TEAM_CT) >= 1) {
		PerformCountdown();
	}
	
	return Plugin_Handled;
}

public Action Command_DelayLr(int client, int args)
{
	if (args != 1) {
		PrintToChat(client, "%s Usage: \x04/delaylr\x01 <time>", PREFIX);
		return Plugin_Handled;
	}
	
	if (!g_bIsLrPeriod) {
		PrintToChat(client, "%s There is no last request period at the moment!", PREFIX);
		return Plugin_Handled;
	}
	
	char szArg[32];
	GetCmdArg(1, szArg, sizeof(szArg));
	int iSeconds = StringToInt(szArg);
	if (!iSeconds || g_iCountdownTime + iSeconds < 1)
	{
		PrintToChat(client, "%s You have specifed an invalid delay value. [\x02%s\x01]", PREFIX, szArg);
		return Plugin_Handled;
	}
	
	PrintToChatAll("%s Admin \x04%N\x01 has delayed the last request \x03countdown timer\x01 for \x02%d\x01 seconds", PREFIX, client, iSeconds);
	g_iCountdownTime += iSeconds;
	return Plugin_Handled;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_AddLr", Native_AddLr);
	CreateNative("JB_IsLrRunning", Native_IsLrRunning);
	CreateNative("JB_IsLrPeriodRunning", Native_IsLrPeriodRunning);
	CreateNative("JB_FindLr", Native_FindLr);
	CreateNative("JB_StopLr", Native_StopLr);
	CreateNative("JB_StartLr", Native_StartLr);
	CreateNative("JB_ShowLrMainMenu", Native_ShowLrMainMenu);
	
	g_fwdOnLrSelected = CreateGlobalForward("JB_OnLrSelected", ET_Event, Param_Cell, Param_Cell);
	g_fwdOnRandomLrSelected = CreateGlobalForward("JB_OnRandomLrSelected", ET_Event, Param_Cell, Param_Cell);
	g_fwdOnLrStart = CreateGlobalForward("JB_OnLrStart", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnLrEnd = CreateGlobalForward("JB_OnLrEnd", ET_Event, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnClientGiveLr = CreateGlobalForward("JB_OnClientGiveLr", ET_Event, Param_Cell, Param_Cell);
	g_fwdOnShowLrInfoMenu = CreateGlobalForward("JB_OnShowLrInfoMenu", ET_Event, Param_Cell, Param_Cell);
	
	RegPluginLibrary("JB_LrSystem");
	return APLRes_Success;
}

public int Native_AddLr(Handle plugin, int numParams)
{
	LastRequest LrData;
	GetNativeString(1, LrData.szName, sizeof(LrData.szName));
	
	int lr_index = GetLrByName(LrData.szName);
	if (lr_index != -1) {
		return lr_index;
	}
	
	LrData.bWeaponPickup = GetNativeCell(2);
	LrData.bWeaponDrop = GetNativeCell(3);
	LrData.bActivateBeacons = GetNativeCell(4);
	LrData.bIncludeRandom = GetNativeCell(5);
	
	return g_arLrsData.PushArray(LrData, sizeof(LrData));
}

public int Native_IsLrRunning(Handle plugin, int numParams)
{
	return g_bIsLrRunning;
}

public int Native_IsLrPeriodRunning(Handle plugin, int numParams)
{
	return g_bIsLrPeriod;
}

public int Native_FindLr(Handle plugin, int numParams)
{
	char szName[64];
	GetNativeString(1, szName, sizeof(szName));
	return g_arLrsData.FindString(szName);
}

public int Native_StopLr(Handle plugin, int numParams)
{
	if (g_iCurrentLr == -1 || !g_bIsLrRunning) {
		return false;
	}
	
	ResetValues(false, false);
	return true;
}

public int Native_StartLr(Handle plugin, int numParams)
{
	g_iLrPlayers[Part_Prisoner] = GetNativeCell(1);
	g_iLrPlayers[Part_Guard] = GetNativeCell(2);
	
	if (g_iLrPlayers[Part_Prisoner] != INVALID_LR_WINNER && g_iLrPlayers[Part_Prisoner] < 1 || g_iLrPlayers[Part_Prisoner] > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid prisoner index (%d)", g_iLrPlayers[Part_Prisoner]);
	}
	if (g_iLrPlayers[Part_Prisoner] != INVALID_LR_WINNER && !IsClientConnected(g_iLrPlayers[Part_Prisoner])) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Prisoner %d is not connected", g_iLrPlayers[Part_Prisoner]);
	}
	
	if (g_iLrPlayers[Part_Guard] != INVALID_LR_WINNER && g_iLrPlayers[Part_Guard] < 1 || g_iLrPlayers[Part_Guard] > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid guard index (%d)", g_iLrPlayers[Part_Guard]);
	}
	if (g_iLrPlayers[Part_Guard] != INVALID_LR_WINNER && !IsClientConnected(g_iLrPlayers[Part_Guard])) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Guard %d is not connected", g_iLrPlayers[Part_Guard]);
	}
	
	GetNativeString(3, g_szLrWeapon, sizeof(g_szLrWeapon));
	g_bContinueGame = GetNativeCell(4);
	
	LastRequest LrData; LrData = GetLrByIndex(g_iCurrentLr);
	
	if (!g_bContinueGame)
	{
		char szSettingValue[16], szSoundPath[PLATFORM_MAX_PATH];
		Format(szSoundPath, sizeof(szSoundPath), "%s/%s/%s", PARENT_SOUNDS_DIR, LRS_PARENT_SOUNDS_DIR, STARTLR_SOUND);
		
		float fSettingVolume;
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				JB_GetClientSetting(iCurrentClient, g_iSoundsSettingId, szSettingValue, sizeof(szSettingValue));
				fSettingVolume = StringToFloat(szSettingValue);
				
				if (fSettingVolume != 0.0) {
					EmitSoundToClient(iCurrentClient, szSoundPath, _, _, _, _, fSettingVolume);
				}
			}
		}
		
		PrintToChatAll(" \x04%N\x01 has started \x08%s\x01 against \x04%N\x01!", g_iLrPlayers[Part_Prisoner], LrData.szName, g_iLrPlayers[Part_Guard]);
	}
	
	if (!LrData.bWeaponPickup)
	{
		SDKHook(g_iLrPlayers[Part_Prisoner], SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
		SDKHook(g_iLrPlayers[Part_Guard], SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
	}
	
	JB_OpenCells();
	JB_TogglePrisonersMute(false, false);
	DeleteAllTimers();
	g_bIsLrRunning = true;
	g_bIsLrPeriod = false;
	
	PrintCenterTextAll("");
	showLrInfoPanel(FloatToInt(INFO_UPDATE_DELAY));
	g_hLrInfoTimer = CreateTimer(INFO_UPDATE_DELAY, Timer_UpdateLrInfoPanel, _, TIMER_REPEAT);
	
	if (LrData.bActivateBeacons)
	{
		g_hBeaconTimer = CreateTimer(1.0, Timer_BeaconPlayers, _, TIMER_REPEAT);
	}
	
	Call_StartForward(g_fwdOnLrStart);
	Call_PushCell(g_iCurrentLr);
	Call_PushCell(g_iLrPlayers[Part_Prisoner]);
	Call_PushCell(g_iLrPlayers[Part_Guard]);
	Call_Finish();
	
	return 0;
}

public int Native_ShowLrMainMenu(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	showLastRequestMenu(client);
	
	if (GetNativeCell(2))
	{
		PerformCountdown();
	}
	
	return 0;
}

//================================[ Menus ]================================//

void showLrInfoPanel(int time = MENU_TIME_FOREVER)
{
	Panel panel = new Panel();
	char szTitle[64];
	Format(szTitle, sizeof(szTitle), "%s Last Request - Information\n ", PREFIX_MENU);
	panel.SetTitle(szTitle);
	
	Call_StartForward(g_fwdOnShowLrInfoMenu);
	Call_PushCell(panel);
	Call_PushCell(g_iCurrentLr);
	Call_Finish();
	
	for (int iCurrentItem = 0; iCurrentItem < 7; iCurrentItem++) {
		panel.DrawItem("", ITEMDRAW_NOTEXT);
	}
	
	panel.DrawItem("", ITEMDRAW_SPACER);
	panel.DrawItem("Exit Forever");
	
	char szSettingValue[16];
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient))
		{
			JB_GetClientSetting(iCurrentClient, g_iInfoMenuSettingId, szSettingValue, sizeof(szSettingValue));
			
			if (StrEqual(szSettingValue, "0")) {
				panel.Send(iCurrentClient, Handler_LrInfo, time);
			}
		}
	}
	
	delete panel;
}

int Handler_LrInfo(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		JB_SetClientSetting(client, g_iInfoMenuSettingId, "1");
		PrintToChat(client, "%s You have \x02disabled\x01 the last request information menu. Type \x0C/settings\x01 to \x04enable\x01 it again.", PREFIX);
	}
	
	return 0;
}

void showLastRequestMenu(int client)
{
	char szItemInfo[16];
	Menu menu = new Menu(Handler_LastRequest);
	menu.SetTitle("%s Last Request - Choose A Game\n ", PREFIX_MENU);
	
	menu.AddItem("", "Random Lr");
	
	LastRequest CurrentLrData;
	for (int iCurrentLr = 0; iCurrentLr < g_arLrsData.Length; iCurrentLr++)
	{
		IntToString(iCurrentLr, szItemInfo, sizeof(szItemInfo));
		CurrentLrData = GetLrByIndex(iCurrentLr);
		menu.AddItem(szItemInfo, CurrentLrData.szName);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_LastRequest(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!IsLrAvailable(client, client))
		{
			return 0;
		}
		
		char szItem[16];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iLrId = -1;
		
		switch (itemNum)
		{
			case 0:
			{
				do
				{
					iLrId = GetRandomInt(0, g_arLrsData.Length - 1);
				} while (!GetLrByIndex(iLrId).bIncludeRandom);
			}
			default:iLrId = StringToInt(szItem);
		}
		
		DeleteAllTimers(false);
		g_iCurrentLr = iLrId;
		
		Call_StartForward(itemNum == 0 ? g_fwdOnRandomLrSelected:g_fwdOnLrSelected);
		Call_PushCell(client);
		Call_PushCell(iLrId);
		Call_Finish();
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void showGiveLrMenu(int client)
{
	char szItem[128], szItemInfo[32];
	Menu menu = new Menu(Handler_GiveLastRequest);
	menu.SetTitle("%s Last Request - Give Last Request\n ", PREFIX_MENU);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T && iCurrentClient != client)
		{
			IntToString(GetClientUserId(iCurrentClient), szItemInfo, sizeof(szItemInfo));
			Format(szItem, sizeof(szItem), "%N", iCurrentClient);
			menu.AddItem(szItemInfo, szItem);
		}
	}
	
	if (!menu.ItemCount) {
		menu.AddItem("", "No prisoner was found.", ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_GiveLastRequest(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iTargetIndex = StringToInt(szItem);
		
		if (GetOnlineTeamCount(CS_TEAM_T) > 1 || GetOnlineTeamCount(CS_TEAM_CT) < 1) {
			PrintToChat(client, "%s Giving Last Request allowed only when there is \x041\x01 prisoner alive and atleast \x041\x01 guard alive.", PREFIX_ERROR);
			return;
		}
		if (g_bIsLrRunning) {
			PrintToChat(client, "%s You are in a middle of another Last Request game!", PREFIX_ERROR);
			return;
		}
		
		if (g_bLastRequestGiven) {
			PrintToChat(client, "%s Last request already given, wait for the next game!", PREFIX_ERROR);
			return;
		}
		
		CS_RespawnPlayer(iTargetIndex);
		ForcePlayerSuicide(client);
		showLastRequestMenu(iTargetIndex);
		PrintToChatAll("%s Prisoner \x0C%N\x01 has gave \x04%N\x01 his last request!", PREFIX, client, iTargetIndex);
		
		Call_StartForward(g_fwdOnClientGiveLr);
		Call_PushCell(client);
		Call_PushCell(iTargetIndex);
		Call_Finish();
		
		g_bLastRequestGiven = true;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

//================================[ Timers ]================================//

public Action Timer_UpdateLrInfoPanel(Handle hTimer)
{
	showLrInfoPanel(FloatToInt(INFO_UPDATE_DELAY));
	return Plugin_Continue;
}

Action Timer_LrCountdown(Handle hTimer)
{
	if (g_bIsLrRunning || !(GetOnlineTeamCount(CS_TEAM_CT) >= 1 && GetOnlineTeamCount(CS_TEAM_T) == 1) || JB_IsSpecialDayRunning())
	{
		if (g_iCurrentLr != -1 && g_bIsLrRunning)
		{
			ResetValues(false, false);
		}
		
		PrintCenterTextAll("");
		
		g_bIsLrPeriod = false;
		g_hCountdownTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_iCountdownTime <= 1)
	{
		int iLastPrisonerAlive = GetLastPrisonerAlive();
		if (iLastPrisonerAlive != -1)
		{
			PrintToChatAll("Prisoner \x10%N\x01 has \x02lost\x01 his last request(s) for delaying the round.", iLastPrisonerAlive);
			ForcePlayerSuicide(iLastPrisonerAlive);
		}
		
		g_bIsLrPeriod = false;
		g_hCountdownTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	PrintCenterTextAll("<font color='#FF00FF'>Last Request Countdown</font> - <font color='#CC0000'>%ss</font>", AddCommas(--g_iCountdownTime));
	
	if (g_iCountdownTime <= g_cvCountdownSoundStartAt.IntValue)
	{
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				ClientCommand(current_client, "play %s", COUNTDOWN_END_SOUND);
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_BeaconPlayers(Handle hTimer)
{
	if (!g_bIsLrRunning) {
		g_hBeaconTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	ActiveBeacon(g_iLrPlayers[Part_Prisoner]);
	ActiveBeacon(g_iLrPlayers[Part_Guard]);
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int GetLrByName(const char[] name)
{
	return g_arLrsData.FindString(name);
}

any[] GetLrByIndex(int index)
{
	LastRequest LrData;
	g_arLrsData.GetArray(index, LrData, sizeof(LrData));
	return LrData;
}

void ActiveBeacon(int client)
{
	int iColor[2][4] = {  { 255, 0, 0, 255 }, { 0, 0, 255, 255 } };
	
	float fVector[3];
	GetClientAbsOrigin(client, fVector);
	fVector[2] += 5.0;
	
	if (g_iBeamSprite > -1 && g_iHaloSprite > -1)
	{
		TE_SetupBeamRingPoint(fVector, 10.0, 125.0, g_iBeamSprite, g_iHaloSprite, 0, 15, 0.5, 5.0, 0.0, { 128, 128, 128, 255 }, 10, 0);
		TE_SendToAll();
		
		TE_SetupBeamRingPoint(fVector, 10.0, 125.0, g_iBeamSprite, g_iHaloSprite, 0, 10, 0.6, 10.0, 0.5, iColor[GetClientTeam(client) - 2], 10, 0);
		TE_SendToAll();
	}
}

void PerformCountdown()
{
	JB_OpenCells();
	JB_TogglePrisonersMute(false, false);
	
	g_iCountdownTime = g_cvStartLrCountdownTime.IntValue + 1;
	
	if (g_hCountdownTimer != INVALID_HANDLE)
	{
		KillTimer(g_hCountdownTimer);
	}
	
	g_hCountdownTimer = CreateTimer(1.0, Timer_LrCountdown, _, TIMER_REPEAT);
	Timer_LrCountdown(INVALID_HANDLE);
	
	JB_TogglePrisonersMute(false, false);
	g_bIsLrPeriod = true;
}

void ResetValues(bool aborted, bool period, int winner = INVALID_LR_WINNER, int loser = INVALID_LR_WINNER)
{
	LastRequest LrData;
	if (g_iCurrentLr != -1) {
		LrData = GetLrByIndex(g_iCurrentLr);
	}
	
	Call_StartForward(g_fwdOnLrEnd);
	Call_PushCell(g_iCurrentLr);
	Call_PushString(LrData.szName);
	Call_PushCell(winner);
	Call_PushCell(loser);
	Call_PushCell(aborted);
	Call_Finish();
	
	if (g_iCurrentLr != -1)
	{
		if (!LrData.bWeaponPickup)
		{
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient)) {
					SDKUnhook(iCurrentClient, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
				}
			}
		}
	}
	
	if (1 <= g_iLrPlayers[Part_Prisoner] <= MaxClients && IsClientInGame(g_iLrPlayers[Part_Prisoner]) && IsPlayerAlive(g_iLrPlayers[Part_Prisoner]))
	{
		DisarmPlayer(g_iLrPlayers[Part_Prisoner]);
		GivePlayerItem(g_iLrPlayers[Part_Prisoner], "weapon_knife");
		SetEntityHealth(g_iLrPlayers[Part_Prisoner], DEFAULT_HEALTH);
	}
	
	if (1 <= g_iLrPlayers[Part_Guard] <= MaxClients && IsClientInGame(g_iLrPlayers[Part_Guard]) && IsPlayerAlive(g_iLrPlayers[Part_Guard]))
	{
		DisarmPlayer(g_iLrPlayers[Part_Guard]);
		GivePlayerItem(g_iLrPlayers[Part_Guard], "weapon_knife");
		SetEntityHealth(g_iLrPlayers[Part_Guard], DEFAULT_HEALTH);
	}
	
	DeleteAllTimers();
	g_iCurrentLr = -1;
	g_bContinueGame = false;
	g_bIsLrRunning = false;
	g_bLastRequestGiven = false;
	g_bIsLrPeriod = period;
	
	g_iLrPlayers[Part_Prisoner] = -1;
	g_iLrPlayers[Part_Guard] = -1;
}

void DeleteAllTimers(bool killCountdown = true)
{
	if (g_hLrInfoTimer != INVALID_HANDLE)
	{
		KillTimer(g_hLrInfoTimer);
		g_hLrInfoTimer = INVALID_HANDLE;
	}
	
	if (g_hBeaconTimer != INVALID_HANDLE)
	{
		KillTimer(g_hBeaconTimer);
		g_hBeaconTimer = INVALID_HANDLE;
	}
	
	if (killCountdown && g_hCountdownTimer != INVALID_HANDLE)
	{
		KillTimer(g_hCountdownTimer);
		g_hCountdownTimer = INVALID_HANDLE;
	}
}

int FloatToInt(float floatValue)
{
	char szFloat[64];
	FloatToString(floatValue, szFloat, sizeof(szFloat));
	return StringToInt(szFloat);
}

int GetLastPrisonerAlive()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T) {
			return iCurrentClient;
		}
	}
	return -1;
}

//================================================================//