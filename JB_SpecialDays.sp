#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_CellsSystem>
#include <JB_GuardsSystem>
#include <JB_MusicSystem>
#include <JB_GangsSystem>
#include <JB_LrSystem>
#include <JB_GangsUpgrades>
#include <JB_SettingsSystem>
#include <JB_SpecialDays>
#include <shop>
#include <multicolors>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define NUMBER_OF_VOTES 4
#define PROGRESS_BAR_LENGTH 10

#define AFTER_DAY_HEALTH 100
#define SPECIAL_DAY_DAY Day_Friday

#define MENU_ITEM_SOUND "buttons/button15.wav"

//====================//

enum struct SpecialDay
{
	char szName[64];
	int iDefaultHealth;
	bool bWeaponPickup;
	bool bWeaponDrop;
	bool bHasSetups;
	
	int iVotes;
}

enum struct Client
{
	GuardRank iOldGuardRank;
	bool bIsClientVoted;
	int iClientVote;
	int iClientDayKills;
	
	void Reset() {
		this.iOldGuardRank = Guard_NotGuard;
		this.bIsClientVoted = false;
		this.iClientVote = -1;
		this.iClientDayKills = 0;
	}
}

Client g_esClientsData[MAXPLAYERS + 1];

ArrayList g_arSpecialDaysData;
ArrayList g_arRandomVoteItems;

GlobalForward g_fwdOnSpecialDayVoteEnd;
GlobalForward g_fwdOnSpecialDayStart;
GlobalForward g_fwdOnSpecialDayEnd;
GlobalForward g_fwdOnClientSetupSpecialDay;

Handle g_hVoteTimer = INVALID_HANDLE;
Handle g_hStartCountDownTimer = INVALID_HANDLE;

ConVar g_cvVoteTime;
ConVar g_cvStartCountdown;
ConVar g_cvRequiredPlayers;
ConVar g_cvMVPRewardMultiplier;
ConVar g_cvMaxPossibleMVPReward;

ConVar g_cvIgnoreConditions;
ConVar g_cvFriendlyFire;
ConVar g_cvTeammatesAreEnemies;
ConVar g_cvRespawnOnDeath;

bool g_IsSetupRunning;
bool g_bIsSpecialDayRunning;
bool g_bIsSpecialDayVoteOn;

bool g_bHasPrisonerWonLrs;
bool g_bStatusPrinted;
bool g_bIsSpecialDayEnded;

int g_iTimer;
int g_iNumOfVotes;
int g_iCurrentDay = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Special Days System", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_arSpecialDaysData = new ArrayList(sizeof(SpecialDay));
	
	g_cvVoteTime = CreateConVar("jb_special_day_vote_time", "10", "Time in seconds for the special day vote to display.", _, true, 5.0, true, 15.0);
	g_cvStartCountdown = CreateConVar("jb_special_day_start_countdown_time", "10", "Time in seconds for the special day countdown before starting.", _, true, 5.0, true, 15.0);
	g_cvRequiredPlayers = CreateConVar("jb_special_day_required_players", "5", "Required players for special day vote to be enabled.", _, true, 1.0, true, 12.0);
	g_cvMVPRewardMultiplier = CreateConVar("jb_special_day_mvp_reward_multiplier", "1000", "Amount of cash to multiply by the MVP's kills.", _, true, 500.0, true, 2500.0);
	g_cvMaxPossibleMVPReward = CreateConVar("jb_special_day_max_mvp_reward", "20000", "Maximum possible amount of credits for special day mvp to get.", _, true, 2500.0, true, 25000.0);
	
	AutoExecConfig(true, "SpecialDays", "JailBreak");
	
	g_cvIgnoreConditions = FindConVar("mp_ignore_round_win_conditions");
	g_cvFriendlyFire = FindConVar("mp_friendlyfire");
	g_cvTeammatesAreEnemies = FindConVar("mp_teammates_are_enemies");
	g_cvRespawnOnDeath = FindConVar("mp_respawn_on_death_t");
	
	RegAdminCmd("sm_days", Command_Days, ADMFLAG_BAN, "Access the special days list menu.");
	RegAdminCmd("sm_voteday", Command_VoteDay, ADMFLAG_BAN, "Starts a special day voting.");
	RegAdminCmd("sm_stopday", Command_StopDay, ADMFLAG_BAN, "Stops the current special day operation that is running.");
	
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_connect_full", Event_PlayerConnectFull);
}

public void OnPluginEnd()
{
	if (g_bIsSpecialDayRunning && g_iCurrentDay != -1)
	{
		EndSpecialDay(g_iCurrentDay, true);
	}
}

//================================[ Events ]================================//

public void OnClientPostAdminCheck(int client)
{
	g_esClientsData[client].Reset();
}

public void OnClientDisconnect_Post(int client)
{
	if (g_bIsSpecialDayRunning && g_hStartCountDownTimer == INVALID_HANDLE)
	{		
		int iAlivePlayers = GetOnlineTeamCount(CS_TEAM_T);
		
		if (iAlivePlayers == 1 && !g_cvRespawnOnDeath.BoolValue)
		{
			CreateTimer(0.1, Timer_EndSpecialDay);
		}
		else if (iAlivePlayers > 2 && Gangs_GetPlayerGang(client) != NO_GANG && !g_cvRespawnOnDeath.BoolValue)
		{
			PrintSpecialDayStatus();
		}
	}
}

public void OnMapStart()
{
	if (g_bIsSpecialDayRunning && g_iCurrentDay != -1)
	{
		EndSpecialDay(g_iCurrentDay, true);
	}
	
	ResetValues();
}

void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsSpecialDayRunning && !g_bIsSpecialDayVoteOn && !g_IsSetupRunning && JB_GetDay() == SPECIAL_DAY_DAY && !JB_IsVoteCTRunning())
	{
		if ((GetOnlineTeamCount(CS_TEAM_CT, false) + GetOnlineTeamCount(CS_TEAM_T, false)) >= g_cvRequiredPlayers.IntValue)
		{
			StartVoteSpecialDay();
		}
		else
		{
			PrintToChatAll("%s \x07Special Day has canceled due to low number of online players!\x01", PREFIX);
		}
	}
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bIsSpecialDayRunning && g_iCurrentDay != -1)
	{
		EndSpecialDay(g_iCurrentDay, true);
		ResetValues();
		
		PrintToChatAll("%s \x10Special Day\x01 has automatically aborted, due to no round time has left.", PREFIX);
	}
	
	if (g_bHasPrisonerWonLrs)
	{
		RequestFrame(RF_UpdateDay);
		g_bHasPrisonerWonLrs = false;
	}
}

void RF_UpdateDay()
{
	JB_SetDay(Day_Sunday);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bIsSpecialDayRunning && g_hStartCountDownTimer == INVALID_HANDLE)
	{
		int iKillerIndex = GetClientOfUserId(event.GetInt("attacker"));
		int iVictimIndex = GetClientOfUserId(event.GetInt("userid"));
		
		if (iKillerIndex && iKillerIndex != iVictimIndex)
		{
			g_esClientsData[iKillerIndex].iClientDayKills++;
		}
		
		int iAlivePlayers = GetOnlineTeamCount(CS_TEAM_T);
		
		if (iAlivePlayers == 1 && !g_cvRespawnOnDeath.BoolValue)
		{
			CreateTimer(0.1, Timer_EndSpecialDay);
		}
		else if (iAlivePlayers > 2 && Gangs_GetPlayerGang(iVictimIndex) != NO_GANG && !g_cvRespawnOnDeath.BoolValue)
		{
			PrintSpecialDayStatus();
		}
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsSpecialDayRunning)
	{
		return;
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (g_hStartCountDownTimer != INVALID_HANDLE)
	{
		SetClientGangColor(client);
		SetGod(client, true);
	}
	else if (!g_bIsSpecialDayEnded && !g_cvIgnoreConditions.BoolValue && !g_IsSetupRunning)
	{
		SDKHooks_TakeDamage(client, client, client, float(GetClientHealth(client)));
		PrintToChat(client, "%s You have slayed due to joining in a middle of a \x10special day\x01, or you have been \x06respawned\x01!", PREFIX);
	}
}

void Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bIsSpecialDayRunning)
	{
		ForcePlayerSuicide(GetClientOfUserId(event.GetInt("userid")));
	}
}

//================================[ Commands ]================================//

public Action Command_Days(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for root administrators only.", PREFIX_ERROR);
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
			PrintToChat(client, "%s Special days list menu allowed for administrators only.", PREFIX_ERROR);
		} else {
			showDaysListMenu(iTargetIndex);
		}
	}
	else {
		showDaysListMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Command_VoteDay(int client, int args)
{
	if (g_bIsSpecialDayVoteOn) {
		PrintToChat(client, "%s There is already a vote day running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_bIsSpecialDayRunning) {
		PrintToChat(client, "%s There is already a special day running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	StartVoteSpecialDay();
	return Plugin_Handled;
}

public Action Command_StopDay(int client, int args)
{
	if (!g_bIsSpecialDayVoteOn && !g_bIsSpecialDayRunning)
	{
		PrintToChat(client, "%s There is no vote day nor special day running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_bIsSpecialDayVoteOn)
	{
		PrintToChatAll("%s Admin: \x0C%N\x01 has stopped the special day vote.", PREFIX, client);
	}
	else if (g_bIsSpecialDayRunning)
	{
		PrintToChatAll("%s Admin: \x0C%N\x01 has stopped the running special day.", PREFIX, client);
	}
	
	EndSpecialDay(g_iCurrentDay, true);
	return Plugin_Handled;
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnWeaponCanUse(int client, int weapon)
{
	if (g_bIsSpecialDayRunning) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
	if (g_bIsSpecialDayRunning && g_hStartCountDownTimer == INVALID_HANDLE && g_iCurrentDay != -1)
	{
		// Separated for 2 if statements to prevent server crash error
		if (!GetSpecialDayByIndex(g_iCurrentDay).bWeaponDrop) {
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_CreateSpecialDay", Native_CreateSpecialDay);
	CreateNative("JB_IsSpecialDayRunning", Native_IsSpecialDayRunning);
	CreateNative("JB_IsSpecialDayVoteRunning", Native_IsSpecialDayVoteRunning);
	CreateNative("JB_FindSpecialDay", Native_FindSpecialDay);
	CreateNative("JB_StartSpecialDay", Native_StartSpecialDay);
	CreateNative("JB_StopSpecialDay", Native_StopSpecialDay);
	
	g_fwdOnSpecialDayVoteEnd = CreateGlobalForward("JB_OnSpecialDayVoteEnd", ET_Event, Param_Cell);
	g_fwdOnSpecialDayStart = CreateGlobalForward("JB_OnSpecialDayStart", ET_Event, Param_Cell);
	g_fwdOnSpecialDayEnd = CreateGlobalForward("JB_OnSpecialDayEnd", ET_Event, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnClientSetupSpecialDay = CreateGlobalForward("JB_OnClientSetupSpecialDay", ET_Event, Param_Cell, Param_Cell);
	
	RegPluginLibrary("JB_SpecialDays");
	return APLRes_Success;
}

public int Native_CreateSpecialDay(Handle plugin, int numParams)
{
	SpecialDay SpecialDayData;
	GetNativeString(1, SpecialDayData.szName, sizeof(SpecialDayData.szName));
	
	if (GetSpecialDayByName(SpecialDayData.szName) != -1) {
		return GetSpecialDayByName(SpecialDayData.szName);
	}
	
	SpecialDayData.iDefaultHealth = GetNativeCell(2);
	SpecialDayData.bWeaponPickup = GetNativeCell(3);
	SpecialDayData.bWeaponDrop = GetNativeCell(4);
	SpecialDayData.bHasSetups = GetNativeCell(5);
	
	return g_arSpecialDaysData.PushArray(SpecialDayData, sizeof(SpecialDayData));
}

public int Native_IsSpecialDayRunning(Handle plugin, int numParams)
{
	return g_bIsSpecialDayRunning;
}

public int Native_IsSpecialDayVoteRunning(Handle plugin, int numParams)
{
	return (g_bIsSpecialDayVoteOn || g_IsSetupRunning);
}

public int Native_FindSpecialDay(Handle plugin, int numParams)
{
	char szName[64];
	GetNativeString(1, szName, sizeof(szName));
	return GetSpecialDayByName(szName);
}

public int Native_StartSpecialDay(Handle plugin, int numParams)
{
	if (g_bIsSpecialDayRunning && g_iCurrentDay != -1)
	{
		// Separated for 2 if statements to prevent server crash error
		if (!GetSpecialDayByIndex(g_iCurrentDay).bHasSetups)
		{
			return false;
		}
	}
	
	int iSpecialDayIndex = GetNativeCell(1);
	
	if (!(0 <= iSpecialDayIndex < g_arSpecialDaysData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid special day index (Got: %d, Max: %d)", iSpecialDayIndex, g_arSpecialDaysData.Length);
	}
	
	StartSpecialDayCountdown(iSpecialDayIndex);
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	WriteLogLine("Special day \"%s\" has been started by plugin \"%s\".", GetSpecialDayByIndex(iSpecialDayIndex).szName, szFileName);
	
	return true;
}

public int Native_StopSpecialDay(Handle plugin, int numParams)
{
	if (!g_bIsSpecialDayRunning || g_iCurrentDay == -1) {
		return false;
	}
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	WriteLogLine("Special day \"%s\" has been stopped by plugin \"%s\".", GetSpecialDayByIndex(g_iCurrentDay).szName, szFileName);
	
	bool bAborted = GetNativeCell(1);
	
	EndSpecialDay(g_iCurrentDay, bAborted);
	return true;
}

//================================[ Menus ]================================//

void showDaysListMenu(int client)
{
	char szItemInfo[16];
	Menu menu = new Menu(Handler_DaysList);
	menu.SetTitle("%s Special Days - List\n ", PREFIX_MENU);
	
	for (int iCurrentDay = 0; iCurrentDay < g_arSpecialDaysData.Length; iCurrentDay++)
	{
		IntToString(iCurrentDay, szItemInfo, sizeof(szItemInfo));
		menu.AddItem(szItemInfo, GetSpecialDayByIndex(iCurrentDay).szName);
	}
	
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No special day was found.", ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_DaysList(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (g_bIsSpecialDayRunning) {
			PrintToChat(client, "%s There is another Special Day game running!", PREFIX_ERROR);
			return 0;
		}
		
		if (g_bIsSpecialDayVoteOn) {
			PrintToChat(client, "%s There is a vote Special Day running!", PREFIX_ERROR);
			return 0;
		}
		
		if (JB_IsVoteCTRunning()) {
			PrintToChat(client, "%s There is a \x0CVote CT\x01 running!", PREFIX_ERROR);
			return 0;
		}
		
		if (JB_IsLrRunning()) {
			PrintToChat(client, "%s There is a last request game running!", PREFIX_ERROR);
			return 0;
		}
		
		char szItem[16];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iSpecialDayIndex = StringToInt(szItem);
		
		JB_SetDay(SPECIAL_DAY_DAY);
		
		PerformSpecialDayActions();
		
		WriteLogLine("Admin \"%L\" started %s special day.", client, GetSpecialDayByIndex(iSpecialDayIndex).szName);
		
		if (!GetSpecialDayByIndex(iSpecialDayIndex).bHasSetups)
		{
			StartSpecialDayCountdown(iSpecialDayIndex);
		}
		else
		{
			Call_StartForward(g_fwdOnSpecialDayVoteEnd);
			Call_PushCell(iSpecialDayIndex);
			Call_Finish();
			
			g_bStatusPrinted = false;
			
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient))
				{
					SetGod(iCurrentClient, true);
					
					SetClientGangColor(iCurrentClient);
				}
			}
			
			JB_OpenCells();
			JB_TogglePrisonersMute(false, false);
			DeleteAllTimers();
			
			g_cvRespawnOnDeath.BoolValue = true;
			g_bIsSpecialDayRunning = true;
			g_bIsSpecialDayVoteOn = false;
			g_IsSetupRunning = true;
			
			g_iCurrentDay = iSpecialDayIndex;
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

void showSpecialDayVotePanel()
{
	char szTitle[128], szItem[128];
	Panel panel = new Panel();
	Format(szTitle, sizeof(szTitle), "%s Special Day Vote - %s\n ", PREFIX_MENU, GetProgressBar(g_iTimer, g_cvVoteTime.IntValue));
	panel.SetTitle(szTitle);
	
	SpecialDay CurrentVoteData;
	for (int iCurrentVote = 0; iCurrentVote < NUMBER_OF_VOTES; iCurrentVote++)
	{
		g_arRandomVoteItems.GetArray(iCurrentVote, CurrentVoteData, sizeof(CurrentVoteData));
		Format(szItem, sizeof(szItem), "%s - (%d/%d | %d%%)", CurrentVoteData.szName, CurrentVoteData.iVotes, g_iNumOfVotes, g_iNumOfVotes == 0 ? 0:RoundToFloor(float(CurrentVoteData.iVotes) / float(g_iNumOfVotes) * 100.0));
		panel.DrawItem(szItem);
	}
	
	if (!g_arRandomVoteItems.Length) {
		panel.DrawItem("No special day was found.", ITEMDRAW_DISABLED);
	}
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			panel.Send(iCurrentClient, Handler_SpecialDayVote, 1);
		}
	}
	
	delete panel;
}

int Handler_SpecialDayVote(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!g_bIsSpecialDayVoteOn)
		{
			return 0;
		}
		
		itemNum -= 1; // Panel's item count starts from 1
		
		SpecialDay SpecialDayData;
		g_arRandomVoteItems.GetArray(itemNum, SpecialDayData, sizeof(SpecialDayData));
		
		bool bUpdateValues;
		if (!g_esClientsData[client].bIsClientVoted) {
			PrintToChat(client, "%s You voted for \x04%s\x01.", PREFIX, SpecialDayData.szName);
			g_esClientsData[client].iClientVote = itemNum;
			g_iNumOfVotes++;
			bUpdateValues = true;
		} else if (itemNum != g_esClientsData[client].iClientVote) {
			SpecialDay ClientSpecialDayData; g_arRandomVoteItems.GetArray(g_esClientsData[client].iClientVote, ClientSpecialDayData, sizeof(ClientSpecialDayData));
			ClientSpecialDayData.iVotes--;
			g_arRandomVoteItems.SetArray(g_esClientsData[client].iClientVote, ClientSpecialDayData, sizeof(ClientSpecialDayData));
			g_esClientsData[client].iClientVote = itemNum;
			PrintToChat(client, "%s You have changed your vote to \x04%s\x01.", PREFIX, SpecialDayData.szName);
			bUpdateValues = true;
		}
		
		SpecialDayData.iVotes++;
		
		if (bUpdateValues) {
			g_arRandomVoteItems.SetArray(itemNum, SpecialDayData, sizeof(SpecialDayData));
		}
		
		EmitSoundToClient(client, MENU_ITEM_SOUND);
		g_esClientsData[client].bIsClientVoted = true;
	}
	
	return 0;
}

//================================[ Timers ]================================//

public Action Timer_SpecialDayVote(Handle hTimer)
{
	if (g_iTimer <= 1)
	{
		int iSpecialDayIndex = GetSpecialDayVoteWinner();
		
		if (!GetSpecialDayByIndex(iSpecialDayIndex).bHasSetups) {
			StartSpecialDayCountdown(iSpecialDayIndex);
		} else {
			Call_StartForward(g_fwdOnSpecialDayVoteEnd);
			Call_PushCell(iSpecialDayIndex);
			Call_Finish();
			
			g_IsSetupRunning = true;
		}
		
		g_bIsSpecialDayVoteOn = false;
		delete g_arRandomVoteItems;
		
		g_hVoteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iTimer--;
	showSpecialDayVotePanel();
	return Plugin_Continue;
}

public Action Timer_StartCountdown(Handle hTimer, int specialDayIndex)
{
	SpecialDay SpecialDayData; SpecialDayData = GetSpecialDayByIndex(specialDayIndex);
	
	if (g_iTimer <= 1)
	{
		g_bIsSpecialDayRunning = true;
		g_bStatusPrinted = false;
		
		char szClassName[32];
		for (int iCurrentEntity = MaxClients + 1; iCurrentEntity < GetMaxEntities(); iCurrentEntity++)
		{
			if (IsValidEntity(iCurrentEntity) && GetEntityClassname(iCurrentEntity, szClassName, sizeof(szClassName)) && (StrContains(szClassName, "hegrenade") != -1 || StrContains(szClassName, "molotov") != -1 || StrContains(szClassName, "incendiary") != -1))
			{
				AcceptEntityInput(iCurrentEntity, "Kill");
			}
		}
		
		Call_StartForward(g_fwdOnSpecialDayStart);
		Call_PushCell(specialDayIndex);
		Call_Finish();
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				if (!IsPlayerAlive(iCurrentClient)) {
					CS_RespawnPlayer(iCurrentClient);
				}
				
				SetGod(iCurrentClient, false);
				SetEntityHealth(iCurrentClient, SpecialDayData.iDefaultHealth);
				SetClientGangColor(iCurrentClient);
				
				Call_StartForward(g_fwdOnClientSetupSpecialDay);
				Call_PushCell(iCurrentClient);
				Call_PushCell(specialDayIndex);
				Call_Finish();
				
				if (!SpecialDayData.bWeaponPickup) {
					SDKHook(iCurrentClient, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
				}
				
				g_esClientsData[iCurrentClient].iClientDayKills = 0;
			}
		}
		
		PrintCenterTextAll("");
		PrintToChatAll("%s \x04%s\x01 has started!", PREFIX, SpecialDayData.szName);
		
		PrintSpecialDayStatus();
		
		g_cvRespawnOnDeath.BoolValue = false;
		g_cvFriendlyFire.BoolValue = true;
		g_cvTeammatesAreEnemies.BoolValue = true;
		
		g_iCurrentDay = specialDayIndex;
		g_hStartCountDownTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iTimer--;
	PrintCenterTextAll(" %s starts in: <font color='#27AFD0'>%ds</font>", SpecialDayData.szName, g_iTimer);
	return Plugin_Continue;
}

Action Timer_EndSpecialDay(Handle hTimer)
{
	if (g_iCurrentDay != -1 && GetOnlineTeamCount(CS_TEAM_T) <= 1) {
		EndSpecialDay(g_iCurrentDay);
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int GetSpecialDayByName(const char[] name)
{
	SpecialDay CurrentSpecialDayData;
	for (int iCurrentDay = 0; iCurrentDay < g_arSpecialDaysData.Length; iCurrentDay++)
	{
		g_arSpecialDaysData.GetArray(iCurrentDay, CurrentSpecialDayData, sizeof(CurrentSpecialDayData));
		if (StrEqual(CurrentSpecialDayData.szName, name, true)) {
			return iCurrentDay;
		}
	}
	return -1;
}

any[] GetSpecialDayByIndex(int index)
{
	SpecialDay SpecialDayData;
	g_arSpecialDaysData.GetArray(index, SpecialDayData, sizeof(SpecialDayData));
	return SpecialDayData;
}

void StartVoteSpecialDay()
{
	if (!g_arSpecialDaysData.Length)
	{
		return;
	}
	
	if (IsVoteInProgress())
	{
		return;
	}
	
	DeleteAllTimers();
	g_bIsSpecialDayVoteOn = true;
	g_iTimer = g_cvVoteTime.IntValue;
	g_iNumOfVotes = 0;
	
	JB_OpenCells();
	JB_TogglePrisonersMute(false, false);
	JB_SetDay(SPECIAL_DAY_DAY);
	
	g_arRandomVoteItems = g_arSpecialDaysData.Clone();
	g_arRandomVoteItems.Sort(Sort_Random, Sort_Integer);
	
	g_hVoteTimer = CreateTimer(1.0, Timer_SpecialDayVote, _, TIMER_REPEAT);
	
	PerformSpecialDayActions();
	
	showSpecialDayVotePanel();
}

void StartSpecialDayCountdown(int specialDayIndex)
{
	g_bStatusPrinted = false;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			SetClientGangColor(iCurrentClient);
		}
	}
	
	JB_OpenCells();
	JB_TogglePrisonersMute(false, false);
	DeleteAllTimers();
	
	g_IsSetupRunning = false;
	
	g_cvRespawnOnDeath.BoolValue = true;
	g_iTimer = g_cvStartCountdown.IntValue;
	g_hStartCountDownTimer = CreateTimer(1.0, Timer_StartCountdown, specialDayIndex, TIMER_REPEAT);
	
	PrintCenterTextAll(" %s starts in: <font color='#27AFD0'>%ds</font>", GetSpecialDayByIndex(specialDayIndex).szName, g_iTimer);
	g_bIsSpecialDayRunning = true;
	g_bIsSpecialDayVoteOn = false;
	
	g_iCurrentDay = specialDayIndex;
	JB_PlayRandomSong();
}

void EndSpecialDay(int specialDayId, bool aborted = false)
{
	int iWinnerIndex, iMVPIndex;
	
	SpecialDay SpecialDayData;
	
	if (specialDayId != -1)
	{
		SpecialDayData = GetSpecialDayByIndex(specialDayId);
	}
	
	g_cvIgnoreConditions.BoolValue = true;
	
	int iMovedGuards;
	
	g_bIsSpecialDayEnded = true;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			if (!aborted && GetClientTeam(iCurrentClient) == CS_TEAM_T)
			{
				if (!iMVPIndex || (g_esClientsData[iCurrentClient].iClientDayKills > g_esClientsData[iMVPIndex].iClientDayKills))
				{
					iMVPIndex = iCurrentClient;
				}
				
				if (IsPlayerAlive(iCurrentClient))
				{
					iWinnerIndex = iCurrentClient;
				}
			}
			
			if (g_esClientsData[iCurrentClient].iOldGuardRank != Guard_NotGuard)
			{
				JB_SetClientGuardRank(iCurrentClient, g_esClientsData[iCurrentClient].iOldGuardRank);
				ChangeClientTeam(iCurrentClient, CS_TEAM_CT);
				CS_RespawnPlayer(iCurrentClient);
				iMovedGuards++;
				
				g_esClientsData[iCurrentClient].iOldGuardRank = Guard_NotGuard;
			}
			
			if (!SpecialDayData.bWeaponPickup)
			{
				SDKUnhook(iCurrentClient, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
			}
			
			if (IsPlayerAlive(iCurrentClient))
			{
				SetGod(iCurrentClient, false);
				SetEntityRenderColor(iCurrentClient, 255, 255, 255, 255);
				
				DisarmPlayer(iCurrentClient);
				GivePlayerItem(iCurrentClient, "weapon_knife");
				SetEntityHealth(iCurrentClient, AFTER_DAY_HEALTH);
			}
			
			JB_StopMusicToClient(iCurrentClient);
		}
	}
	
	g_cvIgnoreConditions.BoolValue = false;
	
	if (iMVPIndex && g_esClientsData[iMVPIndex].iClientDayKills && !aborted)
	{
		int iCashReward = g_cvMVPRewardMultiplier.IntValue * g_esClientsData[iMVPIndex].iClientDayKills;
		
		if (iCashReward > g_cvMaxPossibleMVPReward.IntValue)
		{
			iCashReward = g_cvMaxPossibleMVPReward.IntValue;
		}
		
		Shop_GiveClientCredits(iMVPIndex, iCashReward);
		
		SetHudTextParams(-1.0, 0.100, 4.0, GetRandomInt(1, 255), GetRandomInt(1, 255), GetRandomInt(1, 255), 255, 1, 0.1, 0.1, 0.1);
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				ShowHudText(iCurrentClient, 3, "The MVP of the special day is %N!\nHe killed %d players and earned %s cash", iMVPIndex, g_esClientsData[iMVPIndex].iClientDayKills, AddCommas(iCashReward));
			}
		}
	}
	
	Call_StartForward(g_fwdOnSpecialDayEnd);
	Call_PushCell(specialDayId);
	Call_PushString(SpecialDayData.szName);
	Call_PushCell(aborted ? INVALID_DAY_WINNER:iWinnerIndex);
	Call_PushCell(aborted);
	Call_PushCell(!(g_hStartCountDownTimer == INVALID_HANDLE));
	Call_Finish();
	
	g_cvFriendlyFire.BoolValue = false;
	g_cvTeammatesAreEnemies.BoolValue = false;
	g_cvRespawnOnDeath.BoolValue = false;
	
	ResetValues();
	
	if (!iMovedGuards)
	{
		JB_SetDay(Day_Saturday);
		CS_TerminateRound(3.0, CSRoundEnd_TerroristWin);
		
		PrintToChatAll("%s All the \x0Bguards\x01 has disconnected, a \x0CVote CT\x01 has started!", PREFIX);
		return;
	}
	
	if (iWinnerIndex)
	{
		if (JB_GetClientGuardRank(iWinnerIndex) != Guard_NotGuard)
		{
			CS_TerminateRound(3.0, CSRoundEnd_CTWin);
		}
		else
		{
			JB_ShowLrMainMenu(iWinnerIndex, true);
			g_bHasPrisonerWonLrs = true;
		}
	}
}

void PerformSpecialDayActions()
{
	g_cvIgnoreConditions.BoolValue = true;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			g_esClientsData[iCurrentClient].Reset();
			g_esClientsData[iCurrentClient].iOldGuardRank = JB_GetClientGuardRank(iCurrentClient);
			
			if (GetClientTeam(iCurrentClient) == CS_TEAM_CT)
			{
				ChangeClientTeam(iCurrentClient, CS_TEAM_T);
			}
			
			if (!IsPlayerAlive(iCurrentClient))
			{
				CS_RespawnPlayer(iCurrentClient);
			}
			
			SetGod(iCurrentClient, true);
		}
	}
	
	g_cvIgnoreConditions.BoolValue = false;
}

void DeleteAllTimers()
{
	if (g_hVoteTimer != INVALID_HANDLE) {
		KillTimer(g_hVoteTimer);
	}
	g_hVoteTimer = INVALID_HANDLE;
	
	if (g_hStartCountDownTimer != INVALID_HANDLE) {
		KillTimer(g_hStartCountDownTimer);
	}
	g_hStartCountDownTimer = INVALID_HANDLE;
}

void SetGod(int client, bool bMode)
{
	SetEntProp(client, Prop_Data, "m_takedamage", bMode ? 0:2, 1);
}

void PrintSpecialDayStatus()
{
	int iAlivePlayers[MAX_GANGS], iAliveGangs, iAliveGangIndex;
	bool bIsGangChecked[MAX_GANGS];
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient))
		{
			int iGangId = Gangs_GetPlayerGang(iCurrentClient);
			if (iGangId != NO_GANG)
			{
				if (!bIsGangChecked[iGangId])
				{
					iAliveGangs++;
					iAliveGangIndex = iGangId;
				}
				
				bIsGangChecked[iGangId] = true;
				iAlivePlayers[iGangId]++;
			}
		}
	}
	
	int iMessageSize = iAliveGangs * 64;
	char[] szMessage = new char[iMessageSize];
	char szGangName[64];
	int iGangCounter;
	
	if (iAliveGangs < 1) {
		return;
	}
	
	if (iAliveGangs == 1 && !g_bStatusPrinted)
	{
		Gangs_GetGangName(iAliveGangIndex, szGangName, sizeof(szGangName));
		PrintToChatAll("%s Gang \x0B%s\x01 is the last gang alive!", PREFIX, szGangName);
		g_bStatusPrinted = true;
	}
	
	if (!g_bStatusPrinted)
	{
		strcopy(szMessage, iMessageSize, PREFIX);
		
		for (int iCurrentGang = 0; iCurrentGang < MAX_GANGS; iCurrentGang++)
		{
			if (iAlivePlayers[iCurrentGang] < 1) {
				continue;
			}
			
			iGangCounter++;
			Gangs_GetGangName(iCurrentGang, szGangName, sizeof(szGangName));
			Format(szMessage, iMessageSize, "%s {red}%s\x01: \x04%d\x01%s", szMessage, szGangName, iAlivePlayers[iCurrentGang], iGangCounter == iAliveGangs ? "":" | ");
		}
		
		CPrintToChatAll(false, szMessage);
	}
}

void SetClientGangColor(int client)
{
	int iGangId = Gangs_GetPlayerGang(client);
	if (iGangId != NO_GANG)
	{
		int iGangColor[4];
		GetColorRGB(g_szColors[Gangs_GetGangColor(iGangId)][Color_Rgb], iGangColor);
		SetEntityRenderColor(client, iGangColor[0], iGangColor[1], iGangColor[2], iGangColor[3]);
	}
}

void ResetValues()
{
	DeleteAllTimers();
	
	g_IsSetupRunning = false;
	g_bIsSpecialDayEnded = false;
	g_bIsSpecialDayRunning = false;
	g_bIsSpecialDayVoteOn = false;
	g_bStatusPrinted = false;
	
	g_iTimer = 0;
	g_iNumOfVotes = 0;
	g_iCurrentDay = -1;
	
	g_cvRespawnOnDeath.BoolValue = false;
}

char[] GetProgressBar(int value, int all)
{
	char szProgress[PROGRESS_BAR_LENGTH * 6];
	int iLength = PROGRESS_BAR_LENGTH;
	
	for (int iCurrentChar = 0; iCurrentChar <= (float(value) / float(all) * PROGRESS_BAR_LENGTH) - 1; iCurrentChar++)
	{
		iLength--;
		StrCat(szProgress, sizeof(szProgress), "⬛");
	}
	
	for (int iCurrentChar = 0; iCurrentChar < iLength; iCurrentChar++) {
		StrCat(szProgress, sizeof(szProgress), "•");
	}
	
	StripQuotes(szProgress);
	TrimString(szProgress);
	return szProgress;
}

int GetSpecialDayVoteWinner()
{
	int iWinner = 0;
	
	SpecialDay CurrentVoteData;
	SpecialDay WinnerVoteData;
	
	for (int iCurrentVote = 0; iCurrentVote < g_arRandomVoteItems.Length; iCurrentVote++)
	{
		g_arRandomVoteItems.GetArray(iWinner, WinnerVoteData, sizeof(WinnerVoteData));
		g_arRandomVoteItems.GetArray(iCurrentVote, CurrentVoteData, sizeof(CurrentVoteData));
		
		if (CurrentVoteData.iVotes > WinnerVoteData.iVotes) {
			iWinner = iCurrentVote;
		}
	}
	
	g_arRandomVoteItems.GetArray(iWinner, WinnerVoteData, sizeof(WinnerVoteData));
	return GetSpecialDayByName(WinnerVoteData.szName);
}

//================================================================//
