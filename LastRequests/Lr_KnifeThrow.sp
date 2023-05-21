#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RANDOM_GUARD_STRING "Random Guard"

#define LR_NAME "Knife Throw"
#define LR_ICON "zone_repulsor"
#define ABORT_SYMBOL "-1"

#define KNIFE_THROW_DELAY 1.5
#define KNIFE_TRAIL_TIME 0.7
#define DEFAULT_HEALTH 100
#define MIN_HEALTH 1
#define MAX_HEALTH 200

#define LEFT_CLICK_DAMAGE 50
#define RIGHT_CLICK_DAMAGE 20

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

bool g_bIsLrActivated;
bool g_bIsWrite[MAXPLAYERS + 1];

int g_iLrId = -1;

int g_iBeamSprite = -1;
int g_iHaloSprite = -1;

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

public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
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

void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client != g_esSetupData.iPrisoner && client != g_esSetupData.iAgainst)
	{
		return;
	}
	
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	
	if (iActiveWeapon != -1 && IsValidEntity(iActiveWeapon))
	{
		char szClassName[32];
		GetEntityClassname(iActiveWeapon, szClassName, sizeof(szClassName));
		
		if (StrContains(szClassName, "knife") != -1 || StrContains(szClassName, "bayonet") != -1)
		{
			SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + KNIFE_THROW_DELAY);
			ThrowKnife(client, LEFT_CLICK_DAMAGE);
		}
	}
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
		
		int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (iActiveWeapon != -1 && IsValidEntity(iActiveWeapon))
		{
			int iKnifeIndex = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
			if (iKnifeIndex != -1 && IsValidEntity(iKnifeIndex))
			{
				if (iKnifeIndex == iActiveWeapon && (buttons & IN_ATTACK2) && GetEntPropFloat(client, Prop_Send, "m_flNextAttack") <= GetGameTime())
				{
					SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + KNIFE_THROW_DELAY + 0.1);
					
					ThrowKnife(client, RIGHT_CLICK_DAMAGE);
					CreateTimer(0.25, Timer_ThrowKnife, GetClientSerial(client));
					CreateTimer(0.5, Timer_ThrowKnife, GetClientSerial(client));
				}
			}
		}
		
		if (bPrees) {
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

/*  */

/* Entity Hooks */

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	return Plugin_Handled;
}

Action Hook_OnStartTouch(int entity, int other)
{
	int iThrower = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (IsValidEntity(entity) && other != iThrower)
	{
		if (g_bIsLrActivated)
		{
			if (!(1 <= other <= MaxClients))
			{
				SDKHooks_TakeDamage(other, entity, iThrower, 128.0, DMG_BULLET); // If the knife has touched a vent/etc...
			}
			else if (other == g_esSetupData.iPrisoner || other == g_esSetupData.iAgainst)
			{
				int iDamage = GetEntProp(entity, Prop_Data, "m_iHealth");
				int iVictim = other;
				
				SetVariantString("csblood");
				AcceptEntityInput(entity, "DispatchEffect");
				
				if (GetClientHealth(iVictim) > iDamage) {
					SDKHooks_TakeDamage(iVictim, entity, iThrower, float(iDamage), DMG_BULLET);
				} else {
					ForcePlayerSuicide(iVictim);
				}
			}
		}
		
		AcceptEntityInput(entity, "Kill");
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
	
	Format(szItem, sizeof(szItem), "Enemy: %s", !g_esSetupData.iAgainst ? RANDOM_GUARD_STRING:szItem);
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
	
	return 0;
}

/*  */

/* Timers */

Action Timer_ThrowKnife(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	if (client) 
	{
		ThrowKnife(client, RIGHT_CLICK_DAMAGE);
	}
	
	return Plugin_Continue;
}

/*  */

/* Functions */

void InitRandomSettings()
{
	g_esSetupData.iAgainst = 0;
	g_esSetupData.iHealth = RoundToDivider(GetRandomInt(MIN_HEALTH, MAX_HEALTH), 25);
	g_esSetupData.bAllowJump = GetRandomInt(0, 1) == 1;
	g_esSetupData.bAllowDuck = GetRandomInt(0, 1) == 1;
}

void StartLr()
{
	if (!g_esSetupData.iAgainst)
	{
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
	
	HookEvent("weapon_fire", Event_WeaponFire);
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_ICON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	GivePlayerItem(client, "weapon_knife");
	SetEntityHealth(client, g_esSetupData.iHealth);
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

int ThrowKnife(int client, int damage)
{
	int iEntity = CreateEntityByName("decoy_projectile");
	if (iEntity == -1) {
		return -1;
	}
	
	float fAimPos[3], fEntityPos[3], fEntityAng[3], fEntityVel[3];
	GetOriginByAim(client, fAimPos);
	GetClientEyePosition(client, fEntityPos);
	fEntityPos[2] -= 5.0;
	
	MakeVectorFromPoints(fEntityPos, fAimPos, fEntityVel);
	NormalizeVector(fEntityVel, fEntityVel);
	ScaleVector(fEntityVel, 2000.0);
	GetVectorAngles(fEntityVel, fEntityAng);
	
	DispatchSpawn(iEntity);
	
	SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", client);
	SetEntProp(iEntity, Prop_Data, "m_iHealth", damage);
	SetEntProp(iEntity, Prop_Data, "m_nNextThinkTick", -1);
	
	SetEntProp(iEntity, Prop_Send, "m_usSolidFlags", 152);
	
	SetEntityCollisionGroup(iEntity, 11);
	EntityCollisionRulesChanged(iEntity);

	SetEntityModel(iEntity, "models/weapons/w_knife_default_t_dropped.mdl");
	SetEntPropFloat(iEntity, Prop_Send, "m_flModelScale", 3.0);
	
	SetEntPropFloat(iEntity, Prop_Send, "m_flElasticity", 0.0);
	SetEntityGravity(iEntity, 0.0005);
	
	SDKHook(iEntity, SDKHook_StartTouch, Hook_OnStartTouch);
	
	fEntityAng[0] += 90.0;
	TeleportEntity(iEntity, fEntityPos, fEntityAng, fEntityVel);
	
	if (g_iBeamSprite > -1 && g_iHaloSprite > -1)
	{
		TE_SetupBeamFollow(iEntity, g_iBeamSprite, g_iHaloSprite, KNIFE_TRAIL_TIME, 1.0, 1.0, 1, { 3, 207, 252, 255 } );
		TE_SendToAll();
	}
	
	return iEntity;
}

void GetOriginByAim(int client, float result[3])
{
	float fAngles[3];
	float fOrigin[3];
	
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, fAngles);
	
	Handle hTrace = TR_TraceRayFilterEx(fOrigin, fAngles, MASK_ALL, RayType_Infinite, Filter_DontHitPlayers, client);
	
	if (TR_DidHit(hTrace)) {
		TR_GetEndPosition(result, hTrace);
	}
	
	delete hTrace;
}

public bool Filter_DontHitPlayers(int entity, int mask, int data)
{
	return (entity != data);
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