#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "War Day"
#define DEFAULT_HEALTH 425

#define MAX_WEAPONS 4
#define PROGRESS_BAR_LENGTH SETUP_SECONDS_TIME

#define MENU_ITEM_SOUND "buttons/button15.wav"

//====================//

enum
{
	VoteOption_1 = 0, 
	VoteOption_2, 
	VoteOption_3, 
	VoteOption_4, 
	VoteOption_Total, 
	VoteOption_Max
}

enum
{
	Weapon_Name = 0, 
	Weapon_Tag, 
	Weapon_Max
}

Handle g_hVoteTimer = INVALID_HANDLE;

ConVar g_cvInfiniteAmmo;

char g_szDayWeapon[32];

char g_szVoteWeapons[MAX_WEAPONS][Weapon_Max][] = 
{
	{ "AWP", "weapon_awp" }, 
	{ "AK-47", "weapon_ak47" }, 
	{ "M4A4", "weapon_m4a1" }, 
	{ "Desert Eagle", "weapon_deagle" }
};

bool g_bIsDayActivated;
bool g_bHeadshotOnly;

int g_iDayId = -1;

int g_iVoteTimer;

int g_iVotes[VoteOption_Max];
int g_iChosenVote[MAXPLAYERS + 1] =  { -1, ... };

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
	if (g_bIsDayActivated) 
	{
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
		
		if (g_bHeadshotOnly) 
		{
			SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
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
		
		ShowWeaponSelectionSetupPanel();
		
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
					SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
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

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if (!attacker) {
		return Plugin_Continue;
	}
	
	return (damagetype & CS_DMG_HEADSHOT) ? Plugin_Continue : Plugin_Handled;
}

//================================[ Vote Panels ]================================//

void ShowWeaponSelectionSetupPanel()
{
	char item_display[128];
	Panel panel = new Panel();
	Format(item_display, sizeof(item_display), "%s %s Setup - Weapon Selection [%s]\n ", PREFIX_MENU, DAY_NAME, GetProgressBar(g_iVoteTimer, SETUP_SECONDS_TIME));
	panel.SetTitle(item_display);
	
	for (int iCurrentWeapon = 0; iCurrentWeapon < sizeof(g_szVoteWeapons); iCurrentWeapon++)
	{
		Format(item_display, sizeof(item_display), "%s - (%d/%d | %d%%)", g_szVoteWeapons[iCurrentWeapon][Weapon_Name], g_iVotes[iCurrentWeapon], g_iVotes[VoteOption_Total], !g_iVotes[VoteOption_Total] ? 0 : RoundToFloor(float(g_iVotes[iCurrentWeapon]) / float(g_iVotes[VoteOption_Total]) * 100.0));
		panel.DrawItem(item_display);
	}
	
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
		
		bool bUpdateValues;
		if (g_iChosenVote[client] == -1) {
			PrintToChat(client, "%s You voted for \x04%s\x01.", PREFIX, g_szVoteWeapons[itemNum][Weapon_Name]);
			g_iChosenVote[client] = itemNum;
			g_iVotes[VoteOption_Total]++;
			bUpdateValues = true;
		} else if (itemNum != g_iChosenVote[client]) {
			g_iVotes[g_iChosenVote[client]]--;
			g_iChosenVote[client] = itemNum;
			PrintToChat(client, "%s You have changed your vote to \x04%s\x01.", PREFIX, g_szVoteWeapons[itemNum][Weapon_Name]);
			bUpdateValues = true;
			
		}
		
		if (bUpdateValues) {
			g_iVotes[itemNum]++;
		}
		
		EmitSoundToClient(client, MENU_ITEM_SOUND);
	}
}

void showOnlyHeadshotSetupPanel()
{
	char szTitle[128], szItem[128];
	Panel panel = new Panel();
	Format(szTitle, sizeof(szTitle), "%s %s Setup - Only Headshot [%s]\n ", PREFIX_MENU, DAY_NAME, GetProgressBar(g_iVoteTimer, SETUP_SECONDS_TIME));
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
			panel.Send(iCurrentClient, Handler_OnlyHeadshotSetup, 1);
		}
	}
	
	delete panel;
}

public int Handler_OnlyHeadshotSetup(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		itemNum -= 1; // Panel's item count starts from 1
		
		bool bUpdateValues;
		if (g_iChosenVote[client] == -1) {
			PrintToChat(client, "%s You've voted for %s\x01.", PREFIX, !itemNum ? "\x06Yes" : "\x02No");
			g_iChosenVote[client] = itemNum;
			g_iVotes[VoteOption_Total]++;
			bUpdateValues = true;
		} else if (itemNum != g_iChosenVote[client]) {
			g_iVotes[g_iChosenVote[client]]--;
			g_iChosenVote[client] = itemNum;
			PrintToChat(client, "%s You've changed your vote to %s\x01.", PREFIX, !itemNum ? "\x06Yes" : "\x02No");
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
		int iDayWeapon = GetWeaponSetupWinner();
		
		strcopy(g_szDayWeapon, sizeof(g_szDayWeapon), g_szVoteWeapons[iDayWeapon][Weapon_Tag]);
		
		PrintToChatAll("%s The selected weapon for the war day is \x04%s\x01!", PREFIX, g_szVoteWeapons[iDayWeapon][Weapon_Name]);
		
		ResetValues();
		
		g_iVoteTimer = SETUP_SECONDS_TIME;
		g_hVoteTimer = CreateTimer(1.0, Timer_OnlyHeadshotSetup, _, TIMER_REPEAT);
		showOnlyHeadshotSetupPanel();
		
		return Plugin_Stop;
	}
	
	g_iVoteTimer--;
	ShowWeaponSelectionSetupPanel();
	return Plugin_Continue;
}

public Action Timer_OnlyHeadshotSetup(Handle hTimer)
{
	if (g_iVoteTimer <= 1)
	{
		g_bHeadshotOnly = g_iVotes[VoteOption_1] >= g_iVotes[VoteOption_2];
		
		PrintToChatAll("%s War day will %shave\x01 headshot only!", PREFIX, g_iVotes[VoteOption_1] >= g_iVotes[VoteOption_2] ? "\x06" : "\x02not ");
		
		JB_StartSpecialDay(g_iDayId);
		
		g_hVoteTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iVoteTimer--;
	showOnlyHeadshotSetupPanel();
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
		if (IsClientInGame(iCurrentClient)) 
		{
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

int GetWeaponSetupWinner()
{
	int iWinner;
	
	for (int iCurrentWeapon = 0; iCurrentWeapon < sizeof(g_szVoteWeapons); iCurrentWeapon++)
	{
		if (g_iVotes[iCurrentWeapon] > g_iVotes[iWinner]) {
			iWinner = iCurrentWeapon;
		}
	}
	
	return iWinner;
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

//================================================================//