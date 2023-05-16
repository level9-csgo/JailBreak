#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_AUTHOR "KoNLiG"

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Physics Manager", 
	author = PLUGIN_AUTHOR, 
	description = "Controls the map entities physics state.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	char current_class_name[64];
	
	for (int current_entity = MaxClients + 1; current_entity < GetMaxEntities(); current_entity++)
	{
		if (IsValidEntity(current_entity) && GetEntityClassname(current_entity, current_class_name, sizeof(current_class_name)))
		{
			OnEntityCreated(current_entity, current_class_name);
		}
	}
}

//================================[ Events ]================================//

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrContains(classname, "func_physbox") != -1 || StrContains(classname, "prop_physics") != -1)
	{
		SDKHook(entity, SDKHook_TraceAttack, Hook_OnTraceAttack);
	}
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnTraceAttack(int entity, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (!(1 <= attacker <= MaxClients) || (1 <= entity <= MaxClients))
	{
		return Plugin_Continue;
	}
	
	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	
	float client_angles[3];
	GetClientEyeAngles(attacker, client_angles);
	
	float fwd[3];
	GetAngleVectors(client_angles, fwd, NULL_VECTOR, NULL_VECTOR);
	
	// Scale up the velocity vector to make a knockback effect
	ScaleVector(fwd, 500.0);
	
	// Apply the velocity change on the entity
	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, fwd);
	
	return Plugin_Continue;
}

//================================================================//