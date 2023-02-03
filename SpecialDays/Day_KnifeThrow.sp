#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "Knife Throw Day"
#define DAY_WEAPON "weapon_knife"
#define DEFAULT_HEALTH 100

#define KNIFE_THROW_DELAY 1.5
#define KNIFE_TRAIL_TIME 0.7

#define LEFT_CLICK_DAMAGE 50
#define RIGHT_CLICK_DAMAGE 20

//====================//

bool g_bIsDayActivated;

int g_iDayId = -1;

int g_iBeamSprite = -1;
int g_iHaloSprite = -1;

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
	if (g_bIsDayActivated) {
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_iDayId = JB_CreateSpecialDay(DAY_NAME, DEFAULT_HEALTH, false, false, false);
	}
}

public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		DisarmPlayer(client);
		GivePlayerItem(client, DAY_WEAPON);
		
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
		
		ToggleRunesState(false);
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_bIsDayActivated && g_iDayId == specialDayId)
	{
		// If there is a countdown, these things didn't hook
		if (!countdown)
		{
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient)) {
					SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				}
			}
			
			UnhookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
			
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (g_bIsDayActivated && IsPlayerAlive(client))
	{
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
	}
}

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
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

//================================[ SDK Hooks ]================================//

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	return weapon != -1 ? Plugin_Handled : Plugin_Continue;
}

public Action Hook_OnStartTouch(int entity, int other)
{
	int iThrower = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (IsValidEntity(entity) && other != iThrower)
	{
		if (g_bIsDayActivated)
		{
			if (!(1 <= other <= MaxClients))
			{
				JB_DealDamage(other, iThrower, 128.0, DMG_BULLET); // If the knife has touched a vent/etc...
			}
			else
			{
				int iDamage = GetEntProp(entity, Prop_Data, "m_iHealth");
				int iVictim = other;
				
				SetVariantString("csblood");
				AcceptEntityInput(entity, "DispatchEffect");
				
				JB_DealDamage(iVictim, iThrower, float(iDamage), DMG_BULLET);
			}
		}
		
		AcceptEntityInput(entity, "Kill");
	}
}

//================================[ Timers ]================================//

public Action Timer_ThrowKnife(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (client) 
	{
		ThrowKnife(client, RIGHT_CLICK_DAMAGE);
	}
}

//================================[ Functions ]================================//

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

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

//================================================================//