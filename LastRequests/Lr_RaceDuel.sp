#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

/* Settings */

#define RANDOM_GUARD_STRING "Random Guard"

#define LR_NAME "Race Duel"
#define LR_WEAPON "weapon_knife"
#define LR_ICON "weapon_knife"

#define PREPARE_TIME 3
#define BEACON_MAXSIZE 85.0
#define MAX_RACE_DISTANCE 4000.0

/*  */

enum struct Setup
{
	bool bAllowJump;
	bool bAllowDuck;
	float fStartOrigin[3];
	float fEndOrigin[3];
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.bAllowJump = true;
		this.bAllowDuck = true;
		this.fStartOrigin = view_as<float>( { 0.0, 0.0, 0.0 } );
		this.fEndOrigin = view_as<float>( { 0.0, 0.0, 0.0 } );
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

Handle g_hPrepareTimer = INVALID_HANDLE;
Handle g_hBeaconTimer = INVALID_HANDLE;

bool g_bIsLrActivated;
bool g_IsRuneNeedToTeleport;

int g_iBeamSprite = -1;
int g_iHaloSprite = -1;

int g_iLrId = -1;

int g_iCurrentLeader;
int g_iPrepareTimer;

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
		g_iLrId = JB_AddLr(LR_NAME, false, false, true, false, 5);
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

public void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted)
{
	if (g_bIsLrActivated && g_iLrId == currentLr)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
			}
		}
		
		DeleteAllTimers();
		
		g_IsRuneNeedToTeleport = true;
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		float fOrigin[3];
		GetClientAbsOrigin(g_iCurrentLeader, fOrigin);
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)\n \n• Distance: %.2f Meters \n• Leader: %N(%.1f%%)\n• Jump: %s\n• Duck: %s", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			GetClientHealth(g_esSetupData.iPrisoner), 
			g_esSetupData.iAgainst, 
			GetClientHealth(g_esSetupData.iAgainst), 
			GetVectorDistance(g_esSetupData.fStartOrigin, g_esSetupData.fEndOrigin) * 0.2, 
			g_iCurrentLeader, 
			(100.0 - (GetVectorDistance(fOrigin, g_esSetupData.fEndOrigin) / GetVectorDistance(g_esSetupData.fStartOrigin, g_esSetupData.fEndOrigin) * 100.0)), 
			g_esSetupData.bAllowJump ? "Enabled":"Disabled", 
			g_esSetupData.bAllowDuck ? "Enabled":"Disabled"
			);
		panel.DrawText(szMessage);
	}
}

public Action JB_OnRuneSpawn(int entity, Rune runeData, int &runeId, float origin[3], int &star, int &level, bool natural)
{
	if (g_IsRuneNeedToTeleport && g_esSetupData.iPrisoner && g_esSetupData.iAgainst && IsClientInGame(g_esSetupData.iPrisoner) && IsClientInGame(g_esSetupData.iAgainst) && (IsPlayerAlive(g_esSetupData.iPrisoner) || IsPlayerAlive(g_esSetupData.iAgainst)) && natural)
	{
		RequestFrame(RF_TeleportRuneBox, EntIndexToEntRef(entity));
		g_IsRuneNeedToTeleport = false;
	}
	
	return Plugin_Continue;
}

void RF_TeleportRuneBox(int entRef)
{
	int entity = EntRefToEntIndex(entRef);
	
	if (entity == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	float teleport_pos[3];
	GetClientAbsOrigin(IsPlayerAlive(g_esSetupData.iPrisoner) ? g_esSetupData.iPrisoner : g_esSetupData.iAgainst, teleport_pos);
	
	TeleportEntity(entity, teleport_pos);
}

public void OnMapStart()
{
	DeleteAllTimers();
	
	AddFileToDownloadsTable("materials/panorama/images/icons/equipment/race_flag.svg");
	
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
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
		
		int iTarget = client == g_esSetupData.iPrisoner ? g_esSetupData.iPrisoner:g_esSetupData.iAgainst;
		int iTargetRival = iTarget == g_esSetupData.iPrisoner ? g_esSetupData.iAgainst:g_esSetupData.iPrisoner;
		
		float fTargetOrigin[3];
		float fTargetRivalOrigin[3];
		
		GetClientAbsOrigin(iTarget, fTargetOrigin);
		GetClientAbsOrigin(iTargetRival, fTargetRivalOrigin);
		
		g_iCurrentLeader = GetVectorDistance(fTargetOrigin, g_esSetupData.fEndOrigin) < GetVectorDistance(fTargetRivalOrigin, g_esSetupData.fEndOrigin) ? iTarget:iTargetRival;
		
		if (GetVectorDistance(fTargetOrigin, g_esSetupData.fEndOrigin) < (BEACON_MAXSIZE - 15.0))
		{
			DeleteAllTimers();
			ForcePlayerSuicide(iTargetRival);
		}
		if (GetVectorDistance(fTargetRivalOrigin, g_esSetupData.fEndOrigin) < (BEACON_MAXSIZE - 15.0))
		{
			DeleteAllTimers();
			ForcePlayerSuicide(iTarget);
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
	return Plugin_Handled;
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
	Format(szItem, sizeof(szItem), "(%.2f, %.2f, %.2f)", g_esSetupData.fStartOrigin[0], g_esSetupData.fStartOrigin[1], g_esSetupData.fStartOrigin[2]);
	Format(szItem, sizeof(szItem), "Start Point: %s", g_esSetupData.fStartOrigin[0] == 0.0 ? "None":szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "(%.2f, %.2f, %.2f)", g_esSetupData.fEndOrigin[0], g_esSetupData.fEndOrigin[1], g_esSetupData.fEndOrigin[2]);
	Format(szItem, sizeof(szItem), "End Point: %s", g_esSetupData.fEndOrigin[0] == 0.0 ? "None":szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Jump: %s", g_esSetupData.bAllowJump ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Allow Duck: %s", g_esSetupData.bAllowDuck ? "ON":"OFF");
	menu.AddItem("", szItem);
	
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
		
		switch (itemNum)
		{
			case 0:
			{
				if (g_esSetupData.fStartOrigin[0] == 0.0 || g_esSetupData.fEndOrigin[0] == 0.0) {
					PrintToChat(g_esSetupData.iPrisoner, "%s Please select valid race points.", PREFIX);
					showLrSetupMenu(client);
					return 0;
				}
				
				float fResult[3], fVectorLength;
				SubtractVectors(g_esSetupData.fStartOrigin, g_esSetupData.fEndOrigin, fResult);
				fVectorLength = GetVectorLength(fResult);
				
				if (fVectorLength > MAX_RACE_DISTANCE)
				{
					PrintToChat(client, "%s The distance between the points is too far!", PREFIX);
					showLrSetupMenu(client);
					return 0;
				}
				
				StartLr();
			}
			case 1:
			{
				GetNextGuard();
				showLrSetupMenu(client);
			}
			case 2:
			{
				if (!(GetEntityFlags(client) & FL_ONGROUND))
				{
					PrintToChat(client, "%s You must be standing on the ground to select a starting spot!", PREFIX);
					showLrSetupMenu(client);
					return 0;
				}
				
				GetClientAbsOrigin(client, g_esSetupData.fStartOrigin);
				ActiveBeacon(g_esSetupData.fStartOrigin, { 0, 255, 0, 255 } );
				showLrSetupMenu(client);
			}
			case 3:
			{
				if (!(GetEntityFlags(client) & FL_ONGROUND))
				{
					PrintToChat(client, "%s You must be standing on the ground to select an ending spot!", PREFIX);
					showLrSetupMenu(client);
					return 0;
				}
				
				GetClientAbsOrigin(client, g_esSetupData.fEndOrigin);
				ActiveBeacon(g_esSetupData.fEndOrigin, { 255, 0, 0, 255 } );
				showLrSetupMenu(client);
			}
			case 4:
			{
				g_esSetupData.bAllowJump = !g_esSetupData.bAllowJump;
				showLrSetupMenu(client);
			}
			case 5:
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
	
	return 0;
}

/*  */

/* Timers */

public Action Timer_RacePreapre(Handle hTimer)
{
	if (g_iPrepareTimer <= 1)
	{
		PrintCenterText(g_esSetupData.iPrisoner, "<font color='#CC00CC'>Race Duel has started! Run fast as you can!</font>");
		PrintCenterText(g_esSetupData.iAgainst, "<font color='#CC00CC'>Race Duel has started! Run fast as you can!</font>");
		
		ToggleFreeze(g_esSetupData.iPrisoner, false);
		ToggleFreeze(g_esSetupData.iAgainst, false);
		
		g_hPrepareTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iPrepareTimer--;
	PrintCenterText(g_esSetupData.iPrisoner, "<font color='#1A1AFF'> Prepare! Race Duel will start in</font>: <font color='#CC00CC'>%d</font> seconds.", g_iPrepareTimer);
	PrintCenterText(g_esSetupData.iAgainst, "<font color='#1A1AFF'> Prepare! Race Duel will start in</font>: <font color='#CC00CC'>%d</font> seconds.", g_iPrepareTimer);
	return Plugin_Continue;
}

Action Timer_EndBeacon(Handle hTimer)
{
	ActiveBeacon(g_esSetupData.fEndOrigin, { 0, 0, 255, 255 } );
	return Plugin_Continue;
}

/*  */

/* Functions */

void StartLr()
{
	if (!g_esSetupData.iAgainst) {
		g_esSetupData.iAgainst = GetRandomGuard();
	}
	
	g_iCurrentLeader = g_esSetupData.iPrisoner;
	
	g_iPrepareTimer = PREPARE_TIME;
	g_hPrepareTimer = CreateTimer(1.0, Timer_RacePreapre, _, TIMER_REPEAT);
	g_hBeaconTimer = CreateTimer(1.0, Timer_EndBeacon, _, TIMER_REPEAT);
	
	PrintCenterText(g_esSetupData.iPrisoner, "<font color='#1A1AFF'> Prepare! Race Duel will start in</font>: <font color='#CC00CC'>%d</font> seconds.", g_iPrepareTimer);
	PrintCenterText(g_esSetupData.iAgainst, "<font color='#1A1AFF'> Prepare! Race Duel will start in</font>: <font color='#CC00CC'>%d</font> seconds.", g_iPrepareTimer);
	
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			SDKHook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_ICON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	float fResult[3], fAngles[3];
	SubtractVectors(g_esSetupData.fEndOrigin, g_esSetupData.fStartOrigin, fResult);
	GetVectorAngles(fResult, fAngles);
	TeleportEntity(client, g_esSetupData.fStartOrigin, fAngles, { 0.0, 0.0, 0.0 } );
	
	DisarmPlayer(client);
	GivePlayerItem(client, LR_WEAPON);
	ToggleFreeze(client, true);
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

void DeleteAllTimers()
{
	if (g_hPrepareTimer != INVALID_HANDLE) {
		KillTimer(g_hPrepareTimer);
	}
	g_hPrepareTimer = INVALID_HANDLE;
	if (g_hBeaconTimer != INVALID_HANDLE) {
		KillTimer(g_hBeaconTimer);
	}
	g_hBeaconTimer = INVALID_HANDLE;
}

void ActiveBeacon(float origin[3], int color[4])
{
	if (g_iBeamSprite > -1 && g_iHaloSprite > -1)
	{
		origin[2] += 5.0;
		TE_SetupBeamRingPoint(origin, 10.0, BEACON_MAXSIZE, g_iBeamSprite, g_iHaloSprite, 0, 10, 1.0, 10.0, 0.5, color, 10, 0);
		TE_SendToAll();
		origin[2] -= 5.0;
	}
}

void ToggleFreeze(int client, bool bMode)
{
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", bMode ? 0.0:1.0);
}

/*  */