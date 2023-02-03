#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "Snipers Day"

#define DEFAULT_HEALTH 370

#define PROGRESS_BAR_LENGTH SETUP_SECONDS_TIME

#define MENU_ITEM_SOUND "buttons/button15.wav"

//====================//

enum
{
	VoteOption_1 = 0, 
	VoteOption_2, 
	VoteOption_Total, 
	VoteOption_Max
}

Handle g_hVoteTimer = INVALID_HANDLE;

ConVar g_cvInfiniteAmmo;

char g_szDayWeapon[32];

bool g_bAllowScope;

bool g_bIsDayActivated;

int g_iDayId = -1;

int g_iVoteTimer;

int g_iVotes[VoteOption_Max];
int g_iChosenVote[MAXPLAYERS + 1] = { -1, ... };

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_cvInfiniteAmmo = FindConVar("sv_infinite_ammo");
}

public void OnPluginEnd()
{
	if (g_bIsDayActivated) {
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_iDayId = JB_CreateSpecialDay(DAY_NAME, DEFAULT_HEALTH, false, false, true);
	}
}

public void OnMapStart()
{
	if (g_hVoteTimer != INVALID_HANDLE) {
		KillTimer(g_hVoteTimer);
		g_hVoteTimer = INVALID_HANDLE;
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		DisarmPlayer(client);
		GivePlayerItem(client, g_szDayWeapon);
		
		if (!g_bAllowScope) {
			SDKHook(client, SDKHook_PreThink, Hook_OnPreThink);
		}
	}
}

public void JB_OnSpecialDayVoteEnd(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		ResetValues();
		
		g_iVoteTimer = SETUP_SECONDS_TIME;
		g_hVoteTimer = CreateTimer(1.0, Timer_WeaponSelectionSetup, _, TIMER_REPEAT);
		
		showWeaponSelectionSetupPanel();
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		g_cvInfiniteAmmo.SetInt(2);
		
		ToggleBunnyhop(false);
		ToggleRunesState(false);
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_bIsDayActivated && g_iDayId == specialDayId)
	{
		if (!countdown)
		{
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient)) {
					SDKUnhook(iCurrentClient, SDKHook_PreThink, Hook_OnPreThink);
				}
			}
			
			ToggleBunnyhop(true);
			ToggleRunesState(true);
			
			g_cvInfiniteAmmo.SetInt(0);
		}
		
		if (g_hVoteTimer != INVALID_HANDLE) {
			KillTimer(g_hVoteTimer);
			g_hVoteTimer = INVALID_HANDLE;
		}
		
		g_bIsDayActivated = false;
	}
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnPreThink(int client)
{
	static int m_hActiveWeaponOffset, m_flNextSecondaryAttackOffset;
	if (!m_hActiveWeaponOffset)
	{
		m_hActiveWeaponOffset = FindSendPropInfo("CBasePlayer", "m_hActiveWeapon");
	}
	
	if (!m_flNextSecondaryAttackOffset)
	{
		m_flNextSecondaryAttackOffset = FindSendPropInfo("CBaseCombatWeapon", "m_flNextSecondaryAttack");
	}
	
	int iWeaponIndex = GetEntDataEnt2(client, m_hActiveWeaponOffset);
	if (iWeaponIndex != -1)
	{
		SetEntDataFloat(iWeaponIndex, m_flNextSecondaryAttackOffset, GetGameTime() + 2.0);
	}
}

//================================[ Vote Panels ]================================//

void showWeaponSelectionSetupPanel()
{
	char szTitle[128], szItem[128];
	Panel panel = new Panel();
	Format(szTitle, sizeof(szTitle), "%s %s Setup - Weapon Selection [%s]\n ", PREFIX_MENU, DAY_NAME, GetProgressBar(g_iVoteTimer, SETUP_SECONDS_TIME));
	panel.SetTitle(szTitle);
	
	// Vote Option 1
	Format(szItem, sizeof(szItem), "SSG 08 - (%d/%d | %d%%)", g_iVotes[VoteOption_1], g_iVotes[VoteOption_Total], !g_iVotes[VoteOption_Total] ? 0 : RoundToFloor(float(g_iVotes[VoteOption_1]) / float(g_iVotes[VoteOption_Total]) * 100.0));
	panel.DrawItem(szItem);
	
	// Vote Option 2
	Format(szItem, sizeof(szItem), "AWP - (%d/%d | %d%%)", g_iVotes[VoteOption_2], g_iVotes[VoteOption_Total], !g_iVotes[VoteOption_Total] ? 0 : RoundToFloor(float(g_iVotes[VoteOption_2]) / float(g_iVotes[VoteOption_Total]) * 100.0));
	panel.DrawItem(szItem);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			panel.Send(iCurrentClient, Handler_WeaponSelectionSetup, 1);
		}
	}
	
	delete panel;
}

public int Handler_WeaponSelectionSetup(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		itemNum -= 1; // Panel's item count starts from 1
		
		// 'menuselect x' command can cause a log error, prevent that!
		if (itemNum >= VoteOption_Total)
		{
			return;
		}
		
		bool bUpdateValues;
		if (g_iChosenVote[client] == -1) {
			PrintToChat(client, "%s You voted for \x04%s\x01.", PREFIX, !itemNum ? "SSG 08" : "AWP");
			g_iChosenVote[client] = itemNum;
			g_iVotes[VoteOption_Total]++;
			bUpdateValues = true;
		} else if (itemNum != g_iChosenVote[client]) {
			g_iVotes[g_iChosenVote[client]]--;
			g_iChosenVote[client] = itemNum;
			PrintToChat(client, "%s You have changed your vote to \x04%s\x01.", PREFIX, !itemNum ? "SSG 08" : "AWP");
			bUpdateValues = true;
			
		}
		
		if (bUpdateValues) {
			g_iVotes[itemNum]++;
		}
		
		EmitSoundToClient(client, MENU_ITEM_SOUND);
	}
}

void showAllowScopeSetupPanel()
{
	char szTitle[128], szItem[128];
	Panel panel = new Panel();
	Format(szTitle, sizeof(szTitle), "%s %s Setup - Allow Scope [%s]\n ", PREFIX_MENU, DAY_NAME, GetProgressBar(g_iVoteTimer, SETUP_SECONDS_TIME));
	panel.SetTitle(szTitle);
	
	// Vote Option 1
	Format(szItem, sizeof(szItem), "Yes - (%d/%d | %d%%)", g_iVotes[VoteOption_1], g_iVotes[VoteOption_Total], !g_iVotes[VoteOption_Total] ? 0 : RoundToFloor(float(g_iVotes[VoteOption_1]) / float(g_iVotes[VoteOption_Total]) * 100.0));
	panel.DrawItem(szItem);
	
	// Vote Option 2
	Format(szItem, sizeof(szItem), "No - (%d/%d | %d%%)", g_iVotes[VoteOption_2], g_iVotes[VoteOption_Total], !g_iVotes[VoteOption_Total] ? 0 : RoundToFloor(float(g_iVotes[VoteOption_2]) / float(g_iVotes[VoteOption_Total]) * 100.0));
	panel.DrawItem(szItem);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			panel.Send(iCurrentClient, Handler_AllowScopeSetup, 1);
		}
	}
	
	delete panel;
}

public int Handler_AllowScopeSetup(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		itemNum -= 1; // Panel's item count starts from 1
		
		// 'menuselect x' command can cause a log error, prevent that!
		if (itemNum >= VoteOption_Total)
		{
			return;
		}
		
		bool bUpdateValues;
		if (g_iChosenVote[client] == -1) {
			PrintToChat(client, "%s You voted for %s\x01.", PREFIX, !itemNum ? "\x06Yes" : "\x02No");
			g_iChosenVote[client] = itemNum;
			g_iVotes[VoteOption_Total]++;
			bUpdateValues = true;
		} else if (itemNum != g_iChosenVote[client]) {
			g_iVotes[g_iChosenVote[client]]--;
			g_iChosenVote[client] = itemNum;
			PrintToChat(client, "%s You have changed your vote to %s\x01.", PREFIX, !itemNum ? "\x06Yes" : "\x02No");
			bUpdateValues = true;
			
		}
		
		if (bUpdateValues) {
			g_iVotes[itemNum]++;
		}
		
		EmitSoundToClient(client, MENU_ITEM_SOUND);
	}
}

//================================[ Timers ]================================//

public Action Timer_WeaponSelectionSetup(Handle hTimer)
{
	if (g_iVoteTimer <= 1)
	{
		g_szDayWeapon = g_iVotes[VoteOption_1] >= g_iVotes[VoteOption_2] ? "weapon_ssg08" : "weapon_awp";
		
		PrintToChatAll("%s The selected weapon for the snipers day is \x04%s\x01!", PREFIX, g_iVotes[VoteOption_1] >= g_iVotes[VoteOption_2] ? "SSG 08" : "AWP");
		
		ResetValues();
		
		g_iVoteTimer = SETUP_SECONDS_TIME;
		g_hVoteTimer = CreateTimer(1.0, Timer_AllowScopeSetup, _, TIMER_REPEAT);
		showAllowScopeSetupPanel();
		
		return Plugin_Stop;
	}
	
	g_iVoteTimer--;
	showWeaponSelectionSetupPanel();
	return Plugin_Continue;
}

public Action Timer_AllowScopeSetup(Handle hTimer)
{
	if (g_iVoteTimer <= 1)
	{
		g_bAllowScope = g_iVotes[VoteOption_1] >= g_iVotes[VoteOption_2];
		
		PrintToChatAll("%s Snipers day will %shave\x01 scope!", PREFIX, g_iVotes[VoteOption_1] >= g_iVotes[VoteOption_2] ? "\x06" : "\x02not ");
		
		JB_StartSpecialDay(g_iDayId);
		
		g_hVoteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iVoteTimer--;
	showAllowScopeSetupPanel();
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void ResetValues()
{
	for (int iCurrentIndex = 0; iCurrentIndex < VoteOption_Max; iCurrentIndex++)
	{
		g_iVotes[iCurrentIndex] = 0;
	}
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			g_iChosenVote[iCurrentClient] = -1;
		}
	}
}

char GetProgressBar(int value, int all)
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

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

//================================================================//