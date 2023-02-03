#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG & Ravid"

#define RANDOM_GUARD_STRING "Random Guard"

#define LR_NAME "Custom Duel"
#define ABORT_SYMBOL "-1"

#define DEFAULT_HEALTH 100
#define MIN_HEALTH 1
#define MAX_WEAPONS 19
#define DMG_HEADSHOT 1073745922

enum struct Setup
{
	bool bHeadshot;
	bool bNoScope;
	bool bAllowJump;
	bool bAllowDuck;
	int iHealth;
	int iWeapon;
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.bHeadshot = false;
		this.bNoScope = false;
		this.bAllowJump = true;
		this.bAllowDuck = true;
		this.iHealth = DEFAULT_HEALTH;
		this.iWeapon = 0;
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

ConVar g_InfiniteAmmo;

char g_szWeaponNames[MAX_WEAPONS][] =  { "AK-47", "M4A4", "M4A1-S", "AUG", "AWP", "SSG 08", "PP-Bizon", "Desert Eagle", "Five-Seven", "Glock-18", "P2000", "M249", "Negev", "MP9", "P90", "P250", "Tec-9", "R8 Revolver", "USP-S" };
char g_szWeaponTags[MAX_WEAPONS][] =  { "weapon_ak47", "weapon_m4a1", "weapon_m4a1_silencer", "weapon_aug", "weapon_awp", "weapon_ssg08", "weapon_bizon", "weapon_deagle", "weapon_fiveseven", "weapon_glock", "weapon_hkp2000", "weapon_m249", "weapon_negev", "weapon_mp9", "weapon_p90", "weapon_p250", "weapon_tec9", "weapon_revolver", "weapon_usp_silencer" };

bool g_bIsLrActivated;
bool g_bIsWrite[MAXPLAYERS + 1];

int g_iMaxWeaponHP[MAX_WEAPONS] =  { 1000, 1000, 1000, 1000, 1200, 750, 400, 500, 500, 300, 500, 2000, 2000, 600, 500, 400, 500, 600, 500 };
int g_iLrId = -1;

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
	g_InfiniteAmmo = FindConVar("sv_infinite_ammo");
}

public void OnPluginEnd()
{
	if (g_bIsLrActivated) {
		JB_StopLr();
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_LrSystem"))
	{
		g_iLrId = JB_AddLr(LR_NAME, false, false, true, true);
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
		InitRandomSettings();
		StartLr();
	}
}

public void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted)
{
	if (g_bIsLrActivated && g_iLrId == currentLr)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				SDKUnhook(iCurrentClient, SDKHook_PreThink, Hook_OnPreThink);
			}
		}
		
		g_InfiniteAmmo.IntValue = 0;
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)\n \n• Weapon: %s\n• Health: %d HP\n• Headshot: %s\n• No Scope: %s\n• Jump: %s\n• Duck: %s", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			GetClientHealth(g_esSetupData.iPrisoner), 
			g_esSetupData.iAgainst, 
			GetClientHealth(g_esSetupData.iAgainst), 
			g_szWeaponNames[g_esSetupData.iWeapon], 
			g_esSetupData.iHealth, 
			g_esSetupData.bHeadshot ? "Enabled":"Disabled", 
			g_esSetupData.bNoScope ? "Enabled":"Disabled", 
			g_esSetupData.bAllowJump ? "Enabled":"Disabled", 
			g_esSetupData.bAllowDuck ? "Enabled":"Disabled"
			);
		panel.DrawText(szMessage);
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_bIsWrite[client] = false;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (!g_bIsWrite[client]) {
		return Plugin_Continue;
	}
	
	if (StrEqual(szArgs, ABORT_SYMBOL)) {
		PrintToChat(client, "%s Operation has \x07aborted\x01.", PREFIX);
		showLrSetupMenu(client);
		g_bIsWrite[client] = false;
		return Plugin_Handled;
	}
	
	int iHealthAmount = StringToInt(szArgs);
	if (MIN_HEALTH <= iHealthAmount <= g_iMaxWeaponHP[g_esSetupData.iWeapon]) {
		g_esSetupData.iHealth = iHealthAmount;
	} else {
		PrintToChat(client, "%s You have specifed an invalid \x04health\x01 amount! [\x02%s\x01]", PREFIX, szArgs);
	}
	
	showLrSetupMenu(client);
	g_bIsWrite[client] = false;
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (g_bIsLrActivated && (client == g_esSetupData.iPrisoner || client == g_esSetupData.iAgainst))
	{
		bool bPrees = false;
		if (!g_esSetupData.bAllowJump && (buttons & IN_JUMP)) {
			buttons &= ~IN_JUMP;
			bPrees = true;
		}
		if (!g_esSetupData.bAllowDuck && (buttons & IN_DUCK)) {
			buttons &= ~IN_DUCK;
			bPrees = true;
		}
		
		if (bPrees) {
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

/*  */

/* SDK Hooks */

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((victim == g_esSetupData.iPrisoner && attacker != g_esSetupData.iAgainst) || (victim != g_esSetupData.iAgainst && attacker == g_esSetupData.iPrisoner)) {
		return Plugin_Handled;
	}
	
	if (!(1 <= attacker <= MaxClients))
	{
		return Plugin_Continue;
	}
	
	char szWeapon[64];
	GetClientWeapon(attacker, szWeapon, sizeof(szWeapon));
	
	if (StrContains(szWeapon, "knife") != -1 || StrContains(szWeapon, "bayonet") != -1) {
		return Plugin_Handled;
	}
	
	if (g_esSetupData.bHeadshot) {
		return damagetype == DMG_HEADSHOT ? Plugin_Continue:Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Hook_OnPreThink(int client)
{
	if (g_esSetupData.bNoScope)
	{
		int iWeaponIndex = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (IsValidEntity(iWeaponIndex))
		{
			char szClassName[128];
			GetEdictClassname(iWeaponIndex, szClassName, sizeof(szClassName));
			
			if (StrEqual(szClassName[7], "ssg08") || StrEqual(szClassName[7], "aug") || StrEqual(szClassName[7], "awp")) {
				SetEntDataFloat(iWeaponIndex, FindSendPropInfo("CBaseCombatWeapon", "m_flNextSecondaryAttack"), GetGameTime() + 2.0);
			}
		}
	}
}

/*  */

/* Menus */

void showLrSetupMenu(int client)
{
	char szItem[128];
	Menu menu = new Menu(Handler_LrSetup);
	menu.SetTitle("%s Last Request - %s Setup\n ", PREFIX_MENU, LR_NAME);
	
	menu.AddItem("", "Start Game");
	
	if (g_esSetupData.iAgainst) {
		GetClientName(g_esSetupData.iAgainst, szItem, sizeof(szItem));
	}
	
	Format(szItem, sizeof(szItem), "Enemy: %s", !g_esSetupData.iAgainst ? RANDOM_GUARD_STRING:szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Weapon: %s", g_szWeaponNames[g_esSetupData.iWeapon]);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Health: (%d/%d)", g_esSetupData.iHealth, g_iMaxWeaponHP[g_esSetupData.iWeapon]);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Headshot: %s", g_esSetupData.bHeadshot ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "No Scope: %s", g_esSetupData.bNoScope ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Jump: %s", g_esSetupData.bAllowJump ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Duck: %s", g_esSetupData.bAllowDuck ? "ON":"OFF");
	menu.AddItem("", szItem);
	
	JB_FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_LrSetup(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!IsLrAvailable(client, client))
		{
			return;
		}
		
		switch (itemNum)
		{
			case 0:
			{
				StartLr();
			}
			case 1:
			{
				GetNextGuard();
				showLrSetupMenu(client);
			}
			case 2:
			{
				g_esSetupData.iWeapon++;
				if (g_esSetupData.iWeapon == sizeof(g_szWeaponTags)) {
					g_esSetupData.iWeapon = 0;
				}
				g_esSetupData.iHealth = DEFAULT_HEALTH;
				showLrSetupMenu(client);
			}
			case 3:
			{
				g_bIsWrite[client] = true;
				PrintToChat(client, "%s Type your desired \x04health\x01 amount, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 4:
			{
				g_esSetupData.bHeadshot = !g_esSetupData.bHeadshot;
				showLrSetupMenu(client);
			}
			case 5:
			{
				g_esSetupData.bNoScope = !g_esSetupData.bNoScope;
				showLrSetupMenu(client);
			}
			case 6:
			{
				g_esSetupData.bAllowJump = !g_esSetupData.bAllowJump;
				showLrSetupMenu(client);
			}
			case 7:
			{
				g_esSetupData.bAllowDuck = !g_esSetupData.bAllowDuck;
				showLrSetupMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack) {
		g_esSetupData.Reset();
		JB_ShowLrMainMenu(client);
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

/*  */

/* Functions */

void InitRandomSettings()
{
	g_esSetupData.iAgainst = 0;
	g_esSetupData.iWeapon = GetRandomInt(0, sizeof(g_szWeaponTags) - 1);
	g_esSetupData.iHealth = RoundToDivider(GetRandomInt(MIN_HEALTH, g_iMaxWeaponHP[g_esSetupData.iWeapon]), 50);
	g_esSetupData.bHeadshot = GetRandomInt(0, 1) == 1;
	g_esSetupData.bNoScope = GetRandomInt(0, 1) == 1;
	g_esSetupData.bAllowJump = GetRandomInt(0, 1) == 1;
	g_esSetupData.bAllowDuck = GetRandomInt(0, 1) == 1;
}

void StartLr()
{
	if (!g_esSetupData.iAgainst) {
		g_esSetupData.iAgainst = GetRandomGuard();
	}
	
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			SDKHook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	g_InfiniteAmmo.IntValue = 2;
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, g_szWeaponTags[g_esSetupData.iWeapon]);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	GivePlayerItem(client, g_szWeaponTags[g_esSetupData.iWeapon]);
	GivePlayerItem(client, "weapon_knife");
	SetEntityHealth(client, g_esSetupData.iHealth);
	
	SDKHook(client, SDKHook_PreThink, Hook_OnPreThink);
}

void GetNextGuard()
{
	bool bFound;
	
	while (!bFound)
	{
		g_esSetupData.iAgainst++;
		if (g_esSetupData.iAgainst > MaxClients) {
			bFound = true;
			g_esSetupData.iAgainst = 0;
		}
		else if (IsClientInGame(g_esSetupData.iAgainst) && IsPlayerAlive(g_esSetupData.iAgainst) && JB_GetClientGuardRank(g_esSetupData.iAgainst) != Guard_NotGuard) {
			bFound = true;
		}
	}
}

int RoundToDivider(int value, int divider)
{
	if (value % divider != 0 && value >= 5)
	{
		if (value % divider >= divider / 2 || value - value % divider == 0) {
			value += divider - value % divider;
		}
		else {
			value -= value % divider;
		}
	}
	return value;
}

/*  */