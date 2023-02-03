#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG"

/* Settings */

#define RANDOM_GUARD_STRING "Random Guard"

#define LR_NAME "Flying Stabs"
#define LR_WEAPON "weapon_knife"

#define ABORT_SYMBOL "-1"
#define SHOW_PATH_TIME 5.0
#define FREEZE_TIME 3

#define MAX_HEIGTH 10.0
#define MAX_LR_DISTANCE 700.0
#define MIN_LR_DISTANCE 200.0

#define MIN_HEALTH 1
#define MAX_HEALTH 200
#define DEFAULT_HEALTH 100

/*  */

enum struct Setup
{
	bool bBackstab;
	float fPrisonerOrigin[3];
	float fGuardOrigin[3];
	int iHealth;
	int iPrisoner;
	int iAgainst;
	
	void Reset() {
		this.bBackstab = false;
		this.fPrisonerOrigin = view_as<float>( { 0.0, 0.0, 0.0 } );
		this.fGuardOrigin = view_as<float>( { 0.0, 0.0, 0.0 } );
		this.iHealth = DEFAULT_HEALTH;
		this.iPrisoner = 0;
		this.iAgainst = 0;
	}
}

Setup g_esSetupData;

Handle g_hFlyStabTimer = INVALID_HANDLE;

char g_szFirstStab[MAX_NAME_LENGTH] = "Nobody";

bool g_bIsWrite[MAXPLAYERS + 1];
bool g_bIsLrActivated;
bool g_bIsFrozen = true;

int g_iLrId = -1;

int g_iBeamSprite = -1;
int g_iHaloSprite = -1;
int g_iGlowSprite = -1;

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
		g_iLrId = JB_AddLr(LR_NAME, false, false, true, false);
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
				ToggleFreeze(iCurrentClient, false);
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
			}
		}
		
		if (g_hFlyStabTimer != INVALID_HANDLE) {
			KillTimer(g_hFlyStabTimer);
		}
		g_hFlyStabTimer = INVALID_HANDLE;
		
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Game: %s\n• Prisoner: %N (%d HP)\n• Against: %N (%d HP)\n \n• Health: %d\n• Backstab: %s\n• First Stab: %s", 
			LR_NAME, 
			g_esSetupData.iPrisoner, 
			GetClientHealth(g_esSetupData.iPrisoner), 
			g_esSetupData.iAgainst, 
			GetClientHealth(g_esSetupData.iAgainst), 
			g_esSetupData.iHealth, 
			g_esSetupData.bBackstab ? "Enabled":"Disabled", 
			g_szFirstStab
			);
		panel.DrawText(szMessage);
	}
}

public void OnMapStart()
{
	if (g_hFlyStabTimer != INVALID_HANDLE) {
		KillTimer(g_hFlyStabTimer);
	}
	g_hFlyStabTimer = INVALID_HANDLE;
	
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
	g_iGlowSprite = PrecacheModel("materials/sprites/ledglow.vmt");
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

/*  */

/* SDK Hooks */

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((victim == g_esSetupData.iPrisoner && attacker != g_esSetupData.iAgainst) || (victim != g_esSetupData.iAgainst && attacker == g_esSetupData.iPrisoner)) 
	{
		return Plugin_Handled;
	}
	
	if (!StrEqual(g_szFirstStab, "Nobody", true)) 
	{
		return Plugin_Handled;
	}
	
	if (g_esSetupData.bBackstab)
	{
		if (IsStabBackstab(attacker, victim)) 
		{
			if (1 <= attacker <= MaxClients) 
			{
				GetClientName(attacker, g_szFirstStab, sizeof(g_szFirstStab));
			}

			return Plugin_Continue;
		} 
		else 
		{
			return Plugin_Handled;
		}
	} 
	else if (1 <= attacker <= MaxClients) 
	{
		GetClientName(attacker, g_szFirstStab, sizeof(g_szFirstStab));
	}
	
	return Plugin_Continue;
}

bool IsStabBackstab(int attacker, int victim)
{
    // Initialize buffers.
    float abs_angles[3], victim_forward[3], attacker_origin[3], victim_origin[3], vec_los[3];
    
    GetClientAbsAngles(victim, abs_angles);
    GetAngleVectors(abs_angles, victim_forward, NULL_VECTOR, NULL_VECTOR);
    
    GetClientAbsOrigin(attacker, attacker_origin);
    GetClientAbsOrigin(victim, victim_origin);
    
    SubtractVectors(victim_origin, attacker_origin, vec_los);
    NormalizeVector(vec_los, vec_los);
    
    // 2D Vectors representation.
    vec_los[2] = 0.0;
    victim_forward[2] = 0.0;
    
    return GetVectorDotProduct(victim_forward, vec_los) > 0.475;
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
	Format(szItem, sizeof(szItem), "(%.2f, %.2f, %.2f)", g_esSetupData.fPrisonerOrigin[0], g_esSetupData.fPrisonerOrigin[1], g_esSetupData.fPrisonerOrigin[2]);
	Format(szItem, sizeof(szItem), "Prisoner Position: %s", g_esSetupData.fPrisonerOrigin[0] == 0.0 ? "None":szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "(%.2f, %.2f, %.2f)", g_esSetupData.fGuardOrigin[0], g_esSetupData.fGuardOrigin[1], g_esSetupData.fGuardOrigin[2]);
	Format(szItem, sizeof(szItem), "Guard Position: %s", g_esSetupData.fGuardOrigin[0] == 0.0 ? "None":szItem);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Health: (%d/%d)", g_esSetupData.iHealth, MAX_HEALTH);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Backstab: %s", g_esSetupData.bBackstab ? "ON":"OFF");
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
				static float fCooldown[MAXPLAYERS + 1];
				float fCurrentTime = GetGameTime();
				
				if (fCurrentTime - fCooldown[client] < SHOW_PATH_TIME) {
					PrintToChat(client, "%s Please wait \x04%.1f\x01 seconds before trying to start the lr again.", PREFIX, fCooldown[client] + SHOW_PATH_TIME - fCurrentTime);
					showLrSetupMenu(client);
					return;
				}
				
				if (g_esSetupData.fPrisonerOrigin[0] == 0.0 || g_esSetupData.fGuardOrigin[0] == 0.0) {
					PrintToChat(g_esSetupData.iPrisoner, "%s Please select valid flying stabs points.", PREFIX);
					showLrSetupMenu(client);
					return;
				}
				
				float fResult[3], fVectorLength;
				SubtractVectors(g_esSetupData.fPrisonerOrigin, g_esSetupData.fGuardOrigin, fResult);
				fVectorLength = GetVectorLength(fResult);
				
				if (fVectorLength > MAX_LR_DISTANCE)
				{
					PrintToChat(client, "%s The distance between the points is too far!", PREFIX);
					showLrSetupMenu(client);
					return;
				}
				
				if (fVectorLength < MIN_LR_DISTANCE)
				{
					PrintToChat(client, "%s The distance between the points is too short!", PREFIX);
					showLrSetupMenu(client);
					return;
				}
				
				if ((g_esSetupData.fPrisonerOrigin[2] - g_esSetupData.fGuardOrigin[2]) > MAX_HEIGTH) {
					PrintToChat(g_esSetupData.iPrisoner, "%s The points must be in the same height.", PREFIX);
					showLrSetupMenu(client);
					return;
				}
				
				if (IsEntityBetween(g_esSetupData.fPrisonerOrigin, g_esSetupData.fGuardOrigin)) {
					PrintToChat(g_esSetupData.iPrisoner, "%s The points must be between an empty path.", PREFIX);
					showLrSetupMenu(client);
					fCooldown[client] = fCurrentTime;
					return;
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
					PrintToChat(client, "%s You must be standing on the ground to select a prisoner spot!", PREFIX);
					showLrSetupMenu(client);
					return;
				}
				
				GetClientAbsOrigin(client, g_esSetupData.fPrisonerOrigin);
				ActiveBeacon(g_esSetupData.fPrisonerOrigin, { 0, 255, 0, 255 } );
				showLrSetupMenu(client);
			}
			case 3:
			{
				if (!(GetEntityFlags(client) & FL_ONGROUND))
				{
					PrintToChat(client, "%s You must be standing on the ground to select a guard spot!", PREFIX);
					showLrSetupMenu(client);
					return;
				}
				
				GetClientAbsOrigin(client, g_esSetupData.fGuardOrigin);
				ActiveBeacon(g_esSetupData.fGuardOrigin, { 255, 0, 0, 255 } );
				showLrSetupMenu(client);
			}
			case 4:
			{
				g_bIsWrite[client] = true;
				PrintToChat(client, "%s Write your desired \x04health\x01 amount, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 5:
			{
				g_esSetupData.bBackstab = !g_esSetupData.bBackstab;
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

public Action Timer_FlyStab(Handle hTimer)
{
	if (g_bIsFrozen)
	{
		ToggleFreeze(g_esSetupData.iPrisoner, false);
		ToggleFreeze(g_esSetupData.iAgainst, false);
		g_bIsFrozen = false;
		return Plugin_Continue;
	}
	
	if (!(1 <= g_esSetupData.iAgainst <= MaxClients) || !IsClientInGame(g_esSetupData.iAgainst))
	{
		JB_StopLr();
	}
	
	SetClientPosition(g_esSetupData.iPrisoner);
	SetClientPosition(g_esSetupData.iAgainst);
	ToggleFreeze(g_esSetupData.iPrisoner, true);
	ToggleFreeze(g_esSetupData.iAgainst, true);
	
	g_szFirstStab = "Nobody";
	g_bIsFrozen = true;
	return Plugin_Continue;
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
	
	g_hFlyStabTimer = CreateTimer(float(FREEZE_TIME), Timer_FlyStab, _, TIMER_REPEAT);
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_WEAPON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	GivePlayerItem(client, LR_WEAPON);
	SetEntityHealth(client, g_esSetupData.iHealth);
	
	SetClientPosition(client);
	ToggleFreeze(client, true);
	g_bIsFrozen = true;
}

void ToggleFreeze(int client, bool bMode)
{
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", bMode ? 0.0:1.0);
}

void ActiveBeacon(float origin[3], int color[4])
{
	if (g_iBeamSprite > -1 && g_iHaloSprite > -1)
	{
		origin[2] += 5.0;
		TE_SetupBeamRingPoint(origin, 10.0, 80.0, g_iBeamSprite, g_iHaloSprite, 0, 10, 1.0, 10.0, 0.5, color, 10, 0);
		TE_SendToAll();
		origin[2] -= 5.0;
	}
}

void SetClientPosition(int client)
{
	float fResult[3], fAngles[3];
	float fVelocity[3], fVelocityFwd[3], fVelocityUp[3];
	if (client == g_esSetupData.iPrisoner) {
		SubtractVectors(g_esSetupData.fGuardOrigin, g_esSetupData.fPrisonerOrigin, fResult);
		GetVectorAngles(fResult, fAngles);
		GetAngleVectors(fAngles, fVelocityFwd, NULL_VECTOR, fVelocityUp);
		AddVectors(fVelocityFwd, fVelocityUp, fVelocity);
		ScaleVector(fVelocity, GetVectorDistance(g_esSetupData.fPrisonerOrigin, g_esSetupData.fGuardOrigin) - 50.0);
		TeleportEntity(g_esSetupData.iPrisoner, g_esSetupData.fPrisonerOrigin, fAngles, fVelocity);
	} else {
		SubtractVectors(g_esSetupData.fPrisonerOrigin, g_esSetupData.fGuardOrigin, fResult);
		GetVectorAngles(fResult, fAngles);
		GetAngleVectors(fAngles, fVelocityFwd, NULL_VECTOR, fVelocityUp);
		AddVectors(fVelocityFwd, fVelocityUp, fVelocity);
		ScaleVector(fVelocity, GetVectorDistance(g_esSetupData.fPrisonerOrigin, g_esSetupData.fGuardOrigin) - 50.0);
		TeleportEntity(g_esSetupData.iAgainst, g_esSetupData.fGuardOrigin, fAngles, fVelocity);
	}
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

bool IsEntityBetween(float startPosition[3], float endPosition[3])
{
	startPosition[2] += 25.0;
	endPosition[2] += 25.0;
	
	bool bDitHit;
	TR_TraceRayFilter(startPosition, endPosition, MASK_SHOT, RayType_EndPoint, Filter_DontHitPlayers);
	
	if (TR_DidHit())
	{
		if (g_iGlowSprite > -1 && g_iBeamSprite > -1 && g_iHaloSprite > -1)
		{
			float fHitPosition[3];
			TR_GetEndPosition(fHitPosition);
			
			TE_SetupBeamPoints(startPosition, fHitPosition, g_iBeamSprite, g_iHaloSprite, 0, 0, SHOW_PATH_TIME, 1.0, 1.0, 1, 0.0, { 204, 186, 124, 255 }, 0);
			TE_SendToAll();
			
			TE_SetupBeamPoints(fHitPosition, endPosition, g_iBeamSprite, g_iHaloSprite, 0, 0, SHOW_PATH_TIME, 1.0, 1.0, 1, 0.0, { 93, 121, 220, 255 }, 0);
			TE_SendToAll();
			
			TE_SetupGlowSprite(fHitPosition, g_iGlowSprite, SHOW_PATH_TIME, 1.5, 200);
			TE_SendToAll();
			
<<<<<<< HEAD
			PrecacheModel("materials/sprites/ledglow.vmt");
=======
			PrecacheModel("materials/sprites/ledglow.vmt")
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
			
			TR_TraceRayFilter(endPosition, startPosition, MASK_SHOT, RayType_EndPoint, Filter_DontHitPlayers);
			TR_GetEndPosition(fHitPosition);
			
			TE_SetupGlowSprite(fHitPosition, g_iGlowSprite, SHOW_PATH_TIME, 1.5, 200);
			TE_SendToAll();
		}
		
		bDitHit = true;
	}
	
	startPosition[2] -= 25.0;
	endPosition[2] -= 25.0;
	
	return bDitHit;
}

public bool Filter_DontHitPlayers(int entity, int mask)
{
	return (entity > MaxClients);
}

/*  */