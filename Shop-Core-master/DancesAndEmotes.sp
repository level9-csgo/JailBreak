#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <shop>
#include <JB_GuardsSystem>

#undef REQUIRE_PLUGIN
#include <JB_SettingsSystem>
#define REQUIRE_PLUGIN

#define PREFIX " \x04[Level9]\x01"

#define SETTINGS_LIBRARY_NAME "JB_SettingsSystem"

#define ALLOWED_BUTTONS (IN_RELOAD|IN_JUMP|IN_SCORE|IN_CANCEL)

enum
{
	Shop_Dances, 
	Shop_Emotes, 
	Shop_Max
};

enum struct EmoteEntities
{
	// Client active weapon entity reference
	int active_weapon_ref;
	
	// Client emote visual entity reference
	int emote_ent_ref;
	
	// Client emote sound effect entity reference
	int emote_sound_ent_ref;
	
	void Init()
	{
		this.active_weapon_ref = INVALID_ENT_REFERENCE;
		this.emote_ent_ref = INVALID_ENT_REFERENCE;
		this.emote_sound_ent_ref = INVALID_ENT_REFERENCE;
	}
}

enum struct Client
{
	EmoteEntities entities;
	
	// The client smote sound effect file path
	char emote_sound_effect[PLATFORM_MAX_PATH];
	
	// Next time the client will be able to emote/dance. Represents by 'GetGameTime()'
	float next_emote;
	
	// Old pressed client buttons
	int old_buttons;
	
	void Reset()
	{
		this.emote_sound_effect[0] = '\0';
		this.next_emote = 0.0;
		this.old_buttons = 0;
	}
	
	void Init()
	{
		this.entities.Init();
	}
	
	bool IsDancing()
	{
		return this.entities.emote_ent_ref != INVALID_ENT_REFERENCE;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

CategoryId g_ShopCategoryID[Shop_Max];

GlobalForward g_OnClientEmote;
GlobalForward g_OnClientEmotePost;
GlobalForward g_OnClientEmoteStop;

ConVar g_ActionCooldown;

char g_RpsEmoteUniques[][] = 
{
	"Emote_RockPaperScissor_Rock", 
	"Emote_RockPaperScissor_Paper", 
	"Emote_RockPaperScissor_Scissor"
};

bool g_IsSettingsLoaded;

int g_DancesVolumeSettingIndex = -1;

public Plugin myinfo = 
{
	name = "[Shop Integrated] Dances And Emotes", 
	author = "Kodua, KoNLiG, Ravid", 
	description = "This plugin is for demonstration of some animations from Fortnite in CS:GO.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// ConVars Confugurate	
	g_ActionCooldown = CreateConVar("shop_dances_emotes_cooldown", "3.0", "Cooldown (in seconds) for dances and emotes. (0 to disable)");
	
	ConVar third_person = FindConVar("sv_allow_thirdperson");
	if (!third_person)
	{
		SetFailState("Unable to find convar 'sv_allow_thirdperson'!");
	}
	
	third_person.AddChangeHook(Hook_OnThirdPersonChanged);
	third_person.BoolValue = true;
	
	// Custom console commands to execute dances/emotes
	AddCommandListener(Listener_StartDance, "+dance");
	AddCommandListener(Listener_StopEmote, "-dance");
	AddCommandListener(Listener_StartEmote, "+emote");
	AddCommandListener(Listener_StopEmote, "-emote");
	
	// Default command for emotes execute
	AddCommandListener(Listener_StartEmote, "drop");
	
	// Event Hooks
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_hurt", Event_PlayerHurt);
	
	// Late plugin load stuff
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
	
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
}

public void OnPluginEnd()
{
	// Unregister the shop from this plugin
	Shop_UnregisterMe();
	
	// Loop through all the clients who dancing, and stop their dance
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_ClientsData[current_client].IsDancing())
		{
			StopEmote(current_client);
		}
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, SETTINGS_LIBRARY_NAME))
	{
		JB_CreateSettingCategory("Sound Settings", "This category is associated with sound in general, as well as music settings.");
		
		g_DancesVolumeSettingIndex = JB_CreateSetting("setting_dances_music_volume", "Controls the dances music volume. (Float setting)", "Dances Music Volume", "Sound Settings", Setting_Float, 1.0, "1.0");
		
		g_IsSettingsLoaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, SETTINGS_LIBRARY_NAME))
	{
		g_IsSettingsLoaded = false;
	}
}

void Hook_OnThirdPersonChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (newValue[0] != '1')
	{
		convar.BoolValue = true;
	}
}

public void OnMapStart()
{
	// Add the required dances and emotes files to the server download table
	AddDirectoryToDownloadTable("models/player/custom_player/kodua");
	AddDirectoryToDownloadTable("sound/kodua/fortnite_emotes");
	
	// Precache the dances and emotes manager model file
	PrecacheModel("models/player/custom_player/kodua/fortnite_emotes_v2.mdl", true);
	
	// Precache the required dances and emotes sound effect files
	PrecacheSound("kodua/fortnite_emotes/ninja_dance_01.mp3");
	PrecacheSound("kodua/fortnite_emotes/dance_soldier_03.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/Hip_Hop_Good_Vibes_Mix_01_Loop.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_zippy_A.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_electroshuffle_music.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_aerobics_01.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_music_emotes_bendy.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_bandofthefort_music.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_boogiedown.wav");
	PrecacheSound("kodua/fortnite_emotes/emote_capoeira.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_flapper_music.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_chicken_foley_01.wav");
	PrecacheSound("kodua/fortnite_emotes/emote_cry.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_music_boneless.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emotes_music_shoot_v7.wav");
	PrecacheSound("*/kodua/fortnite_emotes/Athena_Emotes_Music_SwipeIt.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_disco.wav");
	PrecacheSound("kodua/fortnite_emotes/athena_emote_worm_music.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/athena_music_emotes_takethel.wav");
	PrecacheSound("kodua/fortnite_emotes/athena_emote_breakdance_music.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/Emote_Dance_Pump.wav");
	PrecacheSound("kodua/fortnite_emotes/athena_emote_ridethepony_music_01.mp3");
	PrecacheSound("kodua/fortnite_emotes/athena_emote_facepalm_foley_01.mp3");
	PrecacheSound("kodua/fortnite_emotes/Athena_Emotes_OnTheHook_02.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_floss_music.wav");
	PrecacheSound("kodua/fortnite_emotes/Emote_FlippnSexy.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_fresh_music.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_groove_jam_a.wav");
	PrecacheSound("*/kodua/fortnite_emotes/br_emote_shred_guitar_mix_03_loop.wav");
	PrecacheSound("kodua/fortnite_emotes/Emote_HeelClick.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/s5_hiphop_breakin_132bmp_loop.wav");
	PrecacheSound("kodua/fortnite_emotes/Emote_Hotstuff.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/emote_hula_01.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_infinidab.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_Intensity.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_irish_jig_foley_music_loop.wav");
	PrecacheSound("*/kodua/fortnite_emotes/Athena_Music_Emotes_KoreanEagle.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_kpop_01.wav");
	PrecacheSound("kodua/fortnite_emotes/emote_laugh_01.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/emote_LivingLarge_A.wav");
	PrecacheSound("kodua/fortnite_emotes/Emote_Luchador.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/Emote_Hillbilly_Shuffle.wav");
	PrecacheSound("*/kodua/fortnite_emotes/emote_samba_new_B.wav");
	PrecacheSound("kodua/fortnite_emotes/athena_emote_makeitrain_music.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/Athena_Emote_PopLock.wav");
	PrecacheSound("*/kodua/fortnite_emotes/Emote_PopRock_01.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_robot_music.wav");
	PrecacheSound("kodua/fortnite_emotes/athena_emote_salute_foley_01.mp3");
	PrecacheSound("kodua/fortnite_emotes/Emote_Snap1.mp3");
	PrecacheSound("kodua/fortnite_emotes/emote_stagebow.mp3");
	PrecacheSound("kodua/fortnite_emotes/Emote_Dino_Complete.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_founders_music.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emotes_music_twist.wav");
	PrecacheSound("*/kodua/fortnite_emotes/Emote_Warehouse.wav");
	PrecacheSound("*/kodua/fortnite_emotes/Wiggle_Music_Loop.wav");
	PrecacheSound("kodua/fortnite_emotes/Emote_Yeet.mp3");
	PrecacheSound("kodua/fortnite_emotes/youre_awesome_emote_music.mp3");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emotes_lankylegs_loop_02.wav");
	PrecacheSound("*/kodua/fortnite_emotes/eastern_bloc_musc_setup_d.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_bandofthefort_music.wav");
	PrecacheSound("*/kodua/fortnite_emotes/athena_emote_hot_music.wav");
}

public void OnClientPostAdminCheck(int client)
{
	// Initialize the client entities data
	g_ClientsData[client].Init();
}

public void OnClientDisconnect(int client)
{
	StopEmote(client);
	
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
}

public void OnEntityDestroyed(int entity)
{
	if (!(0 <= entity <= GetMaxEntities()) || !IsValidEntity(entity))
	{
		return;
	}
	
	int client = GetEmoteActivator(EntIndexToEntRef(entity));
	
	if (client != -1)
	{
		g_ClientsData[client].Init();
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	static int m_afButtonReleasedOffset;
	if (!m_afButtonReleasedOffset && (m_afButtonReleasedOffset = FindDataMapInfo(client, "m_afButtonReleased")) <= 0)
	{
		SetFailState("Failed to find offset CCSPlayer::m_afButtonReleased");
	}
	
	if (g_ClientsData[client].IsDancing() && !(GetEntityFlags(client) & FL_ONGROUND))
	{
		StopEmote(client);
	}
	
	if (!g_ClientsData[client].IsDancing() && (GetEntData(client, m_afButtonReleasedOffset) & IN_RELOAD))
	{
		ItemId toggled_dance = GetToggledItem(client, Shop_Dances);
		
		if (toggled_dance == INVALID_ITEM || !IsClientHoldingKnife(client))
		{
			return Plugin_Continue;
		}
		
		StartDanceById(client, toggled_dance);
	}
	
	if (!buttons || !g_ClientsData[client].IsDancing())
	{
		return Plugin_Continue;
	}
	
	if ((buttons & ALLOWED_BUTTONS) && !(buttons & ~ALLOWED_BUTTONS))
	{
		return Plugin_Continue;
	}
	
	StopEmote(client);
	return Plugin_Continue;
}

void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_ClientsData[current_client].IsDancing())
		{
			ToggleClientViewAngle(current_client, false);
			ToggleClientWeaponBlock(current_client, false);
		}
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	ToggleClientViewAngle(client, false);
	StopEmote(client);
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	char attacker_classname[16];
	
	if (GetEntityClassname(GetClientOfUserId(event.GetInt("attacker")), attacker_classname, sizeof(attacker_classname)) && StrEqual(attacker_classname, "worldspawn"))
	{
		StopEmote(GetClientOfUserId(event.GetInt("userid")));
	}
}

//================================[ Command Listeners ]================================//

Action Listener_StartDance(int client, const char[] command, int argc)
{
	ItemId toggled_dance_id = GetToggledItem(client, Shop_Dances);
	
	// If the client isn't equipping any emote or he's not holding a knife, don't continue	
	if (toggled_dance_id == INVALID_ITEM || !IsClientHoldingKnife(client))
	{
		return Plugin_Handled;
	}
	
	StartDanceById(client, toggled_dance_id);
	
	return Plugin_Handled;
}

Action Listener_StartEmote(int client, const char[] command, int argc)
{
	// If the client isn't in-game, don't continue
	if (!IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	
	ItemId toggled_emote_id = GetToggledItem(client, Shop_Emotes);
	
	// If the client isn't equipping any emote or he's not holding a knife, don't continue	
	if (toggled_emote_id == INVALID_ITEM || !IsClientHoldingKnife(client))
	{
		return Plugin_Continue;
	}
	
	StartEmoteById(client, toggled_emote_id);
	
	return Plugin_Handled;
}

Action Listener_StopEmote(int client, const char[] command, int argc)
{
	StopEmote(client);
	return Plugin_Handled;
}

//================================[ Entities Hooks ]================================//

public Action Hook_WeaponCanUseSwitch(int client, int weapon)
{
	return Plugin_Handled;
}

void Hook_OnPostThinkPost(int client)
{
	SetEntProp(client, Prop_Send, "m_iAddonBits", 0);
}

public void Hook_OnAnimationDone(const char[] output, int caller, int activator, float delay)
{
	if ((activator = GetEmoteActivator(EntIndexToEntRef(caller))) != -1)
	{
		StopEmote(activator);
	}
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shop_IsClientEmoting", Native_IsClientEmoting);
	
	g_OnClientEmote = new GlobalForward("Shop_OnClientEmote", ET_Event, Param_Cell, Param_String);
	g_OnClientEmotePost = new GlobalForward("Shop_OnClientEmotePost", ET_Ignore, Param_Cell);
	g_OnClientEmoteStop = new GlobalForward("Shop_OnClientEmoteStop", ET_Ignore, Param_Cell);
	
	RegPluginLibrary("Shop_DancesAndEmotes");
	
	return APLRes_Success;
}

public int Native_IsClientEmoting(Handle plugin, int numParams)
{
	// Get and verify the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_ClientsData[client].IsDancing();
}

//================================[ Dances & Emotes Functions ]================================//

void ExecuteEmote(int client, char[] anim1, char[] anim2, char[] sound_name, bool is_looped, int category_type)
{
	Call_StartForward(g_OnClientEmote);
	Call_PushCell(client); // int client
	Call_PushString(anim1); // char[] animation
	
	Action fwdReturn; // Forward action return
	
	int errors = Call_Finish(fwdReturn);
	if (errors != SP_ERROR_NONE)
	{
		ThrowNativeError(errors, "Client emote forward failed - Error: (%d)", errors);
		return;
	}
	
	// The forward has blocked the emote execution
	if (fwdReturn > Plugin_Continue)
	{
		return;
	}
	
	// If the client isn't standing on the ground, warn the client and don't continue
	if (!(GetEntityFlags(client) & FL_ONGROUND))
	{
		// PrintToChat(client, "%s You must stand on the ground to %s!", PREFIX, category_type == Shop_Dances ? "dance" : "emote");
		return;
	}
	
	// If the client emote cooldown is still active, warn the client and don't continue
	float game_time = GetGameTime();
	if (game_time < g_ClientsData[client].next_emote)
	{
		PrintToChat(client, "%s Please wait \x02%.1f\x01 seconds before trying to %s again!", PREFIX, g_ClientsData[client].next_emote - game_time, category_type == Shop_Dances ? "dance" : "emote");
		return;
	}
	
	// The client is dancing, stop the old dance
	if (g_ClientsData[client].IsDancing())
	{
		StopEmote(client);
	}
	
	// If the client is frozen, warn the client and don't continue 
	if (GetEntityMoveType(client) == MOVETYPE_NONE)
	{
		PrintToChat(client, "%s You can't %s while you are frozen!", PREFIX, category_type == Shop_Dances ? "dance" : "emote");
		return;
	}
	
	/* If the client is in noclip, warn the client and don't continue 
	if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		PrintToChat(client, "%s You can't %s while you are in noclip!", PREFIX, category_type == Shop_Dances ? "dance" : "emote");
		return;
	}*/
	
	// Create the emote visual entity
	int entity = CreateEmoteEntity(client, anim1, anim2, sound_name, is_looped);
	if (entity == -1)
	{
		PrintToChat(client, "%s Unable to create your %s entity, plesae try again later.", PREFIX, category_type == Shop_Dances ? "dance" : "emote");
		return;
	}
	
	ToggleClientViewAngle(client, true);
	
	// Apply the emote cooldown
	if (g_ActionCooldown.FloatValue > 0.0)
	{
		g_ClientsData[client].next_emote = game_time + g_ActionCooldown.FloatValue;
	}
	
	ArrayList spectators = GetClientSpectators(client);
	for (int current_spectator, spectator; current_spectator < spectators.Length; current_spectator++)
	{
		spectator = spectators.Get(current_spectator);
		
		// mode 4 - first person [1 iteration]
		// mode 5 - third person [0 iterations]
		// mode 6 - free look [2 iterations]
		int iterations[3] = { 1, 0, 2 };
		int mode = GetEntProp(spectator, Prop_Send, "m_iObserverMode");
		if (mode - 4 >= 0)
		{
			for (int i; i < iterations[mode - 4]; i++)
			{
				FakeClientCommand(spectator, "spec_mode");
			}
		}
	}
	
	delete spectators;
	
	Call_StartForward(g_OnClientEmotePost);
	Call_PushCell(client);
	Call_Finish();
}

void StopEmote(int client)
{
	if (!g_ClientsData[client].IsDancing())
	{
		return;
	}
	
	int iEmoteEnt = EntRefToEntIndex(g_ClientsData[client].entities.emote_ent_ref);
	if (iEmoteEnt && iEmoteEnt != INVALID_ENT_REFERENCE && IsValidEntity(iEmoteEnt))
	{
		char emoteEntName[50];
		GetEntPropString(iEmoteEnt, Prop_Data, "m_iName", emoteEntName, sizeof(emoteEntName));
		SetVariantString(emoteEntName);
		
		AcceptEntityInput(client, "ClearParent", iEmoteEnt, iEmoteEnt);
		
		RequestFrame(Frame_RemoveEmoteEntity, g_ClientsData[client].entities.emote_ent_ref);
		
		ToggleClientViewAngle(client, false);
		ToggleClientWeaponBlock(client, false);
		
		SetEntityMoveType(client, MOVETYPE_WALK);
		ToggleClientFreeze(client, false);
	}
	
	if (g_ClientsData[client].entities.emote_sound_ent_ref != INVALID_ENT_REFERENCE)
	{
		int iEmoteSoundEnt = EntRefToEntIndex(g_ClientsData[client].entities.emote_sound_ent_ref);
		
		if (g_ClientsData[client].emote_sound_effect[0] != '\0' && iEmoteSoundEnt && iEmoteSoundEnt != INVALID_ENT_REFERENCE && IsValidEntity(iEmoteSoundEnt))
		{
			StopSound(iEmoteSoundEnt, SNDCHAN_AUTO, g_ClientsData[client].emote_sound_effect);
			AcceptEntityInput(iEmoteSoundEnt, "Kill");
		}
	}
	
	ArrayList spectators = GetClientSpectators(client);
	for (int current_spectator, spectator; current_spectator < spectators.Length; current_spectator++)
	{
		spectator = spectators.Get(current_spectator);
		
		// mode 4 - first person [0 iteration]
		// mode 5 - third person [2 iterations]
		// mode 6 - free look [1 iterations]
		int iterations[3] = { 0, 2, 1 };
		int mode = GetEntProp(spectator, Prop_Send, "m_iObserverMode");
		if (mode - 4 >= 0)
		{
			for (int i; i < iterations[mode - 4]; i++)
			{
				FakeClientCommand(spectator, "spec_mode");
			}
		}
	}
	
	delete spectators;
	
	Call_StartForward(g_OnClientEmoteStop);
	Call_PushCell(client);
	Call_Finish();
	
	if (!IsValidEntity(client))
	{
		return;
	}
	
	int stuck_entity = GetStuckEntity(client);
	if (stuck_entity == -1)
	{
		return;
	}
	
	char classname[32];
	GetEntityClassname(stuck_entity, classname, sizeof(classname));
	
	if (StrContains(classname, "weapon_") != -1)
	{
		return;
	}
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	AcceptEntityInput(stuck_entity, "Open");
	
	CreateTimer(0.1, Timer_RestoreMovetype, GetClientUserId(client), TIMER_REPEAT);
}

void Frame_RemoveEmoteEntity(int ent_ref)
{
	int entity = EntRefToEntIndex(ent_ref);
	if (entity && entity != -1 && IsValidEntity(entity))
	{
		RemoveEntity(entity);
	}
}

Action Timer_RestoreMovetype(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client)
	{
		return Plugin_Stop;
	}
	
	if (GetStuckEntity(client) == -1)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void StartDanceById(int client, ItemId item_id)
{
	char item_unique[64];
	Shop_GetItemById(item_id, item_unique, sizeof(item_unique));
	
	if (StrEqual(item_unique, "DanceMoves"))
	{
		ExecuteEmote(client, "DanceMoves", "none", "ninja_dance_01", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Mask_Off_Intro")) {
		ExecuteEmote(client, "Emote_Mask_Off_Intro", "Emote_Mask_Off_Loop", "Hip_Hop_Good_Vibes_Mix_01_Loop", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Zippy_Dance")) {
		ExecuteEmote(client, "Emote_Zippy_Dance", "none", "emote_zippy_A", true, Shop_Dances);
	} else if (StrEqual(item_unique, "ElectroShuffle")) {
		ExecuteEmote(client, "ElectroShuffle", "none", "athena_emote_electroshuffle_music", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_AerobicChamp")) {
		ExecuteEmote(client, "Emote_AerobicChamp", "none", "emote_aerobics_01", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Bendy")) {
		ExecuteEmote(client, "Emote_Bendy", "none", "athena_music_emotes_bendy", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_BandOfTheFort")) {
		ExecuteEmote(client, "Emote_BandOfTheFort", "none", "athena_emote_bandofthefort_music", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Boogie_Down_Intro")) {
		ExecuteEmote(client, "Emote_Boogie_Down_Intro", "Emote_Boogie_Down", "emote_boogiedown", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Capoeira")) {
		ExecuteEmote(client, "Emote_Capoeira", "none", "emote_capoeira", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Charleston")) {
		ExecuteEmote(client, "Emote_Charleston", "none", "athena_emote_flapper_music", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Chicken")) {
		ExecuteEmote(client, "Emote_Chicken", "none", "athena_emote_chicken_foley_01", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_NoBones")) {
		ExecuteEmote(client, "Emote_Dance_NoBones", "none", "athena_emote_music_boneless", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_Shoot")) {
		ExecuteEmote(client, "Emote_Dance_Shoot", "none", "athena_emotes_music_shoot_v7", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_SwipeIt")) {
		ExecuteEmote(client, "Emote_Dance_SwipeIt", "none", "Athena_Emotes_Music_SwipeIt", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_Disco_T3")) {
		ExecuteEmote(client, "Emote_Dance_Disco_T3", "none", "athena_emote_disco", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_DG_Disco")) {
		ExecuteEmote(client, "Emote_DG_Disco", "none", "athena_emote_disco", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_Worm")) {
		ExecuteEmote(client, "Emote_Dance_Worm", "none", "athena_emote_worm_music", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_Loser")) {
		ExecuteEmote(client, "Emote_Dance_Loser", "Emote_Dance_Loser_CT", "athena_music_emotes_takethel", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_Breakdance")) {
		ExecuteEmote(client, "Emote_Dance_Breakdance", "none", "athena_emote_breakdance_music", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_Pump")) {
		ExecuteEmote(client, "Emote_Dance_Pump", "none", "Emote_Dance_Pump", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dance_RideThePony")) {
		ExecuteEmote(client, "Emote_Dance_RideThePony", "none", "athena_emote_ridethepony_music_01", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Dab")) {
		ExecuteEmote(client, "Emote_Dab", "none", "", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_EasternBloc_Start")) {
		ExecuteEmote(client, "Emote_EasternBloc_Start", "Emote_EasternBloc", "eastern_bloc_musc_setup_d", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_FancyFeet")) {
		ExecuteEmote(client, "Emote_FancyFeet", "Emote_FancyFeet_CT", "athena_emotes_lankylegs_loop_02", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_FlossDance")) {
		ExecuteEmote(client, "Emote_FlossDance", "none", "athena_emote_floss_music", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_FlippnSexy")) {
		ExecuteEmote(client, "Emote_FlippnSexy", "none", "Emote_FlippnSexy", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Fresh")) {
		ExecuteEmote(client, "Emote_Fresh", "none", "athena_emote_fresh_music", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_GrooveJam")) {
		ExecuteEmote(client, "Emote_GrooveJam", "none", "emote_groove_jam_a", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_guitar")) {
		ExecuteEmote(client, "Emote_guitar", "none", "br_emote_shred_guitar_mix_03_loop", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Hillbilly_Shuffle_Intro")) {
		ExecuteEmote(client, "Emote_Hillbilly_Shuffle_Intro", "Emote_Hillbilly_Shuffle", "Emote_Hillbilly_Shuffle", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Hiphop_01")) {
		ExecuteEmote(client, "Emote_Hiphop_01", "Emote_Hip_Hop", "s5_hiphop_breakin_132bmp_loop", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Hula_Start")) {
		ExecuteEmote(client, "Emote_Hula_Start", "Emote_Hula", "emote_hula_01", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_InfiniDab_Intro")) {
		ExecuteEmote(client, "Emote_InfiniDab_Intro", "Emote_InfiniDab_Loop", "athena_emote_infinidab", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Intensity_Start")) {
		ExecuteEmote(client, "Emote_Intensity_Start", "Emote_Intensity_Loop", "emote_Intensity", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_IrishJig_Start")) {
		ExecuteEmote(client, "Emote_IrishJig_Start", "Emote_IrishJig", "emote_irish_jig_foley_music_loop", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_KoreanEagle")) {
		ExecuteEmote(client, "Emote_KoreanEagle", "none", "Athena_Music_Emotes_KoreanEagle", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Kpop_02")) {
		ExecuteEmote(client, "Emote_Kpop_02", "none", "emote_kpop_01", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_LivingLarge")) {
		ExecuteEmote(client, "Emote_LivingLarge", "none", "emote_LivingLarge_A", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Maracas")) {
		ExecuteEmote(client, "Emote_Maracas", "none", "emote_samba_new_B", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_PopLock")) {
		ExecuteEmote(client, "Emote_PopLock", "none", "Athena_Emote_PopLock", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_PopRock")) {
		ExecuteEmote(client, "Emote_PopRock", "none", "Emote_PopRock_01", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_RobotDance")) {
		ExecuteEmote(client, "Emote_RobotDance", "none", "athena_emote_robot_music", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_T-Rex")) {
		ExecuteEmote(client, "Emote_T-Rex", "none", "Emote_Dino_Complete", false, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_TechnoZombie")) {
		ExecuteEmote(client, "Emote_TechnoZombie", "none", "athena_emote_founders_music", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Twist")) {
		ExecuteEmote(client, "Emote_Twist", "none", "athena_emotes_music_twist", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_WarehouseDance_Start")) {
		ExecuteEmote(client, "Emote_WarehouseDance_Start", "Emote_WarehouseDance_Loop", "Emote_Warehouse", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Wiggle")) {
		ExecuteEmote(client, "Emote_Wiggle", "none", "Wiggle_Music_Loop", true, Shop_Dances);
	} else if (StrEqual(item_unique, "Emote_Youre_Awesome")) {
		ExecuteEmote(client, "Emote_Youre_Awesome", "none", "youre_awesome_emote_music", false, Shop_Dances);
	}
}

void StartEmoteById(int client, ItemId item_id)
{
	char item_unique[64];
	Shop_GetItemById(item_id, item_unique, sizeof(item_unique));
	
	if (StrEqual(item_unique, "Emote_Fonzie_Pistol"))
	{
		ExecuteEmote(client, "Emote_Fonzie_Pistol", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Bring_It_On")) {
		ExecuteEmote(client, "Emote_Bring_It_On", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_ThumbsDown")) {
		ExecuteEmote(client, "Emote_ThumbsDown", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_ThumbsUp")) {
		ExecuteEmote(client, "Emote_ThumbsUp", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Celebration_Loop")) {
		ExecuteEmote(client, "Emote_Celebration_Loop", "", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_BlowKiss")) {
		ExecuteEmote(client, "Emote_BlowKiss", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Calculated")) {
		ExecuteEmote(client, "Emote_Calculated", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Confused")) {
		ExecuteEmote(client, "Emote_Confused", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Chug")) {
		ExecuteEmote(client, "Emote_Chug", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Cry")) {
		ExecuteEmote(client, "Emote_Cry", "none", "emote_cry", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_DustingOffHands")) {
		ExecuteEmote(client, "Emote_DustingOffHands", "none", "athena_emote_bandofthefort_music", true, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_DustOffShoulders")) {
		ExecuteEmote(client, "Emote_DustOffShoulders", "none", "athena_emote_hot_music", true, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Facepalm")) {
		ExecuteEmote(client, "Emote_Facepalm", "none", "athena_emote_facepalm_foley_01", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Fishing")) {
		ExecuteEmote(client, "Emote_Fishing", "none", "Athena_Emotes_OnTheHook_02", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Flex")) {
		ExecuteEmote(client, "Emote_Flex", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_golfclap")) {
		ExecuteEmote(client, "Emote_golfclap", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_HandSignals")) {
		ExecuteEmote(client, "Emote_HandSignals", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_HeelClick")) {
		ExecuteEmote(client, "Emote_HeelClick", "none", "Emote_HeelClick", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Hotstuff")) {
		ExecuteEmote(client, "Emote_Hotstuff", "none", "Emote_Hotstuff", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_IBreakYou")) {
		ExecuteEmote(client, "Emote_IBreakYou", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_IHeartYou")) {
		ExecuteEmote(client, "Emote_IHeartYou", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Kung-Fu_Salute")) {
		ExecuteEmote(client, "Emote_Kung-Fu_Salute", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Laugh")) {
		ExecuteEmote(client, "Emote_Laugh", "Emote_Laugh_CT", "emote_laugh_01", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Luchador")) {
		ExecuteEmote(client, "Emote_Luchador", "none", "Emote_Luchador", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Make_It_Rain")) {
		ExecuteEmote(client, "Emote_Make_It_Rain", "none", "athena_emote_makeitrain_music", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_NotToday")) {
		ExecuteEmote(client, "Emote_NotToday", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_RockPaperScissor")) {
		ExecuteEmote(client, g_RpsEmoteUniques[GetRandomInt(0, sizeof(g_RpsEmoteUniques) - 1)], "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Salt")) {
		ExecuteEmote(client, "Emote_Salt", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Salute")) {
		ExecuteEmote(client, "Emote_Salute", "none", "athena_emote_salute_foley_01", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_SmoothDrive")) {
		ExecuteEmote(client, "Emote_SmoothDrive", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Snap")) {
		ExecuteEmote(client, "Emote_Snap", "none", "Emote_Snap1", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_StageBow")) {
		ExecuteEmote(client, "Emote_StageBow", "none", "emote_stagebow", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Wave2")) {
		ExecuteEmote(client, "Emote_Wave2", "none", "", false, Shop_Emotes);
	} else if (StrEqual(item_unique, "Emote_Yeet")) {
		ExecuteEmote(client, "Emote_Yeet", "none", "Emote_Yeet", false, Shop_Emotes);
	}
}

//================================[ Shop ]================================//

public void Shop_Started()
{
	g_ShopCategoryID[Shop_Dances] = Shop_RegisterCategory("dances", "Dances", "Break the floor with fancy dances!");
	g_ShopCategoryID[Shop_Emotes] = Shop_RegisterCategory("emotes", "Emotes", "Show some emotional feelings.");
	
	RegisterDances();
	RegisterEmotes();
}

void RegisterDances()
{
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Dances");
	
	// Find the Config
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/shop/dances.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(sFilePath) || !kv.GotoFirstSubKey())
	{
		SetFailState("Couldn't load dances config.");
	}
	
	char unique[64], name[64], description[64];
	
	// Parse agents one by one.
	do
	{
		// Get unique
		kv.GetString("unique", unique, sizeof(unique));
		
		// Get name
		kv.GetString("name", name, sizeof(name));
		
		// Get description
		kv.GetString("description", description, sizeof(description));
		
		if (Shop_StartItem(g_ShopCategoryID[Shop_Dances], unique))
		{
			Shop_SetInfo(name, description, kv.GetNum("price"), kv.GetNum("sell_price"), Item_Togglable, 0, kv.GetNum("price_gold"), kv.GetNum("sell_price_gold"));
			Shop_SetCallbacks(.use_toggle = OnEquipItem);
			
			Shop_EndItem();
		}
	} while (kv.GotoNextKey());
	
	// Don't leak handles
	kv.Close();
}

void RegisterEmotes()
{
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Emotes");
	
	// Find the Config
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/shop/emotes.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(sFilePath) || !kv.GotoFirstSubKey())
	{
		SetFailState("Couldn't load emotes config.");
	}
	
	char unique[64], name[64], description[64];
	
	// Parse agents one by one.
	do
	{
		// Get unique
		kv.GetString("unique", unique, sizeof(unique));
		
		// Get name
		kv.GetString("name", name, sizeof(name));
		
		// Get description
		kv.GetString("description", description, sizeof(description));
		
		if (Shop_StartItem(g_ShopCategoryID[Shop_Emotes], unique))
		{
			Shop_SetInfo(name, description, kv.GetNum("price"), kv.GetNum("sell_price"), Item_Togglable, 0, kv.GetNum("price_gold"), kv.GetNum("sell_price_gold"));
			Shop_SetCallbacks(.use_toggle = OnEquipItem);
			
			Shop_EndItem();
		}
	} while (kv.GotoNextKey());
	
	// Don't leak handles
	kv.Close();
}

public ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	// If already equiped, just unequip.
	if (isOn)
	{
		return Shop_UseOff;
	}
	
	// Toggle off all other items off.
	Shop_ToggleClientCategoryOff(client, category_id);
	
	// Player
	return Shop_UseOn;
}

//================================[ Functions ]================================//

int CreateEmoteEntity(int client, char[] emote_animation, char[] default_animation, char[] sound_name, bool is_looped)
{
	int emote_entity = CreateEntityByName("prop_dynamic");
	
	if (emote_entity == -1 || !IsValidEntity(emote_entity))
	{
		return -1;
	}
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	
	ToggleClientFreeze(client, true);
	ToggleClientWeaponBlock(client, true);
	
	float pos[3], ang[3];
	GetClientAbsOrigin(client, pos);
	GetClientAbsAngles(client, ang);
	
	DispatchKeyValue(emote_entity, "model", "models/player/custom_player/kodua/fortnite_emotes_v2.mdl");
	DispatchKeyValue(emote_entity, "solid", "0");
	DispatchKeyValue(emote_entity, "rendermode", "10");
	
	ActivateEntity(emote_entity);
	DispatchSpawn(emote_entity);
	
	TeleportEntity(emote_entity, pos, ang, NULL_VECTOR);
	
	SetVariantString("!activator");
	AcceptEntityInput(client, "SetParent", emote_entity, client);
	
	g_ClientsData[client].entities.emote_ent_ref = EntIndexToEntRef(emote_entity);
	
	int client_effects = GetEntProp(client, Prop_Send, "m_fEffects");
	client_effects |= 1; // EF_BONEMERGE 
	client_effects |= 16; // EF_NOSHADOW 
	client_effects |= 64; // EF_NORECEIVESHADOW 
	client_effects |= 128; // EF_BONEMERGE_FASTCULL 
	client_effects |= 512; //  EF_PARENT_ANIMATES 
	SetEntProp(client, Prop_Send, "m_fEffects", client_effects);
	
	if (sound_name[0] != '\0')
	{
		int sound_entity = CreateEntityByName("info_target");
		
		if (sound_entity == -1 || !IsValidEntity(sound_entity))
		{
			return -1;
		}
		
		char sound_unique_name[16];
		FormatEx(sound_unique_name, sizeof(sound_unique_name), "sound_%d", GetRandomInt(1000000, 9999999));
		
		DispatchKeyValue(sound_entity, "targetname", sound_unique_name);
		
		DispatchSpawn(sound_entity);
		
		pos[2] += 72.0;
		TeleportEntity(sound_entity, pos, NULL_VECTOR, NULL_VECTOR);
		
		SetVariantString("!activator");
		AcceptEntityInput(sound_entity, "SetParent", emote_entity);
		
		g_ClientsData[client].entities.emote_sound_ent_ref = EntIndexToEntRef(sound_entity);
		
		// Format sound path
		char emote_sound_name[64];
		
		if (StrEqual(sound_name, "ninja_dance_01") || StrEqual(sound_name, "dance_soldier_03"))
		{
			emote_sound_name = GetRandomInt(0, 1) ? "ninja_dance_01" : "dance_soldier_03";
		}
		else
		{
			strcopy(emote_sound_name, sizeof(emote_sound_name), sound_name);
		}
		
		FormatEx(g_ClientsData[client].emote_sound_effect, PLATFORM_MAX_PATH, "%skodua/fortnite_emotes/%s.%s", is_looped ? "*/" : "", emote_sound_name, is_looped ? "wav" : "mp3");
		
		if (g_IsSettingsLoaded)
		{
			char setting_value[16];
			
			for (int current_client = 1; current_client <= MaxClients; current_client++)
			{
				if (IsClientInGame(current_client))
				{
					JB_GetClientSetting(current_client, g_DancesVolumeSettingIndex, setting_value, sizeof(setting_value));
					
					EmitSoundToClient(current_client, g_ClientsData[client].emote_sound_effect, sound_entity, .level = SNDLEVEL_CONVO, .volume = StringToFloat(setting_value), .origin = pos);
				}
			}
		}
		else
		{
			EmitSoundToAll(g_ClientsData[client].emote_sound_effect, sound_entity, .level = SNDLEVEL_CONVO, .origin = pos);
		}
	}
	else
	{
		g_ClientsData[client].emote_sound_effect = "";
	}
	
	if (StrEqual(default_animation, "none"))
	{
		HookSingleEntityOutput(emote_entity, "OnAnimationDone", Hook_OnAnimationDone, true);
	}
	else
	{
		SetVariantString(default_animation);
		AcceptEntityInput(emote_entity, "SetDefaultAnimation");
	}
	
	SetVariantString(emote_animation);
	AcceptEntityInput(emote_entity, "SetAnimation");
	
	return emote_entity;
}

bool IsClientHoldingKnife(int client)
{
	// Get the client holding weapon string
	char client_weapon[32];
	GetClientWeapon(client, client_weapon, sizeof(client_weapon));
	
	return !(StrContains(client_weapon, "knife", false) == -1 && StrContains(client_weapon, "bayonet", false) == -1);
}

int GetEmoteActivator(int emote_ent_ref)
{
	if (emote_ent_ref == INVALID_ENT_REFERENCE)
	{
		return -1;
	}
	
	// Loop through all the online clients and compare their emote entity reference to the given emote entity reference
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_ClientsData[current_client].entities.emote_ent_ref == emote_ent_ref)
		{
			// Compare has succeed, return the current client index
			return current_client;
		}
	}
	
	return -1;
}

void AddDirectoryToDownloadTable(const char[] dir)
{
	char file_name[PLATFORM_MAX_PATH], file_path[PLATFORM_MAX_PATH];
	DirectoryListing dir_listing = OpenDirectory(dir);
	FileType file_type;
	
	if (!dir_listing)
	{
		return;
	}
	
	while (ReadDirEntry(dir_listing, file_name, sizeof(file_name), file_type))
	{
		FormatEx(file_path, sizeof(file_path), "%s/%s", dir, file_name);
		
		if (file_type == FileType_File)
		{
			AddFileToDownloadsTable(file_path);
		}
		else if (file_type == FileType_Directory && !StrEqual(file_name, ".") && !StrEqual(file_name, ".."))
		{
			AddDirectoryToDownloadTable(file_path);
		}
	}
	
	delete dir_listing;
}

ItemId GetToggledItem(int client, int category_type)
{
	// Cannot use shop natives on bots.
	if (IsFakeClient(client))
	{
		return INVALID_ITEM;
	}
	
	// Get the client shop items arraylist, and make sure it's not empty
	ArrayList client_shop_items = Shop_GetClientItems(client);
	
	if (!client_shop_items.Length)
	{
		// Don't leak handles!
		delete client_shop_items;
		
		// Return invalid item id
		return INVALID_ITEM;
	}
	
	ItemId current_item_id;
	
	for (int current_item = 0; current_item < client_shop_items.Length; current_item++)
	{
		// Get the current shop item id by the current client inventory item index
		current_item_id = client_shop_items.Get(current_item);
		
		// The item toggle statments are valid!
		if (Shop_GetItemCategoryId(current_item_id) == g_ShopCategoryID[category_type] && Shop_IsClientItemToggled(client, current_item_id))
		{
			// Don't leak handles!
			delete client_shop_items;
			
			// Return the current item id
			return current_item_id;
		}
	}
	
	// Don't leak handles!
	delete client_shop_items;
	
	// Return invalid item id
	return INVALID_ITEM;
}

void ToggleClientFreeze(int client, bool mode)
{
	if (JB_IsInvitePeriodRunning() && JB_GetClientGuardRank(client) != Guard_NotGuard && !mode)
	{
		return;
	}
	
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", mode ? 0.0 : 1.0);
}

void ToggleClientViewAngle(int client, bool mode)
{
	if (mode)
	{
		ClientCommand(client, "thirdperson; cam_collision 0; cam_idealpitch 0; cam_idealyaw 0");
	}
	else
	{
		ClientCommand(client, "firstperson; cam_collision 1");
	}
}

void ToggleClientWeaponBlock(int client, bool mode)
{
	if (mode)
	{
		// Perform the requried sdk hooks on the client
		SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUseSwitch);
		SDKHook(client, SDKHook_WeaponSwitch, Hook_WeaponCanUseSwitch);
		SDKHook(client, SDKHook_PostThinkPost, Hook_OnPostThinkPost);
		
		// Get the active weapon entity index
		int active_weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		
		// If it's valid store it inside the client data, and remove the current active weapon
		if (active_weapon != -1)
		{
			g_ClientsData[client].entities.active_weapon_ref = EntIndexToEntRef(active_weapon);
			
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
		}
	}
	else
	{
		// Perform the requried sdk unhooks on the client
		SDKUnhook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUseSwitch);
		SDKUnhook(client, SDKHook_WeaponSwitch, Hook_WeaponCanUseSwitch);
		SDKUnhook(client, SDKHook_PostThinkPost, Hook_OnPostThinkPost);
		
		// If the client is alive and the old active weapon entity reference is valid, return the weapon
		if (IsPlayerAlive(client) && g_ClientsData[client].entities.active_weapon_ref != INVALID_ENT_REFERENCE)
		{
			int entity = EntRefToEntIndex(g_ClientsData[client].entities.active_weapon_ref);
			
			if (entity != INVALID_ENT_REFERENCE)
			{
				SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", entity);
			}
		}
		
		g_ClientsData[client].entities.active_weapon_ref = INVALID_ENT_REFERENCE;
	}
}

int GetStuckEntity(int entity)
{
	// Initialize the entity's mins, maxs and position vectors
	float ent_mins[3], ent_maxs[3], pos[3];
	
	GetEntPropVector(entity, Prop_Send, "m_vecMins", ent_mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", ent_maxs);
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	
	// Create a global trace hull that will ensure the entity will not stuck inside the world/another entity
	TR_TraceHullFilter(pos, pos, ent_mins, ent_maxs, MASK_ALL, Filter_OnlyPlayers, entity);
	
	return TR_GetEntityIndex();
}

bool Filter_OnlyPlayers(int entity, int contentsMask, int other)
{
	return entity > MaxClients && entity != EntRefToEntIndex(g_ClientsData[other].entities.emote_ent_ref);
}

ArrayList GetClientSpectators(int client)
{
	ArrayList spectators = new ArrayList();
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsPlayerAlive(current_client) && GetEntPropEnt(current_client, Prop_Send, "m_hObserverTarget") == client)
		{
			spectators.Push(current_client);
		}
	}
	
	return spectators;
}

//================================================================//