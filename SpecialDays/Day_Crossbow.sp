#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <JB_SpecialDays>
#include <fpvm_interface>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "Crossbow Day"
#define DAY_WEAPON "weapon_m4a1"
#define DAY_HEALTH 1250

#define SHOT_COOLDOWN 0.9
#define ARROW_DMG 125.0

#define DEFAULT_CLIP1_AMMO 30

#define CROSSBOW_VIEW_MODEL "models/weapons/eminem/advanced_crossbow/v_advanced_crossbow.mdl"
#define CROSSBOW_WORLD_MODEL "models/weapons/eminem/advanced_crossbow/w_advanced_crossbow.mdl"

#define ZOMBIE_CHIKEN_MODEL "models/chicken/chicken_zombie.mdl"

//====================//

enum struct Client
{
	ArrayList OwnedEntities;
	
	bool IsReloading;
	
	int OldButtons;
	int OldAmmo;
	
	void Reset() {
		delete this.OwnedEntities;
		
		this.IsReloading = false;
		
		this.OldButtons = 0;
		this.OldAmmo = 0;
	}
}

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

bool g_IsDayActivated;

int g_DayIndex = -1;

int g_iCrossbowViewId = -1;
int g_iCrossbowWorldId = -1;

int g_iBeamSprite = -1;
int g_iExplosionSprite = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginEnd()
{
	// If the special day is running, and the plugin has come to his end, stop the special day
	if (g_IsDayActivated)
	{
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_DayIndex = JB_CreateSpecialDay(DAY_NAME, DAY_HEALTH, false, false, false);
	}
}

public void OnMapStart()
{
	// Precache the required day models
	g_iCrossbowViewId = PrecacheModel(CROSSBOW_VIEW_MODEL);
	g_iCrossbowWorldId = PrecacheModel(CROSSBOW_WORLD_MODEL);
	
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iExplosionSprite = PrecacheModel("sprites/sprite_fire01.vmt");
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	// Make sure the given special day index, is the plugin's index
	if (g_DayIndex != specialDayId)
	{
		return;
	}
	
	g_ClientsData[client].Reset();
	
	DisarmPlayer(client);
	GivePlayerItem(client, DAY_WEAPON);
	
	FPVMI_AddViewModelToClient(client, DAY_WEAPON, g_iCrossbowViewId);
	FPVMI_AddWorldModelToClient(client, DAY_WEAPON, g_iCrossbowWorldId);
	
	g_ClientsData[client].OwnedEntities = new ArrayList();
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	// Make sure the given special day index, is the plugin's index
	if (g_DayIndex != specialDayId)
	{
		return;
	}
	
	ToggleRunesState(false);
	
	g_cvInfiniteAmmo = FindConVar("sv_infinite_ammo");
	g_cvInfiniteAmmo.IntValue = 2;
	
	g_IsDayActivated = true;
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (!g_IsDayActivated && g_DayIndex != specialDayId)
	{
		return;
	}
	
	if (!countdown)
	{
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				FPVMI_RemoveViewModelToClient(current_client, DAY_WEAPON);
				FPVMI_RemoveWorldModelToClient(current_client, DAY_WEAPON);
				
				g_ClientsData[current_client].Reset();
			}
		}
		
		char current_class_name[64];
		
		for (int current_entity = MAXPLAYERS; current_entity < GetMaxEntities(); current_entity++)
		{
			if (IsValidEntity(current_entity) && GetEntityClassname(current_entity, current_class_name, sizeof(current_class_name)) && StrContains(current_class_name, "chicken") != -1)
			{
				RemoveEntity(current_entity);
			}
		}
		
		ToggleRunesState(true);
		
		g_cvInfiniteAmmo.IntValue = 0;
		delete g_cvInfiniteAmmo;
	}
	
	g_IsDayActivated = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_IsDayActivated && IsPlayerAlive(client))
	{
		int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (iActiveWeapon != -1)
		{
			char szClassName[32];
			GetEntityClassname(iActiveWeapon, szClassName, sizeof(szClassName));
			
			if (buttons && StrEqual(szClassName, DAY_WEAPON))
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
				
				// Detect if weapon just reloaded
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
				
				if (g_ClientsData[client].OwnedEntities && (buttons & IN_ATTACK2) && !(g_ClientsData[client].OldButtons & IN_ATTACK2))
				{
					float fEntityPos[3];
					
					for (int iCurrentIndex = 0, iCurrentEntity; iCurrentIndex < g_ClientsData[client].OwnedEntities.Length; iCurrentIndex++)
					{
						iCurrentEntity = g_ClientsData[client].OwnedEntities.Get(iCurrentIndex);
						
						if (IsValidEntity(iCurrentEntity))
						{
							GetEntPropVector(iCurrentEntity, Prop_Send, "m_vecOrigin", fEntityPos);
							CS_CreateExplosion(client, ARROW_DMG, 325.0, fEntityPos);
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

public Action Hook_OnStartTouch(int entity, int other)
{
	int iThrower = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (IsValidEntity(entity) && other != iThrower)
	{
		if (g_IsDayActivated)
		{
			if (!(1 <= other <= MaxClients)) {
				JB_DealDamage(other, iThrower, 128.0, DMG_BULLET); // If the arrow has touched a vent/etc...
			}
			else
			{
				int iVictim = other;
				
				SetVariantString("csblood");
				AcceptEntityInput(entity, "DispatchEffect");
				
				JB_DealDamage(iVictim, iThrower, ARROW_DMG, DMG_BULLET);
			}
			
			float fEntityPos[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fEntityPos);
			CS_CreateExplosion(iThrower, ARROW_DMG + 25, 325.0, fEntityPos);
			
			if (g_ClientsData[iThrower].OwnedEntities != null)
			{
				int iArrayIndex = g_ClientsData[iThrower].OwnedEntities.FindValue(entity);
				if (iArrayIndex > -1) {
					g_ClientsData[iThrower].OwnedEntities.Erase(iArrayIndex);
				}
			}
		}
		
		AcceptEntityInput(entity, "Kill");
	}
}

//================================[ Timers ]================================//

public Action Timer_ReloadAnimationFinished(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client || !g_IsDayActivated)
	{
		return Plugin_Continue;
	}
	
	g_ClientsData[client].IsReloading = false;
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

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
	
	if (iRandomBodyIndex == 6) {
		SetEntityModel(iEntity, ZOMBIE_CHIKEN_MODEL);
	} else {
		SetEntProp(iEntity, Prop_Data, "m_nBody", iRandomBodyIndex);
		SetEntProp(iEntity, Prop_Data, "m_nSkin", GetRandomInt(0, 1));
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

void CS_CreateExplosion(int attacker, float damage, float radius, float vec[3])
{
	TE_SetupExplosion(vec, g_iExplosionSprite, 15.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	float fCurrentPos[3], fCurrentDis;
	for (int iCurrentVictim = 1; iCurrentVictim <= MaxClients; iCurrentVictim++)
	{
		if (IsClientInGame(iCurrentVictim) && IsPlayerAlive(iCurrentVictim))
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
				
				if (attacker != iCurrentVictim) {
					float fResult = Sine(((radius - fCurrentDis) / radius) * (3.14159 / 2)) * damage;
					JB_DealDamage(iCurrentVictim, attacker, fResult, DMG_BLAST);
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

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
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
	SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() - 2.0);
}

void PlayRandomChickenSound(int client)
{
	EmitSoundToClient(client, g_ChickenSounds[GetRandomInt(0, sizeof(g_ChickenSounds) - 1)], .volume = 0.1);
}

//================================================================//