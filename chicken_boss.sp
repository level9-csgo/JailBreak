#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <regex>
// perform a shake effect on chicken jump phase
// Platform includes.
#include <JailBreak>

#pragma semicolon 1
#pragma newdecls required

#define OWNERSHIP_RESPONSE_COOLDOWN 10.0

// Displayed in chat messages.
#define CHICKEN_BOSS_NAME "Dexon"

#define CLIENTS_HEALTH 200

#define DEATH_PHASE_THUNDERSTORM_FREQ 0.2

#define DEATH_PHASE_LASERS_COUNT 25
#define DEATH_PHASE_LASERS_INTERVAL 0.5

#define DEATH_PHASE_SEQUENCE 8

#define WIND_PHASE_SEQUENCE 3
#define WIND_PHASE_SEQUENCE_DURATION 0.699999
#define WIND_PHASE_SOUND "physics/destruction/smash_rockcollapse1.wav"

#define MISSILE_EXPLODE_SOUND "weapons/eminem/bms_rpg/rocket_explode.wav"

// Physics model of the actual gift.
#define GIFT_MODEL "models/items/cs_gift.mdl"

#define EVACUATE_COMMAND "leave"
#define AUTO_EVACUATE_TIME 90

//#define BOSS_HEALTH 250000.0
#define BOSS_HEALTH 10000.0
// #define GIFT_COUNT (5 * GetClientCount())
#define GIFT_COUNT 150

#define PHASES_COUNT 3
#define DMG_PER_PHASE (BOSS_HEALTH / (PHASES_COUNT + 1))

#define TREE_MODEL "models/props_foliage/urban_tree_giant01.mdl"

enum struct Player
{
	float next_ownership_response_time;
	
	// Damage dealt to the chicken boss.
	float damage_dealt;
	
	bool allowed_to_evacuate;
	
	//========================================//
	
	void Close()
	{
		this.next_ownership_response_time = 0.0;
		this.damage_dealt = 0.0;
		this.allowed_to_evacuate = false;
	}
}

Player g_Players[MAXPLAYERS + 1];

// Game convars.
ConVar sv_infinite_ammo;

// Plugin convars.
ConVar chicken_boss_scale;

// Sound effects file paths.
char g_DeathPhaseEntrySounds[][] = 
{
	"ambient/creatures/chicken_panic_01.wav", 
	"ambient/creatures/chicken_panic_02.wav", 
	"ambient/creatures/chicken_panic_03.wav", 
	"ambient/creatures/chicken_panic_04.wav"
};

char g_DeathSounds[][] = 
{
	"ambient/creatures/chicken_death_01.wav", 
	"ambient/creatures/chicken_death_02.wav", 
	"ambient/creatures/chicken_death_03.wav"
};

char g_AfterDeathSounds[][] = 
{
	"player/vo/separatist/chickenhate01.wav", 
	"player/vo/separatist/chickenhate02.wav", 
	"player/vo/separatist/chickenhate03.wav", 
	"player/vo/separatist/chickenhate04.wav"
};

char g_LaserSounds[][] = 
{
	"buttons/arena_switch_press_02.wav", 
	"buttons/light_power_on_switch_01.wav"
};

int m_vecOriginOffset;
int m_angRotationOffset;

int g_TreeEntityReference = INVALID_ENT_REFERENCE;

enum struct ChickenBoss
{
	int entity_reference;
	
	// [ Health properties ]
	float health;
	
	// [ Fade rendering properties ]
	
	// Fade render RGB color.
	int fade_color[3];
	
	// Fade render cycle speed. 1 is default.
	// Setting this property to 0 will stop the fade cycle.
	int fade_cycle_speed;
	
	// Whether the death phase is currently activated.
	bool is_death_phase_active;
	
	// Userid of the client who dealt the final hit.
	int final_hit_userid;
	
	// True if the phase has been already passed.
	bool phase_passed[PHASES_COUNT];
	
	// Whether to stop overriding sequences.
	bool stop_overriding_sequences;
	
	ArrayList pending_to_explosion;
	
	//=======================================//
	
	void Init()
	{
		this.entity_reference = INVALID_ENT_REFERENCE;
		this.fade_color = { 255, 0, 0 };
		this.fade_cycle_speed = 1;
		this.is_death_phase_active = false;
		this.final_hit_userid = 0;
		
		for (int current_index; current_index < sizeof(this.phase_passed); current_index++)
		{
			this.phase_passed[current_index] = false;
		}
		
		this.stop_overriding_sequences = false;
	}
	
	int Spawn(float origin[3])
	{
		this.RemoveTree();
		
		int entity = CreateEntityByName("chicken");
		if (entity == -1)
		{
			return -1;
		}
		
		this.health = BOSS_HEALTH;
		
		// Glow the chicken!
		DispatchKeyValue(entity, "glowenabled", "1");
		DispatchKeyValue(entity, "glowdist", "999999");
		DispatchKeyValue(entity, "glowstyle", "0");
		
		DispatchSpawn(entity);
		TeleportEntity(entity, origin);
		
		// Represents the scaler of the model size
		float scale = chicken_boss_scale.FloatValue;
		
		// HITBOX FIX: Update the entity's mins and maxs to the correct ones
		float entity_mins[3], entity_maxs[3];
		GetEntPropVector(entity, Prop_Send, "m_vecMins", entity_mins);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", entity_maxs);
		
		ScaleVector(entity_mins, scale);
		ScaleVector(entity_maxs, scale);
		
		SetEntPropVector(entity, Prop_Send, "m_vecMins", entity_mins);
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", entity_maxs);
		
		// Scale up the model size of the entity.
		SetEntPropFloat(entity, Prop_Data, "m_flModelScale", scale);
		
		SetVariantFloat(this.health);
		AcceptEntityInput(entity, "SetHealth");
		
		SetEntityCollisionGroup(entity, 11);
		EntityCollisionRulesChanged(entity);
		
		// Might be used later
		// SetEntPropFloat(entity, Prop_Data, "m_explodeDamage", 100.0);
		// SetEntPropFloat(entity, Prop_Data, "m_explodeRadius", 1500.0);
		
		// Perform the required sdkhooks.
		SDKHook(entity, SDKHook_Use, Hook_OnBossUse);
		SDKHook(entity, SDKHook_OnTakeDamage, Hook_OnBossTakeDamage);
		SDKHook(entity, SDKHook_Think, Hook_OnBossThink);
		
		Frame_FadeEntity((this.entity_reference = EntIndexToEntRef(entity)));
		
		sv_infinite_ammo.IntValue = 2;
		
		return entity;
	}
	
	void RemoveEntity()
	{
		this.SpawnTree();
		
		float origin[3], angles[3];
		GetEntDataVector(this.entity_reference, m_vecOriginOffset, origin);
		
		for (int current_gift, gift_ent; current_gift < GIFT_COUNT; current_gift++)
		{
			angles[0] = GetRandomFloatEx(-75.0, 0.0);
			angles[1] = GetRandomFloatEx(-180.0, 180.0);
			
			if ((gift_ent = ThrowGift(origin, angles)) != -1)
			{
				// DispatchKeyValue(gift_ent, "OnUser1", "!self,Kill,,1.0,-1");
				// AcceptEntityInput(gift_ent, "FireUser1");
				
				GlowEntity(gift_ent);
				CreateTimer(3.5, Timer_ReglowEntity, EntIndexToEntRef(gift_ent), .flags = TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		
		sv_infinite_ammo.IntValue = 0;
		
		delete this.pending_to_explosion;
		
		int entity = EntRefToEntIndex(this.entity_reference);
		if (entity != -1)
		{
			RemoveEntity(entity);
		}
		
		this.EmitRandomSound(g_DeathSounds, sizeof(g_DeathSounds));
		
		CreateTimer(3.0, Timer_AfterDeathSoundEffect, .flags = TIMER_FLAG_NO_MAPCHANGE);
		
		this.PrintLeaderboard();
		
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				if (IsPlayerAlive(current_client))
				{
					SetPlayerShootAbility(current_client, true);
					
					PerformScreenShake(current_client, 100.0);
				}
				else
				{
					CS_RespawnPlayer(current_client);
					
					// TeleportEntity(current_client, { 7916.043457, 7567.659668, -91.906189 }, { 0.117253, 0.134460, 0.000000 } );
				}
				
				SDKUnhook(current_client, SDKHook_OnTakeDamage, Hook_OnClientTakeDamage);
				
				if (g_Players[current_client].damage_dealt)
				{
					// FIX: GIVE MONEY
					// RP_GiveClientCash(current_client, BANK_CASH, RoundFloat(g_Players[current_client].damage_dealt / 4));
				}
				
				g_Players[current_client].Close();
				
				g_Players[current_client].allowed_to_evacuate = true;
				
				PrintToChat(current_client, "Type \x10/%s\x01 to leave the area. You will be evacuated automatically in \x04%ds\x01", EVACUATE_COMMAND, AUTO_EVACUATE_TIME);
				
				CreateTimer(float(AUTO_EVACUATE_TIME), Timer_AutoEvacuate, GetClientUserId(current_client), TIMER_FLAG_NO_MAPCHANGE);
				
				SetPlayerGodMode(current_client, true);
				
				SetEntityHealth(current_client, 100);
			}
		}
		
		// Reset base properties.
		this.Init();
	}
	
	char[] GetName()
	{
		char name[MAX_NAME_LENGTH] = " \x10["...CHICKEN_BOSS_NAME..."]\x01 ";
		return name;
	}
	
	bool IsSpawned()
	{
		return this.entity_reference != INVALID_ENT_REFERENCE;
	}
	
	void ActivateDeathPhase()
	{
		this.is_death_phase_active = true;
		
		this.ActiveThunderStorm();
		
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client) && IsPlayerAlive(current_client))
			{
				SetPlayerShootAbility(current_client, false);
			}
		}
		
		this.EmitRandomSound(g_DeathPhaseEntrySounds, sizeof(g_DeathPhaseEntrySounds));
		
		CreateTimer(2.0, Timer_PrintDeathResponse, .flags = TIMER_FLAG_NO_MAPCHANGE);
	}
	
	void ActiveThunderStorm()
	{
		// This is a repeated timer that will constantly change the map area weather and time.
		// The timer will automatically be closed once the chicken boss entity is removed from the world.
		// CreateTimer(DEATH_PHASE_THUNDERSTORM_FREQ, Timer_ThunderStorm, .flags = TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	
	void EmitRandomSound(char[][] buffer, int size)
	{
		int rnd_index = GetURandomInt() % size;
		
		EmitSoundToAll(buffer[rnd_index]);
		EmitSoundToAll(buffer[rnd_index]);
		EmitSoundToAll(buffer[rnd_index]);
	}
	
	void PrintLeaderboard()
	{
		ArrayList participants = new ArrayList();
		
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				participants.Push(current_client);
			}
		}
		
		// Sort the players by the amount of damage each player dealt.
		participants.SortCustom(SortPlayers_DamageDealt);
		
		//===============================//
		
		// Message opener.
		PrintToChatAll(" \x04========================================================\x01");
		PrintToChatAll(" \x10‎‎ ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎ ‎‎ ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎ ‎‎ ‎  ‎  ‎  ‎‎  ‎  ‎    ‎  ‎  ‎  ‎  ‎  ‎  ‎   ‎  ‎ ‎  ‎‎  ‎ ‎  ‎‎%s DOWN!\x01", CHICKEN_BOSS_NAME);
		PrintToChatAll(" ");
		
		// Print the client name who dealt the final hit.
		char client_name[MAX_NAME_LENGTH] = "NULL";
		
		int client = GetClientOfUserId(this.final_hit_userid);
		if (client)
		{
			GetClientName(client, client_name, sizeof(client_name));
		}
		
		PrintToChatAll(" ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎   ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  \x10%s\x01 \x0Adealt the final hit.\x01", client_name);
		
		// Print the top three damagers.
		PrintToChatAll(" ");
		
		if (participants.Length)
		{
			GetClientName((client = participants.Get(0)), client_name, sizeof(client_name));
		}
		else
		{
			client_name = "NULL";
		}
		
		PrintToChatAll(" ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎    ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎   \x091st Damager \x0A-\x01 \x06%s\x01 \x0A-\x01 \x09%s\x01", 
			client_name, StrEqual(client_name, "NULL") ? "0" : AddCommas(RoundFloat(g_Players[client].damage_dealt)));
		
		if (participants.Length > 1)
		{
			GetClientName((client = participants.Get(1)), client_name, sizeof(client_name));
		}
		else
		{
			client_name = "NULL";
		}
		
		PrintToChatAll(" ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎    ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎   \x102nd Damager \x0A-\x01 \x06%s\x01 \x0A-\x01 \x09%s\x01", 
			client_name, StrEqual(client_name, "NULL") ? "0" : AddCommas(RoundFloat(g_Players[client].damage_dealt)));
		
		if (participants.Length > 2)
		{
			GetClientName((client = participants.Get(2)), client_name, sizeof(client_name));
		}
		else
		{
			client_name = "NULL";
		}
		
		PrintToChatAll(" ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎    ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎   \x073rd Damager \x0A-\x01 \x06%s\x01 \x0A-\x01 \x09%s\x01", 
			client_name, StrEqual(client_name, "NULL") ? "0" : AddCommas(RoundFloat(g_Players[client].damage_dealt)));
		
		// Print each player their personal damage.
		PrintToChatAll(" ");
		
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				PrintToChat(current_client, " ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎    ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎  ‎   \x09Your Damage: \x04%s\x01 \x08(Position: #%d)\x01", 
					AddCommas(RoundFloat(g_Players[current_client].damage_dealt)), 
					participants.FindValue(current_client) + 1
					);
			}
		}
		
		PrintToChatAll(" \x04========================================================\x01");
		
		//===============================//
		
		// Don't leak memory!
		delete participants;
	}
	
	// Called whenever a new boss phase attack should begin.
	void OnPhaseChange()
	{
		// Find a valid phase attack index.
		ArrayList valid_phase_indexes = new ArrayList();
		
		for (int current_index; current_index < PHASES_COUNT; current_index++)
		{
			if (!this.phase_passed[current_index])
			{
				valid_phase_indexes.Push(current_index);
			}
		}
		
		int phase_index = valid_phase_indexes.Get(GetURandomInt() % valid_phase_indexes.Length);
		
		delete valid_phase_indexes;
		
		this.phase_passed[phase_index] = true;
		
		switch (phase_index)
		{
			// Wind phase.
			case 0:
			{
				this.fade_color = { 0, 0, 255 };
				this.fade_cycle_speed = 0;
				
				CreateTimer(3.0, Timer_WindPhase, .flags = TIMER_FLAG_NO_MAPCHANGE);
			}
			// Explosion phase.
			case 1:
			{
				SetEntProp(this.entity_reference, Prop_Data, "m_nGlowStyle", 1);
				
				CreateTimer(3.0, Timer_BeginExplosionAttack, .flags = TIMER_FLAG_NO_MAPCHANGE);
			}
			// Grenades phase.
			case 2:
			{
				for (int current_grenade; current_grenade < 50; current_grenade++)
				{
					if (0 <= current_grenade <= 10)
					{
						CreateGrenade("flashbang_projectile");
					}
					else
					{
						CreateGrenade();
					}
				}
			}
		}
	}
	
	// Returns the chicken boss eye position.
	void GetEyePosition(float eye_position[3])
	{
		#define UP_DETERMINER -17.6
		#define FWD_DETERMINER 6.8
		
		int entity = EntRefToEntIndex(this.entity_reference);
		if (entity == -1)
		{
			return;
		}
		
		float boss_origin[3], boss_angles[3];
		GetEntDataVector(entity, m_vecOriginOffset, boss_origin);
		GetEntDataVector(entity, m_angRotationOffset, boss_angles);
		
		boss_angles[1] -= 180.0;
		
		float fwd[3], up[3], sum[3];
		GetAngleVectors(boss_angles, fwd, NULL_VECTOR, up);
		
		ScaleVector(up, UP_DETERMINER * chicken_boss_scale.FloatValue);
		ScaleVector(fwd, FWD_DETERMINER * chicken_boss_scale.FloatValue);
		
		AddVectors(fwd, up, sum);
		SubtractVectors(boss_origin, sum, eye_position);
	}
	
	// Restricts the chickene entity to stay still on the world ground.
	void ValidateOrigin()
	{
		int entity = EntRefToEntIndex(this.entity_reference);
		if (entity == -1)
		{
			return;
		}
		
		float boss_origin[3];
		GetEntDataVector(entity, m_vecOriginOffset, boss_origin);
		
		TR_TraceRayFilter(boss_origin, { 90.0, 0.0, 0.0 }, MASK_ALL, RayType_Infinite, Filter_WorldOnly);
		
		if (TR_DidHit())
		{
			TR_GetEndPosition(boss_origin);
			TeleportEntity(entity, boss_origin);
		}
	}
	
	int SpawnTree()
	{
		int boss_entity = EntRefToEntIndex(this.entity_reference);
		if (boss_entity == -1)
		{
			return -1;
		}
		
		// tree!
		int prop_dynamic_override = CreateEntityByName("prop_dynamic_override");
		if (prop_dynamic_override == -1)
		{
			return -1;
		}
		
		DispatchKeyValue(prop_dynamic_override, "model", TREE_MODEL);
		// DispatchKeyValue(prop_dynamic_override, "solid", "6"); // makes entity solid
		
		float boss_origin[3];
		GetEntDataVector(boss_entity, m_vecOriginOffset, boss_origin);
		
		DispatchKeyValueVector(prop_dynamic_override, "origin", boss_origin);
		
		DispatchKeyValue(prop_dynamic_override, "glowenabled", "1");
		DispatchKeyValue(prop_dynamic_override, "glowdist", "999999");
		DispatchKeyValue(prop_dynamic_override, "glowstyle", "1");
		
		char color[16];
		Format(color, sizeof(color), "%d %d %d", 255, 0, 0);
		DispatchKeyValue(prop_dynamic_override, "glowcolor", color);
		
		if (!DispatchSpawn(prop_dynamic_override))
		{
			return -1;
		}
		
		DispatchKeyValue(prop_dynamic_override, "rendermode", "4"); // SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
		DispatchKeyValue(prop_dynamic_override, "renderamt", "0");
		
		g_TreeEntityReference = EntIndexToEntRef(prop_dynamic_override);
		
		Frame_FadeEntityAlpha(g_TreeEntityReference);
		Frame_FadeEntity(g_TreeEntityReference);
		
		return prop_dynamic_override;
	}
	
	void RemoveTree()
	{
		int entity = EntRefToEntIndex(g_TreeEntityReference);
		if (entity != -1)
		{
			RemoveEntity(entity);
		}
	}
}

ChickenBoss g_ChickenBoss;

// Chicken chat messages.
char g_OwnershipResponses[][] = 
{
	"You think you can trick me that easily??", 
	"You will never be my owner!", 
	"Don't you dare...", 
	"A friend...? of yours?", 
	"Don't make me laugh, please...", 
	"You're too weak to be my ally."
};

char g_DeathResponses[][] = 
{
	"Is this.. my limit…?", 
	"I had no choice... I had to do it... I just see the opportunity. When I'm gone, everyone gonna remember my name... "...CHICKEN_BOSS_NAME..."!", 
	"I say… bit of bad luck", 
	"No, no, no... I can't die like this... Not when I'm so close...", 
	"I...am...Deathwing. The Destroyer, the end of all things. Inevitable, indomitable. I...AM... "...CHICKEN_BOSS_NAME..."!", 
	"God, I hate how this has to end.", 
	"My death will shine light upon ubiquitous darkness."
};

char g_KillResponses[][] = 
{
	"I guess \x03{name}\x02 was too weak to survive me.", 
	"I will destroy you all, as I did to \x03{name}\x01.", 
	"Better luck next time, \x03{name}\x01.", 
	"You thought you had a chance \x03{name}\x02???"
};

int g_FireSpriteIndex;
int g_LaserBeam;

int m_nSequenceOffset;

public Plugin myinfo = 
{
	name = "[RolePlay] Chicken Boss", 
	author = "KoNLiG", 
	description = "A chicken boss!", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Convars Configuration.
	if (!(sv_infinite_ammo = FindConVar("sv_infinite_ammo")))
	{
		SetFailState("Failed to find convar 'sv_infinite_ammo'");
	}
	
	if ((m_nSequenceOffset = FindSendPropInfo("CChicken", "m_nSequence")) <= 0)
	{
		SetFailState("Failed to find 'CChicken::m_nSequence' offset");
	}
	
	if ((m_vecOriginOffset = FindSendPropInfo("CBaseEntity", "m_vecOrigin")) <= 0)
	{
		SetFailState("Failed to find 'CBaseEntity::m_vecOrigin' offset");
	}
	
	if ((m_angRotationOffset = FindSendPropInfo("CBaseEntity", "m_angRotation")) <= 0)
	{
		SetFailState("Failed to find 'CBaseEntity::m_angRotation' offset");
	}
	
	chicken_boss_scale = CreateConVar("chicken_boss_scale", "25.0", "A scaler deteminer for the chicken size.");
	
	// Register cmds.
	RegAdminCmd("sm_chickenboss", Command_ChickenBoss, ADMFLAG_ROOT, "Spawns a chicken boss at the user location.");
	RegAdminCmd("sm_tpchickenboss", Command_TpChickenBoss, ADMFLAG_ROOT, "Spawns a chicken boss at the user location.");
	
	RegConsoleCmd("sm_"...EVACUATE_COMMAND, Command_Evecuate, "Evacuates from the chicken boss area.");
	
	HookEvent("player_death", Event_PlayerDeath);
	
	g_ChickenBoss.Init();
}

public void OnPluginEnd()
{
	int entity = EntRefToEntIndex(g_ChickenBoss.entity_reference);
	if (entity != -1)
	{
		RemoveEntity(entity);
	}
	
	g_ChickenBoss.RemoveTree();
}

//================================[ Forwards ]================================//

// Server events.
public void OnMapStart()
{
	// Precache all sound effect...
	PrecacheSoundBuffer(g_DeathPhaseEntrySounds, sizeof(g_DeathPhaseEntrySounds));
	PrecacheSoundBuffer(g_DeathSounds, sizeof(g_DeathSounds));
	PrecacheSoundBuffer(g_AfterDeathSounds, sizeof(g_AfterDeathSounds));
	PrecacheSoundBuffer(g_LaserSounds, sizeof(g_LaserSounds));
	
	PrecacheSound(WIND_PHASE_SOUND);
	PrecacheSound(MISSILE_EXPLODE_SOUND);
	
	PrecacheModel(TREE_MODEL);
	
	g_LaserBeam = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_FireSpriteIndex = PrecacheModel("sprites/sprite_fire01.vmt");
	
	// Pickable gift model.
	AddDirectoryToDownloadsTable("models/items");
	AddDirectoryToDownloadsTable("materials/models/items");
	
	PrecacheModel(GIFT_MODEL);
}

// If passes all checks, the chicken boss entity is removed from the world.
// Perform the necessary actions. 
public void OnEntityDestroyed(int entity)
{
	if (entity <= 0 || !g_ChickenBoss.IsSpawned())
	{
		return;
	}
	
	int chicken_boss_entity = EntRefToEntIndex(g_ChickenBoss.entity_reference);
	if (chicken_boss_entity == -1 || chicken_boss_entity != entity)
	{
		return;
	}
	
	g_ChickenBoss.RemoveEntity();
}

// Triggered whenever a client is trying to take "ownership" on the chicken boss.
// The chicken will give a salty response once in a while.
Action Hook_OnBossUse(int entity, int activator, int caller, UseType type, float value)
{
	float game_time = GetGameTime();
	if (g_Players[activator].next_ownership_response_time > game_time)
	{
		return Plugin_Stop;
	}
	
	PrintToChat(activator, "%s\x02%s\x01", g_ChickenBoss.GetName(), g_OwnershipResponses[GetURandomInt() % sizeof(g_OwnershipResponses)]);
	
	g_Players[activator].next_ownership_response_time = game_time + OWNERSHIP_RESPONSE_COOLDOWN;
	
	return Plugin_Stop;
}

// Triggered whenever the chicken boss is damaged by any player.
// Performs most of the boss machanic.
Action Hook_OnBossTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	// Block self damage.
	if (!(1 <= attacker <= MaxClients))
	{
		return Plugin_Handled;
	}
	
	if (g_ChickenBoss.health - damage <= 1.0)
	{
		if (!g_ChickenBoss.is_death_phase_active)
		{
			g_ChickenBoss.ActivateDeathPhase();
			
			g_ChickenBoss.final_hit_userid = GetClientUserId(attacker);
			
			g_Players[attacker].damage_dealt += g_ChickenBoss.health;
			
			g_ChickenBoss.health = 0.0;
			
			for (int current_client = 1; current_client <= MaxClients; current_client++)
			{
				if (IsClientInGame(current_client))
				{
					DisplayChickenState(current_client);
				}
			}
		}
		
		return Plugin_Handled;
	}
	
	// Detect phase changes.
	if (g_ChickenBoss.health != BOSS_HEALTH
		 && RoundToFloor(g_ChickenBoss.health / DMG_PER_PHASE) > RoundToFloor((g_ChickenBoss.health - damage) / DMG_PER_PHASE))
	{
		g_ChickenBoss.OnPhaseChange();
	}
	
	g_ChickenBoss.health -= damage;
	g_Players[attacker].damage_dealt += damage;
	
	DisplayChickenState(attacker);
	
	return Plugin_Continue;
}

void DisplayChickenState(int client)
{
	PrintCenterText(client, "<font color='#000000'>[</font>%s<font color='#000000'>]</font><br><br><font color='#AA00AA'>‎ ‎ ‎ ‎ ‎ ‎ ‎Your Damage: %.1f (%d$)", GetProgressBar(g_ChickenBoss.health, BOSS_HEALTH), g_Players[client].damage_dealt, RoundFloat(g_Players[client].damage_dealt / 4));
}

// Triggered whenever the chicken (boss) entity is thinking.
// Used to manipulate the entity sequences.
// 
// [0] ref
// [1] walk01
// [2] run01
// [3] bunnyhop		(Reserved for wind phase)
// [4] run01Flap
// [5] idle01
// [6] peck_idle2
// [7] flap
// [8] flap_falling	(Reserved for explosion phase)
// [9] bounce
Action Hook_OnBossThink(int entity)
{
	if (g_ChickenBoss.is_death_phase_active)
	{
		if (GetEntitySequence(entity) != DEATH_PHASE_SEQUENCE)
		{
			SetEntitySequence(entity, DEATH_PHASE_SEQUENCE);
		}
		
		return Plugin_Continue;
	}
	
	if (!g_ChickenBoss.stop_overriding_sequences)
	{
		SetEntitySequence(entity, 5);
	}
	
	// g_ChickenBoss.ValidateOrigin();
	
	return Plugin_Continue;
}

// Client events.
public void OnClientDisconnect(int client)
{
	g_Players[client].Close();
}

public Action CS_OnCSWeaponDrop(int client, int weaponIndex, bool donated)
{
	return g_ChickenBoss.is_death_phase_active ? Plugin_Stop : Plugin_Continue;
}

// Triggered whenever a client is picking up a gift.
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
	GetEntDataVector(entity, m_vecOriginOffset, origin);
	DispatchConfettiEffect(origin);
	
	// Erase the entity from the world.
	RemoveEntity(entity);
	
	bool rare_drop;
	
	char reward[32];
	RewardClient(client, reward, sizeof(reward), rare_drop);
	
	PrintToChat(client, "You obtained %s from a \x04g\x0Ci\x10f\x07t\x01!", reward);
	
	if (rare_drop)
	{
		PrintToChatAll(" \x0ECRAZY RARE DROP!\x01 \x04%N\x01 obtained %s from a \x04g\x0Ci\x10f\x07t\x01!", client, reward);
	}
	
	return Plugin_Continue;
}

Action Hook_OnClientTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	return (1 <= attacker <= MaxClients) ? Plugin_Handled : Plugin_Continue;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!victim)
	{
		return;
	}
	
	g_Players[victim].allowed_to_evacuate = false;
	
	if (g_ChickenBoss.IsSpawned())
	{
		char msg[256];
		Format(msg, sizeof(msg), g_KillResponses[GetURandomInt() % sizeof(g_KillResponses)]);
		
		char victim_name[MAX_NAME_LENGTH];
		GetClientName(victim, victim_name, sizeof(victim_name));
		
		ReplaceString(msg, sizeof(msg), "{name}", victim_name);
		
		PrintToChatAll("%s\x02%s\x01", g_ChickenBoss.GetName(), msg);
	}
}

//================================[ Command Callbacks ]================================//

Action Command_ChickenBoss(int client, int argc)
{
	// Deny the command access from the server console.
	if (!client)
	{
		ReplyToCommand(client, "%s This command cannot be used from the server console.", PREFIX_MENU);
		return Plugin_Handled;
	}
	
	if (g_ChickenBoss.IsSpawned())
	{
		PrintToChat(client, "%s A chicken boss is already spawned.", PREFIX);
		return Plugin_Handled;
	}
	
	float origin[3];
	GetClientAbsOrigin(client, origin);
	
	int chicken_entity = g_ChickenBoss.Spawn(origin);
	if (chicken_entity == -1)
	{
		PrintToChat(client, "%s An error has occured while trying to spawn a chicken boss.", PREFIX);
		return Plugin_Handled;
	}
	
	for (int current_client = 1, ent; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			SDKHook(current_client, SDKHook_OnTakeDamage, Hook_OnClientTakeDamage);
			
			SetEntityHealth(current_client, CLIENTS_HEALTH);
			
			g_Players[current_client].allowed_to_evacuate = false;
			
			SetPlayerGodMode(current_client, false);
			
			if ((ent = GetPlayerWeaponSlot(current_client, CS_SLOT_PRIMARY)) != -1)
			{
				RemovePlayerItem(current_client, ent);
				RemoveEntity(ent);
			}
			
			GivePlayerItem(current_client, "weapon_negev");
		}
	}
	
	return Plugin_Handled;
}

Action Command_TpChickenBoss(int client, int argc)
{
	int entity = EntRefToEntIndex(g_ChickenBoss.entity_reference);
	if (entity == -1)
	{
		return Plugin_Handled;
	}
	
	float origin[3];
	GetClientAbsOrigin(client, origin);
	
	TeleportEntity(entity, origin);
	
	return Plugin_Handled;
}

Action Command_Evecuate(int client, int argc)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!g_Players[client].allowed_to_evacuate)
	{
		PrintToChat(client, " \x02You are not allowed to evacuate!\x01");
		return Plugin_Handled;
	}
	
	// TeleportEntity(client, { -2044.297729, -3319.993408, -79.906189 }, { 2.155786, 90.591316, 0.000000 } );
	CS_RespawnPlayer(client);
	
	SetPlayerGodMode(client, false);
	
	g_Players[client].allowed_to_evacuate = false;
	
	return Plugin_Handled;
}

//================================[ Timers ]================================//

Action Timer_AutoEvacuate(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !g_Players[client].allowed_to_evacuate)
	{
		return Plugin_Continue;
	}
	
	Command_Evecuate(client, 0);
	
	return Plugin_Continue;
}

Action Timer_BeginExplosionAttack(Handle timer)
{
	if (!g_ChickenBoss.IsSpawned() || g_ChickenBoss.is_death_phase_active)
	{
		return Plugin_Stop;
	}
	
	g_ChickenBoss.pending_to_explosion = new ArrayList();
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client))
		{
			g_ChickenBoss.pending_to_explosion.Push(GetClientUserId(current_client));
		}
	}
	
	CreateTimer(0.1, Timer_ExplodePlayer, .flags = TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Continue;
}

Action Timer_ExplodePlayer(Handle timer)
{
	// Phase has been skipped.
	if (!g_ChickenBoss.IsSpawned() || g_ChickenBoss.is_death_phase_active || !g_ChickenBoss.pending_to_explosion || !g_ChickenBoss.pending_to_explosion.Length)
	{
		if (g_ChickenBoss.IsSpawned())
		{
			SetEntProp(g_ChickenBoss.entity_reference, Prop_Data, "m_nGlowStyle", 0);
		}
		
		delete g_ChickenBoss.pending_to_explosion;
		
		return Plugin_Stop;
	}
	
	int entity = EntRefToEntIndex(g_ChickenBoss.entity_reference);
	if (entity == -1)
	{
		delete g_ChickenBoss.pending_to_explosion;
		
		return Plugin_Stop;
	}
	
	float boss_eye_origin[3];
	g_ChickenBoss.GetEyePosition(boss_eye_origin);
	
	int rnd_index = GetURandomInt() % g_ChickenBoss.pending_to_explosion.Length;
	
	int client = GetClientOfUserId(g_ChickenBoss.pending_to_explosion.Get(rnd_index));
	if (client)
	{
		float client_origin[3];
		GetClientEyePosition(client, client_origin);
		
		TR_TraceRayFilter(boss_eye_origin, client_origin, MASK_ALL, RayType_EndPoint, Filter_WorldOnly);
		
		// Make sure the client is not hiding behind a wall.
		if (!TR_DidHit())
		{
			for (int i; i < 4; i++)
			{
				TE_SetupBeamPoints(boss_eye_origin, client_origin, g_LaserBeam, 0, 0, 0, 1.0, 2.0, 1.0, 10, !i ? 0.0 : GetRandomFloatEx(2.0, 10.0), { 255, 0, 0, 255 }, 0);
				TE_SendToAll();
			}
			
			CS_CreateExplosion(client, entity, 225.0, 125.0, client_origin);
		}
	}
	
	g_ChickenBoss.pending_to_explosion.Erase(rnd_index);
	
	return Plugin_Continue;
}

Action Timer_WindPhase(Handle timer)
{
	// Phase has been skipped.
	if (!g_ChickenBoss.IsSpawned() || g_ChickenBoss.is_death_phase_active)
	{
		return Plugin_Continue;
	}
	
	g_ChickenBoss.fade_cycle_speed = 1;
	
	g_ChickenBoss.stop_overriding_sequences = true;
	
	SetEntitySequence(g_ChickenBoss.entity_reference, WIND_PHASE_SEQUENCE);
	
	CreateTimer(WIND_PHASE_SEQUENCE_DURATION, Timer_FinishWindPhase, .flags = TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Continue;
}

Action Timer_FinishWindPhase(Handle timer)
{
	// Phase has been skipped.
	if (!g_ChickenBoss.IsSpawned() || g_ChickenBoss.is_death_phase_active)
	{
		return Plugin_Continue;
	}
	
	int entity = EntRefToEntIndex(g_ChickenBoss.entity_reference);
	if (entity == -1)
	{
		return Plugin_Continue;
	}
	
	// Declare vectors.
	float boss_origin[3], client_origin[3], angles[3], fwd[3], up[3], velocity[3];
	GetEntDataVector(entity, m_vecOriginOffset, boss_origin);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			GetClientEyePosition(current_client, client_origin);
			
			TR_TraceRayFilter(boss_origin, client_origin, MASK_ALL, RayType_EndPoint, Filter_WorldOnly);
			
			// The client is hiding behind a wall.
			if (TR_DidHit())
			{
				continue;
			}
			
			MakeVectorFromPoints(boss_origin, client_origin, angles);
			GetVectorAngles(angles, angles);
			
			angles[0] = 0.0;
			
			GetAngleVectors(angles, fwd, NULL_VECTOR, up);
			
			ScaleVector(fwd, 1500.0);
			ScaleVector(up, 500.0);
			
			AddVectors(fwd, up, velocity);
			
			TeleportEntity(current_client, .velocity = velocity);
			PerformScreenShake(current_client, 100.0);
		}
	}
	
	EmitAmbientSound(WIND_PHASE_SOUND, boss_origin);
	EmitAmbientSound(WIND_PHASE_SOUND, boss_origin);
	EmitAmbientSound(WIND_PHASE_SOUND, boss_origin);
	
	g_ChickenBoss.stop_overriding_sequences = false;
	
	return Plugin_Continue;
}

Action Timer_PrintDeathResponse(Handle timer)
{
	PrintToChatAll("%s\x02%s\x01", g_ChickenBoss.GetName(), g_DeathResponses[GetURandomInt() % sizeof(g_DeathResponses)]);
	
	CreateTimer(DEATH_PHASE_LASERS_INTERVAL, Timer_LasersEffect, .flags = TIMER_FLAG_NO_MAPCHANGE);
	
	SetEntProp(g_ChickenBoss.entity_reference, Prop_Data, "m_nGlowStyle", 1);
	
	DispatchKeyValue(g_ChickenBoss.entity_reference, "OnUser1", "!self,Kill,,4.0,-1");
	AcceptEntityInput(g_ChickenBoss.entity_reference, "FireUser1");
	
	return Plugin_Continue;
}

Action Timer_AfterDeathSoundEffect(Handle timer)
{
	g_ChickenBoss.EmitRandomSound(g_AfterDeathSounds, sizeof(g_AfterDeathSounds));
	
	return Plugin_Continue;
}

Action Timer_LasersEffect(Handle timer)
{
	static int snd_pitch = SNDPITCH_LOW;
	static float next_time = DEATH_PHASE_LASERS_INTERVAL;
	
	// Chicken boss entity has been removed. Stop the timer.
	if (!g_ChickenBoss.IsSpawned())
	{
		snd_pitch = SNDPITCH_LOW;
		next_time = DEATH_PHASE_LASERS_INTERVAL;
		
		return Plugin_Stop;
	}
	
	int entity = EntRefToEntIndex(g_ChickenBoss.entity_reference);
	if (entity == -1)
	{
		snd_pitch = SNDPITCH_LOW;
		next_time = DEATH_PHASE_LASERS_INTERVAL;
		
		return Plugin_Stop;
	}
	
	float origin[3], end_origin[3], angles[3];
	GetEntDataVector(entity, m_vecOriginOffset, origin);
	
	int color[4];
	
	for (int current_laser; current_laser < DEATH_PHASE_LASERS_COUNT; current_laser++)
	{
		angles[0] = GetRandomFloatEx(-90.0, 0.0);
		angles[1] = GetRandomFloatEx(-180.0, 180.0);
		
		TR_TraceRayFilter(origin, angles, MASK_ALL, RayType_Infinite, Filter_WorldOnly);
		TR_GetEndPosition(end_origin);
		
		color[0] = GetURandomInt() % 255;
		color[1] = GetURandomInt() % 255;
		color[2] = GetURandomInt() % 255;
		color[3] = 255;
		
		TE_SetupBeamPoints(origin, end_origin, g_LaserBeam, 0, 0, 0, 0.1, 2.0, 2.0, 10, (GetURandomInt() % 2) ? GetRandomFloatEx(0.0, 10.0) : 0.0, color, 0);
		TE_SendToAll();
	}
	
	snd_pitch += 3;
	EmitSoundToAll(g_LaserSounds[GetURandomInt() % sizeof(g_LaserSounds)], .pitch = snd_pitch);
	
	if (next_time > 0.1)
	{
		next_time -= 0.07;
	}
	
	g_ChickenBoss.fade_cycle_speed = 20 - RoundToFloor(next_time * 20);
	CreateTimer(next_time, Timer_LasersEffect, .flags = TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Continue;
}

bool Filter_WorldOnly(int entity, int contentsMask, any data)
{
	return entity == 0;
}

Action Timer_ReglowEntity(Handle timer, int entity_reference)
{
	int entity = EntRefToEntIndex(entity_reference);
	if (entity == -1)
	{
		return Plugin_Stop;
	}
	
	GlowEntity(entity);
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int SortPlayers_DamageDealt(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList arraylist = view_as<ArrayList>(array);
	
	Player player1; player1 = g_Players[arraylist.Get(index1)];
	Player player2; player2 = g_Players[arraylist.Get(index2)];
	
	return player1.damage_dealt > player2.damage_dealt ? -1 : player1.damage_dealt < player2.damage_dealt ? 1 : 0;
}

native void RP_GiveClientVehicle(int client, const char[] vehicle_identifier);

// bfffer will be the gift reward string
void RewardClient(int client, char[] buffer, int maxlength, bool &rare_drop)
{
	strcopy(buffer, maxlength, "nothing");
	
	client = client + 1 - 1;
	
	// rng prize check
	// 0.0009 = 0.09 / (0.09 / 100)
	float rng = GetURandomFloat();
	if (rng <= 0.0009)
	{
		
		
		rare_drop = true;
	}
}

void Frame_FadeEntityAlpha(int ent_ref)
{
	int entity = EntRefToEntIndex(ent_ref);
	if (entity == -1)
	{
		return;
	}
	
	int color[4];
	GetEntityRenderColor(entity, color[0], color[1], color[2], color[3]);
	
	int alpha = color[3];
	if (alpha >= 255)
	{
		return;
	}
	
	SetEntityRenderColor(entity, .a = alpha + 1);
	
	RequestFrame(Frame_FadeEntityAlpha, ent_ref);
}

void Frame_FadeEntity(int ent_ref)
{
	int entity = EntRefToEntIndex(ent_ref);
	if (entity == -1)
	{
		return;
	}
	
	if (g_ChickenBoss.fade_cycle_speed)
	{
		if (g_ChickenBoss.fade_color[0] > 0 && g_ChickenBoss.fade_color[2] <= 0)
		{
			g_ChickenBoss.fade_color[0] -= g_ChickenBoss.fade_cycle_speed;
			g_ChickenBoss.fade_color[1] += g_ChickenBoss.fade_cycle_speed;
		}
		
		if (g_ChickenBoss.fade_color[1] > 0 && g_ChickenBoss.fade_color[0] <= 0)
		{
			g_ChickenBoss.fade_color[1] -= g_ChickenBoss.fade_cycle_speed;
			g_ChickenBoss.fade_color[2] += g_ChickenBoss.fade_cycle_speed;
		}
		
		if (g_ChickenBoss.fade_color[2] > 0 && g_ChickenBoss.fade_color[1] <= 0)
		{
			g_ChickenBoss.fade_color[2] -= g_ChickenBoss.fade_cycle_speed;
			g_ChickenBoss.fade_color[0] += g_ChickenBoss.fade_cycle_speed;
		}
	}
	
	char color[16];
	Format(color, sizeof(color), "%d %d %d", g_ChickenBoss.fade_color[0], g_ChickenBoss.fade_color[1], g_ChickenBoss.fade_color[2]);
	DispatchKeyValue(entity, "glowcolor", color);
	
	RequestFrame(Frame_FadeEntity, ent_ref);
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
	
	SetEntPropFloat(entity, Prop_Send, "m_flCycle", GetGameTime() + 0.5);
	
	SetEntityCollisionGroup(entity, 11);
	EntityCollisionRulesChanged(entity);
	
	SDKHook(entity, SDKHook_StartTouch, Hook_OnStartTouch);
	
	return entity;
}

void SetPlayerShootAbility(int client, bool value)
{
	SetEntPropFloat(client, Prop_Send, "m_flNextAttack", value ? GetGameTime() : GetGameTime() + 999999.0);
}

stock int GetRandomIntEx(int min, int max)
{
	int random = GetURandomInt();
	if (!random)
	{
		random++;
	}
	
	return RoundToCeil(float(random) / (float(2147483647) / float(max - min + 1))) + min - 1;
}

float GetRandomFloatEx(float min, float max)
{
	return (GetURandomFloat() * (max - min)) + min;
}

void GlowEntity(int entity)
{
	Protobuf msg = view_as<Protobuf>(StartMessageAll("EntityOutlineHighlight"));
	
	msg.SetInt("entidx", entity); // Entity index to glow
	
	EndMessage();
}

void PerformScreenShake(int client, float amplitude = 1.0, float frequency = 255.0, float duration = 1.0)
{
	Handle message = StartMessageOne("Shake", client);
	
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("command", 0);
		pb.SetFloat("local_amplitude", amplitude);
		pb.SetFloat("frequency", frequency);
		pb.SetFloat("duration", duration);
	}
	else
	{
		PbSetInt(message, "command", 0);
		PbSetFloat(message, "local_amplitude", amplitude);
		PbSetFloat(message, "frequency", frequency);
		PbSetFloat(message, "duration", duration);
	}
	
	EndMessage();
}

void PrecacheSoundBuffer(char[][] buffer, int size)
{
	for (int current_sound; current_sound < size; current_sound++)
	{
		PrecacheSound(buffer[current_sound]);
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

int GetEntitySequence(int entity)
{
	return GetEntData(entity, m_nSequenceOffset);
}

void SetEntitySequence(int entity, int sequence)
{
	SetEntData(entity, m_nSequenceOffset, sequence);
}

char[] AddCommas(int value, const char[] seperator = ",")
{
	// Static regex insted of a global one.
	static Regex rgxCommasPostions = null;
	
	// Complie our regex only once.
	if (!rgxCommasPostions)
		rgxCommasPostions = CompileRegex("\\d{1,3}(?=(\\d{3})+(?!\\d))");
	
	// The buffer that will store the number so we can use the regex.
	char buffer[MAX_NAME_LENGTH];
	IntToString(value, buffer, MAX_NAME_LENGTH);
	
	// perform the regex.
	rgxCommasPostions.MatchAll(buffer);
	
	// Loop through all Offsets
	for (int iCurrentOffset = 0; iCurrentOffset < rgxCommasPostions.MatchCount(); iCurrentOffset++)
	{
		// Get the offset.
		int offset = rgxCommasPostions.MatchOffset(iCurrentOffset);
		
		offset += iCurrentOffset;
		
		// Insert seperator.
		Format(buffer[offset], sizeof(buffer) - offset, "%c%s", seperator, buffer[offset]);
	}
	
	// Return buffer
	return buffer;
}

void CS_CreateExplosion(int attacker, int weapon, float damage, float radius, float vec[3])
{
	TE_SetupExplosion(vec, g_FireSpriteIndex, 10.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	EmitSoundToAll(MISSILE_EXPLODE_SOUND, SOUND_FROM_LOCAL_PLAYER, .origin = vec);
	
	float current_pos[3], current_dis;
	
	for (int current_entity = 1, max_ents = GetMaxEntities(); current_entity < max_ents; current_entity++)
	{
		if (!IsValidEntity(current_entity) || !HasEntProp(current_entity, Prop_Send, "m_vecOrigin"))
		{
			continue;
		}
		
		GetEntDataVector(current_entity, m_vecOriginOffset, current_pos);
		current_dis = GetVectorDistance(vec, current_pos);
		
		if (current_dis <= radius)
		{
			float result = Sine(((radius - current_dis) / radius) * (FLOAT_PI / 2)) * damage;
			SDKHooks_TakeDamage(current_entity, attacker, attacker, result, DMG_BLAST, weapon, NULL_VECTOR, vec, .bypassHooks = true);
		}
	}
}

#define PROGRESS_BAR_LENGTH 20

char[] GetProgressBar(float value, float all)
{
	char progress_bar[256];
	int len = PROGRESS_BAR_LENGTH;
	
	Format(progress_bar, sizeof(progress_bar), "<font color='#0000B3'>");
	
	for (int i; i < (value / all * PROGRESS_BAR_LENGTH); i++)
	{
		len--;
		StrCat(progress_bar, sizeof(progress_bar), "⚫");
	}
	
	StrCat(progress_bar, sizeof(progress_bar), "<font color='#CC0000'>");
	
	for (int i; i < len; i++)
	{
		StrCat(progress_bar, sizeof(progress_bar), "⬛");
	}
	
	return progress_bar;
}

char g_GrenadeClassnames[][] = 
{
	"molotov_projectile", 
	"hegrenade_projectile"
};

void CreateGrenade(char classname[64] = "")
{
	int boss_entity = EntRefToEntIndex(g_ChickenBoss.entity_reference);
	if (boss_entity == -1)
	{
		return;
	}
	
	if (!classname[0])
	{
		strcopy(classname, sizeof(classname), g_GrenadeClassnames[GetURandomInt() % sizeof(g_GrenadeClassnames)]);
	}
	
	int entity = CreateEntityByName(classname);
	if (entity == -1)
	{
		return;
	}
	
	// Declare vectors.
	float boss_eye_origin[3], angles[3], fwd[3], up[3], velocity[3];
	g_ChickenBoss.GetEyePosition(boss_eye_origin);
	
	angles[0] = GetRandomFloatEx(0.0, 45.0);
	angles[1] = GetRandomFloatEx(-180.0, 180.0);
	
	GetAngleVectors(angles, fwd, NULL_VECTOR, up);
	
	ScaleVector(fwd, 1000.0);
	ScaleVector(up, -200.0);
	
	AddVectors(fwd, up, velocity);
	
	TeleportEntity(entity, boss_eye_origin, .velocity = velocity);
	
	DispatchSpawn(entity);
	DispatchKeyValue(entity, "globalname", "custom");
	
	AcceptEntityInput(entity, "InitializeSpawnFromWorld");
	AcceptEntityInput(entity, "FireUser1", boss_entity);
	
	SetEntProp(entity, Prop_Send, "m_iTeamNum", CS_TEAM_CT);
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", boss_entity);
	SetEntPropEnt(entity, Prop_Send, "m_hThrower", boss_entity);
}

void SetPlayerGodMode(int client, bool val)
{
	SetEntProp(client, Prop_Data, "m_takedamage", val ? 0 : 2, 1);
}

//================================================================//