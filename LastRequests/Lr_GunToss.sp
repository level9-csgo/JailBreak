#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG & Ravid"

#define LR_NAME "Gun Toss"
#define LR_WEAPON "weapon_deagle"
#define LR_ICON "weapon_knife"

#define DEFAULT_HEALTH 100

enum struct Setup
{
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

ConVar g_FallDamageScale;

bool g_bIsLrActivated;

int g_iLrId = -1;
int g_ClientDeagleIndex[Part_Max];

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...LR_NAME..." Lr", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_FallDamageScale = FindConVar("sv_falldamage_scale");
	
	if (LibraryExists(JB_LRSYSTEM_LIBNAME))
	{
		OnLibraryAdded(JB_LRSYSTEM_LIBNAME);
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, JB_LRSYSTEM_LIBNAME))
	{
		g_iLrId = JB_AddLr(LR_NAME, false, true, true, true, 2);
	}
}

public void JB_OnLrSelected(int client, int lrId)
{
	if (g_iLrId == lrId)
	{
		g_esSetupData.Reset();
		g_esSetupData.iPrisoner = client;
		showLrSetupMenu(client);
	}
}

public void JB_OnRandomLrSelected(int client, int lrId)
{
	if (g_iLrId == lrId)
	{
		g_esSetupData.Reset();
		g_esSetupData.iPrisoner = client;
		g_esSetupData.iAgainst = GetRandomGuard();
		StartLr();
	}
}

public void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted)
{
	if (g_bIsLrActivated && g_iLrId == currentLr)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				SDKUnhook(iCurrentClient, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
			}
		}
		
		g_FallDamageScale.IntValue = 1;
		
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			GetClientHealth(g_esSetupData.iPrisoner), 
			g_esSetupData.iAgainst, 
			GetClientHealth(g_esSetupData.iAgainst)
			);
		panel.DrawText(szMessage);
	}
}

/*  */

/* SDK Hooks */

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((victim == g_esSetupData.iPrisoner && attacker != g_esSetupData.iAgainst) || (victim != g_esSetupData.iAgainst && attacker == g_esSetupData.iPrisoner))
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Hook_OnWeaponCanUse(int client, int weapon)
{
	if ((client != g_esSetupData.iPrisoner && client != g_esSetupData.iAgainst) && (g_ClientDeagleIndex[Part_Prisoner] == weapon || g_ClientDeagleIndex[Part_Guard] == weapon))
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/*  */

/* Menus */

void showLrSetupMenu(int client)
{
	char szItem[128], szItemInfo[8];
	Menu menu = new Menu(Handler_LrSetup);
	menu.SetTitle("%s Last Request - %s (Choose Your Enemy)\n ", PREFIX_MENU, LR_NAME);
	
	menu.AddItem("", "Random Enemy\n ", GetOnlineTeamCount(CS_TEAM_CT) <= 1 ? ITEMDRAW_IGNORE:ITEMDRAW_DEFAULT);
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_CT && !IsFakeClient(iCurrentClient))
		{
			IntToString(iCurrentClient, szItemInfo, sizeof(szItemInfo));
			GetClientName(iCurrentClient, szItem, sizeof(szItem));
			menu.AddItem(szItemInfo, szItem);
		}
	}
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Handler_LrSetup(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!IsLrAvailable(client, client))
		{
			return 0;
		}
		
		char szItem[16];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		
		switch (itemNum)
		{
			case 0:g_esSetupData.iAgainst = GetRandomGuard();
			default:g_esSetupData.iAgainst = StringToInt(szItem);
		}
		
		if (!IsPlayerAlive(g_esSetupData.iAgainst) || GetClientTeam(g_esSetupData.iAgainst) != CS_TEAM_CT)
		{
			showLrSetupMenu(client);
		} else {
			StartLr();
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		g_esSetupData.Reset();
		JB_ShowLrMainMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

/*  */

/* Functions */

void StartLr()
{
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && !IsFakeClient(iCurrentClient))
		{
			SDKHook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
			SDKHook(iCurrentClient, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
		}
	}
	
	g_FallDamageScale.IntValue = 0;
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_ICON);
}

void SetupPlayer(int client)
{
	if (client == -1 || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	SetEntityHealth(client, DEFAULT_HEALTH);
	int weapon_index = GivePlayerItem(client, LR_WEAPON);
	GivePlayerItem(client, "weapon_knife");
	
	g_ClientDeagleIndex[GetClientTeam(client) == CS_TEAM_T ? Part_Prisoner : Part_Guard] = weapon_index;
	
	int iSecondery = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	if (IsValidEntity(iSecondery) && iSecondery != -1) 
	{
		SetEntProp(iSecondery, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
		SetEntProp(iSecondery, Prop_Send, "m_iClip1", 0);
	}
}

/*  */