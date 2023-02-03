#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define RANDOM_GUARD_STRING "Random Guard"
#define ABORT_SYMBOL "-1"

#define DEFAULT_HEALTH 750
#define MIN_HEALTH 1
#define MAX_HEALTH 1250

#define LR_NAME "Zeus Duel"
#define LR_WEAPON "weapon_taser"
#define LR_ICON "weapon_taser"

#define REFILL_TIME 3.0

//====================//

enum struct Setup
{
	bool bAllowJump;
	bool bAllowDuck;
	int iHealth;
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.bAllowJump = true;
		this.bAllowDuck = true;
		this.iHealth = DEFAULT_HEALTH;
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

Handle g_hRefillTimer[MAXPLAYERS + 1] =  { INVALID_HANDLE, ... };

bool g_bIsLrActivated = false;
bool g_bIsWrite[MAXPLAYERS + 1];

int g_flSimulationTime;
int g_flProgressBarStartTime;
int g_iProgressBarDuration;
int g_iBlockingUseActionInProgress;

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
	g_flSimulationTime = FindSendPropInfo("CBaseEntity", "m_flSimulationTime");
	g_flProgressBarStartTime = FindSendPropInfo("CCSPlayer", "m_flProgressBarStartTime");
	g_iProgressBarDuration = FindSendPropInfo("CCSPlayer", "m_iProgressBarDuration");
	g_iBlockingUseActionInProgress = FindSendPropInfo("CCSPlayer", "m_iBlockingUseActionInProgress");
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
				
				ResetProgressBar(iCurrentClient);
				
				if (g_hRefillTimer[iCurrentClient] != INVALID_HANDLE) 
				{
					KillTimer(g_hRefillTimer[iCurrentClient]);
				}
				
				g_hRefillTimer[iCurrentClient] = INVALID_HANDLE;
			}
		}
		
		UnhookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
		
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)\n \n• Health: %d HP\n• Jump: %s\n• Duck: %s", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			GetClientHealth(g_esSetupData.iPrisoner), 
			g_esSetupData.iAgainst, 
			GetClientHealth(g_esSetupData.iAgainst), 
			g_esSetupData.iHealth, 
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
	if (MIN_HEALTH <= iHealthAmount <= MAX_HEALTH) {
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

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	int primary_weapon = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
	
	// Make sure the primary weapon is exists and valid
	if (primary_weapon != -1 && IsValidEntity(primary_weapon))
	{
		// Set clip2 bullets to 1, prevents the taser from dropping
		SetEntProp(primary_weapon, Prop_Data, "m_iClip2", 1);
		
		// If the client has successfully shot, create the refill timer
		if (GetEntProp(primary_weapon, Prop_Data, "m_iClip1") == 1)
		{
			g_hRefillTimer[client] = CreateTimer(REFILL_TIME, Timer_RefillTaser, GetClientSerial(client));
			SetProgressBarFloat(client, REFILL_TIME);
		}
	}
}

/*  */

/* SDK Hooks */

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((victim == g_esSetupData.iPrisoner && attacker != g_esSetupData.iAgainst) || (victim != g_esSetupData.iAgainst && attacker == g_esSetupData.iPrisoner)) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
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
	
	Format(szItem, sizeof(szItem), "Enemy: %s", !g_esSetupData.iAgainst ? RANDOM_GUARD_STRING : szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Health: (%d/%d)", g_esSetupData.iHealth, MAX_HEALTH);
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
				g_bIsWrite[client] = true;
				PrintToChat(client, "%s Write your desired \x04health\x01 amount, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 3:
			{
				g_esSetupData.bAllowJump = !g_esSetupData.bAllowJump;
				showLrSetupMenu(client);
			}
			case 4:
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

/* Timers */

public Action Timer_RefillTaser(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (client)
	{
		int iPrimary = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
		
		if (iPrimary != -1 && IsValidEntity(iPrimary)) {
			SetEntProp(iPrimary, Prop_Data, "m_iClip2", 0);
			SetEntProp(iPrimary, Prop_Data, "m_iClip1", 1);
		}
		
		ResetProgressBar(client);
	}
	
	// Set the timer handle as invalid, to prevent timer errors
	g_hRefillTimer[client] = INVALID_HANDLE;
}

/*  */

/* Functions */

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
	
	HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_ICON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	GivePlayerItem(client, LR_WEAPON);
	SetEntityHealth(client, g_esSetupData.iHealth);
}

void InitRandomSettings()
{
	g_esSetupData.iAgainst = 0;
	g_esSetupData.iHealth = RoundToDivider(GetRandomInt(MIN_HEALTH, MAX_HEALTH), 50);
	g_esSetupData.bAllowJump = GetRandomInt(0, 1) == 1;
	g_esSetupData.bAllowDuck = GetRandomInt(0, 1) == 1;
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

void SetProgressBarFloat(int client, float fProgressTime)
{
	int iProgressTime = RoundToCeil(fProgressTime);
	float fGameTime = GetGameTime();
	
	SetEntDataFloat(client, g_flSimulationTime, fGameTime + fProgressTime, true);
	SetEntData(client, g_iProgressBarDuration, iProgressTime, 4, true);
	SetEntDataFloat(client, g_flProgressBarStartTime, fGameTime - (iProgressTime - fProgressTime), true);
	SetEntData(client, g_iBlockingUseActionInProgress, 0, 4, true);
}

void ResetProgressBar(int client)
{
	SetEntDataFloat(client, g_flProgressBarStartTime, 0.0, true);
	SetEntData(client, g_iProgressBarDuration, 0, 1, true);
}

int RoundToDivider(int value, int divider)
{
	if (value % divider != 0 && value <= 5)
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