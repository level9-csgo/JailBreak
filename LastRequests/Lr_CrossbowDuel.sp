#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_LrSystem>
#include <customweapons>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define RANDOM_GUARD_STRING "Random Guard"
#define ABORT_SYMBOL "-1"

#define LR_NAME "Crossbow Duel"
#define LR_WEAPON "weapon_m4a1"

#define DEFAULT_HEALTH 1500
#define MIN_HEALTH 1250
#define MAX_HEALTH 1750

#define SHOT_COOLDOWN 0.9
#define ARROW_DMG 125.0

#define DEFAULT_CLIP1_AMMO 30

#define CROSSBOW_VIEW_MODEL "models/weapons/eminem/advanced_crossbow/v_advanced_crossbow.mdl"
#define CROSSBOW_WORLD_MODEL "models/weapons/eminem/advanced_crossbow/w_advanced_crossbow.mdl"

#define ZOMBIE_CHIKEN_MODEL "models/chicken/chicken_zombie.mdl"

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

enum struct Client
{
	ArrayList OwnedEntities;
	
	bool bIsWrite;
	bool IsReloading;
	
	int OldButtons;
	int OldAmmo;
	
	void Reset() {
		delete this.OwnedEntities;
		this.bIsWrite = false;
		this.IsReloading = false;
		this.OldButtons = 0;
		this.OldAmmo = 0;
	}
}

Setup g_esSetupData;
Client g_ClientsData[MAXPLAYERS + 1];

ConVar g_cvInfiniteAmmo;

char g_ChickenSounds[][] = 
{
	"ambient/creatures/chicken_panic_01.wav", 
	"ambient/creatures/chicken_panic_02.wav", 
	"ambient/creatures/chicken_panic_04.wav", 
	"ambient/creatures/chicken_death_01.wav", 
	"ambient/creatures/chicken_death_02.wav", 
	"ambient/creatures/chicken_death_03.wav", 
	"ambient/creatures/chicken_idle_01.wav"
};

bool g_bIsLrActivated;

int g_iLrId = -1;
int g_iExplosionSprite = -1;

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

//================================[ Events ]================================//

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
		g_bIsLrActivated = false;
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				
				delete g_ClientsData[iCurrentClient].OwnedEntities;
				
				int weapon = GetPlayerWeaponSlot(iCurrentClient, CS_SLOT_PRIMARY);
				if (weapon != -1)
				{
					CustomWeapon custom_weapon = CustomWeapon(weapon);
					if (custom_weapon)
					{
						custom_weapon.SetModel(CustomWeaponModel_View, "");
						custom_weapon.SetModel(CustomWeaponModel_World, "");
					}
				}
			}
		}
		
		char szClassName[64];
		for (int iCurrentEntity = MaxClients + 1; iCurrentEntity < GetMaxEntities(); iCurrentEntity++)
		{
			if (IsValidEdict(iCurrentEntity) && IsValidEntity(iCurrentEntity))
			{
				GetEdictClassname(iCurrentEntity, szClassName, sizeof(szClassName));
				if (StrContains(szClassName, "chicken") != -1) {
					RemoveEdict(iCurrentEntity);
				}
			}
		}
		
		g_cvInfiniteAmmo.IntValue = 0;
		delete g_cvInfiniteAmmo;
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

public void OnClientDisconnect(int client)
{
	g_ClientsData[client].Reset();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (!g_ClientsData[client].bIsWrite) {
		return Plugin_Continue;
	}
	
	if (StrEqual(szArgs, ABORT_SYMBOL)) {
		PrintToChat(client, "%s Operation has \x07aborted\x01.", PREFIX);
		showLrSetupMenu(client);
		g_ClientsData[client].bIsWrite = false;
		return Plugin_Handled;
	}
	
	int iHealthAmount = StringToInt(szArgs);
	if (MIN_HEALTH <= iHealthAmount <= MAX_HEALTH) {
		g_esSetupData.iHealth = iHealthAmount;
	} else {
		PrintToChat(client, "%s You have specifed an invalid \x04health\x01 amount! [\x02%s\x01]", PREFIX, szArgs);
	}
	
	showLrSetupMenu(client);
	g_ClientsData[client].bIsWrite = false;
	return Plugin_Handled;
}

public void OnMapStart()
{
	PrecacheModel(CROSSBOW_VIEW_MODEL);
	PrecacheModel(CROSSBOW_WORLD_MODEL);
	
	g_iExplosionSprite = PrecacheModel("sprites/sprite_fire01.vmt");
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (g_bIsLrActivated && (client == g_esSetupData.iPrisoner || client == g_esSetupData.iAgainst))
	{
		if (!g_esSetupData.bAllowJump && (buttons & IN_JUMP))
		{
			buttons &= ~IN_JUMP;
		}
		if (!g_esSetupData.bAllowDuck && (buttons & IN_DUCK))
		{
			buttons &= ~IN_DUCK;
		}
		
		int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (iActiveWeapon != -1)
		{
			char szClassName[32];
			GetEntityClassname(iActiveWeapon, szClassName, sizeof(szClassName));
			
			if (buttons && StrEqual(szClassName, LR_WEAPON))
			{
				//Check if it is any paintball weapon
				int ammo = GetEntProp(iActiveWeapon, Prop_Send, "m_iClip1");
				
				//Detect, when player wants to reload
				if (GetEntProp(iActiveWeapon, Prop_Send, "m_iPrimaryReserveAmmoCount") != 0 && DEFAULT_CLIP1_AMMO != ammo)
				{
					if ((buttons & IN_RELOAD) && !(g_ClientsData[client].OldButtons & IN_RELOAD) && !g_ClientsData[client].IsReloading && !(buttons & IN_ATTACK) && !(g_ClientsData[client].OldButtons & IN_ATTACK))
						WeaponReload(client, iActiveWeapon);
					
					if (ammo == 0)
						WeaponReload(client, iActiveWeapon);
				}
				
				//Detect if weapon just reloaded
				if (ammo > g_ClientsData[client].OldAmmo && g_ClientsData[client].IsReloading)
				{
					JustReloaded(client, iActiveWeapon);
				}
				
				//Shooting stuff
				if (!g_ClientsData[client].IsReloading && ammo > 0)
				{
					BlockRealShooting(iActiveWeapon);
					
					if ((buttons & IN_ATTACK) && !(g_ClientsData[client].OldButtons & IN_ATTACK))
						ShootBullet(client, iActiveWeapon, ammo);
					
					else if (buttons & IN_ATTACK)
						ShootBullet(client, iActiveWeapon, ammo);
					
				}
				
				if (!g_ClientsData[client].OwnedEntities && (buttons & IN_ATTACK2) && !(g_ClientsData[client].OldButtons & IN_ATTACK2))
				{
					float fEntityPos[3];
					
					for (int iCurrentIndex = 0, iCurrentEntity; iCurrentIndex < g_ClientsData[client].OwnedEntities.Length; iCurrentIndex++)
					{
						iCurrentEntity = g_ClientsData[client].OwnedEntities.Get(iCurrentIndex);
						
						if (IsValidEntity(iCurrentEntity))
						{
							GetEntPropVector(iCurrentEntity, Prop_Send, "m_vecOrigin", fEntityPos);
							CS_CreateExplosion(client, iCurrentEntity, ARROW_DMG, 325.0, fEntityPos);
							AcceptEntityInput(iCurrentEntity, "Kill");
						}
					}
					
					g_ClientsData[client].OwnedEntities.Clear();
				}
				
				g_ClientsData[client].OldAmmo = ammo;
				g_ClientsData[client].OldButtons = buttons;
			}
		}
	}
	
	return Plugin_Continue;
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if ((client == g_esSetupData.iPrisoner && attacker != g_esSetupData.iAgainst) || (client != g_esSetupData.iAgainst && attacker == g_esSetupData.iPrisoner)) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Hook_OnStartTouch(int entity, int other)
{
	int iThrower = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (IsValidEntity(entity) && other != iThrower)
	{
		if (g_bIsLrActivated)
		{
			if (!(1 <= other <= MaxClients)) {
				SDKHooks_TakeDamage(other, entity, iThrower, 128.0, DMG_BULLET); // If the arrow has touched a vent/etc...
			}
			else if (other == g_esSetupData.iPrisoner || other == g_esSetupData.iAgainst)
			{
				int iVictim = other;
				
				SetVariantString("csblood");
				AcceptEntityInput(entity, "DispatchEffect");
				
				if (GetClientHealth(iVictim) > ARROW_DMG) {
					SDKHooks_TakeDamage(iVictim, entity, iThrower, ARROW_DMG, DMG_BULLET);
				} else {
					ForcePlayerSuicide(iVictim);
				}
			}
			
			float fEntityPos[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fEntityPos);
			CS_CreateExplosion(iThrower, entity, ARROW_DMG + 25, 325.0, fEntityPos);
			
			if (g_ClientsData[iThrower].OwnedEntities)
			{
				int iArrayIndex = g_ClientsData[iThrower].OwnedEntities.FindValue(entity);
				if (iArrayIndex > -1) {
					g_ClientsData[iThrower].OwnedEntities.Erase(iArrayIndex);
				}
			}
		}
		
		AcceptEntityInput(entity, "Kill");
	}
	
	return Plugin_Continue;
}

//================================[ Menus ]================================//

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
				g_ClientsData[client].bIsWrite = true;
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

//================================[ Timers ]================================//

public Action Timer_ReloadAnimationFinished(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client || !g_bIsLrActivated)
	{
		return Plugin_Continue;
	}
	
	g_ClientsData[client].IsReloading = false;
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void StartLr()
{
	if (!g_esSetupData.iAgainst) {
		g_esSetupData.iAgainst = GetRandomGuard();
	}
	
	SetupPlayer(g_esSetupData.iPrisoner);
	SetupPlayer(g_esSetupData.iAgainst);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && !IsFakeClient(iCurrentClient))
		{
			SDKHook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
		}
	}
	
	g_cvInfiniteAmmo = FindConVar("sv_infinite_ammo");
	g_cvInfiniteAmmo.IntValue = 2;
	
	g_bIsLrActivated = true;
	JB_StartLr(g_esSetupData.iPrisoner, g_esSetupData.iAgainst, LR_WEAPON);
}

void SetupPlayer(int client)
{
	if (!client || IsFakeClient(client)) {
		return;
	}
	
	DisarmPlayer(client);
	SetEntityHealth(client, g_esSetupData.iHealth);
	
	g_ClientsData[client].OwnedEntities = new ArrayList();
	
	int weapon = GivePlayerItem(client, LR_WEAPON);
	if (weapon == -1)
	{
		return;
	}
	
	CustomWeapon custom_weapon = CustomWeapon(weapon);
	if (!custom_weapon)
	{
		return;
	}
	
	custom_weapon.SetModel(CustomWeaponModel_View, CROSSBOW_VIEW_MODEL);
	custom_weapon.SetModel(CustomWeaponModel_World, CROSSBOW_WORLD_MODEL);
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

void ShootBullet(int client, int weapon, int ammo)
{
	if (GetEntPropFloat(client, Prop_Send, "m_flNextAttack") <= GetGameTime() && !g_ClientsData[client].IsReloading && ammo > 0)
	{
		//Spam delay
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + SHOT_COOLDOWN);
		
		//Set default stuff
		SetEntProp(client, Prop_Send, "m_iShotsFired", GetEntProp(client, Prop_Send, "m_iShotsFired") + 1);
		SetEntProp(weapon, Prop_Send, "m_iClip1", ammo - 1);
		
		int iEntity = ShootChicken(client);
		if (iEntity != -1)
		{
			g_ClientsData[client].OwnedEntities.Push(iEntity);
		}
		
		PlayRandomChickenSound(client);
	}
}

int ShootChicken(int client)
{
	int iEntity = CreateEntityByName("chicken");
	if (iEntity == -1 || !IsValidEntity(iEntity)) {
		return -1;
	}
	
	float fClientPos[3], fClientAng[3];
	GetClientEyePosition(client, fClientPos);
	GetClientEyeAngles(client, fClientAng);
	fClientPos[2] -= 5.0;
	
	float fForward[3], fUp[3], fEntityVel[3];
	GetAngleVectors(fClientAng, fForward, NULL_VECTOR, fUp);
	
	ScaleVector(fForward, 2400.0);
	ScaleVector(fUp, 50.0);
	
	AddVectors(fForward, fEntityVel, fEntityVel);
	AddVectors(fUp, fEntityVel, fEntityVel);
	
	DispatchSpawn(iEntity);
	
	int iRandomBodyIndex = GetRandomInt(0, 6);
	
	if (iRandomBodyIndex == 6)
	{
		SetEntityModel(iEntity, ZOMBIE_CHIKEN_MODEL);
	}
	else
	{
		SetEntProp(iEntity, Prop_Data, "m_nBody", iRandomBodyIndex);
		SetEntProp(iEntity, Prop_Data, "m_nSkin", GetRandomInt(0, 4));
	}
	
	SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", client);
	SetEntProp(iEntity, Prop_Data, "m_nNextThinkTick", -1);
	SetEntPropString(iEntity, Prop_Data, "m_iName", "lrChicken");
	
	SetEntProp(iEntity, Prop_Send, "m_usSolidFlags", 152);
	SetEntityCollisionGroup(iEntity, 11);
	EntityCollisionRulesChanged(iEntity);
	
	SetEntPropFloat(iEntity, Prop_Send, "m_flElasticity", 0.0);
	
	SDKHook(iEntity, SDKHook_StartTouch, Hook_OnStartTouch);
	
	TeleportEntity(iEntity, fClientPos, fClientAng, fEntityVel);
	
	return iEntity;
}

void CS_CreateExplosion(int attacker, int weapon, float damage, float radius, float vec[3])
{
	TE_SetupExplosion(vec, g_iExplosionSprite, 15.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	float fCurrentPos[3], fCurrentDis;
	for (int iCurrentVictim = 1; iCurrentVictim <= MaxClients; iCurrentVictim++)
	{
		if (IsClientInGame(iCurrentVictim) && IsPlayerAlive(iCurrentVictim) && (iCurrentVictim == g_esSetupData.iPrisoner || iCurrentVictim == g_esSetupData.iAgainst))
		{
			GetClientEyePosition(iCurrentVictim, fCurrentPos);
			
			if (!IsPathClear(vec, fCurrentPos, iCurrentVictim))
			{
				continue;
			}
			
			fCurrentDis = GetVectorDistance(vec, fCurrentPos);
			
			if (fCurrentDis <= radius)
			{
				float fClientVelocity[3], fVelocity[3];
				MakeVectorFromPoints(vec, fCurrentPos, fVelocity);
				ScaleVector(fVelocity, 650.0 / fCurrentDis);
				
				GetEntPropVector(iCurrentVictim, Prop_Data, "m_vecVelocity", fClientVelocity);
				AddVectors(fClientVelocity, fVelocity, fVelocity);
				TeleportEntity(iCurrentVictim, NULL_VECTOR, NULL_VECTOR, fVelocity);
				
				if (attacker != iCurrentVictim)
				{
					float fResult = Sine(((radius - fCurrentDis) / radius) * (FLOAT_PI / 2)) * damage;
					SDKHooks_TakeDamage(iCurrentVictim, attacker, attacker, fResult, DMG_BLAST, weapon, NULL_VECTOR, vec);
				}
			}
		}
	}
}

bool IsPathClear(float start_pos[3], float end_pos[3], int victimIndex)
{
	float client_angles[3];
	SubtractVectors(end_pos, start_pos, client_angles);
	GetVectorAngles(client_angles, client_angles);
	
	TR_TraceRayFilter(start_pos, client_angles, 33570827, RayType_Infinite, Filter_HitTargetOnly, victimIndex);
	
	return victimIndex == TR_GetEntityIndex();
}

public bool Filter_HitTargetOnly(int entity, int contentsMask, any data)
{
	return data == entity;
}

void WeaponReload(int client, int weapon)
{
	g_ClientsData[client].IsReloading = true;
	UnBlockRealShooting(weapon);
}

void JustReloaded(int client, int weapon)
{
	BlockRealShooting(weapon);
	
	CreateTimer(1.38, Timer_ReloadAnimationFinished, GetClientUserId(client));
}

void BlockRealShooting(int weapon)
{
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", 2.0 + GetGameTime());
}

void UnBlockRealShooting(int weapon)
{
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() - 2);
}

void PlayRandomChickenSound(int client)
{
	EmitSoundToClient(client, g_ChickenSounds[GetRandomInt(0, sizeof(g_ChickenSounds) - 1)], .volume = 0.1);
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

//================================================================//