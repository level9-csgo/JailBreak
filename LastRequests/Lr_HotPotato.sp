#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RANDOM_GUARD_STRING "Random Guard"

#define LR_NAME "Hot Potato"
#define LR_WEAPON "weapon_deagle"
#define LR_ICON "inferno"

#define DEFAULT_HEALTH 100
#define MIN_LR_TIME 15.0
#define MAX_LR_TIME 20.0

enum struct Setup
{
	bool bFreezeMode;
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.bFreezeMode = true;
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

Handle g_hExplodeTimer = INVALID_HANDLE;

bool g_bIsLrActivated;
bool g_IsRuneNeedToTeleport;

int g_iLrId = -1;
int g_iCurrentHolder;
int g_iWeaponRef = INVALID_ENT_REFERENCE;

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
		g_iLrId = JB_AddLr(LR_NAME, true, true, true, true);
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
		if (g_hExplodeTimer != INVALID_HANDLE)
		{
			KillTimer(g_hExplodeTimer);
		}
		
		g_hExplodeTimer = INVALID_HANDLE;
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				SDKUnhook(iCurrentClient, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
				
				ToggleFreeze(iCurrentClient, false);
			}
		}
		
		g_IsRuneNeedToTeleport = true;
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr && g_bIsLrActivated)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)\n \n• Current Holder: %N\n• Freeze Mode: %s", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			GetClientHealth(g_esSetupData.iPrisoner), 
			g_esSetupData.iAgainst, 
			GetClientHealth(g_esSetupData.iAgainst), 
			g_iCurrentHolder, 
			g_esSetupData.bFreezeMode ? "Enabled":"Disabled"
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

public Action CS_OnCSWeaponDrop(int client, int weaponIndex)
{
	if (g_bIsLrActivated)
	{
		int iEntity = EntRefToEntIndex(g_iWeaponRef);
		if (iEntity != INVALID_ENT_REFERENCE && iEntity == weaponIndex) {
			SDKHook(weaponIndex, SDKHook_Think, Hook_OnThink);
		}
	}
}

/*  */

/* SDK Hooks */

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	return Plugin_Handled;
}

public Action Hook_OnWeaponCanUse(int client, int weapon)
{
	int iEntity = EntRefToEntIndex(g_iWeaponRef);
	if (iEntity != INVALID_ENT_REFERENCE && iEntity == weapon && (client == g_esSetupData.iPrisoner || client == g_esSetupData.iAgainst))
	{
		g_iCurrentHolder = client;
		SDKUnhook(EntRefToEntIndex(g_iWeaponRef), SDKHook_Think, Hook_OnThink);
	}
}

void Hook_OnThink(int entity)
{
	static float last_origin[3];
	
	if (!g_bIsLrActivated)
	{
		AcceptEntityInput(entity, "Kill");
		return;
	}
	
	float current_origin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", current_origin);
	
	if (current_origin[0] == last_origin[0] && current_origin[1] == last_origin[1] && current_origin[2] == last_origin[2])
	{
		AcceptEntityInput(entity, "Kill");
		
		int iSecondery = GivePlayerItem(g_iCurrentHolder, LR_WEAPON);
		EquipPlayerWeapon(g_iCurrentHolder, iSecondery);
		g_iWeaponRef = EntIndexToEntRef(iSecondery);
		
		if (IsValidEntity(iSecondery) && iSecondery != -1) {
			SetEntProp(iSecondery, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
			SetEntProp(iSecondery, Prop_Send, "m_iClip1", 0);
		}
	}
	
	last_origin = current_origin;
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
	Format(szItem, sizeof(szItem), "Freeze Mode: %s", g_esSetupData.bFreezeMode ? "ON":"OFF");
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
				g_esSetupData.bFreezeMode = !g_esSetupData.bFreezeMode;
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

public Action Timer_Explode(Handle hTimer)
{
	ForcePlayerSuicide(g_iCurrentHolder);
	g_hExplodeTimer = INVALID_HANDLE;
}

/*  */

/* Functions */

void ToggleFreeze(int client, bool bMode)
{
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", bMode ? 0.0:1.0);
}

void StartLr()
{
	float fPrisonerPos[3], fPrisonerAng[3];
	GetClientAbsOrigin(g_esSetupData.iPrisoner, fPrisonerPos);
	GetClientAbsAngles(g_esSetupData.iPrisoner, fPrisonerAng);
	
	float fForward[3], fFinalPos[3], fFinalAng[3];
	GetAngleVectors(fPrisonerAng, fForward, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(fForward, 150.0);
	AddVectors(fPrisonerPos, fForward, fFinalPos);
	
	float fResult[3];
	SubtractVectors(fPrisonerPos, fFinalPos, fResult);
	GetVectorAngles(fResult, fFinalAng);
	
	fPrisonerPos[2] += 10.0; fFinalPos[2] += 10.0;
	TR_TraceRayFilter(fPrisonerPos, fFinalPos, MASK_ALL, RayType_EndPoint, Filter_DontHitPlayers);
	
	if (TR_DidHit()) {
		PrintToChat(g_esSetupData.iPrisoner, "%s Don't pick a position next to a wall!", PREFIX_ERROR);
		showLrSetupMenu(g_esSetupData.iPrisoner);
		return;
	}
	
	if (!g_esSetupData.iAgainst) {
		g_esSetupData.iAgainst = GetRandomGuard();
	}
	
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	int iSecondery = GivePlayerItem(g_esSetupData.iPrisoner, LR_WEAPON);
	EquipPlayerWeapon(g_esSetupData.iPrisoner, iSecondery);
	g_iWeaponRef = EntIndexToEntRef(iSecondery);
	g_iCurrentHolder = g_esSetupData.iPrisoner;
	
	if (IsValidEntity(iSecondery) && iSecondery != -1) {
		SetEntProp(iSecondery, Prop_Send, "m_iPrimaryReserveAmmoCount", 0);
		SetEntProp(iSecondery, Prop_Send, "m_iClip1", 0);
	}
	
	g_hExplodeTimer = CreateTimer(GetRandomFloat(MIN_LR_TIME, MAX_LR_TIME), Timer_Explode);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && !IsFakeClient(iCurrentClient)) {
			SDKHook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	TeleportEntity(g_esSetupData.iPrisoner, fPrisonerPos, NULL_VECTOR, { 0.0, 0.0, 0.0 } );
	TeleportEntity(g_esSetupData.iAgainst, fFinalPos, fFinalAng, { 0.0, 0.0, 0.0 } );
	
	if (g_esSetupData.bFreezeMode) {
		ToggleFreeze(g_esSetupData.iPrisoner, true);
		ToggleFreeze(g_esSetupData.iAgainst, true);
	} else {
		ToggleFreeze(g_esSetupData.iPrisoner, false);
		ToggleFreeze(g_esSetupData.iAgainst, false);
	}
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_ICON);
}

public bool Filter_DontHitPlayers(int entity, int mask)
{
	return !(1 <= entity <= MaxClients);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	SetEntityHealth(client, DEFAULT_HEALTH);
	SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
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

/* */