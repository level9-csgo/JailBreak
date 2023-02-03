#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <JailBreak>
#include <JB_GangsSystem>
#include <JB_CellsSystem>
#include <JB_LrSystem>
#include <JB_SpecialDays>
#include <JB_GuardsSystem>
#include <basecomm>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define PANEL_SHOW_TIME 2

#define GUARD_PER_PLAYERS 3
#define REQUIED_PASSED_VOTES 2
#define PROGRESS_BAR_LENGTH 10

#define MAX_REMAIN_THE_SAME 3

#define COUNTDOWN_END_SOUND "ui/beep07"

#define MENU_ITEM_SOUND "buttons/button15.wav"

//====================//

enum
{
	Action_VoteCT = 0, 
	Action_ChangeMap, 
	Action_RemainTheSame
}

enum struct Vote
{
	char szName[128];
	char szDesc[256];
	
	int iVotes;
}

enum struct Client
{
	GuardRank iGuardRank;
	GuardRank iGuardRankBackUp;
	bool bIsClientVoted;
	int iClientVote;
	
	void Reset(bool resetBackUp = true)
	{
		this.iGuardRank = Guard_NotGuard;
		this.iGuardRankBackUp = resetBackUp ? Guard_NotGuard:this.iGuardRankBackUp;
		this.bIsClientVoted = false;
		this.iClientVote = -1;
	}
}

Client g_esClientsData[MAXPLAYERS + 1];

ArrayList g_arVoteData;
ArrayList g_arRandomVoteItems;

GlobalForward g_fwdOnVoteCTStart;
GlobalForward g_fwdOnVoteCTEnd;
GlobalForward g_fwdOnVoteCTStop;
GlobalForward g_fwdOnGuardsShiftChange;
GlobalForward g_fwdOnOpenMainGuardMenu;
GlobalForward g_fwdOnPressMainGuardMenu;

Handle g_hVoteTimer = INVALID_HANDLE;
Handle g_hResetTimer = INVALID_HANDLE;
Handle g_hInviteTimer = INVALID_HANDLE;

ConVar g_cvVoteTime;
ConVar g_cvResetTime;
ConVar g_cvPassedRoundSeconds;
ConVar g_cvGuardsInviteTime;
ConVar g_cvCountdownSoundStartAt;
ConVar g_cvIgnoreConditions;

bool g_bIsVoteOn;
bool g_bIsVoteDisabled;
bool g_bIsInvitePeriodOn;
bool g_bIsInvitePeriodTimedOut;

char g_szActionVotes[][] = 
{
	"Change Guards", 
	"Change Map", 
	"Remain The Same"
};

int g_iActionVotes[sizeof(g_szActionVotes)];
int g_iTimer;
int g_iRoundStartTime;

int g_iNumOfVotes;
int g_iNumOfPassedVotes;
int g_iNumOfRemainTheSame;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Guards System", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_arVoteData = new ArrayList(sizeof(Vote));
	
	g_cvVoteTime = CreateConVar("jb_vote_ct_time", "10", "Time in seconds for the vote ct to display.", _, true, 5.0, true, 15.0);
	g_cvResetTime = CreateConVar("jb_vote_ct_reset_time", "30", "Time in seconds for the vote ct to start again when there is no winner.", _, true, 10.0, true, 30.0);
	g_cvPassedRoundSeconds = CreateConVar("jb_passed_round_seconds", "30", "Maximum seconds that passed from the start of the round, used for respawn clients.", _, true, 20.0, true, 60.0);
	g_cvGuardsInviteTime = CreateConVar("jb_vote_ct_guards_invite_time", "60", "The time that the main guard has to invite prisoners to the guards team.", _, true, 10.0, true, 90.0);
	g_cvCountdownSoundStartAt = CreateConVar("jb_vote_ct_countdown_sound_start_at", "5", "The time left for the invite countdown for the sound effect to be function, 0 to disable.", _, true, 0.0, true, g_cvGuardsInviteTime.FloatValue);
	
	AutoExecConfig(true, "GuardsSystem", "JailBreak");
	
	g_cvIgnoreConditions = FindConVar("mp_ignore_round_win_conditions");
	
	LoadTranslations("common.phrases");
	
	// Admin Commands
	RegAdminCmd("sm_votect", Command_VoteCT, ADMFLAG_BAN, "Switches all the players to the prisoner team, and starts a new vote ct.");
	RegAdminCmd("sm_stopvotect", Command_StopVoteCT, ADMFLAG_BAN, "Stops the current vote ct.");
	RegAdminCmd("sm_disablevotect", Command_DisableVoteCT, ADMFLAG_BAN, "Stops the current vote ct and disabled it, will turn on again on a map change.");
	RegAdminCmd("sm_dvc", Command_DisableVoteCT, ADMFLAG_BAN, "Stops the current vote ct and disabled it, will turn on again on a map change. (An Alias)");
	RegAdminCmd("sm_delaycd", Command_DelayCountdown, ADMFLAG_BAN, "Adds a seconds to the guards choose count down timer.");
	
	// Client Commands
	RegConsoleCmd("sm_ctlist", Command_CTList, "Access the guards list menu, allowed for the current main guard only.");
	RegConsoleCmd("sm_mainguard", Command_MainGuard, "Allows the client to see the name of the current main guard.");
	RegConsoleCmd("sm_mg", Command_MainGuard, "Allows the client to see the name of the current main guard. (An Alias)");
	
	HookEvent("player_connect_full", Event_PlayerConnectFull, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Post);
}

//================================[ Events ]================================//

public void OnMapStart()
{
	g_bIsVoteOn = false;
	g_bIsVoteDisabled = false;
	g_bIsInvitePeriodOn = false;
	g_bIsInvitePeriodTimedOut = false;
	g_iNumOfPassedVotes = 0;
	
	DeleteAllTimers();
	
	Call_StartForward(g_fwdOnVoteCTStop);
	Call_Finish();
}

public void OnClientPostAdminCheck(int client)
{
	if (g_bIsVoteOn)
	{
		CS_RespawnPlayer(client);
		SetGod(client, true);
	}
	
	g_esClientsData[client].Reset();
}

public void OnClientDisconnect(int client)
{
	if (g_bIsVoteOn && g_esClientsData[client].iClientVote != -1)
	{
		if (g_arRandomVoteItems != null)
		{
			Vote VoteData; g_arRandomVoteItems.GetArray(g_esClientsData[client].iClientVote, VoteData, sizeof(VoteData));
			VoteData.iVotes--;
			g_arRandomVoteItems.SetArray(g_esClientsData[client].iClientVote, VoteData, sizeof(VoteData));
		}
		else
		{
			g_iActionVotes[g_esClientsData[client].iClientVote]--;
		}
		
		g_iNumOfVotes--;
		g_esClientsData[client].iClientVote = -1;
	}
	
	if (g_esClientsData[client].iGuardRank == Guard_Main)
	{
		if (GetOnlineTeamCount(CS_TEAM_CT, false) - 1) {
			SelectNewMainGuard(client);
		} else if (!g_bIsVoteDisabled && !g_bIsVoteOn && GetOnlineTeamCount(CS_TEAM_T, false) - 1 >= 1 && !JB_IsSpecialDayRunning() && !JB_IsSpecialDayVoteRunning()) {
			StartVoteCT(false);
			PrintToChatAll("%s Since the old \x0Bmain guard\x01 \x04%N\x01 has left, a new vote ct has started!", PREFIX, client);
		}
	}
	
	g_esClientsData[client].iGuardRank = Guard_NotGuard;
}

public void OnClientDisconnect_Post(int client)
{
	if (!GetOnlineTeamCount(CS_TEAM_T, false)) {
		DeleteAllTimers();
		g_bIsVoteOn = false;
	}
	
	if (GetAvailableGuards() <= 0 && g_hInviteTimer != INVALID_HANDLE)
	{
		KillTimer(g_hInviteTimer);
		g_hInviteTimer = INVALID_HANDLE;
		
		RemoveCommandListener(Listener_Suicide, "kill");
		RemoveCommandListener(Listener_Suicide, "killvector");
		RemoveCommandListener(Listener_Suicide, "explode");
		RemoveCommandListener(Listener_Suicide, "explodevector");
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				ToggleFreeze(iCurrentClient, false);
			}
		}
		
		g_bIsInvitePeriodOn = false;
		g_bIsInvitePeriodTimedOut = false;
		ServerCommand("mp_restartgame 1");
	}
}

public void JB_OnBanCTExecuted(int client, int admin, int length, const char[] reason)
{
	g_esClientsData[client].iGuardRankBackUp = Guard_NotGuard;
}

public Action Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsVoteDisabled && !g_bIsVoteOn && GetOnlineTeamCount(CS_TEAM_T, false) && (JB_GetDay() == Day_Sunday || !GetOnlineTeamCount(CS_TEAM_CT, false)) && !JB_IsSpecialDayVoteRunning() && !JB_IsSpecialDayRunning())
	{
		StartVoteCT();
	}
	
	g_iRoundStartTime = GetTime();
	
	if (GetAvailableGuards() < 0)
	{
		int iNumOfKickedGuards = GetAvailableGuards() * -1;
		char szMessage[512];
		Format(szMessage, sizeof(szMessage), "%s The guard%s ", PREFIX, iNumOfKickedGuards > 1 ? "s":"");
		
		for (int iCurrentGuard = 0; iCurrentGuard < iNumOfKickedGuards; iCurrentGuard++)
		{
			int iRandomGuard = GetRandomGuard(false, false);
			if (iRandomGuard != -1) {
				g_esClientsData[iRandomGuard].iGuardRank = Guard_NotGuard;
				ChangeClientTeam(iRandomGuard, CS_TEAM_T);
				CS_RespawnPlayer(iRandomGuard);
				Format(szMessage, sizeof(szMessage), "%s \x03%N\x01%s", szMessage, iRandomGuard, iCurrentGuard != (iNumOfKickedGuards - 1) ? ", ":"");
			}
		}
		
		Format(szMessage, sizeof(szMessage), "%s %s been moved to the \x10prisoners\x01 team beacuse %s \x02exceeded\x01 the allowed guards amount!", szMessage, iNumOfKickedGuards == 1 ? "has":"have", iNumOfKickedGuards == 1 ? "he has":"they have");
		PrintToChatAll(szMessage);
		
		ReplaceString(szMessage, sizeof(szMessage), "[Play-IL]", "");
		TrimString(szMessage);
		StripQuotes(szMessage);
		
		JB_WriteLogLine(RemoveColors(szMessage));
	}
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && g_esClientsData[iCurrentClient].iGuardRank == Guard_Normal && JB_IsClientBannedCT(iCurrentClient) && !IsFakeClient(iCurrentClient))
		{
			g_esClientsData[iCurrentClient].iGuardRank = Guard_NotGuard;
			ChangeClientTeam(iCurrentClient, CS_TEAM_T);
			CS_RespawnPlayer(iCurrentClient);
			PrintToChatAll("%s The guard \x03%N\x01 has been moved to the \x10prisoners\x01 team beacuse he's \x07banned from being a guard\x01!", PREFIX, iCurrentClient);
		}
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !BaseComm_IsClientMuted(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_CT)
		{
			SetClientListeningFlags(iCurrentClient, VOICE_NORMAL);
		}
	}
	
	int iAvailableGuards = GetAvailableGuards(), iMainGuardIndex = GetMainGuardIndex();
	
	if (iMainGuardIndex == -1)
	{
		int new_mainguard = GetRandomGuard(false, false);
		if (new_mainguard == -1)
		{
			return;
		}
		
		g_esClientsData[new_mainguard].iGuardRank = Guard_Main;
		
		PrintToChat(new_mainguard, "%s Since the old \x0Bmain guard\x01 has left, you have been placed as the new \x0Bmain-guard\x01.", PREFIX);
	}
	
	if (GetOnlineTeamCount(CS_TEAM_CT, false) >= 1 && iAvailableGuards > 0 && !g_bIsInvitePeriodTimedOut)
	{
		if (JB_GetDay() == Day_Monday)
		{
			JB_OpenCells();
			
			DeleteAllTimers();
			
			g_iTimer = g_cvGuardsInviteTime.IntValue;
			g_hInviteTimer = CreateTimer(1.0, Timer_Invite, _, TIMER_REPEAT);
			
			AddCommandListener(Listener_Suicide, "kill");
			AddCommandListener(Listener_Suicide, "killvector");
			AddCommandListener(Listener_Suicide, "explode");
			AddCommandListener(Listener_Suicide, "explodevector");
			
			if (iMainGuardIndex != -1)
			{
				showMainGuardMenu(iMainGuardIndex);
			}
			
			ShowPanel2("<font class='fontSize-xl'>The <font color='#235CB8'>Main Guard</font> has to choose %d guard%s | Time Left: %ds</font>", iAvailableGuards, iAvailableGuards > 1 ? "s":"", g_iTimer);
		}
		else if (iMainGuardIndex != -1)
		{
			showInviteMenu(iMainGuardIndex);
		}
	}
}

public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	if (GetAvailableGuards() > 0 && JB_GetDay() == Day_Monday && !g_bIsInvitePeriodTimedOut) {
		g_bIsInvitePeriodOn = true;
	} else {
		g_bIsInvitePeriodOn = false;
	}
}

public Action Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsVoteDisabled && !g_bIsVoteOn && GetOnlineTeamCount(CS_TEAM_T, false) >= 1 && GetOnlineTeamCount(CS_TEAM_CT, false) == 0 && !JB_IsSpecialDayRunning() && !JB_IsSpecialDayVoteRunning())
	{
		StartVoteCT();
	}
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int iNewTeam = event.GetInt("team");
	
	if (iNewTeam == CS_TEAM_CT)
	{
		if (g_esClientsData[client].iGuardRank != Guard_Main)
		{
			g_esClientsData[client].iGuardRank = Guard_Normal;
		}
		
		if (!GetOnlineTeamCount(CS_TEAM_CT, false) && !JB_IsSpecialDayVoteRunning() && !JB_IsSpecialDayRunning())
		{
			g_esClientsData[client].iGuardRank = Guard_Main;
			
			if (g_bIsVoteOn)
			{
				DeleteAllTimers();
				
				Call_StartForward(g_fwdOnVoteCTStop);
				Call_Finish();
				
				g_bIsVoteOn = false;
			}
			
			JB_SetDay(Day_Monday);
			ServerCommand("mp_restartgame 3");
		}
		
		if (g_hInviteTimer != INVALID_HANDLE && GetAvailableGuards() <= 1)
		{
			KillTimer(g_hInviteTimer);
			g_hInviteTimer = INVALID_HANDLE;
			
			RemoveCommandListener(Listener_Suicide, "kill");
			RemoveCommandListener(Listener_Suicide, "killvector");
			RemoveCommandListener(Listener_Suicide, "explode");
			RemoveCommandListener(Listener_Suicide, "explodevector");
			
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient))
				{
					ToggleFreeze(iCurrentClient, false);
				}
			}
			
			g_bIsInvitePeriodOn = false;
			g_bIsInvitePeriodTimedOut = false;
			ServerCommand("mp_restartgame 1");
		}
	}
	else if (iNewTeam == CS_TEAM_T)
	{
		if (g_esClientsData[client].iGuardRank == Guard_Main && !JB_IsSpecialDayVoteRunning() && !JB_IsSpecialDayRunning())
		{
			SelectNewMainGuard(client);
		}
		
		g_esClientsData[client].iGuardRank = Guard_NotGuard;
	}
	
	return Plugin_Continue;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsInvitePeriodOn)
	{
		return;
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	SetGod(client, true);
	
	if (GetClientTeam(client) == CS_TEAM_CT)
	{
		float fOrigin[3];
		GetClientAbsOrigin(client, fOrigin);
		fOrigin[2] += 15.0;
		TeleportEntity(client, fOrigin, NULL_VECTOR, NULL_VECTOR);
		
		ToggleFreeze(client, true);
	}
}

//================================[ Commands ]================================//

public Action Listener_Suicide(int client, char[] command, int argc)
{
	if (g_hInviteTimer == INVALID_HANDLE)
	{
		return Plugin_Continue;
	}
	
	PrintToConsole(client, "%s Suiciding is currently unavailable.", PREFIX_MENU);
	return Plugin_Handled;
}

public Action Command_VoteCT(int client, int args)
{
	if (JB_IsSpecialDayVoteRunning() || JB_IsSpecialDayRunning())
	{
		PrintToChat(client, "%s There is a vote/special day running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (JB_IsLrRunning())
	{
		PrintToChat(client, "%s There is a last request game running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_bIsVoteOn)
	{
		PrintToChat(client, "%s There is already \x0CVote CT\x01 running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	JB_WriteLogLine("Admin \"%L\" has started a vote ct manually.", client);
	StartVoteCT();
	
	return Plugin_Handled;
}

public Action Command_StopVoteCT(int client, int args)
{
	if (!g_bIsVoteOn)
	{
		PrintToChat(client, "%s There is no \x0CVote CT\x01 running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	DeleteAllTimers();
	g_bIsVoteOn = false;
	
	Call_StartForward(g_fwdOnVoteCTStop);
	Call_Finish();
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			SetGod(iCurrentClient, false);
		}
	}
	
	JB_WriteLogLine("Admin \"%L\" has stopped the vote ct manually.", client);
	PrintToChatAll("%s \x04%N\x01 has stopped the \x0CVote CT\x01!", PREFIX, client);
	return Plugin_Handled;
}

public Action Command_DisableVoteCT(int client, int args)
{
	DeleteAllTimers();
	g_bIsVoteOn = false;
	
	Call_StartForward(g_fwdOnVoteCTStop);
	Call_Finish();
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			SetGod(iCurrentClient, false);
		}
	}
	
	JB_WriteLogLine("Admin \"%L\" has %s the vote ct manually.", client, g_bIsVoteDisabled ? "\x04enabled\x01":"\x02disabled");
	PrintToChatAll("%s \x04%N\x01 has %s\x01 the \x0CVote CT\x01!", PREFIX, client, g_bIsVoteDisabled ? "\x04enabled\x01":"\x02disabled");
	g_bIsVoteDisabled = !g_bIsVoteDisabled;
	return Plugin_Handled;
}

public Action Command_DelayCountdown(int client, int args)
{
	if (args != 1) {
		PrintToChat(client, "%s Usage: \x04/delaycd\x01 <time>", PREFIX);
		return Plugin_Handled;
	}
	
	if (g_hInviteTimer == INVALID_HANDLE) {
		PrintToChat(client, "%s You cannot delay the countdown right now.", PREFIX);
		return Plugin_Handled;
	}
	
	char szArg[32];
	GetCmdArg(1, szArg, sizeof(szArg));
	int iSeconds = StringToInt(szArg);
	
	if (!iSeconds || g_iTimer + iSeconds < 1)
	{
		PrintToChat(client, "%s You have specifed an invalid delay value. [\x02%s\x01]", PREFIX, szArg);
		return Plugin_Handled;
	}
	
	g_iTimer += iSeconds;
	PrintToChatAll("%s Admin \x04%N\x01 has delayed the \x0CVote CT\x01 count down for \x03%d\x01 seconds.", PREFIX, client, iSeconds);
	return Plugin_Handled;
}

public Action Command_CTList(int client, int args)
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
		
		if (iTargetIndex == -1)
		{
			/* Automated message from SourceMod. */
			return Plugin_Handled;
		}
		
		if (g_esClientsData[iTargetIndex].iGuardRank != Guard_Main) {
			PrintToChat(client, "%s Main guard menu allowed for \x0Cmain guards\x01 only.", PREFIX_ERROR);
		} else {
			showMainGuardMenu(iTargetIndex);
		}
	}
	else
	{
		if (g_esClientsData[client].iGuardRank != Guard_Main)
		{
			PrintToChat(client, "%s Command allowed for \x0Cmain guard\x01 only.", PREFIX_ERROR);
		}
		else
		{
			showMainGuardMenu(client);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_MainGuard(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	int main_guard_index = GetMainGuardIndex();
	
	if (main_guard_index == -1)
	{
		PrintToChat(client, "%s The \x0CMain Guard\x01 name is currently unavailable.", PREFIX);
	}
	else
	{
		PrintToChat(client, "%s The current \x0CMain Guard\x01 is \x04%N\x01.", PREFIX, main_guard_index);
	}
	
	return Plugin_Handled;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_AddVoteCT", Native_AddVoteCT);
	CreateNative("JB_GetClientGuardRank", Native_GetClientGuardRank);
	CreateNative("JB_SetClientGuardRank", Native_SetClientGuardRank);
	CreateNative("JB_FindVoteCT", Native_FindVoteCT);
	CreateNative("JB_SetVoteCTWinner", Native_SetVoteCTWinner);
	CreateNative("JB_StartVoteCT", Native_StartVoteCT);
	CreateNative("JB_StopVoteCT", Native_StopVoteCT);
	CreateNative("JB_IsVoteCTRunning", Native_IsVoteCTRunning);
	CreateNative("JB_IsInvitePeriodRunning", Native_IsInvitePeriodRunning);
	
	g_fwdOnVoteCTStart = CreateGlobalForward("JB_OnVoteCTStart", ET_Ignore, Param_Cell);
	g_fwdOnVoteCTEnd = CreateGlobalForward("JB_OnVoteCTEnd", ET_Ignore, Param_Cell);
	g_fwdOnVoteCTStop = CreateGlobalForward("JB_OnVoteCTStop", ET_Ignore);
	g_fwdOnGuardsShiftChange = CreateGlobalForward("JB_OnGuardsShiftChange", ET_Ignore, Param_Cell, Param_Cell);
	g_fwdOnOpenMainGuardMenu = CreateGlobalForward("JB_OnOpenMainGuardMenu", ET_Ignore, Param_Cell, Param_Cell);
	g_fwdOnPressMainGuardMenu = CreateGlobalForward("JB_OnPressMainGuardMenu", ET_Ignore, Param_Cell, Param_String);
	
	RegPluginLibrary("JB_GuardsSystem");
	return APLRes_Success;
}

public int Native_AddVoteCT(Handle plugin, int numParams)
{
	Vote VoteData;
	GetNativeString(1, VoteData.szName, sizeof(VoteData.szName));
	
	if (GetVoteByName(VoteData.szName) != -1) {
		return GetVoteByName(VoteData.szName);
	}
	
	GetNativeString(2, VoteData.szDesc, sizeof(VoteData.szDesc));
	
	return g_arVoteData.PushArray(VoteData, sizeof(VoteData));
}

public any Native_GetClientGuardRank(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client < 1 || client > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_esClientsData[client].iGuardRank;
}

public int Native_SetClientGuardRank(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	GuardRank iRank = GetNativeCell(2);
	
	if (client < 1 || client > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	g_esClientsData[client].iGuardRank = iRank;
	return 0;
}

public int Native_FindVoteCT(Handle plugin, int numParams)
{
	char szName[64];
	GetNativeString(1, szName, sizeof(szName));
	return g_arVoteData.FindString(szName);
}

public int Native_SetVoteCTWinner(Handle plugin, int numParams)
{
	int iVoteId = GetNativeCell(1);
	int iWinnerIndex = GetNativeCell(2);
	
	if (iWinnerIndex < -1 || iWinnerIndex == 0 || iWinnerIndex > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", iWinnerIndex);
	}
	if (iWinnerIndex != -1 && !IsClientConnected(iWinnerIndex)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", iWinnerIndex);
	}
	
	char szAdditionalText[256];
	GetNativeString(3, szAdditionalText, sizeof(szAdditionalText));
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			SetGod(iCurrentClient, true);
		}
	}
	
	char szMessage[256];
	if (iWinnerIndex != -1 && IsClientConnected(iWinnerIndex))
	{
		if (JB_IsClientBannedCT(iWinnerIndex))
		{
			PrintToChatAll("%s \x0E%N\x01 is banned from being a guard, vote ct will start again in \x04%d\x01 seconds.", PREFIX, iWinnerIndex, g_cvResetTime.IntValue);
			Format(szMessage, sizeof(szMessage), "%s Vote CT\n \n%N is banned from being a guard, vote ct will start again in %d seconds.", PREFIX_MENU, iWinnerIndex, g_cvResetTime.IntValue);
			showAlertPanel(szMessage, 3);
			
			JB_WriteLogLine("The winner \"%L\" is banned from being a guard, vote restart.", iWinnerIndex);
			g_hResetTimer = CreateTimer(g_cvResetTime.FloatValue, Timer_ResetVoteCT);
			return 0;
		}
		
		JB_WriteLogLine("Player \"%L\" has won the vote ct the became the main guard.", iWinnerIndex);
		g_esClientsData[iWinnerIndex].iGuardRank = Guard_Main;
		ChangeClientTeam(iWinnerIndex, CS_TEAM_CT);
		CS_RespawnPlayer(iWinnerIndex);
		SetGod(iWinnerIndex, true);
		
		JB_SetDay(Day_Monday);
		
		ServerCommand("mp_restartgame 3");
		EmitSoundToAll("buttons/blip2.wav", _, _, _, _, 0.2);
		
		if (GetAvailableGuards() > 0) {
			g_bIsInvitePeriodTimedOut = false;
		}
		
		Vote VoteData; VoteData = GetVoteByIndex(iVoteId);
		
		Format(szMessage, sizeof(szMessage), ", %s", szAdditionalText);
		PrintToChatAll("%s \x04%N\x01 has won the %s and became the \x0Cmain guard\x01%s", PREFIX, iWinnerIndex, VoteData.szName, szAdditionalText[0] == '\0' ? ".":szMessage);
		
		Format(szMessage, sizeof(szMessage), ",\n %s", RemoveColors(szAdditionalText));
		Format(szMessage, sizeof(szMessage), "%s Vote CT - %s\n \n%N has won the %s and became the main guard%s", PREFIX_MENU, VoteData.szName, iWinnerIndex, VoteData.szName, szAdditionalText[0] == '\0' ? ".":szMessage);
		showAlertPanel(szMessage, 3);
		
		Call_StartForward(g_fwdOnGuardsShiftChange);
		Call_PushCell(iWinnerIndex);
		Call_PushCell(iVoteId);
		Call_Finish();
	} else {
		PrintToChatAll("%s \x0ENo winner\x01, \x0CVote CT\x01 will start again in \x04%d\x01 seconds.", PREFIX, g_cvResetTime.IntValue);
		Format(szMessage, sizeof(szMessage), "%s Vote CT\n \nNo winner, Vote CT will start again in %d seconds.", PREFIX_MENU, g_cvResetTime.IntValue);
		showAlertPanel(szMessage, 3);
		
		JB_WriteLogLine("The vote ct has ended, no winners were found.");
		g_hResetTimer = CreateTimer(g_cvResetTime.FloatValue, Timer_ResetVoteCT);
	}
	
	g_bIsVoteOn = false;
	return 0;
}

public int Native_StartVoteCT(Handle plugin, int numParams)
{
	if (JB_IsSpecialDayVoteRunning() || JB_IsSpecialDayRunning() || JB_IsLrRunning() || g_bIsVoteOn)
	{
		return false;
	}
	
	StartVoteCT(GetNativeCell(1));
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	JB_WriteLogLine("A Vote CT has started by plugin \"%s\".", szFileName);
	
	return true;
}

public int Native_StopVoteCT(Handle plugin, int numParams)
{
	if (!g_bIsVoteOn) {
		return false;
	}
	
	bool bBroadcast = GetNativeCell(1);
	
	DeleteAllTimers();
	g_bIsVoteOn = false;
	
	Call_StartForward(g_fwdOnVoteCTStop);
	Call_Finish();
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			SetGod(iCurrentClient, false);
		}
	}
	
	if (bBroadcast) {
		PrintToChatAll("%s \x0CVote CT\x01 has stopped!", PREFIX);
	}
	
	char szFileName[64];
	GetPluginFilename(plugin, szFileName, sizeof(szFileName));
	JB_WriteLogLine("The Vote CT has stopped by plugin \"%s\".", szFileName);
	
	return true;
}

public int Native_IsVoteCTRunning(Handle plugin, int numParams)
{
	return g_bIsVoteOn;
}

public int Native_IsInvitePeriodRunning(Handle plugin, int numParams)
{
	return g_bIsInvitePeriodOn;
}

//================================[ Vote Menus ]================================//

void showVoteActionPanel()
{
	char szTitle[128], szItem[128];
	Panel panel = new Panel();
	Format(szTitle, sizeof(szTitle), "%s Vote CT Action - %s\n ", PREFIX_MENU, GetProgressBar(g_iTimer, g_cvVoteTime.IntValue));
	panel.SetTitle(szTitle);
	
	for (int iCurrectAction = 0; iCurrectAction < sizeof(g_szActionVotes); iCurrectAction++)
	{
		Format(szItem, sizeof(szItem), "%s - (%d/%d | %d%%)", g_szActionVotes[iCurrectAction], g_iActionVotes[iCurrectAction], g_iNumOfVotes, g_iNumOfVotes == 0 ? 0:RoundToFloor(float(g_iActionVotes[iCurrectAction]) / float(g_iNumOfVotes) * 100.0));
		panel.DrawItem(szItem, iCurrectAction == Action_VoteCT ? ITEMDRAW_DEFAULT:iCurrectAction == Action_ChangeMap && g_iNumOfPassedVotes > REQUIED_PASSED_VOTES ? ITEMDRAW_DEFAULT:iCurrectAction == Action_RemainTheSame && IsGuardsBackUpAvailable() && g_iNumOfRemainTheSame < MAX_REMAIN_THE_SAME ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient))
		{
			panel.Send(iCurrentClient, Handler_VoteAction, 1);
		}
	}
	
	delete panel;
}

public int Handler_VoteAction(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!g_bIsVoteOn || !(1 <= itemNum <= 3))
		{
			return;
		}
		
		itemNum -= 1; // Panel's item count starts from 1
		if (!g_esClientsData[client].bIsClientVoted) {
			PrintToChat(client, "%s You voted for \x04%s\x01.", PREFIX, g_szActionVotes[itemNum]);
			g_iActionVotes[itemNum]++;
			g_esClientsData[client].iClientVote = itemNum;
			g_iNumOfVotes++;
		} else if (itemNum != g_esClientsData[client].iClientVote) {
			g_iActionVotes[g_esClientsData[client].iClientVote]--;
			g_iActionVotes[itemNum]++;
			g_esClientsData[client].iClientVote = itemNum;
			PrintToChat(client, "%s You have changed your vote to \x04%s\x01.", PREFIX, g_szActionVotes[itemNum]);
		}
		
		EmitSoundToClient(client, MENU_ITEM_SOUND);
		g_esClientsData[client].bIsClientVoted = true;
	}
}

void showVoteCTPanel()
{
	char szTitle[128], szItem[128];
	Panel panel = new Panel();
	Format(szTitle, sizeof(szTitle), "%s Vote CT - %s\n ", PREFIX_MENU, GetProgressBar(g_iTimer, g_cvVoteTime.IntValue));
	panel.SetTitle(szTitle);
	
	Vote CurrentVoteData;
	for (int iCurrentVote = 0; iCurrentVote < g_arRandomVoteItems.Length; iCurrentVote++)
	{
		g_arRandomVoteItems.GetArray(iCurrentVote, CurrentVoteData, sizeof(CurrentVoteData));
		Format(szItem, sizeof(szItem), "%s - (%d/%d | %d%%)", CurrentVoteData.szName, CurrentVoteData.iVotes, g_iNumOfVotes, g_iNumOfVotes == 0 ? 0:RoundToFloor(float(CurrentVoteData.iVotes) / float(g_iNumOfVotes) * 100.0));
		panel.DrawItem(szItem);
	}
	
	if (!g_arRandomVoteItems.Length) {
		panel.DrawItem("No vote ct was found.", ITEMDRAW_DISABLED);
	}
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			panel.Send(iCurrentClient, Handler_VoteCT, 1);
		}
	}
	
	delete panel;
}

public int Handler_VoteCT(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!g_bIsVoteOn)
		{
			return;
		}
		
		if (JB_IsClientBannedCT(client)) {
			PrintToChat(client, "%s You cannot vote due to your Ban CT.", PREFIX_ERROR);
			return;
		}
		
		itemNum -= 1; // Panel's item count starts from 1
		
		Vote VoteData;
		g_arRandomVoteItems.GetArray(itemNum, VoteData, sizeof(VoteData));
		
		bool bUpdateValues;
		if (!g_esClientsData[client].bIsClientVoted) {
			PrintToChat(client, "%s You voted for \x04%s\x01.", PREFIX, VoteData.szName);
			g_esClientsData[client].iClientVote = itemNum;
			g_iNumOfVotes++;
			bUpdateValues = true;
		} else if (itemNum != g_esClientsData[client].iClientVote) {
			Vote ClientVoteData; g_arRandomVoteItems.GetArray(g_esClientsData[client].iClientVote, ClientVoteData, sizeof(ClientVoteData));
			ClientVoteData.iVotes--;
			g_arRandomVoteItems.SetArray(g_esClientsData[client].iClientVote, ClientVoteData, sizeof(ClientVoteData));
			g_esClientsData[client].iClientVote = itemNum;
			PrintToChat(client, "%s You have changed your vote to \x04%s\x01.", PREFIX, VoteData.szName);
			bUpdateValues = true;
		}
		
		VoteData.iVotes++;
		
		if (bUpdateValues) {
			g_arRandomVoteItems.SetArray(itemNum, VoteData, sizeof(VoteData));
		}
		
		EmitSoundToClient(client, MENU_ITEM_SOUND);
		g_esClientsData[client].bIsClientVoted = true;
	}
}

//================================[ Regular Menus ]================================//

void showAlertPanel(char[] szMessage, int iTime = MENU_TIME_FOREVER)
{
	Panel panel = new Panel();
	panel.DrawText(szMessage);
	
	for (int iCurrentItem = 0; iCurrentItem < 7; iCurrentItem++) {
		panel.DrawItem("", ITEMDRAW_NOTEXT);
	}
	panel.DrawItem("", ITEMDRAW_SPACER);
	panel.DrawItem("Exit");
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			panel.Send(iCurrentClient, Handler_DoNothing, iTime);
		}
	}
	
	delete panel;
}

public int Handler_DoNothing(Menu menu, MenuAction action, int client, int itemNum)
{
	/* Do Nothing */
}

void showMainGuardMenu(int client)
{
	char szItem[128], szItemInfo[16];
	Menu menu = new Menu(Handler_CTList);
	Format(szItem, sizeof(szItem), "%d Rounds Left", Day_Friday - JB_GetDay());
	menu.SetTitle("%s Vote CT - Main Guard Menu (%s)\n ", PREFIX_MENU, Day_Friday - JB_GetDay() == -1 ? "Bonus Guards Round":Day_Friday - JB_GetDay() == 0 ? "Last Round":szItem);
	
	int iAvailableGuards = GetAvailableGuards();
	Format(szItem, sizeof(szItem), "Invite Players [%d %s]\n ", iAvailableGuards, iAvailableGuards < 0 ? "Less":"More");
	menu.AddItem("", szItem, iAvailableGuards <= 0 ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	Call_StartForward(g_fwdOnOpenMainGuardMenu);
	Call_PushCell(client);
	Call_PushCell(menu);
	Call_Finish();
	
	Format(szItem, sizeof(szItem), "• Guards List:\n ");
	menu.AddItem("", szItem, ITEMDRAW_DISABLED);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && g_esClientsData[iCurrentClient].iGuardRank == Guard_Normal && !IsFakeClient(iCurrentClient))
		{
			Format(szItem, sizeof(szItem), "%N", iCurrentClient);
			IntToString(GetClientUserId(iCurrentClient), szItemInfo, sizeof(szItemInfo));
			menu.AddItem(szItemInfo, szItem);
		}
	}
	
	if (!szItemInfo[0]) {
		menu.AddItem("", "There are no guards playing with you.", ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_CTList(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		if (GetMainGuardIndex() != client)
		{
			PrintToChat(client, "%s You are no longer the \x0Cmain guard\x01 anymore!", PREFIX_ERROR);
			return;
		}
		
		char szItem[16];
		menu.GetItem(item_position, szItem, sizeof(szItem));
		int guard_userid = StringToInt(szItem);
		
		Call_StartForward(g_fwdOnPressMainGuardMenu);
		Call_PushCell(client);
		Call_PushString(szItem);
		Call_Finish();
		
		switch (item_position)
		{
			case 0:
			{
				if (GetAvailableGuards() <= 0) {
					showMainGuardMenu(client);
					return;
				}
				
				showInviteMenu(client);
			}
			default:
			{
				if (guard_userid > 0) {
					showViewGuardMenu(client, guard_userid);
				}
			}
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showInviteMenu(int client)
{
	char szItem[MAX_NAME_LENGTH], szItemInfo[32];
	Menu menu = new Menu(Handler_Invite);
	menu.SetTitle("%s Vote CT - Invite Players\n ", PREFIX_MENU);
	
	menu.AddItem("", "Invite All");
	menu.AddItem("", "Invite Online Gang Members\n ", Gangs_GetPlayerGang(client) == NO_GANG ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	bool is_ct_banned;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T && !IsFakeClient(iCurrentClient))
		{
			is_ct_banned = JB_IsClientBannedCT(iCurrentClient);
			
			Format(szItem, sizeof(szItem), "• %N%s", iCurrentClient, is_ct_banned ? " [CT Banned]" : "");
			IntToString(GetClientUserId(iCurrentClient), szItemInfo, sizeof(szItemInfo));
			menu.AddItem(szItemInfo, szItem, !is_ct_banned ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
		}
	}
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Invite(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				{
					if (IsClientInGame(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T && !IsFakeClient(iCurrentClient)) {
						showInvitationMenu(iCurrentClient, client);
					}
				}
				
				PrintToChatAll("%s \x0C%N\x01 has invited everyone to be a guard!", PREFIX, client);
			}
			case 1:
			{
				int iClientGangId = Gangs_GetPlayerGang(client);
				if (iClientGangId != NO_GANG)
				{
					int iCounter = 0;
					for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
					{
						if (IsClientInGame(iCurrentClient) && Gangs_GetPlayerGang(iCurrentClient) == iClientGangId && GetClientTeam(iCurrentClient) == CS_TEAM_T && !IsFakeClient(iCurrentClient)) {
							iCounter++;
							showInvitationMenu(iCurrentClient, client);
						}
					}
					
					if (iCounter) {
						PrintToChat(client, "%s \x04Successfully\x01 invited all online gang members! [\x10%d Member(s)\x01]", PREFIX, iCounter);
					} else {
						PrintToChat(client, "%s There are no online gang members to invite!", PREFIX_ERROR);
					}
				}
				
			}
			default:
			{
				char szItem[16];
				menu.GetItem(itemNum, szItem, sizeof(szItem));
				int iInviteIndex = GetClientOfUserId(StringToInt(szItem));
				
				if (!iInviteIndex)
				{
					PrintToChat(client, "%s The selected player is no longer in-game.", PREFIX_ERROR);
					showInviteMenu(client);
					return;
				}
				
				showInvitationMenu(iInviteIndex, client);
				showInviteMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		showMainGuardMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

void showInvitationMenu(int client, int iMainGuardIndex)
{
	char szItemInfo[32];
	Menu menu = new Menu(Handler_Invitation);
	menu.SetTitle("%s Vote CT - %N has invited you to be a guard with him!\n ", PREFIX_MENU, iMainGuardIndex);
	
	IntToString(GetClientUserId(iMainGuardIndex), szItemInfo, sizeof(szItemInfo));
	
	menu.AddItem(szItemInfo, "Accept");
	menu.AddItem(szItemInfo, "Decline");
	
	menu.ExitButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
	JB_WriteLogLine("Main guard \"%L\" has invited \"%L\" to be a guard.", iMainGuardIndex, client);
}

public int Handler_Invitation(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (JB_IsClientBannedCT(client))
		{
			PrintToChat(client, "%s Cannot accept the guard invitation due to your ct ban.", PREFIX_ERROR);
			return;
		}
		
		if (GetAvailableGuards() <= 0)
		{
			PrintToChat(client, "%s No \x0Cguards\x01 are needed anymore!", PREFIX);
			return;
		}
		
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iMainGuardIndex = GetClientOfUserId(StringToInt(szItem));
		
		if (!iMainGuardIndex)
		{
			PrintToChat(client, "%s The \x0Bmain guard\x01 who invited you is no longer in-game!", PREFIX_ERROR);
			return;
		}
		
		switch (itemNum)
		{
			case 0:
			{
				g_esClientsData[client].iGuardRank = Guard_Normal;
				ChangeClientTeam(client, CS_TEAM_CT);
				
				if (((GetTime() - g_iRoundStartTime) <= g_cvPassedRoundSeconds.IntValue && !JB_IsCellsOpened() && !IsPlayerAlive(client)) || (g_bIsInvitePeriodOn && !IsPlayerAlive(client))) {
					CS_RespawnPlayer(client);
				}
				
				PrintToChatAll("%s Prisoner \x10%N\x01 has accepted \x0C%N\x01 guard invitation and moved to the guards team!", PREFIX, client, iMainGuardIndex);
				JB_WriteLogLine("Player \"%L\" has accepted \"%L\" invitation to be a guard.", client, iMainGuardIndex);
				
				SetClientListeningFlags(client, VOICE_NORMAL);
				
				if (g_hInviteTimer != INVALID_HANDLE && GetAvailableGuards() <= 0)
				{
					KillTimer(g_hInviteTimer);
					g_hInviteTimer = INVALID_HANDLE;
					
					RemoveCommandListener(Listener_Suicide, "kill");
					RemoveCommandListener(Listener_Suicide, "killvector");
					RemoveCommandListener(Listener_Suicide, "explode");
					RemoveCommandListener(Listener_Suicide, "explodevector");
					
					for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
					{
						if (IsClientInGame(iCurrentClient))
						{
							ToggleFreeze(iCurrentClient, false);
						}
					}
					
					g_bIsInvitePeriodOn = false;
					g_bIsInvitePeriodTimedOut = false;
					ServerCommand("mp_restartgame 1");
				}
			}
			case 1:
			{
				PrintToChat(client, "%s You have \x02declined\x01 the guard invitatian from \x0C%N\x01.", PREFIX, iMainGuardIndex);
				PrintToChat(iMainGuardIndex, "%s Prisoner \x10%N\x01 has \x07declined\x01 your guard invitation.", PREFIX, client);
				JB_WriteLogLine("Player \"%L\" has declined \"%L\" invitation to be a guard.", client, iMainGuardIndex);
			}
		}
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

void showViewGuardMenu(int client, int guard_userid)
{
	int guard_index = GetClientOfUserId(guard_userid);
	
	char szItemInfo[32];
	Menu menu = new Menu(Handler_ViewGuard);
	menu.SetTitle("%s Vote CT - Viewing Guard \"%N\"\n \nRequirements for kicking a guard:\n \n1. Less than %d seconds have passed since the start of the round,\nor the player is dead.\n2.The current day is not a special day nor yesterday.\n ", PREFIX_MENU, guard_index, g_cvPassedRoundSeconds.IntValue);
	
	IntToString(GetClientUserId(guard_index), szItemInfo, sizeof(szItemInfo));
	
	menu.AddItem(szItemInfo, "Kick Guard");
	menu.AddItem("", "Transfer Main Guard");
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_ViewGuard(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(0, szItem, sizeof(szItem));
		int guard_index = GetClientOfUserId(StringToInt(szItem));
		
		if (!guard_index)
		{
			PrintToChat(client, "%s The selected player is no longer in-game!", PREFIX);
			showMainGuardMenu(client);
			return;
		}
		
		switch (itemNum)
		{
			case 0:
			{
				if (JB_GetDay() >= Day_Friday || ((GetTime() - g_iRoundStartTime) > g_cvPassedRoundSeconds.IntValue && IsPlayerAlive(guard_index)) && g_bIsInvitePeriodOn) {
					PrintToChat(client, "%s Kicking doesn't meet the \x02requirements\x01 at the moment.", PREFIX);
					return;
				}
				
				g_esClientsData[guard_index].iGuardRank = Guard_NotGuard;
				ChangeClientTeam(guard_index, CS_TEAM_T);
				if ((GetTime() - g_iRoundStartTime) <= g_cvPassedRoundSeconds.IntValue && !JB_IsCellsOpened()) {
					CS_RespawnPlayer(guard_index);
				}
				
				PrintToChatAll("%s \x0CMain guard %N\x01 has \x02kicked %N\x01 from the guards team.", PREFIX, client, guard_index);
				JB_WriteLogLine("Main guard \"%L\" has kicked \"%L\" from being a guard.", client, guard_index);
			}
			case 1:
			{
				g_esClientsData[guard_index].iGuardRank = Guard_Main;
				g_esClientsData[client].iGuardRank = Guard_Normal;
				
				JB_WriteLogLine("Main guard \"%L\" has gave his role to guard \"%L\".", client, guard_index);
				
				PrintToChat(client, "%s You have gave \x0B%N\x01 the \x0Cmain guard\x01 role, you are \x07no longer\x01 the main guard.", PREFIX, guard_index);
				PrintToChat(guard_index, "%s The \x0CMain Guard\x01 decided to give you his role, now you are controlling the guards team!", PREFIX);
				PrintToChat(guard_index, "type \x04/ctlist\x01 for main guard futures.");
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		showMainGuardMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

//================================[ Timers ]================================//

public Action Timer_ActionVote(Handle hTimer)
{
	if (JB_IsSpecialDayRunning() || JB_IsSpecialDayVoteRunning())
	{
		g_hVoteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_iTimer <= 1)
	{
		g_hVoteTimer = INVALID_HANDLE;
		
		switch (GetActionVoteWinner())
		{
			case Action_VoteCT:
			{
				g_bIsVoteOn = true;
				g_iTimer = g_cvVoteTime.IntValue;
				g_iNumOfVotes = 0;
				g_hVoteTimer = CreateTimer(1.0, Timer_VoteCT, _, TIMER_REPEAT);
				
				GetRandomVotesOrder();
				
				for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				{
					if (IsClientInGame(iCurrentClient)) {
						g_esClientsData[iCurrentClient].Reset();
					}
				}
				
				g_iNumOfRemainTheSame = 0;
				showVoteCTPanel();
				return Plugin_Stop;
			}
			case Action_ChangeMap:
			{
				ServerCommand("sm_cm");
				g_bIsVoteOn = false;
				
				g_iNumOfRemainTheSame = 0;
			}
			case Action_RemainTheSame:
			{
				for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
				{
					if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient))
					{
						if (g_esClientsData[iCurrentClient].iGuardRankBackUp != Guard_NotGuard) {
							ChangeClientTeam(iCurrentClient, CS_TEAM_CT);
							g_esClientsData[iCurrentClient].iGuardRank = g_esClientsData[iCurrentClient].iGuardRankBackUp;
						}
						g_esClientsData[iCurrentClient].iGuardRankBackUp = Guard_NotGuard;
					}
				}
				
				Call_StartForward(g_fwdOnVoteCTEnd);
				Call_PushCell(-1);
				Call_Finish();
				
				g_iNumOfRemainTheSame++;
				JB_SetDay(Day_Monday);
				ServerCommand("mp_restartgame 1");
				g_bIsVoteOn = false;
			}
		}
		return Plugin_Stop;
	}
	
	g_iTimer--;
	showVoteActionPanel();
	return Plugin_Continue;
}

public Action Timer_VoteCT(Handle hTimer)
{
	if (JB_IsSpecialDayRunning() || JB_IsSpecialDayVoteRunning())
	{
		g_hVoteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_iTimer <= 1)
	{
		Call_StartForward(g_fwdOnVoteCTEnd);
		Call_PushCell(GetVoteCTWinner());
		Call_Finish();
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				g_esClientsData[iCurrentClient].Reset(false);
			}
		}
		
		delete g_arRandomVoteItems;
		g_hVoteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iTimer--;
	showVoteCTPanel();
	return Plugin_Continue;
}

public Action Timer_ResetVoteCT(Handle hTimer)
{
	if (!g_bIsVoteDisabled && !g_bIsVoteOn && GetOnlineTeamCount(CS_TEAM_T, false) >= 1 && GetOnlineTeamCount(CS_TEAM_CT, false) == 0 && !JB_IsSpecialDayRunning() && !JB_IsSpecialDayVoteRunning()) {
		StartVoteCT();
	}
	
	g_hResetTimer = INVALID_HANDLE;
}

public Action Timer_Invite(Handle hTimer)
{
	if (JB_IsSpecialDayRunning() || JB_IsSpecialDayVoteRunning() || GetAvailableGuards() <= 0)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				ToggleFreeze(iCurrentClient, false);
			}
		}
		
		RemoveCommandListener(Listener_Suicide, "kill");
		RemoveCommandListener(Listener_Suicide, "killvector");
		RemoveCommandListener(Listener_Suicide, "explode");
		RemoveCommandListener(Listener_Suicide, "explodevector");
		
		g_bIsInvitePeriodOn = false;
		g_bIsInvitePeriodTimedOut = false;
		
		g_hInviteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_iTimer <= 1)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				ToggleFreeze(iCurrentClient, false);
			}
		}
		
		RemoveCommandListener(Listener_Suicide, "kill");
		RemoveCommandListener(Listener_Suicide, "killvector");
		RemoveCommandListener(Listener_Suicide, "explode");
		RemoveCommandListener(Listener_Suicide, "explodevector");
		
		g_bIsInvitePeriodOn = false;
		g_bIsInvitePeriodTimedOut = true;
		ServerCommand("mp_restartgame 1");
		
		g_hInviteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iTimer--;
	int iAvailableGuards = GetAvailableGuards();
	ShowPanel2("<font class='fontSize-xl'>The <font color='#235CB8'>Main Guard</font> has to choose %d guard%s‏‏‎ | Time Left: %ds</font>", iAvailableGuards, iAvailableGuards > 1 ? "s":"", g_iTimer);
	
	if (g_iTimer <= g_cvCountdownSoundStartAt.IntValue)
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

//================================[ Functions ]================================//

int GetVoteByName(const char[] name)
{
	Vote CurrentVoteData;
	for (int iCurrentVote = 0; iCurrentVote < g_arVoteData.Length; iCurrentVote++)
	{
		g_arVoteData.GetArray(iCurrentVote, CurrentVoteData, sizeof(CurrentVoteData));
		if (StrEqual(CurrentVoteData.szName, name, true)) {
			return iCurrentVote;
		}
	}
	return -1;
}

any[] GetVoteByIndex(int index)
{
	Vote VoteData;
	g_arVoteData.GetArray(index, VoteData, sizeof(VoteData));
	return VoteData;
}

void StartVoteCT(bool broadcast = true)
{
	if (JB_IsSpecialDayRunning() || JB_IsSpecialDayVoteRunning())
	{
		return;
	}
	
	if (IsVoteInProgress())
	{
		PrintToChatAll("%s The \x0CVote CT\x01 has cancelled due to a vote running.", PREFIX);
		return;
	}
	
	DeleteAllTimers();
	g_bIsInvitePeriodTimedOut = false;
	g_bIsInvitePeriodOn = false;
	g_bIsVoteDisabled = false;
	
	JB_OpenCells();
	JB_SetDay(Day_Sunday);
	JB_TogglePrisonersMute(false, false);
	InitGuardsBackUp();
	g_iNumOfPassedVotes++;
	
	g_bIsVoteOn = true;
	g_iTimer = g_cvVoteTime.IntValue;
	g_iNumOfVotes = 0;
	g_hVoteTimer = CreateTimer(1.0, g_iNumOfPassedVotes <= REQUIED_PASSED_VOTES && !IsGuardsBackUpAvailable() ? Timer_VoteCT:Timer_ActionVote, _, TIMER_REPEAT);
	
	g_cvIgnoreConditions.BoolValue = true;
	
	if (g_iNumOfPassedVotes <= REQUIED_PASSED_VOTES && !IsGuardsBackUpAvailable()) {
		GetRandomVotesOrder();
	} else {
		for (int iCurrectAction = 0; iCurrectAction < sizeof(g_szActionVotes); iCurrectAction++) {
			g_iActionVotes[iCurrectAction] = 0;
		}
	}
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			g_esClientsData[iCurrentClient].Reset(false);
			if (GetClientTeam(iCurrentClient) == CS_TEAM_CT) {
				ChangeClientTeam(iCurrentClient, CS_TEAM_T);
			}
			if (!IsPlayerAlive(iCurrentClient)) {
				CS_RespawnPlayer(iCurrentClient);
			}
			
			SetGod(iCurrentClient, true);
		}
	}
	
	g_cvIgnoreConditions.BoolValue = false;
	
	bool votect_method_vote = g_iNumOfPassedVotes <= REQUIED_PASSED_VOTES && !IsGuardsBackUpAvailable();
	
	if (votect_method_vote) {
		showVoteCTPanel();
	} else {
		showVoteActionPanel();
	}
	
	Call_StartForward(g_fwdOnVoteCTStart);
	Call_PushCell(!votect_method_vote);
	Call_Finish();
	
	if (broadcast) {
		PrintToChatAll("%s \x0CVote CT\x01 has started!", PREFIX);
	}
	
	JB_WriteLogLine("Vote CT has started.");
}

void DeleteAllTimers()
{
	if (g_hResetTimer != INVALID_HANDLE) {
		KillTimer(g_hResetTimer);
	}
	g_hResetTimer = INVALID_HANDLE;
	
	if (g_hVoteTimer != INVALID_HANDLE) {
		KillTimer(g_hVoteTimer);
	}
	g_hVoteTimer = INVALID_HANDLE;
	
	if (g_hInviteTimer != INVALID_HANDLE) {
		KillTimer(g_hInviteTimer);
	}
	g_hInviteTimer = INVALID_HANDLE;
}

void SelectNewMainGuard(int oldMainGuard)
{
	int iChosenClient = GetRandomGuard(false, false);
	if (iChosenClient == -1 || iChosenClient == oldMainGuard) {
		return;
	}
	
	g_esClientsData[iChosenClient].iGuardRank = Guard_Main;
	
	PrintToChat(iChosenClient, "%s Since the old \x0Bmain guard\x01 has left, you the the new \x0CMain Guard\x01!", PREFIX);
	PrintToChat(iChosenClient, "Type \x04/ctlist\x01 to access the \x0Bmain guard\x01 menu.");
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && iCurrentClient != iChosenClient) {
			PrintToChat(iCurrentClient, "%s Since the old \x0Bmain guard\x01 \x04%N\x01 has left, \x04%N\x01 is the new \x0CMain Guard\x01!", PREFIX, oldMainGuard, iChosenClient);
		}
	}
	
	JB_WriteLogLine("The old main guard \"%L\" has left the server, guard \"%L\" has been chosen to the new main guard.", oldMainGuard, iChosenClient);
}

void GetRandomVotesOrder()
{
	g_arRandomVoteItems = g_arVoteData.Clone();
	g_arRandomVoteItems.Sort(Sort_Random, Sort_String);
}

void ShowPanel2(const char[] message, any...)
{
	char formatted_message[256];
	VFormat(formatted_message, sizeof(formatted_message), message, 2);
	
	Event event = CreateEvent("show_survival_respawn_status");
	if (event)
	{
		event.SetString("loc_token", formatted_message);
		event.SetInt("duration", PANEL_SHOW_TIME);
		event.SetInt("userid", -1);
		event.Fire();
	}
}

void InitGuardsBackUp()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			g_esClientsData[iCurrentClient].iGuardRankBackUp = g_esClientsData[iCurrentClient].iGuardRank;
		}
	}
}

void ToggleFreeze(int client, bool bMode)
{
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", bMode ? 0.0:1.0);
	if (bMode)
		SetEntityRenderColor(client, 0, 128, 255, 192);
	else
		SetEntityRenderColor(client, 255, 255, 255, 255);
}

void SetGod(int client, bool bMode)
{
	SetEntProp(client, Prop_Data, "m_takedamage", bMode ? 0:2, 1);
}

char[] GetProgressBar(int value, int all)
{
	char output[PROGRESS_BAR_LENGTH * 6];
	int iLength = PROGRESS_BAR_LENGTH;
	
	for (int iCurrentChar = 0; iCurrentChar <= (float(value) / float(all) * PROGRESS_BAR_LENGTH) - 1; iCurrentChar++)
	{
		iLength--;
		StrCat(output, sizeof(output), "⬛");
	}
	
	for (int iCurrentChar = 0; iCurrentChar < iLength; iCurrentChar++)
	{
		StrCat(output, sizeof(output), "•");
	}
	
	// StripQuotes(output);
	// TrimString(output);
	
	return output;
}

char RemoveColors(const char[] string)
{
	char szFixedString[128];
	strcopy(szFixedString, sizeof(szFixedString), string);
	
	char szColors[16][4] = { "\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07", "\x08", "\x09", "\x0A", "\x0B", "\x0C", "\x0D", "\x0E", "\x0F", "\x10" };
	
	for (int iCurrentColor = 0; iCurrentColor < sizeof(szColors); iCurrentColor++)
	{
		ReplaceString(szFixedString, sizeof(szFixedString), szColors[iCurrentColor], "", true);
	}
	
	return szFixedString;
}

bool IsGuardsBackUpAvailable()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && g_esClientsData[iCurrentClient].iGuardRankBackUp != Guard_NotGuard && !IsFakeClient(iCurrentClient))
		{
			return true;
		}
	}
	
	return false;
}

int GetActionVoteWinner()
{
	int iWinner = 0;
	for (int iCurrentVote = 0; iCurrentVote < sizeof(g_szActionVotes); iCurrentVote++)
	{
		if (g_iActionVotes[iCurrentVote] > g_iActionVotes[iWinner]) {
			iWinner = iCurrentVote;
		}
	}
	return iWinner;
}

int GetVoteCTWinner()
{
	int iWinner = 0;
	
	Vote CurrentVoteData;
	Vote WinnerVoteData;
	
	for (int iCurrentVote = 0; iCurrentVote < g_arRandomVoteItems.Length; iCurrentVote++)
	{
		g_arRandomVoteItems.GetArray(iWinner, WinnerVoteData, sizeof(WinnerVoteData));
		g_arRandomVoteItems.GetArray(iCurrentVote, CurrentVoteData, sizeof(CurrentVoteData));
		
		if (CurrentVoteData.iVotes > WinnerVoteData.iVotes) {
			iWinner = iCurrentVote;
		}
	}
	
	g_arRandomVoteItems.GetArray(iWinner, WinnerVoteData, sizeof(WinnerVoteData));
	return GetVoteByName(WinnerVoteData.szName);
}

int GetAvailableGuards()
{
	int guards = GetOnlineTeamCount(CS_TEAM_CT, false);
	int total_players = GetOnlineTeamCount(CS_TEAM_T, false) + guards;
	
	return ((total_players < 7) ? 1 : (total_players / (GUARD_PER_PLAYERS + 1))) - guards;
}

//================================================================//