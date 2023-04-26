#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <shop>

int m_hOwnerEntityOffset;

enum struct Player
{
	// This player slot index.
	int index;
	
	// ItemId of the currently equipped face mask.
	ItemId equipped_facemask;
	
	// Entity reference of the player face mask entity.
	int facemask_entity_reference;
	//================================//
	void Init(int client)
	{
		this.index = client;
		this.facemask_entity_reference = INVALID_ENT_REFERENCE;
	}
	
	void Close()
	{
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
		
		SetEntDataEnt2(prop_dynamic_override, m_hOwnerEntityOffset, this.index);
		
		SetVariantString("!activator");
		AcceptEntityInput(prop_dynamic_override, "SetParent", this.index);
		
		SetVariantString("facemask");
		AcceptEntityInput(prop_dynamic_override, "SetParentAttachment");
		
		SDKHook(prop_dynamic_override, SDKHook_SetTransmit, Hook_OnSetTransmit);
		
		this.facemask_entity_reference = EntIndexToEntRef(prop_dynamic_override);
	}
	
	void RemoveFacemaskEntity()
	{
		int entity = EntRefToEntIndex(this.facemask_entity_reference);
		if (entity != -1)
		{
			RemoveEntity(entity);
		}
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
	if ((m_hOwnerEntityOffset = FindSendPropInfo("CCSPlayer", "m_hOwnerEntity")) <= 0)
	{
		SetFailState("Failed to find 'm_hOwnerEntity' netprop offset.");
	}
	
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

Action Hook_OnSetTransmit(int entity, int client)
{
	return GetEntDataEnt2(entity, m_hOwnerEntityOffset) == client ? Plugin_Handled : Plugin_Continue;
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
	if (!g_FacemaskModels)
	{
		g_FacemaskModels = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	}
	else
	{
		g_FacemaskModels.Clear();
	}
	
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