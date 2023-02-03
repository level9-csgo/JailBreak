#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <customweapons>

// JailBreak includes.
#include <JailBreak>
#include <shop>
#include <shop_premium>

#pragma semicolon 1
#pragma newdecls required

// Gift gun shot sound. This is a game sound.
#define GIFTGUN_SHOT_SOUND "Weapon_PartyHorn.Single"

// Gift-gun addon models.
#define GIFTGUN_VIEW_MODEL "models/weapons/v_ak47royalguard.mdl"
#define GIFTGUN_WORLD_MODEL "models/weapons/w_ak47royalguard.mdl"
#define GIFTGUN_DROPPED_MODEL "models/weapons/w_ak47royalguard_dropped.mdl"

// Physics model of the actual gift.
#define GIFT_MODEL "models/items/cs_gift.mdl"

// Stores all spawned gift gun |entity references|.
ArrayList g_GiftGuns;

ConVar sv_infinite_ammo;

public Plugin myinfo = 
{
	name = "[JailBreak Misc] Gift Gun", 
	author = "KoNLiG", 
	description = "Provides a custom weapon that shoots gifts!", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_GiftGuns = new ArrayList();
	
	sv_infinite_ammo = FindConVar("sv_infinite_ammo");
	
	RegAdminCmd("sm_giftgun", Command_GiftGun, ADMFLAG_ROOT, "Equips the command user with a gift gun.");
	
	// Used to spawn gifts on shots!
	HookEvent("weapon_fire", Event_WeaponFire);
}

public void OnMapStart()
{
	// Gift-Gun addons.
	AddDirectoryToDownloadsTable("models/weapons");
	AddDirectoryToDownloadsTable("materials/models/weapons");
	AddDirectoryToDownloadsTable("sound/weapons/ak47");
	
	PrecacheModel(GIFTGUN_VIEW_MODEL);
	PrecacheModel(GIFTGUN_WORLD_MODEL);
	
	PrecacheScriptSound(GIFTGUN_SHOT_SOUND);
	
	// Pickable gift model itself.
	AddDirectoryToDownloadsTable("models/items");
	AddDirectoryToDownloadsTable("materials/models/items");
	
	PrecacheModel(GIFT_MODEL);
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= 0)
	{
		return;
	}
	
	int index = g_GiftGuns.FindValue(EntIndexToEntRef(entity));
	if (index != -1)
	{
		g_GiftGuns.Erase(index);
		
		if (!g_GiftGuns.Length)
		{
			sv_infinite_ammo.BoolValue = false;
		}
	}
}

Action Command_GiftGun(int client, int argc)
{
	if (!client)
	{
		ReplyToCommand(client, "This command cannot be used from the server console");
		return Plugin_Handled;
	}
	
	int gift_gun = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
	
	if (gift_gun != -1)
	{
		RemovePlayerItem(client, gift_gun);
		RemoveEntity(gift_gun);
	}
	
	if ((gift_gun = GivePlayerItem(client, "weapon_ak47")) == -1)
	{
		PrintToChat(client, "%s An error has occured, please try again later.");
		return Plugin_Handled;
	}
	
	CustomWeapon custom_weapon = CustomWeapon(gift_gun);
	if (custom_weapon)
	{
		custom_weapon.SetModel(CustomWeaponModel_View, GIFTGUN_VIEW_MODEL);
		custom_weapon.SetModel(CustomWeaponModel_World, GIFTGUN_WORLD_MODEL);
		custom_weapon.SetModel(CustomWeaponModel_Dropped, GIFTGUN_DROPPED_MODEL);
		
		custom_weapon.SetShotSound(GIFTGUN_SHOT_SOUND);
	}
	
	sv_infinite_ammo.BoolValue = true;
	
	PrintToChat(client, "%s Equipped you with a \x02G\x07i\x0Ff\x0Et\x10-\x04G\x05u\x01n\x0C!", PREFIX);
	
	// 'custom_weapon' itself represents a entity reference.
	g_GiftGuns.Push(custom_weapon);
	
	return Plugin_Handled;
}

void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	static int m_hActiveWeaponOffset;
	if (!m_hActiveWeaponOffset)
	{
		m_hActiveWeaponOffset = FindSendPropInfo("CBasePlayer", "m_hActiveWeapon");
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client)
	{
		return;
	}
	
	// Retrieve the event weapon through 'm_hActiveWeapon' netprop.
	int weapon = GetEntDataEnt2(client, m_hActiveWeaponOffset);
	if (weapon == -1)
	{
		return;
	}
	
	// This weapon isn't a gift gun, skip.
	if (g_GiftGuns.FindValue(EntIndexToEntRef(weapon)) == -1)
	{
		return;
	}
	
	// Allow the usage of the gift gun to root access administrators only.
	if (!(GetUserFlagBits(client) & ADMFLAG_ROOT))
	{
		PrintToChat(client, "%s Nice try...", PREFIX);
		return;
	}
	
	float origin[3], angles[3];
	GetClientEyePosition(client, origin);
	GetClientEyeAngles(client, angles);
	
	ThrowGift(origin, angles);
}

int ThrowGift(float origin[3], float angles[3])
{
	int entity = CreateEntityByName("prop_physics_override");
	if (entity == -1)
	{
		return -1;
	}
	
	float fwd[3], up[3], final_vel[3];
	GetAngleVectors(angles, fwd, NULL_VECTOR, up);
	
	// Scale up the forward vec to create a knockback effect.
	ScaleVector(fwd, 2200.0);
	ScaleVector(up, 40.0);
	AddVectors(fwd, up, final_vel);
	
	DispatchKeyValue(entity, "model", GIFT_MODEL);
	
	DispatchSpawn(entity);
	TeleportEntity(entity, origin, angles, final_vel);
	
	SetEntProp(entity, Prop_Send, "m_usSolidFlags", 0x98);
	
	SetEntPropFloat(entity, Prop_Send, "m_flCycle", GetGameTime() + 0.1);
	
	SetEntityCollisionGroup(entity, 11);
	EntityCollisionRulesChanged(entity);
	
	SDKHook(entity, SDKHook_StartTouch, Hook_OnStartTouch);
	
	return entity;
}

Action Hook_OnStartTouch(int entity, int other)
{
	// Make sure the second entity is an actual client who tries to pick-up a gift.
	if (!(1 <= other <= MaxClients))
	{
		return Plugin_Continue;
	}
	
	int client = other;
	
	if (GetEntPropFloat(entity, Prop_Send, "m_flCycle") > GetGameTime())
	{
		return Plugin_Continue;
	}
	
	// Dispatch a pick-up particle effect from the gift.
	float origin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	DispatchConfettiEffect(origin);
	
	// Erase the entity from the world.
	RemoveEntity(entity);
	
	char reward[32];
	RewardClient(client, reward, sizeof(reward));
	
	PrintToChatAll("%s\x04%N\x01 has picked up a \x04g\x0Ci\x10f\x07t\x01, which contains %s!", strlen(reward) == 16 ? " \x0ECRAZY RARE DROP!\x01 " : " ", client, reward);
	
	return Plugin_Continue;
}

// Hardcoded function ):
// bfffer will be the gift reward string
void RewardClient(int client, char[] buffer, int maxlength)
{
	// premium check
	// 0.001 = 0.1 / (0.1 / 100)
	if (GetURandomFloat() <= 0.001)
	{
		Shop_GivePremium(client, 7);
		Format(buffer, maxlength, "\x0B7 PREMIUM DAYS\x01");
	}
	else
	{
		int credits = GetRandomInt(500, 2500);
		
		Format(buffer, maxlength, "\x07%d credits\x01", credits);
		
		Shop_GiveClientCredits(client, credits, CREDITS_BY_LUCK);
	}
}

// Utl function that wraps 'AddFileToDownloadTable' with a directory input.
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

// https://developer.valvesoftware.com/wiki/List_of_CS:GO_Particles
// CTEEffectDispatch based
void DispatchConfettiEffect(const float origin[3])
{
	static int weapon_confetti_omni = INVALID_STRING_INDEX;
	static int effect_index = INVALID_STRING_INDEX;
	
	if (weapon_confetti_omni == INVALID_STRING_INDEX && 
		(weapon_confetti_omni = GetStringTableItemIndex("ParticleEffectNames", "weapon_confetti_omni")) == INVALID_STRING_INDEX)
	{
		return;
	}
	
	if (effect_index == INVALID_STRING_INDEX && (effect_index = GetStringTableItemIndex("EffectDispatch", "ParticleEffect")) == INVALID_STRING_INDEX)
	{
		return;
	}
	
	TE_Start("EffectDispatch");
	
	TE_WriteFloatArray("m_vOrigin.x", origin, sizeof(origin));
	TE_WriteFloatArray("m_vStart.x", origin, sizeof(origin));
	TE_WriteNum("m_nHitBox", weapon_confetti_omni);
	TE_WriteNum("m_iEffectName", effect_index);
	// TE_WriteNum("m_flRadius", 250);
	
	TE_SendToAll();
}

int GetStringTableItemIndex(const char[] stringTable, const char[] string)
{
	int tableIndex = FindStringTable(stringTable);
	
	if (tableIndex == INVALID_STRING_TABLE)
	{
		LogError("Failed to find string table \"%s\"!", stringTable);
		
		return INVALID_STRING_INDEX;
	}
	
	int index = FindStringIndex(tableIndex, string);
	
	if (index == INVALID_STRING_TABLE)
	{
		LogError("Failed to receive item \"%s\" in string table \"%s\"!", string, stringTable);
	}
	
	return index;
} 