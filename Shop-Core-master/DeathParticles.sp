#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <shop>
#include <JailBreak>

#pragma semicolon 1
#pragma newdecls required

CategoryId g_ShopCategoryID;

ItemId g_EquippedParticle[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[Shop Integrated] Death Particles", 
	author = "KoNLiG", 
	description = "Implemention of CS:GO paticles to shop.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Late load.
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	HookEvent("player_death", Event_PlayerDeath);
	
	RegAdminCmd("sm_particle", Command_Particle, ADMFLAG_ROOT, "Creates a particle.");
}

public void OnClientDisconnect(int client)
{
	g_EquippedParticle[client] = INVALID_ITEM;
}

Action Command_Particle(int client, int argc)
{
	if (argc != 2)
	{
		PrintToChat(client, "sm_particle <effect_name> <living_time>");
		return Plugin_Handled;
	}
	
	char effect_name[PLATFORM_MAX_PATH];
	GetCmdArg(1, effect_name, sizeof(effect_name));
	
	PrintToChat(client, "Effect idx: %d", SpawnEffectParticle(client, effect_name, GetCmdArgFloat(2)));
	
	return Plugin_Handled;
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
}

public void Shop_Started()
{
	g_ShopCategoryID = Shop_RegisterCategory("death_particles", "Death Particles", "Particle effect that will be spawned whenever you die in a last request.");
	
	LoadDeathParticles();
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(Frame_PlayerDeathPost, event.GetInt("userid"));
}

void Frame_PlayerDeathPost(int userid)
{
	if (GetOnlineTeamCount(CS_TEAM_T) > 1)
	{
		return;
	}
	
	int client = GetClientOfUserId(userid);
	
	// Client is invalid
	if (!client)
	{
		return;
	}
	
	// Client doesn't have any equipped particle.
	if (g_EquippedParticle[client] == INVALID_ITEM)
	{
		return;
	}
	
	char effect_name[PLATFORM_MAX_PATH];
	Shop_GetItemCustomInfoString(g_EquippedParticle[client], "effect_name", effect_name, sizeof(effect_name));
	
	float live_duration = Shop_GetItemCustomInfoFloat(g_EquippedParticle[client], "live_duration");
	
	SpawnEffectParticle(client, effect_name, live_duration);
}

ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	// If already equiped, just unequip.
	if (isOn)
	{
		g_EquippedParticle[client] = INVALID_ITEM;
		return Shop_UseOff;
	}
	
	// Toggle off all other items off.
	Shop_ToggleClientCategoryOff(client, category_id);
	
	g_EquippedParticle[client] = item_id;
	
	return Shop_UseOn;
}

void LoadDeathParticles()
{
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("DeathParticles");
	
	// Find the Config
	static char file_path[PLATFORM_MAX_PATH];
	if (!file_path[0])
	{
		BuildPath(Path_SM, file_path, sizeof(file_path), "configs/shop/death_particles.cfg");
	}
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(file_path) || !kv.GotoFirstSubKey())
	{
		SetFailState("Couldn't load plugin config.");
	}
	
	char name[64], description[64], effect_name[PLATFORM_MAX_PATH];
	
	// Parse particles one by one.
	do
	{
		// Get name
		kv.GetString("name", name, sizeof(name));
		
		// Get description
		kv.GetString("description", description, sizeof(description));
		
		// Get model path
		kv.GetString("effect_name", effect_name, sizeof(effect_name));
		
		if (!effect_name[0])
		{
			continue;
		}
		
		if (Shop_StartItem(g_ShopCategoryID, name))
		{
			Shop_SetInfo(name, description, kv.GetNum("price"), kv.GetNum("price") / 2, Item_Togglable, 0, kv.GetNum("price_gold"), kv.GetNum("sell_price_gold"));
			Shop_SetCallbacks(.use_toggle = OnEquipItem);
			
			Shop_SetCustomInfoString("effect_name", effect_name);
			Shop_SetCustomInfoFloat("live_duration", kv.GetFloat("live_duration"));
			
			Shop_EndItem();
		}
	} while (kv.GotoNextKey());
	
	// Don't leak handles
	kv.Close();
}

int SpawnEffectParticle(int client, char[] particleType, float time)
{
	int info_particle_system = CreateEntityByName("info_particle_system");
	if (info_particle_system == -1)
	{
		return -1;
	}
	
	float origin[3];
	GetClientAbsOrigin(client, origin);
	OriginToFloor(origin);
	
	DispatchKeyValueVector(info_particle_system, "origin", origin);
	DispatchKeyValue(info_particle_system, "effect_name", particleType);
	DispatchKeyValue(info_particle_system, "start_active", "1");
	DispatchSpawn(info_particle_system);
	ActivateEntity(info_particle_system);
	
	if (time)
	{
		char output[64];
		Format(output, sizeof(output), "!self,Kill,,%.1f,-1", time);
		DispatchKeyValue(info_particle_system, "OnUser1", output);
		AcceptEntityInput(info_particle_system, "FireUser1");
	}
	
	return info_particle_system;
}

void OriginToFloor(float origin[3])
{
	TR_TraceRayFilter(origin, { 90.0, 0.0, 0.0 }, MASK_ALL, RayType_Infinite, Filter_WorldOnly);
	
	if (TR_DidHit())
	{
		TR_GetEndPosition(origin);
	}
}

bool Filter_WorldOnly(int entity, int contentsMask)
{
	return !entity;
} 