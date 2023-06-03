#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>
#include <JB_GangsSystem>
#include <customweapons>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define RANDOM_GUARD_STRING "Random Guard"
#define ABORT_SYMBOL "-1"

#define DAY_NAME "Laser Day"
#define DAY_WEAPON "weapon_m4a1"
#define DAY_HEALTH 1250

#define ABILITY_COOLDOWN 10.0

#define ABILITY_BULLETS_COST 4

#define LASER_GUN_VIEW_MODEL "models/weapons/eminem/ethereal/v_ethereal.mdl"
#define LASER_GUN_WORLD_MODEL "models/weapons/eminem/ethereal/w_ethereal.mdl"
#define LASER_GUN_SHOOT_SOUND "weapons/eminem/ethereal/ethereal_shoot1.wav"

//====================//

enum struct Client
{
	float NextAbilityAttack;
	int OldButtons;
	
	void Reset() {
		this.NextAbilityAttack = 0.0;
		this.OldButtons = 0;
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

ConVar g_cvInfiniteAmmo;

bool g_IsDayActivated;

int g_DayIndex = -1;

int g_iShotSprite = -1;
int g_iBombSprite = -1;
int g_iExplosionSprite = -1;

int g_flSimulationTime;
int g_flProgressBarStartTime;
int g_iProgressBarDuration;
int g_iBlockingUseActionInProgress;

int m_hActiveWeaponOffset;

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
	// Initialize the required progress bar network offsets
	g_flSimulationTime = FindSendPropInfo("CBaseEntity", "m_flSimulationTime");
	g_flProgressBarStartTime = FindSendPropInfo("CCSPlayer", "m_flProgressBarStartTime");
	g_iProgressBarDuration = FindSendPropInfo("CCSPlayer", "m_iProgressBarDuration");
	g_iBlockingUseActionInProgress = FindSendPropInfo("CCSPlayer", "m_iBlockingUseActionInProgress");
	
	m_hActiveWeaponOffset = FindSendPropInfo("CCSPlayer", "m_hActiveWeapon");
	
	g_cvInfiniteAmmo = FindConVar("sv_infinite_ammo");
}

public void OnPluginEnd()
{
	// If the special day is running, and the plugin has come to his end, stop the special day
	if (g_IsDayActivated)
	{
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_DayIndex = JB_CreateSpecialDay(DAY_NAME, DAY_HEALTH, false, false, false);
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	// Make sure the given special day index, is the plugin's index
	if (g_DayIndex != specialDayId)
	{
		return;
	}
	
	g_ClientsData[client].Reset();
	ResetProgressBar(client);
	
	DisarmPlayer(client);
	SetEntityHealth(client, DAY_HEALTH);
	
	int weapon = GivePlayerItem(client, DAY_WEAPON);
	if (weapon != -1)
	{
		SetupCustomWeapon(weapon, true);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	// Make sure the given special day index, is the plugin's index
	if (g_DayIndex != specialDayId)
	{
		return;
	}
	
	// Add the special day event hooks
	HookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
	
	g_cvInfiniteAmmo.SetInt(2);
	
	ToggleBunnyhop(false);
	ToggleRunesState(false);
	
	g_IsDayActivated = true;
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	// Make sure the special day is running, and the given special day index is the plugin's index
	if (!g_IsDayActivated || g_DayIndex != specialDayId)
	{
		return;
	}
	
	if (!countdown)
	{
		// Loop through all the clients, and remove their custom weapon models
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				ResetProgressBar(current_client);
				
				int weapon = GetPlayerWeaponSlot(current_client, CS_SLOT_PRIMARY);
				if (weapon != -1)
				{
					SetupCustomWeapon(weapon, false);
				}
			}
		}
		
		// Remove the special day event hooks
		UnhookEvent("bullet_impact", Event_BulletImpact, EventHookMode_Post);
		
		ToggleBunnyhop(true);
		ToggleRunesState(true);
		
		g_cvInfiniteAmmo.SetInt(0);
	}
	
	g_IsDayActivated = false;
}

public void OnMapStart()
{
	g_iShotSprite = PrecacheModel("materials/supporter_tracers/phys_beam.vmt");
	g_iBombSprite = PrecacheModel("materials/supporter_tracers/squiggly_beam.vmt");
	
	g_iExplosionSprite = PrecacheModel("sprites/sprite_fire01.vmt");
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	// Make sure the special day is running, and the client is alive
	if (!g_IsDayActivated || !IsPlayerAlive(client) || !buttons)
	{
		return Plugin_Continue;
	}
	
	// Initialize the client's active weapon, and make sure it's valid
	int active_weapon = GetEntDataEnt2(client, m_hActiveWeaponOffset);
	
	// The client's active weapon index is invalid
	if (active_weapon == -1 || !IsValidEntity(active_weapon))
	{
		return Plugin_Continue;
	}
	
	char weapon_name[32];
	
	// The client's active weapon name is not available, or the weapon name isn't matching the special day weapon
	if (!GetEntityClassname(active_weapon, weapon_name, sizeof(weapon_name)) || !StrEqual(weapon_name, DAY_WEAPON))
	{
		return Plugin_Continue;
	}
	
	// The client isn't pressing the ability key, or the next ability attack isn't ready yet
	if (!(g_ClientsData[client].OldButtons & IN_ATTACK2) && (buttons & IN_ATTACK2) && g_ClientsData[client].NextAbilityAttack <= GetGameTime())
	{
		// Apply the ability attack cooldown
		g_ClientsData[client].NextAbilityAttack = GetGameTime() + ABILITY_COOLDOWN;
		
		// Dispaly the progress bar panel, and create the reset timer
		SetProgressBarFloat(client, ABILITY_COOLDOWN);
		CreateTimer(ABILITY_COOLDOWN, Timer_ResetProgressBar, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		
		// Initialize the client eye position and angles, for the trace ray filter to be function
		float client_eye_pos[3], client_eye_angles[3], trace_hit_pos[3];
		
		GetClientEyePosition(client, client_eye_pos);
		GetClientEyeAngles(client, client_eye_angles);
		
		TR_TraceRayFilter(client_eye_pos, client_eye_angles, MASK_ALL, RayType_Infinite, Filter_DontHitPlayers, client);
		
		if (TR_DidHit())
		{
			TR_GetEndPosition(trace_hit_pos);
		}
		
		// Perform the ability side effects
		CS_CreateExplosion(client, 275.0, 250.0, trace_hit_pos);
		PerformScreenShake(client, 10000.0 / GetVectorDistance(client_eye_pos, trace_hit_pos));
		
		// Take the bullets for the weapon due to the ability cost
		int ammo = GetEntProp(active_weapon, Prop_Send, "m_iClip1");
		SetEntProp(active_weapon, Prop_Send, "m_iClip1", ammo - KeepInRange(ABILITY_BULLETS_COST, 0, ammo));
		
		// Setup the tracer beam points, etc... And send to to everyone
		TE_SetupBeamPoints(client_eye_pos, trace_hit_pos, g_iBombSprite, 0, 0, 0, 0.4, 1.0, 1.0, 1, 0.0, { 0, 255, 0, 255 }, 0);
		TE_SendToAll();
	}
	
	g_ClientsData[client].OldButtons = buttons;
	
	return Plugin_Continue;
}

bool Filter_DontHitPlayers(int entity, int contentsMask, any data)
{
	return (entity != data);
}

void Event_BulletImpact(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	// Initialize the client's eye position, and the bullet hit position
	float client_pos[3], bullet_pos[3];
	GetClientEyePosition(client, client_pos);
	client_pos[2] -= 5.0;
	
	bullet_pos[0] = event.GetFloat("x");
	bullet_pos[1] = event.GetFloat("y");
	bullet_pos[2] = event.GetFloat("z");
	
	// Setup the tracer line colors by the client's gang color
	int tracer_colors[4];
	
	int client_gang_id = Gangs_GetPlayerGang(client);
	if (client_gang_id != NO_GANG)
	{
		GetColorRGB(g_szColors[Gangs_GetGangColor(client_gang_id)][Color_Rgb], tracer_colors);
	}
	else
	{
		tracer_colors = { 255, 255, 255, 255 };
	}
	
	// Setup the tracer beam points, and send it to everyone
	TE_SetupBeamPoints(client_pos, bullet_pos, g_iShotSprite, 0, 0, 0, 2.0, 1.0, 5.0, 1, 0.0, tracer_colors, 0);
	TE_SendToAll();
}

//================================[ Timers ]================================//

Action Timer_ResetProgressBar(Handle timer, int serial)
{
	// Initialize the client index by the given serial, and validate it
	int client = GetClientFromSerial(serial);
	
	if (client)
	{
		// Reset the progress bar panel
		ResetProgressBar(client);
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void CS_CreateExplosion(int attacker, float damage, float radius, float pos[3])
{
	// Setup and send the explosion sprite effect
	TE_SetupExplosion(pos, g_iExplosionSprite, 10.0, 30, 0, 600, 5000);
	TE_SendToAll();
	
	// Play the explosion sound effect to everyone from the explode position
	EmitSoundToAll("weapons/hegrenade/explode4.wav", SOUND_FROM_LOCAL_PLAYER, .volume = 1.0, .origin = pos);
	
	float current_position[3], current_distance;
	
	for (int current_victim = 1; current_victim <= MaxClients; current_victim++)
	{
		if (IsClientInGame(current_victim) && IsPlayerAlive(current_victim))
		{
			GetClientAbsOrigin(current_victim, current_position);
			
			if (!IsPathClear(pos, current_position, current_victim))
			{
				continue;
			}
			
			current_distance = GetVectorDistance(pos, current_position);
			
			if (current_distance <= radius)
			{
				SDKHooks_TakeDamage(current_victim, attacker, sizeof(attacker), Sine(((radius - current_distance) / radius) * (FLOAT_PI / 2)) * damage, DMG_BLAST, .bypassHooks = false);
			}
		}
	}
}

bool IsPathClear(float start_pos[3], float end_pos[3], int victimIndex)
{
	float client_angles[3];
	SubtractVectors(end_pos, start_pos, client_angles);
	GetVectorAngles(client_angles, client_angles);
	
	TR_TraceRayFilter(start_pos, client_angles, MASK_ALL, RayType_Infinite, Filter_HitTargetOnly, victimIndex);
	
	return victimIndex == TR_GetEntityIndex();
}

bool Filter_HitTargetOnly(int entity, int contentsMask, any data)
{
	return data == entity;
}

void SetProgressBarFloat(int client, float fProgressTime)
{
	int iProgressTime = RoundToCeil(fProgressTime);
	float fGameTime = GetGameTime();
	
	SetEntDataFloat(client, g_flSimulationTime, fGameTime + fProgressTime, true);
	SetEntData(client, g_iProgressBarDuration, iProgressTime, 4, true);
	SetEntDataFloat(client, g_flProgressBarStartTime, fGameTime - (iProgressTime - fProgressTime), true);
	SetEntData(client, g_iBlockingUseActionInProgress, 0, 4, true);
}

void ResetProgressBar(int client)
{
	SetEntDataFloat(client, g_flProgressBarStartTime, 0.0, true);
	SetEntData(client, g_iProgressBarDuration, 0, 1, true);
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

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

int KeepInRange(int value, int min, int max)
{
	return value < min ? min : value > max ? max : value;
}

void SetupCustomWeapon(int weapon, bool apply)
{
	CustomWeapon custom_weapon = CustomWeapon(weapon);
	if (!custom_weapon)
	{
		return;
	}
	
	custom_weapon.SetModel(CustomWeaponModel_View, apply ? LASER_GUN_VIEW_MODEL : "");
	custom_weapon.SetModel(CustomWeaponModel_World, apply ? LASER_GUN_WORLD_MODEL : "");
	custom_weapon.SetShotSound(apply ? LASER_GUN_SHOOT_SOUND : "");
}

//================================================================//