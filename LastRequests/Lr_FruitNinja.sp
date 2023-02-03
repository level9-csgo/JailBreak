#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#include <customweapons>

#define PLUGIN_AUTHOR "KoNLiG & TorNim0s"

/* Settings */

#define RANDOM_GUARD_STRING "Random Guard"

#define LR_NAME "Fruit Ninja"
#define LR_WEAPON "weapon_knife"
#define PREPARE_TIME 3
#define KILL_FRUIT_TIME 0.8

#define DEFAULT_HEALTH 100
#define DEFAULT_NEEDED_SLICES 15
#define MIN_NEEDED_SLICES 10
#define MAX_NEEDED_SLICES 20

#define FRUIT_SWORD_MODEL "models/weapons/eminem/master_sword/v_master_sword.mdl"

/*  */

enum struct Setup
{
	int iNeededSlices;
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.iNeededSlices = DEFAULT_NEEDED_SLICES;
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

Handle g_hPrepareTimer = INVALID_HANDLE;
Handle g_hSpawnFruitsTimer = INVALID_HANDLE;

char g_szFruitsModels[][] = 
{
	"models/props_junk/watermelon01.mdl", 
	"models/props/cs_italy/orange.mdl", 
	"models/props/cs_italy/bananna.mdl", 
	"models/props/cs_italy/bananna_bunch.mdl"
};

bool g_bIsLrActivated;

int g_iLrId = -1;
int g_iPrepareTime;

int g_iPrisonerCounter;
int g_iGuardCounter;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...LR_NAME..." Lr", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

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
			if (IsClientInGame(iCurrentClient))
			{
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				
				int lr_weapon = GetPlayerWeaponSlot(iCurrentClient, CS_SLOT_KNIFE);
				if (lr_weapon != -1)
				{
					RemovePlayerItem(iCurrentClient, lr_weapon);
					EquipPlayerWeapon(iCurrentClient, lr_weapon);
				}
			}
		}
		
		DeleteAllTimers();
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d Fruits Left)\n• Against: %N (%d Fruits Left)", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			g_iPrisonerCounter, 
			g_esSetupData.iAgainst, 
			g_iGuardCounter
			);
		panel.DrawText(szMessage);
	}
}

public void OnMapStart()
{
	DeleteAllTimers();
	
	PrecacheModel(FRUIT_SWORD_MODEL);
}

/*  */

/* SDK Hooks */

public Action Hook_OnTakeDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if (1 <= entity <= MaxClients) {
		return Plugin_Handled;
	}
	
	char sEntityName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", sEntityName, sizeof(sEntityName));
	
	if (IsValidEntity(entity) && (1 <= attacker <= MaxClients))
	{
		int iClientTeam = GetClientTeam(attacker);
		if (StrEqual(sEntityName, "PrisonerFruit"))
		{
			if (iClientTeam == CS_TEAM_T) {
				g_iPrisonerCounter--;
			}
			else if (iClientTeam == CS_TEAM_CT) {
				if (g_iGuardCounter > g_esSetupData.iNeededSlices - 1)
					g_iGuardCounter = g_esSetupData.iNeededSlices;
				else
					g_iGuardCounter++;
			}
		}
		else if (StrEqual(sEntityName, "GuardFruit"))
		{
			if (iClientTeam == CS_TEAM_CT) {
				g_iGuardCounter--;
			}
			else if (iClientTeam == CS_TEAM_T)
			{
				if (g_iPrisonerCounter > g_esSetupData.iNeededSlices - 1)
					g_iPrisonerCounter = g_esSetupData.iNeededSlices;
				else
					g_iPrisonerCounter++;
			}
		}
		else if (StrEqual(sEntityName, "Bomb"))
		{
			int iBombValue = RoundToFloor(g_esSetupData.iNeededSlices * 0.25);
			if (iClientTeam == CS_TEAM_T)
			{
				if (g_iPrisonerCounter > g_esSetupData.iNeededSlices - iBombValue)
					g_iPrisonerCounter = g_esSetupData.iNeededSlices;
				else
					g_iPrisonerCounter += iBombValue;
				
			}
			else if (iClientTeam == CS_TEAM_CT)
			{
				if (g_iGuardCounter > g_esSetupData.iNeededSlices - iBombValue)
					g_iGuardCounter = g_esSetupData.iNeededSlices;
				else
					g_iGuardCounter += iBombValue;
			}
		}
		
		if (g_iPrisonerCounter <= 0) {
			ForcePlayerSuicide(g_esSetupData.iAgainst);
		}
		if (g_iGuardCounter <= 0) {
			ForcePlayerSuicide(g_esSetupData.iPrisoner);
		}
		
		AcceptEntityInput(entity, "Kill");
		PrintCenterTextAll("<font color='#8AC7DB'> %N</font> Counter: <font color='#CC0000'>%d</font> \n<font color='#8AC7DB'>%N</font> Counter: <font color='#CC0000'>%d</font>", g_esSetupData.iPrisoner, g_iPrisonerCounter, g_esSetupData.iAgainst, g_iGuardCounter);
	}
	
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (g_bIsLrActivated && StrEqual(classname, "prop_physics"))
	{
		SDKHook(entity, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		CreateTimer(KILL_FRUIT_TIME, Timer_KillFruit, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
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
	Format(szItem, sizeof(szItem), "Needed Slices: (%d/%d)", g_esSetupData.iNeededSlices, MAX_NEEDED_SLICES);
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
				StartLr();
			}
			case 1:
			{
				GetNextGuard();
				showLrSetupMenu(client);
			}
			case 2:
			{
				g_esSetupData.iNeededSlices++;
				if (g_esSetupData.iNeededSlices == MAX_NEEDED_SLICES + 1) {
					g_esSetupData.iNeededSlices = MIN_NEEDED_SLICES;
				}
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

public Action Timer_Prepare(Handle hTimer)
{
	if (g_iPrepareTime <= 1) {
		PrintCenterTextAll("<font color=#ff0000> %N</font> Counter: %d <br><font color=#0000ff>%N</font> Counter: %d", g_esSetupData.iPrisoner, g_iPrisonerCounter, g_esSetupData.iAgainst, g_iGuardCounter);
		
		g_hSpawnFruitsTimer = CreateTimer(1.0, Timer_SpawnFruits, _, TIMER_REPEAT);
		g_hPrepareTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iPrepareTime--;
	PrintCenterTextAll("<font color='#0000B3'> %s</font> will start in <font color='#CC0000'>%d</font> seconds.", LR_NAME, g_iPrepareTime);
	return Plugin_Continue;
}

public Action Timer_SpawnFruits(Handle hTimer)
{
	if (!g_bIsLrActivated) {
		g_hSpawnFruitsTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	PrintCenterTextAll("<font color='#8AC7DB'> %N</font> Counter: <font color='#CC0000'>%d</font> \n<font color='#8AC7DB'>%N</font> Counter: <font color='#CC0000'>%d</font>", g_esSetupData.iPrisoner, g_iPrisonerCounter, g_esSetupData.iAgainst, g_iGuardCounter);
	SpawnFruit(g_esSetupData.iPrisoner);
	SpawnFruit(g_esSetupData.iAgainst);
	return Plugin_Continue;
}

public Action Timer_KillFruit(Handle hTimer, int entRef)
{
	int iEntity = EntRefToEntIndex(entRef);
	if (iEntity != INVALID_ENT_REFERENCE)
	{
		char sEntityName[64];
		GetEntPropString(iEntity, Prop_Data, "m_iName", sEntityName, sizeof(sEntityName));
		if (StrEqual(sEntityName, "PrisonerFruit") || StrEqual(sEntityName, "GuardFruit") || StrEqual(sEntityName, "Bomb"))
		{
			AcceptEntityInput(iEntity, "Kill");
		}
	}
	
	return Plugin_Continue;
}

/*  */

/* Functions */

void StartLr()
{
	if (!g_esSetupData.iAgainst) {
		g_esSetupData.iAgainst = GetRandomGuard();
	}
	
	g_iPrisonerCounter = g_esSetupData.iNeededSlices;
	g_iGuardCounter = g_esSetupData.iNeededSlices;
	
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			SDKHook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	g_iPrepareTime = PREPARE_TIME;
	PrintCenterTextAll("<font color='#0000B3'> %s</font> will start in <font color='#CC0000'>%d</font> seconds.", LR_NAME, g_iPrepareTime);
	g_hPrepareTimer = CreateTimer(1.0, Timer_Prepare, _, TIMER_REPEAT);
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_WEAPON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	SetEntityHealth(client, DEFAULT_HEALTH);
	int sword = GivePlayerItem(client, LR_WEAPON);
	if (sword != -1)
	{
		CustomWeapon custom_weapon = CustomWeapon(sword);
		if (custom_weapon)
		{
			custom_weapon.SetModel(CustomWeaponModel_View, FRUIT_SWORD_MODEL);
		}
	}
}

void InitRandomSettings()
{
	g_esSetupData.iAgainst = 0;
	g_esSetupData.iNeededSlices = GetRandomInt(MIN_NEEDED_SLICES, MAX_NEEDED_SLICES);
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
	if (g_hSpawnFruitsTimer != INVALID_HANDLE) {
		KillTimer(g_hSpawnFruitsTimer);
	}
	g_hSpawnFruitsTimer = INVALID_HANDLE;
}

void SpawnFruit(int client)
{
	if (!IsPlayerAlive(client)) {
		return;
	}
	
	float fFruitSpawnOrigin[3];
	GetClientAbsOrigin(client, fFruitSpawnOrigin);
	
	float fRandomPos[3];
	int iEntity = -1;
	int iBombPercent;
	
	for (int iSpawnedFruits = 0; iSpawnedFruits < GetRandomInt(3, 10); iSpawnedFruits++)
	{
		iEntity = CreateEntityByName("prop_physics");
		iBombPercent = GetRandomInt(0, 15);
		fRandomPos[0] = GetRandomFloat(-30.0, 30.0);
		fRandomPos[1] = GetRandomFloat(-30.0, 30.0);
		fRandomPos[2] = GetRandomFloat(150.0, 250.0);
		
		if (iBombPercent != 5) {
			DispatchKeyValue(iEntity, "model", g_szFruitsModels[GetRandomInt(0, 3)]);
			SetEntPropString(iEntity, Prop_Data, "m_iName", client == g_esSetupData.iPrisoner ? "PrisonerFruit":"GuardFruit");
		} else {
			DispatchKeyValue(iEntity, "model", "models/props_junk/watermelon01.mdl");
			SetEntityRenderColor(iEntity, 0, 0, 0, 255);
			SetEntPropString(iEntity, Prop_Data, "m_iName", "Bomb");
		}
		
		fFruitSpawnOrigin[0] += fRandomPos[0];
		fFruitSpawnOrigin[1] += fRandomPos[1];
		fFruitSpawnOrigin[2] += fRandomPos[2];
		
		DispatchSpawn(iEntity);
		TeleportEntity(iEntity, fFruitSpawnOrigin, NULL_VECTOR, NULL_VECTOR);
		
		fFruitSpawnOrigin[0] -= fRandomPos[0];
		fFruitSpawnOrigin[1] -= fRandomPos[1];
		fFruitSpawnOrigin[2] -= fRandomPos[2];
	}
}

/*  */