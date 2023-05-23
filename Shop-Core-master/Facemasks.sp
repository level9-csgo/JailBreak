#include <sourcemod>
#include <sdktools>
#include <shop>
#include <TransmitManager>
#include <spec_hooks>

enum struct Player
{
	// This player slot index.
	int index;
	
	// This player userid.
	int userid;
	
	// ItemId of the currently equipped face mask.
	ItemId equipped_facemask;
	
	// Entity reference of the player face mask entity.
	int facemask_entity_reference;
	//================================//
	void Init(int client)
	{
		this.index = client;
		this.userid = GetClientUserId(client);
		this.facemask_entity_reference = INVALID_ENT_REFERENCE;
	}
	
	void Close()
	{
		this.userid = 0;
		this.equipped_facemask = INVALID_ITEM;
		this.facemask_entity_reference = 0;
	}
	
	void SpawnFacemaskEntity()
	{
		this.RemoveFacemaskEntity();
		
		int prop_dynamic_override = CreateEntityByName("prop_dynamic_override");
		if (prop_dynamic_override == -1)
		{
			return;
		}
		
		// Retrieve the face mask model via the equipped face mask data.
		char model[PLATFORM_MAX_PATH];
		Shop_GetItemCustomInfoString(this.equipped_facemask, "model_path", model, sizeof(model));
		
		DispatchKeyValue(prop_dynamic_override, "model", model);
		DispatchKeyValue(prop_dynamic_override, "solid", "0");
		
		DispatchSpawn(prop_dynamic_override);
		
		SetVariantString("!activator");
		AcceptEntityInput(prop_dynamic_override, "SetParent", this.index);
		
		SetVariantString("facemask");
		AcceptEntityInput(prop_dynamic_override, "SetParentAttachment");
		
		TransmitManager_AddEntityHooks(prop_dynamic_override);
		TransmitManager_SetEntityState(prop_dynamic_override, this.index, false);
		
		this.facemask_entity_reference = EntIndexToEntRef(prop_dynamic_override);
	}
	
	void RemoveFacemaskEntity()
	{
		int entity = this.GetFacemaskEntity();
		if (entity != -1)
		{
			RemoveEntity(entity);
		}
	}
	
	// -1 for invalid.
	int GetFacemaskEntity()
	{
		return EntRefToEntIndex(this.facemask_entity_reference);
	}
}

Player g_Players[MAXPLAYERS + 1];

CategoryId g_ShopCategoryID;

// Stores all the facemasks models to precache them later.
ArrayList g_FacemaskModels;

public Plugin myinfo = 
{
	name = "[Shop Integrated] Face Masks", 
	author = "KoNLiG", 
	description = "Provides face masks as a feature in the shop system.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_FacemaskModels = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	Lateload();
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			g_Players[current_client].RemoveFacemaskEntity();
		}
	}
}

//================================[ Events ]================================//

public void Shop_Started()
{
	g_ShopCategoryID = Shop_RegisterCategory("facemasks", "Face Masks", "Unique holiday face masks to show off to your friends!");
	
	LoadFacemasks();
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		g_Players[client].Init(client);
	}
}

public void OnClientDisconnect(int client)
{
	g_Players[client].Close();
}

public void OnMapStart()
{
	PrecacheFacemasksModels();
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(Frame_ApplyClientFacemask, event.GetInt("userid"));
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		g_Players[client].RemoveFacemaskEntity();
	}
}

void Frame_ApplyClientFacemask(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client && g_Players[client].equipped_facemask)
	{
		g_Players[client].SpawnFacemaskEntity();
	}
}

public void Shop_OnClientEmotePost(int client)
{
	if (!g_Players[client].equipped_facemask)
	{
		return;
	}
	
	int entity = g_Players[client].GetFacemaskEntity();
	if (entity == -1)
	{
		return;
	}
	
	TransmitManager_SetEntityState(entity, client, true);
}

public void Shop_OnClientEmoteStop(int client)
{
	if (!g_Players[client].equipped_facemask)
	{
		return;
	}
	
	int entity = g_Players[client].GetFacemaskEntity();
	if (entity == -1)
	{
		return;
	}
	
	TransmitManager_SetEntityState(entity, client, false);
}

public void SpecHooks_OnObserverTargetChange(int client, int target, int last_target)
{
	if (last_target != -1 && g_Players[last_target].equipped_facemask)
	{
		int entity = g_Players[last_target].GetFacemaskEntity();
		if (entity != -1)
		{
			TransmitManager_SetEntityState(entity, client, true);
		}
	}
	
	if (g_Players[target].equipped_facemask)
	{
		int entity = g_Players[target].GetFacemaskEntity();
		if (entity != -1)
		{
			TransmitManager_SetEntityState(entity, client, !(SpecHooks_GetObserverMode(client) == OBS_MODE_IN_EYE));
		}
	}
}

public void SpecHooks_OnObserverModeChangePost(int client, int mode, int last_mode)
{
	int observer_target = SpecHooks_GetObserverTarget(client);
	if (observer_target != -1 && g_Players[observer_target].equipped_facemask)
	{
		int entity = g_Players[observer_target].GetFacemaskEntity();
		if (entity != -1)
		{
			TransmitManager_SetEntityState(entity, client, !(SpecHooks_GetObserverMode(client) == OBS_MODE_IN_EYE));
		}
	}
}

//================================[ Shop ]================================//

ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	// If already equiped, just unequip.
	if (isOn)
	{
		g_Players[client].equipped_facemask = INVALID_ITEM;
		
		if (IsPlayerAlive(client))
		{
			g_Players[client].RemoveFacemaskEntity();
		}
		
		return Shop_UseOff;
	}
	
	// Toggle off all other items off.
	Shop_ToggleClientCategoryOff(client, category_id);
	
	g_Players[client].equipped_facemask = item_id;
	
	if (IsPlayerAlive(client))
	{
		g_Players[client].SpawnFacemaskEntity();
	}
	
	// Player
	return Shop_UseOn;
}

//================================[ Utils ]================================//

void Lateload()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPutInServer(current_client);
		}
	}
}

void LoadFacemasks()
{
	g_FacemaskModels.Clear();
	
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Facemasks");
	
	// Find the Config
	static char file_path[PLATFORM_MAX_PATH];
	if (!file_path[0])
	{
		BuildPath(Path_SM, file_path, sizeof(file_path), "configs/shop/facemasks.cfg");
	}
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(file_path) || !kv.GotoFirstSubKey())
	{
		SetFailState("Couldn't load plugin config.");
	}
	
	char name[64], description[64], model_path[PLATFORM_MAX_PATH];
	
	// Parse face masks one by one.
	do
	{
		// Get name
		kv.GetString("name", name, sizeof(name));
		
		// Get description
		kv.GetString("description", description, sizeof(description));
		
		// Get model path
		kv.GetString("model_path", model_path, sizeof(model_path));
		
		if (Shop_StartItem(g_ShopCategoryID, name))
		{
			Shop_SetInfo(name, description, kv.GetNum("price"), kv.GetNum("sell_price"), Item_Togglable, 0, kv.GetNum("price_gold"), kv.GetNum("sell_price_gold"));
			Shop_SetCallbacks(.use_toggle = OnEquipItem);
			
			Shop_SetCustomInfoString("model_path", model_path);
			
			Shop_EndItem();
			
			g_FacemaskModels.PushString(model_path);
		}
	} while (kv.GotoNextKey());
	
	// Don't leak handles
	kv.Close();
}

void PrecacheFacemasksModels()
{
	char model[PLATFORM_MAX_PATH];
	for (int current_model; current_model < g_FacemaskModels.Length; current_model++)
	{
		g_FacemaskModels.GetString(current_model, model, sizeof(model));
		
		PrecacheModel(model);
	}
}

//================================================================//