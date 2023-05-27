#include <sourcemod>
#include <sdktools>
#include <shop>
#include <TransmitManager>
#include <spec_hooks>

#define HATS_PREVIEW_FILES_PATH "hat_previews"

enum struct Player
{
	// This player slot index.
	int index;
	
	// This player userid.
	int userid;
	
	// ItemId of the currently equipped hat.
	ItemId equipped_hat;
	
	// Entity reference of the player hat entity.
	int hat_entity_reference;
	//================================//
	void Init(int client)
	{
		this.index = client;
		this.userid = GetClientUserId(client);
		this.hat_entity_reference = INVALID_ENT_REFERENCE;
	}
	
	void Close()
	{
		this.userid = 0;
		this.equipped_hat = INVALID_ITEM;
		this.hat_entity_reference = 0;
	}
	
	void SpawnHatEntity()
	{
		this.RemoveHatEntity();
		
		int prop_dynamic_override = CreateEntityByName("prop_dynamic_override");
		if (prop_dynamic_override == -1)
		{
			return;
		}
		
		// Retrieve the hat model via the equipped hat data.
		char model[PLATFORM_MAX_PATH];
		Shop_GetItemCustomInfoString(this.equipped_hat, "model_path", model, sizeof(model));
		
		DispatchKeyValue(prop_dynamic_override, "model", model);
		DispatchKeyValue(prop_dynamic_override, "solid", "0");
		
		DispatchSpawn(prop_dynamic_override);
		
		SetVariantString("!activator");
		AcceptEntityInput(prop_dynamic_override, "SetParent", this.index);
		
		SetVariantString("facemask");
		AcceptEntityInput(prop_dynamic_override, "SetParentAttachment");
		
		float origin_alignment[3];
		origin_alignment[0] = Shop_GetItemCustomInfoFloat(this.equipped_hat, "origin_alignment_x");
		origin_alignment[1] = Shop_GetItemCustomInfoFloat(this.equipped_hat, "origin_alignment_y");
		origin_alignment[2] = Shop_GetItemCustomInfoFloat(this.equipped_hat, "origin_alignment_z");
		
		float angles_alignment[3];
		angles_alignment[0] = Shop_GetItemCustomInfoFloat(this.equipped_hat, "angles_alignment_x");
		angles_alignment[1] = Shop_GetItemCustomInfoFloat(this.equipped_hat, "angles_alignment_y");
		angles_alignment[2] = Shop_GetItemCustomInfoFloat(this.equipped_hat, "angles_alignment_z");
		
		TeleportEntity(prop_dynamic_override, origin_alignment, angles_alignment);
		
		TransmitManager_AddEntityHooks(prop_dynamic_override);
		TransmitManager_SetEntityState(prop_dynamic_override, this.index, false);
		
		this.hat_entity_reference = EntIndexToEntRef(prop_dynamic_override);
	}
	
	void RemoveHatEntity()
	{
		int entity = this.GetHatEntity();
		if (entity != -1 && IsValidEdict(entity))
		{
			RemoveEdict(entity);
		}
	}
	
	// -1 for invalid.
	int GetHatEntity()
	{
		return EntRefToEntIndex(this.hat_entity_reference);
	}
}

Player g_Players[MAXPLAYERS + 1];

CategoryId g_ShopCategoryID;

// Stores all the hats models to precache them later.
ArrayList g_HatModels;

public Plugin myinfo = 
{
	name = "[Shop Integrated] Hats", 
	author = "KoNLiG", 
	description = "Provides hats as a feature in the shop system.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_HatModels = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	Lateload();
	
	RegConsoleCmd("sm_kovaim", Command_Kovaim);
}

Action Command_Kovaim(int client, int argc)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!IsPlayerAlive(client))
	{
		FakeClientCommand(client, "say \"%s\"", "אני הומו");
	}
	
	SlapPlayer(client, .sound = false);
	
	return Plugin_Handled;
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			g_Players[current_client].RemoveHatEntity();
		}
	}
}

//================================[ Events ]================================//

public void Shop_Started()
{
	g_ShopCategoryID = Shop_RegisterCategory("hats", "Hats", "Get yourself a hat and get hotter!");
	
	LoadHats();
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
	AddDirectoryToDownloadsTable("models/gmod_tower");
	AddDirectoryToDownloadsTable("models/heavy");
	AddDirectoryToDownloadsTable("models/mudhatk");
	AddDirectoryToDownloadsTable("models/pedobear");
	AddDirectoryToDownloadsTable("models/pikahat");
	AddDirectoryToDownloadsTable("models/player");
	AddDirectoryToDownloadsTable("models/sentry_hat");
	AddDirectoryToDownloadsTable("models/spartahelm");
	AddDirectoryToDownloadsTable("models/store");
	AddDirectoryToDownloadsTable("models/vikinghelmet");
	AddDirectoryToDownloadsTable("models/player/items/engineer");
	AddDirectoryToDownloadsTable("models/ptrunners");
	AddDirectoryToDownloadsTable("materials/models/gmod_tower");
	AddDirectoryToDownloadsTable("materials/models/mudhatk");
	AddDirectoryToDownloadsTable("materials/models/pedobear");
	AddDirectoryToDownloadsTable("materials/models/pikahat");
	AddDirectoryToDownloadsTable("materials/models/player");
	AddDirectoryToDownloadsTable("materials/models/sentry_hat");
	AddDirectoryToDownloadsTable("materials/models/spartahelm");
	AddDirectoryToDownloadsTable("materials/models/store");
	AddDirectoryToDownloadsTable("materials/models/vikinghelmet");
	AddDirectoryToDownloadsTable("materials/models/player/items/engineer");
	AddDirectoryToDownloadsTable("materials/models/ptrunners");
	
	// Add all preview images to download table.
	AddDirectoryToDownloadsTable("materials/hat_previews");
	
	PrecacheHatsModels();
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(Frame_ApplyClientHat, event.GetInt("userid"));
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		g_Players[client].RemoveHatEntity();
	}
}

void Frame_ApplyClientHat(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client && g_Players[client].equipped_hat)
	{
		g_Players[client].SpawnHatEntity();
	}
}

public void Shop_OnClientEmotePost(int client)
{
	if (!g_Players[client].equipped_hat)
	{
		return;
	}
	
	int entity = g_Players[client].GetHatEntity();
	if (entity == -1)
	{
		return;
	}
	
	TransmitManager_SetEntityState(entity, client, true);
}

public void Shop_OnClientEmoteStop(int client)
{
	if (!g_Players[client].equipped_hat)
	{
		return;
	}
	
	int entity = g_Players[client].GetHatEntity();
	if (entity == -1)
	{
		return;
	}
	
	TransmitManager_SetEntityState(entity, client, false);
}

public void SpecHooks_OnObserverTargetChangePost(int client, int target, int last_target)
{
	if (last_target != -1 && g_Players[last_target].equipped_hat)
	{
		int entity = g_Players[last_target].GetHatEntity();
		if (entity != -1)
		{
			TransmitManager_SetEntityState(entity, client, true);
		}
	}
	
	if (g_Players[target].equipped_hat)
	{
		int entity = g_Players[target].GetHatEntity();
		if (entity != -1)
		{
			TransmitManager_SetEntityState(entity, client, !(SpecHooks_GetObserverMode(client) == OBS_MODE_IN_EYE));
		}
	}
}

public void SpecHooks_OnObserverModeChangePost(int client, int mode, int last_mode)
{
	int observer_target = SpecHooks_GetObserverTarget(client);
	if (observer_target != -1 && g_Players[observer_target].equipped_hat)
	{
		int entity = g_Players[observer_target].GetHatEntity();
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
		g_Players[client].equipped_hat = INVALID_ITEM;
		
		if (IsPlayerAlive(client))
		{
			g_Players[client].RemoveHatEntity();
		}
		
		return Shop_UseOff;
	}
	
	// Toggle off all other items off.
	Shop_ToggleClientCategoryOff(client, category_id);
	
	g_Players[client].equipped_hat = item_id;
	
	if (IsPlayerAlive(client))
	{
		g_Players[client].SpawnHatEntity();
	}
	
	// Player
	return Shop_UseOn;
}

void OnItemPreview(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item)
{
	char model_path[PLATFORM_MAX_PATH];
	Shop_GetItemCustomInfoString(item_id, "model_path", model_path, sizeof(model_path));
	
	int backslash_idx = FindCharInString(model_path, '/', true);
	if (backslash_idx == -1)
	{
		// Invalid model file path?
		return;
	}
	
	ReplaceString(model_path, sizeof(model_path), ".mdl", "");
	
	PreviewHat(client, model_path[backslash_idx]);
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

void LoadHats()
{
	g_HatModels.Clear();
	
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Hats");
	
	// Find the Config
	static char file_path[PLATFORM_MAX_PATH];
	if (!file_path[0])
	{
		BuildPath(Path_SM, file_path, sizeof(file_path), "configs/shop/hats.cfg");
	}
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(file_path) || !kv.GotoFirstSubKey())
	{
		SetFailState("Couldn't load plugin config.");
	}
	
	char name[64], description[64], model_path[PLATFORM_MAX_PATH];
	float origin_alignment[3], angles_alignment[3];
	
	// Parse hats one by one.
	do
	{
		// Get name
		kv.GetString("name", name, sizeof(name));
		
		// Get description
		kv.GetString("description", description, sizeof(description));
		
		// Get model path
		kv.GetString("model_path", model_path, sizeof(model_path));
		
		kv.GetVector("origin_alignment", origin_alignment);
		kv.GetVector("angles_alignment", angles_alignment);
		
		if (!model_path[0])
		{
			continue;
		}
		
		if (Shop_StartItem(g_ShopCategoryID, name))
		{
			Shop_SetInfo(name, description, kv.GetNum("price"), kv.GetNum("sell_price"), Item_Togglable, 0, kv.GetNum("price_gold"), kv.GetNum("sell_price_gold"));
			Shop_SetCallbacks(.use_toggle = OnEquipItem, .preview = OnItemPreview);
			
			Shop_SetCustomInfoString("model_path", model_path);
			
			Shop_SetCustomInfoFloat("origin_alignment_x", origin_alignment[0]);
			Shop_SetCustomInfoFloat("origin_alignment_y", origin_alignment[1]);
			Shop_SetCustomInfoFloat("origin_alignment_z", origin_alignment[2]);
			
			Shop_SetCustomInfoFloat("angles_alignment_x", angles_alignment[0]);
			Shop_SetCustomInfoFloat("angles_alignment_y", angles_alignment[1]);
			Shop_SetCustomInfoFloat("angles_alignment_z", angles_alignment[2]);
			
			Shop_EndItem();
			
			g_HatModels.PushString(model_path);
		}
	} while (kv.GotoNextKey());
	
	// Don't leak handles
	kv.Close();
}

void PrecacheHatsModels()
{
	char model[PLATFORM_MAX_PATH];
	for (int current_model; current_model < g_HatModels.Length; current_model++)
	{
		g_HatModels.GetString(current_model, model, sizeof(model));
		
		PrecacheModel(model);
	}
}

void AddDirectoryToDownloadsTable(const char[] directory)
{
	// Open directory
	DirectoryListing directory_listing = OpenDirectory(directory);
	if (!directory_listing)
	{
		return;
	}
	
	char entry[PLATFORM_MAX_PATH], full_entry_path[PLATFORM_MAX_PATH];
	FileType file_type;
	
	// loop through all files
	while (directory_listing.GetNext(entry, sizeof(entry), file_type))
	{
		FormatEx(full_entry_path, sizeof(full_entry_path), "%s/%s", directory, entry);
		switch (file_type)
		{
			case FileType_File:
			{
				AddFileToDownloadsTable(full_entry_path);
			}
			
			case FileType_Directory:
			{
				// this / back / hidden folders are not allowed
				if (entry[0] != '.')
				{
					AddDirectoryToDownloadsTable(full_entry_path);
				}
			}
		}
	}
	
	delete directory_listing;
}

void PreviewHat(int client, char[] identifier, bool isFirstRun = true)
{
	static char sMessage[PLATFORM_MAX_PATH];
	
	Protobuf hMessage = view_as<Protobuf>(StartMessageOne("TextMsg", client));
	
	Format(sMessage, sizeof(sMessage), "</font><img src='file://{images}/../../%s/%s.png'/><script>", HATS_PREVIEW_FILES_PATH, identifier);
	
	hMessage.SetInt("msg_dst", 4);
	hMessage.AddString("params", "#SFUI_ContractKillStart");
	hMessage.AddString("params", sMessage);
	hMessage.AddString("params", NULL_STRING);
	hMessage.AddString("params", NULL_STRING);
	hMessage.AddString("params", NULL_STRING);
	hMessage.AddString("params", NULL_STRING);
	
	EndMessage();
	
	// show again so it won't be a small icon!
	if (isFirstRun)
	{
		DataPack dp = new DataPack();
		CreateDataTimer(0.1, Timer_PreviewIconRepeat, dp);
		dp.WriteCell(GetClientUserId(client));
		dp.WriteString(identifier);
		dp.Reset();
	}
}

Action Timer_PreviewIconRepeat(Handle timer, DataPack dp)
{
	int client = GetClientOfUserId(dp.ReadCell());
	if (!client)
	{
		return Plugin_Continue;
	}
	
	char identifier[64];
	dp.ReadString(identifier, sizeof(identifier));
	
	PreviewHat(client, identifier, false);
	return Plugin_Continue;
}

//================================================================//