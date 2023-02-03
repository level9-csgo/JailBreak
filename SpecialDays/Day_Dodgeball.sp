#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <JB_GangsUpgrades>
#include <JB_RunesSystem>
#include <JB_SpecialDays>

#define PLUGIN_AUTHOR "KoNLiG"

#define DAY_NAME "Dodgeball Day"
#define DAY_WEAPON "weapon_decoy"
#define DEFAULT_HEALTH 1

#define COLLISION_GROUP_DEBRIS_TRIGGER 2      // Default client collision group, non solid
#define COLLISION_GROUP_INTERACTIVE_DEBRIS 3  // Required client collision group, interactive solid

ConVar g_cvFallDamageScale;

bool g_bIsDayActivated;

int g_iDayId = -1;

// Stores the trail precached model index.
int g_TrailModelIndex;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_cvFallDamageScale = FindConVar("sv_falldamage_scale");
}

public void OnPluginEnd()
{
	if (g_bIsDayActivated) {
		JB_StopSpecialDay();
	}
}

/* Events */

public void OnMapStart()
{
	// Precache the decoy projectile trail model index, and store the return index.
	g_TrailModelIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
}


public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_iDayId = JB_CreateSpecialDay(DAY_NAME, DEFAULT_HEALTH, false, false, false);
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		SetEntityCollisionGroup(client, COLLISION_GROUP_INTERACTIVE_DEBRIS);
		EntityCollisionRulesChanged(client);
		
		SetEntProp(client, Prop_Data, "m_iMaxHealth", DEFAULT_HEALTH);
		
		DisarmPlayer(client);
		GivePlayerItem(client, DAY_WEAPON);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		g_cvFallDamageScale.IntValue = 0;
		
		HookEvent("grenade_thrown", Event_GrenadeThrow, EventHookMode_Post);
		
		int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
		if (iUpgradeIndex != -1) {
			JB_ToggleGangUpgrade(iUpgradeIndex, false);
		}
		
		ToggleBunnyhop(false);
		ToggleRunesState(false);
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_bIsDayActivated && g_iDayId == specialDayId)
	{
		if (!countdown)
		{
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient)) 
				{
					SetEntityCollisionGroup(client, COLLISION_GROUP_DEBRIS_TRIGGER);
					EntityCollisionRulesChanged(client);

					SetEntProp(iCurrentClient, Prop_Data, "m_iMaxHealth", 100);
				}
			}
			
			g_cvFallDamageScale.IntValue = 1;
			
			UnhookEvent("grenade_thrown", Event_GrenadeThrow, EventHookMode_Post);
			
			int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
			if (iUpgradeIndex != -1) {
				JB_ToggleGangUpgrade(iUpgradeIndex, true);
			}
			
			int iRuneIndex = JB_FindRune("healthrune");
			if (iRuneIndex != -1) {
				JB_ToggleRune(iRuneIndex, true);
			}
			
			ToggleBunnyhop(true);
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (g_bIsDayActivated && StrEqual(classname, "decoy_projectile"))
	{
		// This is too soon to retrive data from the entity by network properties, etc...
		// We must wait until the entity will fully spawn.
		SDKHook(entity, SDKHook_SpawnPost, Hook_OnSpawnPost);
	}
}

void Hook_OnSpawnPost(int entity)
{
	// Once the projectile is touching anything, remove it.
	SDKHook(entity, SDKHook_StartTouch, Hook_OnStartTouch);
	
	// Display a colored following trail behind the projectile.
	if (g_TrailModelIndex)
	{
		int color[4];
		
		color[0] = GetRandomInt(1, 255);
		color[1] = GetRandomInt(1, 255);
		color[2] = GetRandomInt(1, 255);
		color[3] = 255;
		
		TE_SetupBeamFollow(entity, g_TrailModelIndex, 0, 1.5, 0.5, 2.0, 1, color);
		TE_SendToAll();
	}
}

Action Hook_OnStartTouch(int entity, int other)
{
	int thrower = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (thrower != -1 && (1 <= other <= MaxClients))
	{
		// Set the victim armor value to 0, else it won't kill him.
		SetEntProp(other, Prop_Send, "m_ArmorValue", 0);
		
		// Eliminate the victim.
		SDKHooks_TakeDamage(other, thrower, thrower, float(GetClientHealth(other)), entity);
	}
	
	// Remove the entity from the world.
	AcceptEntityInput(entity, "Kill");
}

public Action Event_GrenadeThrow(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	DisarmPlayer(client);
	EquipPlayerWeapon(client, GivePlayerItem(client, DAY_WEAPON));
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

/*  */