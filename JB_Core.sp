#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <basecomm>
#include <cstrike>
#include <chat-processor>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>
#include <JB_SettingsSystem>
#include <JB_SpecialMods>
#include <Misc_Ghost>
#include <multicolors>
#include <clientprefs>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DEFAULT_GUARD_PRIMARY "weapon_m4a1"
#define DEFAULT_GUARD_SECONDARY "weapon_deagle"

#define SPECMODE_FREELOOK 6

//====================//

enum struct Client
{
	bool bIsReported;
	int iKillerIndex;
	
	void Reset() {
		this.bIsReported = false;
		this.iKillerIndex = 0;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

Database g_dbDatabase;

GlobalForward g_fwdOnDatabaseConnected;

Handle g_hPrisonersMuteTimer = INVALID_HANDLE;

Cookie g_InvisibleMode;

ConVar g_cvMedicCooldown;
ConVar g_cvPrisonersMute;

char g_szDays[][] = 
{
	"Sunday", 
	"Monday", 
	"Tuesday", 
	"Wednesday", 
	"Thursday", 
	"Friday", 
	"Saturday"
};

float g_fStartMapTime;

int g_iCurrentDay;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Core", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	Database.Connect(SQL_OnDatabaseConnected_CB, DATABASE_ENTRY);
	
	// ConVars Configurate
	g_cvMedicCooldown = CreateConVar("jb_medic_cooldown", "15", "Cooldown in seconds for the /medic command.", _, true, 5.0, true, 30.0);
	g_cvPrisonersMute = CreateConVar("jb_prisoners_mute", "30", "Time in seconds for the prisoners mute, will be apply every start of round.", _, true, 15.0, true, 60.0);
	
	AutoExecConfig(true, "JailBreak_Core", "JailBreak");
	
	g_InvisibleMode = FindClientCookie("admins_list_invisible");
	
	// Prisoner commands
	RegConsoleCmd("sm_freekill", Command_FreeKill, "Sumbit a freekill report to every online admin.");
	RegConsoleCmd("sm_fk", Command_FreeKill, "Sumbit a freekill report to every online admin. (An Alias)");
	RegConsoleCmd("sm_medic", Command_Medic, "Request for medic from the guards.");
	
	// Global Commands
	RegConsoleCmd("sm_day", Command_Day, "Prints the current day.");
	RegConsoleCmd("sm_maptime", Command_MapTime, "Prints the time that the current map running.");
	
	HookEvent("server_cvar", Event_ServerCvar, EventHookMode_Pre);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_Post);
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Post);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
	HookEvent("player_connect_full", Event_ClientConnectFull, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			OnClientPostAdminCheck(iCurrentClient);
			
			RenewClientTalkState(iCurrentClient);
		}
	}
}

public void OnAllPluginsLoaded()
{
	Database.Connect(SQL_OnDatabaseConnected_CB, DATABASE_ENTRY);
}

//================================[ Events ]================================//

public void OnMapStart()
{
	GameRules_SetProp("m_bWarmupPeriod", 0);
	
	// Disable any manual team menu interaction for players.
	GameRules_SetProp("m_bIsQueuedMatchmaking", true);
	
	g_iCurrentDay = Day_Sunday;
	g_fStartMapTime = GetEngineTime();
}

public Action CP_OnChatMessage(int & author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool & processcolors, bool & removecolors)
{
	if (GetUserAdmin(author) == INVALID_ADMIN_ID)
	{
		return Plugin_Continue;
	}
	
	if (g_InvisibleMode != null)
	{
		char szCookieValue[16];
		g_InvisibleMode.Get(author, szCookieValue, sizeof(szCookieValue));
		
		if (StrEqual(szCookieValue, "0"))
		{
			return Plugin_Continue;
		}
	}
	
	Format(message, MAXLENGTH_MESSAGE, "\x04%s\x01", message);
	return Plugin_Changed;
}

public void OnClientPostAdminCheck(int client)
{
	g_ClientsData[client].Reset();
}

public Action Event_ServerCvar(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;
	return Plugin_Continue;
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			g_ClientsData[iCurrentClient].Reset();
		}
	}
	
	char szMessage[32];
	Format(szMessage, sizeof(szMessage), "\x4%d\x01 days till Special Day!", Day_Friday - g_iCurrentDay);
	Format(szMessage, sizeof(szMessage), "%s", Day_Friday - g_iCurrentDay > 0 ? szMessage:"\x0CBonus Guards Round\x01!");
	PrintToChatAll("Day: \x0C%s\x01 | %s", g_szDays[g_iCurrentDay], g_iCurrentDay == Day_Friday ? "\x10Special Day!":szMessage);
	
	g_hPrisonersMuteTimer = CreateTimer(g_cvPrisonersMute.FloatValue, Timer_PrisonersMute);
	PrintToChatAll("Prisoners are now muted for \x03%d\x01 seconds.", g_cvPrisonersMute.IntValue);
	TogglePrisonersMute();
}

public void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	if (g_hPrisonersMuteTimer != INVALID_HANDLE)
	{
		KillTimer(g_hPrisonersMuteTimer);
		g_hPrisonersMuteTimer = INVALID_HANDLE;
	}
	
	TogglePrisonersMute(false);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_iCurrentDay = ++g_iCurrentDay % sizeof(g_szDays);
}

void Event_ClientConnectFull(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ChangeClientTeam(client, CS_TEAM_T);
	
	RenewClientTalkState(client);
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;
	return Plugin_Changed;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	RequestFrame(RenewClientTalkState, client);
	
	DisarmPlayer(client);
	GivePlayerItem(client, "weapon_knife");
	
	g_ClientsData[client].bIsReported = false;
	
	if (IsCrazyKnifeRunning())
	{
		return;
	}
	
	if (GetClientTeam(client) == CS_TEAM_CT)
	{
		GivePlayerItem(client, DEFAULT_GUARD_PRIMARY);
		GivePlayerItem(client, DEFAULT_GUARD_SECONDARY);
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int iVictimIndex = GetClientOfUserId(event.GetInt("userid"));
	int iKillerIndex = GetClientOfUserId(event.GetInt("attacker"));
	
	RenewClientTalkState(iVictimIndex);
	
	g_ClientsData[iVictimIndex].iKillerIndex = iKillerIndex;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int iVictimIndex = GetClientOfUserId(event.GetInt("userid"));
	int iAttackerIndex = GetClientOfUserId(event.GetInt("attacker"));
	int iDamage = event.GetInt("dmg_health");
	
	SetHudTextParams(0.4, -1.0, 3.0, 255, 50, 50, 255);
	ShowHudText(iVictimIndex, 1, "%d", iDamage);
	
	ArrayList VictimSpectators = GetClientSpectators(iVictimIndex);
	
	for (int current_spectator = 0; current_spectator < VictimSpectators.Length; current_spectator++)
	{
		ShowHudText(VictimSpectators.Get(current_spectator), 1, "%d", iDamage);
	}
	
	delete VictimSpectators;
	
	if (iAttackerIndex)
	{
		SetHudTextParams(0.45, -1.0, 3.0, 50, 50, 255, 255);
		ShowHudText(iAttackerIndex, 2, "%d", iDamage);
		
		ArrayList AttackerSpectators = GetClientSpectators(iAttackerIndex);
		
		for (int current_spectator = 0; current_spectator < AttackerSpectators.Length; current_spectator++)
		{
			ShowHudText(AttackerSpectators.Get(current_spectator), 2, "%d", iDamage);
		}
		
		delete AttackerSpectators;
	}
}

//================================[ Commands ]================================//

public Action Command_FreeKill(int client, int args)
{
	if (GetClientTeam(client) != CS_TEAM_T || g_ClientsData[client].iKillerIndex == 0 || !IsClientInGame(g_ClientsData[client].iKillerIndex) || GetClientTeam(g_ClientsData[client].iKillerIndex) != CS_TEAM_CT || IsPlayerAlive(client)) {
		PrintToChat(client, "%s \x02Error:\x01 You cannot report while you are alive or guard didn't killed you.", PREFIX);
		g_ClientsData[client].iKillerIndex = 0;
		return Plugin_Handled;
	}
	if (g_ClientsData[client].bIsReported) {
		PrintToChat(client, "%s \x02Error:\x01 You can only report freekill once in a round.", PREFIX);
		return Plugin_Handled;
	}
	
	char szArg[128];
	GetCmdArgString(szArg, sizeof(szArg));
	
	PrintToChat(client, "%s Your \x02Freekill\x01 report on \x0B%N\x01 was sent to the online admins.", PREFIX, g_ClientsData[client].iKillerIndex);
	PrintToAdmins("\x10%N\x01 has reported \x0B%N\x01 for \x02freekilling\x01 him.", client, g_ClientsData[client].iKillerIndex);
	PrintToAdmins("\x09Info:\x01 \x0E%s\x01.", szArg[0] == '\0' ? "No additional information added":szArg);
	
	JB_WriteLogLine("Player \"%L\" has submitted a freekill report on \"%L\".", client, g_ClientsData[client].iKillerIndex);
	g_ClientsData[client].bIsReported = true;
	return Plugin_Handled;
}

public Action Command_Medic(int client, int args)
{
	static int iCooldown[MAXPLAYERS + 1];
	int iCurrentTime = GetTime();
	
	if (iCurrentTime - iCooldown[client] < g_cvMedicCooldown.IntValue) {
		PrintToChat(client, "%s Please wait \x0B%d\x01 seconds before asking for \x06medic\x01 again.", PREFIX, iCooldown[client] + g_cvMedicCooldown.IntValue - iCurrentTime);
		return Plugin_Handled;
	}
	
	iCooldown[client] = iCurrentTime;
	
	if (!IsPlayerAlive(client) || GetClientHealth(client) >= 100 || GetClientTeam(client) != CS_TEAM_T)
	{
		PrintToChat(client, "%s Command allowed to \x04alive\x01 prisoners only with hp below \x06100\x01.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	PrintToChatAll("%s Prisoner \x0E%N\x01 wants medic! (\x02%d\x01 HP)", PREFIX, client, GetClientHealth(client));
	JB_WriteLogLine("Player \"%L\" asked for medic.", client);
	return Plugin_Handled;
}

public Action Command_Day(int client, int args)
{
	PrintToChat(client, "%s Current day is \x04%s\x01!", PREFIX, g_szDays[g_iCurrentDay]);
	return Plugin_Handled;
}

public Action Command_MapTime(int client, int args)
{
	float iTime = GetEngineTime();
	int iMapTime = RoundToZero(iTime - g_fStartMapTime);
	int iDays = iMapTime / 60 / 60 / 24;
	int iHours = iMapTime / 60 / 60 % 60;
	int iMinutes = iMapTime / 60 % 60;
	int iSeconds = iMapTime % 60;
	
	char szMapName[32];
	GetCurrentMap(szMapName, sizeof(szMapName));
	
	if (iDays == 0 && iHours == 0 && iMinutes == 0) {
		PrintToChat(client, "%s Playing \x07%s\x01 for \x04%d\x01 %s.", PREFIX, szMapName, iSeconds, iSeconds != 1 ? "seconds":"second");
	}
	else if (iDays == 0 && iHours == 0) {
		PrintToChat(client, "%s Playing \x07%s\x01 for \x04%d\x01 %s and \x04%d\x01 %s.", PREFIX, szMapName, iMinutes, iMinutes != 1 ? "minutes":"minute", iSeconds, iSeconds != 1 ? "seconds":"second");
	}
	else if (iDays == 0) {
		PrintToChat(client, "%s Playing \x07%s\x01 for \x04%d\x01 %s and \x04%d\x01 %s and \x04%d\x01 %s.", PREFIX, szMapName, iHours, iHours != 1 ? "hours":"hour", iMinutes, iMinutes != 1 ? "minutes":"minute", iSeconds, iSeconds != 1 ? "seconds":"second");
	}
	else {
		PrintToChat(client, "%s Playing \x07%s\x01 for \x04%d\x01 %s and \x04%d\x01 %s and \x04%d\x01 %s and \x04%d\x01 %s.", PREFIX, szMapName, iDays, iDays != 1 ? "days":"day", iHours, iHours != 1 ? "hours":"hour", iMinutes, iMinutes != 1 ? "minutes":"minute", iSeconds, iSeconds != 1 ? "seconds":"second");
	}
	
	return Plugin_Handled;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_GetDay", Native_GetDay);
	CreateNative("JB_SetDay", Native_SetDay);
	CreateNative("JB_TogglePrisonersMute", Native_TogglePrisonersMute);
	CreateNative("JB_GetDatabase", Native_GetDatabase);
	
	g_fwdOnDatabaseConnected = CreateGlobalForward("JB_OnDatabaseConnected", ET_Event, Param_Cell);
	
	RegPluginLibrary("JailBreak");
	return APLRes_Success;
}

public int Native_GetDay(Handle plugin, int numParams)
{
	return g_iCurrentDay;
}

public int Native_SetDay(Handle plugin, int numParams)
{
	int iDay = GetNativeCell(1);
	if (0 > iDay >= MAX_DAYS) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid day index (Got: %d | Max: %d)", iDay, MAX_DAYS);
	}
	
	g_iCurrentDay = iDay;
	return 0;
}

public int Native_TogglePrisonersMute(Handle plugin, int numParams)
{
	bool bMode = GetNativeCell(1);
	bool bBroadcast = GetNativeCell(2);
	
	if (bMode) {
		g_hPrisonersMuteTimer = CreateTimer(g_cvPrisonersMute.FloatValue, Timer_PrisonersMute);
		TogglePrisonersMute();
		if (bBroadcast) {
			PrintToChatAll("Prisoners are now muted for \x03%d\x01 seconds.", g_cvPrisonersMute.IntValue);
		}
	} else {
		TogglePrisonersMute(false);
		
		if (g_hPrisonersMuteTimer != INVALID_HANDLE) {
			KillTimer(g_hPrisonersMuteTimer);
		}
		g_hPrisonersMuteTimer = INVALID_HANDLE;
		if (bBroadcast) {
			PrintToChatAll("Prisoners can speak now.");
		}
	}
	
	return 0;
}

public any Native_GetDatabase(Handle plugin, int numParams)
{
	return g_dbDatabase;
}

//================================[ Database ]================================//

public void SQL_OnDatabaseConnected_CB(Database db, const char[] error, any data)
{
	if (db == null)
	{
		SetFailState("Cannot connect to MySQL Server! | Error: %s", error);
	}
	
	g_dbDatabase = db;
	
	Call_StartForward(g_fwdOnDatabaseConnected);
	Call_PushCell(g_dbDatabase);
	Call_Finish();
}

//================================[ Timers ]================================//

Action Timer_PrisonersMute(Handle hTimer)
{
	TogglePrisonersMute(false);
	PrintToChatAll(" \x0FPrisoners can speak now... quietly...\x01");
	g_hPrisonersMuteTimer = INVALID_HANDLE;
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void TogglePrisonersMute(bool bMute = true)
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && GetUserAdmin(iCurrentClient) == INVALID_ADMIN_ID && IsPlayerAlive(iCurrentClient) && !BaseComm_IsClientMuted(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T)
		{
			SetClientListeningFlags(iCurrentClient, bMute ? VOICE_MUTED:VOICE_NORMAL);
		}
	}
}

void RenewClientTalkState(int client)
{
	bool talk_permission = (!BaseComm_IsClientMuted(client) && !JB_IsClientGhost(client) && IsPlayerAlive(client) || GetUserAdmin(client) != INVALID_ADMIN_ID);
	
	SetClientListeningFlags(client, talk_permission ? VOICE_NORMAL : VOICE_MUTED);
}

ArrayList GetClientSpectators(int client)
{
	ArrayList spectators = new ArrayList();
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsPlayerAlive(current_client) && GetEntProp(current_client, Prop_Send, "m_iObserverMode") != SPECMODE_FREELOOK && GetEntPropEnt(current_client, Prop_Send, "m_hObserverTarget") == client)
		{
			spectators.Push(current_client);
		}
	}
	
	return spectators;
}

bool IsCrazyKnifeRunning()
{
	static int crazy_knife_mod_index = -1;
	if (crazy_knife_mod_index == -1)
	{
		crazy_knife_mod_index = JB_FindSpecialMod("Crazy Knife");
	}
	
	return crazy_knife_mod_index != -1 && crazy_knife_mod_index == JB_GetCurrentSpecialMod();
}

//================================================================//