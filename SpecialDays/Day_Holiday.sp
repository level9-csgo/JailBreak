#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <customweapons>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "Holiday Day"
#define DAY_HEALTH 950

#define TAKE_DAMAGE_TIME 0.23
#define PROGRESS_BAR_LENGTH SETUP_SECONDS_TIME

#define COLORED_SMOKE_PARTICLE "particles/colored_smoke.pcf"

#define SMOKE_SATURATION 1.0
#define SMOKE_BRIGHTNESS 0.9

#define UTILITY_WEAPON_TAG "weapon_smokegrenade"
#define UTILITY_REFILL_TIME 15.0

#define DEFAULT_PRIMARY_WEAPON "TAR-21"

//====================//

enum
{
	Item_TagName, 
	Item_DisplayName, 
	Item_ViewModelPath, 
	Item_WorldModelPath, 
	Item_DroppedModelPath, 
	Item_FireSoundPath, 
	Item_FireSoundVolume, 
	Item_DefaultLoadout
}

enum struct Smoke
{
	int thrower_userid;
	float position[3];
}

enum struct SmokeEffect
{
	float m_vOrigin[3];
	float m_vStart[3];
	float m_vNormal[3];
	float m_vAngles[3];
	int m_fFlags;
	int m_nEntIndex;
	float m_flScale;
	float m_flMagnitude;
	float m_flRadius;
	int m_nAttachmentIndex;
	int m_nSurfaceProp;
	int m_nMaterial;
	int m_nDamageType;
	int m_nHitBox;
	int m_nOtherEntIndex;
	int m_nColor;
	bool m_bPositionsAreRelativeToEntity;
	int m_iEffectName;
}

enum struct Client
{
	int chosen_weapon;
	Handle RefillTimer;
	
	void Reset()
	{
		this.chosen_weapon = 0;
		
		this.DeleteTimer();
	}
	
	void DeleteTimer()
	{
		if (this.RefillTimer != INVALID_HANDLE)
		{
			KillTimer(this.RefillTimer);
			this.RefillTimer = INVALID_HANDLE;
		}
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

ArrayList g_SmokesData;

Handle g_WeaponSelectionTimer = INVALID_HANDLE;

Menu g_SetupMenu;

char g_CustomWeapons[][][] = 
{
	{ "weapon_knife", "Hammer", "models/weapons/eminem/csnz/hammer/v_hammer_halloween.mdl", "models/weapons/eminem/csnz/hammer/w_hammer_halloween.mdl", "models/weapons/eminem/csnz/hammer/w_hammer_halloween_dropped.mdl", "", "0.0", "1" }, 
	{ "weapon_deagle", "AMT AutoMag V", "models/weapons/eminem/csnz/amt_automag_v/v_amt_automag_v.mdl", "models/weapons/eminem/csnz/amt_automag_v/w_amt_automag_v.mdl", "models/weapons/eminem/csnz/amt_automag_v/w_amt_automag_v_dropped.mdl", "sound/weapons/eminem/csnz/amt_automag_v/amg_fire.wav", "0.2", "1" }, 
	{ "weapon_mag7", "Rail Cannon", "models/weapons/eminem/csnz/rail_cannon/v_rail_cannon.mdl", "models/weapons/eminem/csnz/rail_cannon/w_rail_cannon.mdl", "models/weapons/eminem/csnz/rail_cannon/w_rail_cannon_dropped.mdl", "sound/weapons/eminem/csnz/rail_cannon/railcanon_fire.wav", "0.215", "0" }, 
	{ "weapon_bizon", "TDI Dual Kriss Super Vector", "models/weapons/eminem/csnz/dual_kriss/v_dual_kriss.mdl", "models/weapons/eminem/csnz/dual_kriss/w_dual_kriss.mdl", "models/weapons/eminem/csnz/dual_kriss/w_dual_kriss_dropped.mdl", "sound/weapons/eminem/csnz/dual_kriss/dualkriss_fire.wav", "0.05", "0" }, 
	{ "weapon_p90", "TAR-21", "models/weapons/eminem/csnz/tar_21/v_tar_21.mdl", "models/weapons/eminem/csnz/tar_21/w_tar_21.mdl", "models/weapons/eminem/csnz/tar_21/w_tar_21_dropped.mdl", "sound/weapons/eminem/csnz/tar_21/tar_21_fire.wav", "0.1", "0" }, 
	{ "weapon_scar20", "PSG-1", "models/weapons/eminem/csnz/psg_1/v_psg_1.mdl", "models/weapons/eminem/csnz/psg_1/w_psg_1.mdl", "models/weapons/eminem/csnz/psg_1/w_psg_1_dropped.mdl", "sound/weapons/eminem/csnz/psg_1/psg1_fire.wav", "0.08", "0" }, 
	{ "weapon_negev", "FN Mk 48", "models/weapons/eminem/csnz/fn_mk_48/v_fn_mk_48.mdl", "models/weapons/eminem/csnz/fn_mk_48/w_fn_mk_48.mdl", "models/weapons/eminem/csnz/fn_mk_48/w_fn_mk_48_dropped.mdl", "sound/weapons/eminem/csnz/fn_mk_48/mk48_fire.wav", "0.08", "0" }
};

bool g_IsDayActivated;
bool g_IsWeaponSelectionPeriod;

int g_DayId;
int g_iSelectionTimer;

int g_flSimulationTime;
int g_flProgressBarStartTime;
int g_iProgressBarDuration;
int g_iBlockingUseActionInProgress;

int g_TakeDmgTime;

int m_vecOriginOffset;

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
	g_flSimulationTime = FindSendPropInfo("CBaseEntity", "m_flSimulationTime");
	g_flProgressBarStartTime = FindSendPropInfo("CCSPlayer", "m_flProgressBarStartTime");
	g_iProgressBarDuration = FindSendPropInfo("CCSPlayer", "m_iProgressBarDuration");
	g_iBlockingUseActionInProgress = FindSendPropInfo("CCSPlayer", "m_iBlockingUseActionInProgress");
	
	m_vecOriginOffset = FindSendPropInfo("CSmokeGrenadeProjectile", "m_vecOrigin");
	
	g_TakeDmgTime = RoundToFloor(1.0 / GetTickInterval() * TAKE_DAMAGE_TIME);
}

public void OnPluginEnd()
{
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
		g_DayId = JB_CreateSpecialDay(DAY_NAME, DAY_HEALTH, true, true, true);
	}
}

public void OnMapStart()
{
	PrecacheGeneric(COLORED_SMOKE_PARTICLE, true);
	
	for (int current_weapon = 0; current_weapon < sizeof(g_CustomWeapons); current_weapon++)
	{
		PrecacheModel(g_CustomWeapons[current_weapon][Item_ViewModelPath]);
		PrecacheModel(g_CustomWeapons[current_weapon][Item_WorldModelPath]);
		PrecacheModel(g_CustomWeapons[current_weapon][Item_DroppedModelPath]);
	}
}

public void JB_OnSpecialDayVoteEnd(int specialDayId)
{
	if (g_DayId == specialDayId)
	{
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client))
			{
				g_ClientsData[current_client].Reset();
			}
		}
		
		g_iSelectionTimer = SETUP_SECONDS_TIME;
		
		CreateSetupMenu();
		DisplaySetupMenuToAll();
		
		g_WeaponSelectionTimer = CreateTimer(1.0, Timer_WeaponSelection, .flags = TIMER_REPEAT);
		
		g_IsDayActivated = true;
		g_IsWeaponSelectionPeriod = true;
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_DayId != specialDayId)
	{
		return;
	}
	
	DisarmPlayer(client);
	
	for (int current_weapon; current_weapon < sizeof(g_CustomWeapons); current_weapon++)
	{
		if (StrEqual(g_CustomWeapons[current_weapon][Item_DefaultLoadout], "1"))
		{
			GiveClientCustomWeapon(client, current_weapon);
		}
	}
	
	if (!g_ClientsData[client].chosen_weapon)
	{
		g_ClientsData[client].chosen_weapon = GetDefaultPrimaryIndex();
	}
	
	GiveClientCustomWeapon(client, g_ClientsData[client].chosen_weapon);
	
	GivePlayerItem(client, UTILITY_WEAPON_TAG);
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_DayId == specialDayId)
	{
		g_SmokesData = new ArrayList(sizeof(Smoke));
		
		HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
		HookEvent("smokegrenade_detonate", Event_SmokeDetonate, EventHookMode_Post);
		
		AddAmbientSoundHook(AdjustCustomWeaponVolume);
		
		char current_class_name[32];
		for (int current_entity = MaxClients + 1; current_entity < GetMaxEntities(); current_entity++)
		{
			if (IsValidEntity(current_entity) && GetEntityClassname(current_entity, current_class_name, sizeof(current_class_name)) && StrContains(current_class_name, "weapon_") != -1)
			{
				RemoveEntity(current_entity);
			}
		}
		
		g_IsDayActivated = true;
		g_IsWeaponSelectionPeriod = false;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_IsDayActivated && g_DayId == specialDayId)
	{
		if (!countdown)
		{
			for (int current_client = 1; current_client <= MaxClients; current_client++)
			{
				if (IsClientInGame(current_client))
				{
					ResetClientCustomWeapons(current_client);
					
					DisarmPlayer(current_client);
					GivePlayerItem(current_client, "weapon_deagle");
					DisarmPlayer(current_client);
					GivePlayerItem(current_client, "weapon_knife");
					
					ResetProgressBar(current_client);
				}
			}
			
			if (g_WeaponSelectionTimer == INVALID_HANDLE)
			{
				delete g_SmokesData;
				
				UnhookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
				UnhookEvent("smokegrenade_detonate", Event_SmokeDetonate, EventHookMode_Post);
				
				RemoveAmbientSoundHook(AdjustCustomWeaponVolume);
			}
		}
		else
		{
			delete g_SetupMenu;
		}
		
		if (g_WeaponSelectionTimer != INVALID_HANDLE)
		{
			KillTimer(g_WeaponSelectionTimer);
			g_WeaponSelectionTimer = INVALID_HANDLE;
		}
		
		g_IsDayActivated = false;
		g_IsWeaponSelectionPeriod = false;
	}
}

Action AdjustCustomWeaponVolume(char sample[PLATFORM_MAX_PATH], int &entity, float &volume, int &level, int &pitch, float pos[3], int &flags, float &delay)
{
	int idx = FindCustomWeaponBySound(sample);
	if (idx != -1)
	{
		volume = StringToFloat(g_CustomWeapons[idx][Item_FireSoundVolume]);
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	// Make sure to reset the client data, to avoid client data override
	g_ClientsData[client].Reset();
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!g_IsDayActivated || g_IsWeaponSelectionPeriod || !IsPlayerAlive(client) || tickcount % g_TakeDmgTime != 0)
	{
		return;
	}
	
	float client_position[3];
	GetClientAbsOrigin(client, client_position);
	
	Smoke CurrentSmokeData;
	
	for (int current_smoke, thrower_index; current_smoke < g_SmokesData.Length; current_smoke++)
	{
		CurrentSmokeData = GetSmokeByIndex(current_smoke);
		
		if (GetVectorDistance(CurrentSmokeData.position, client_position) <= 144.0)
		{
			thrower_index = GetClientOfUserId(CurrentSmokeData.thrower_userid);
			
			SDKHooks_TakeDamage(client, !thrower_index ? client : thrower_index, !thrower_index ? client : thrower_index, GetRandomFloat(7.0, 15.0), DMG_ACID, .bypassHooks = false);
		}
	}
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	char weapon_name[32];
	event.GetString("weapon", weapon_name, sizeof(weapon_name));
	
	if (StrEqual(weapon_name, UTILITY_WEAPON_TAG))
	{
		g_ClientsData[client].RefillTimer = CreateTimer(UTILITY_REFILL_TIME, Timer_UtilityRefill, GetClientSerial(client));
		SetProgressBarFloat(client, UTILITY_REFILL_TIME);
	}
}

public void Event_SmokeDetonate(Event event, const char[] name, bool dontBroadcast)
{
	StopParticleEffect(0, "explosion_smokegrenade_fallback");
	
	float deploy_position[3];
	deploy_position[0] = event.GetFloat("x");
	deploy_position[1] = event.GetFloat("y");
	deploy_position[2] = event.GetFloat("z");
	
	StartSmokeEffect("explosion_smokegrenade_colored", deploy_position);
	
	Smoke SmokeData;
	
	SmokeData.thrower_userid = event.GetInt("userid");
	SmokeData.position = deploy_position;
	
	g_SmokesData.PushArray(SmokeData);
	
	DataPack dPack;
	CreateDataTimer(18.0, Timer_SmokeExpire, dPack, TIMER_FLAG_NO_MAPCHANGE);
	dPack.WriteFloat(deploy_position[0]);
	dPack.WriteFloat(deploy_position[1]);
	dPack.WriteFloat(deploy_position[2]);
	dPack.Reset();
	
	int index = MaxClients + 1;
	float deploy_position2[3];
	while ((index = FindEntityByClassname(index, "smokegrenade_projectile")) != -1)
	{
		GetEntDataVector(index, m_vecOriginOffset, deploy_position2);
		
		if (deploy_position[0] == deploy_position2[0] && deploy_position[1] == deploy_position2[1] && deploy_position[2] == deploy_position2[2])
		{
			AcceptEntityInput(index, "Kill");
		}
	}
}

//================================[ Menus ]================================//

void CreateSetupMenu()
{
	g_SetupMenu = new Menu(Handler_WeaponSelection, MenuAction_Select | MenuAction_DrawItem | MenuAction_DisplayItem);
	g_SetupMenu.SetTitle("%s %s - Weapon Selection [%s]\n• Choose your cutsom weapon:\n ", PREFIX_MENU, DAY_NAME, GetProgressBar(g_iSelectionTimer, SETUP_SECONDS_TIME));
	
	char item_info[4];
	
	for (int current_weapon = 0; current_weapon < sizeof(g_CustomWeapons); current_weapon++)
	{
		if (StrEqual(g_CustomWeapons[current_weapon][Item_DefaultLoadout], "0"))
		{
			IntToString(current_weapon, item_info, sizeof(item_info));
			g_SetupMenu.AddItem(item_info, g_CustomWeapons[current_weapon][Item_DisplayName]);
		}
	}
}

public int Handler_WeaponSelection(Menu menu, MenuAction action, int param1, int param2)
{
	int client = param1, item_position = param2;
	
	// Initialize the selected weapon index by the item information
	char item_info[4];
	menu.GetItem(item_position, item_info, sizeof(item_info));
	int weapon_index = StringToInt(item_info);
	
	if (action == MenuAction_Select)
	{
		if (!g_IsWeaponSelectionPeriod)
		{
			PrintToChat(client, "%s The weapon selection period is no longer running!", PREFIX_ERROR);
			return 0;
		}
		
		PrintToChat(client, "%s You've %s to play with \x04%s\x01!", PREFIX, g_ClientsData[client].chosen_weapon == -1 ? "selected" : "switched", g_CustomWeapons[weapon_index][Item_DisplayName]);
		
		g_ClientsData[client].chosen_weapon = weapon_index;
		
		menu.Display(client, 1);
	}
	else if (action == MenuAction_DrawItem)
	{
		return g_ClientsData[client].chosen_weapon != weapon_index ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
	}
	else if (action == MenuAction_DisplayItem && g_ClientsData[client].chosen_weapon == weapon_index)
	{
		char item_display[64];
		Format(item_display, sizeof(item_display), "%s [Selected]", g_CustomWeapons[g_ClientsData[client].chosen_weapon][Item_DisplayName]);
		RedrawMenuItem(item_display);
	}
	
	return 0;
}

void DisplaySetupMenuToAll()
{
	if (!g_SetupMenu)
	{
		return;
	}
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			g_SetupMenu.Display(current_client, 1);
		}
	}
}

//================================[ Timers ]================================//

public Action Timer_WeaponSelection(Handle timer)
{
	if (g_iSelectionTimer <= 1)
	{
		JB_StartSpecialDay(g_DayId);
		
		int default_weapon_index = -1;
		
		for (int current_weapon = 0; current_weapon < sizeof(g_CustomWeapons); current_weapon++)
		{
			if (StrEqual(g_CustomWeapons[current_weapon][Item_DefaultLoadout], "0"))
			{
				default_weapon_index = current_weapon;
				break;
			}
		}
		
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client) && g_ClientsData[current_client].chosen_weapon == -1)
			{
				g_ClientsData[current_client].chosen_weapon = default_weapon_index;
			}
		}
		
		delete g_SetupMenu;
		
		g_WeaponSelectionTimer = INVALID_HANDLE;
		
		return Plugin_Stop;
	}
	
	g_iSelectionTimer--;
	
	char menu_title[128];
	g_SetupMenu.GetTitle(menu_title, sizeof(menu_title));
	ReplaceString(menu_title, sizeof(menu_title), GetProgressBar(g_iSelectionTimer + 1, SETUP_SECONDS_TIME), GetProgressBar(g_iSelectionTimer, SETUP_SECONDS_TIME));
	g_SetupMenu.SetTitle(menu_title);
	
	DisplaySetupMenuToAll();
	
	return Plugin_Continue;
}

public Action Timer_UtilityRefill(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Set the timer handle as invalid, to prevent timer errors
	g_ClientsData[client].RefillTimer = INVALID_HANDLE;
	
	// Make sure the client index is in-game and valid
	if (!client || !g_IsDayActivated || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	
	GivePlayerItem(client, UTILITY_WEAPON_TAG);
	ResetProgressBar(client);
	
	return Plugin_Continue;
}

Action Timer_SmokeExpire(Handle timer, DataPack dPack)
{
	if (!g_SmokesData)
	{
		return Plugin_Continue;
	}
	
	float position[3];
	position[0] = dPack.ReadFloat();
	position[1] = dPack.ReadFloat();
	position[2] = dPack.ReadFloat();
	
	int smoke_index = GetSmokeByPosition(position);
	if (smoke_index != -1)
	{
		g_SmokesData.Erase(smoke_index);
	}
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

any[] GetSmokeByIndex(int index)
{
	Smoke SmokeData;
	g_SmokesData.GetArray(index, SmokeData);
	return SmokeData;
}

int GetSmokeByPosition(float pos[3])
{
	Smoke CurrentSmokeData;
	
	for (int current_smoke = 0; current_smoke < g_SmokesData.Length; current_smoke++)
	{
		CurrentSmokeData = GetSmokeByIndex(current_smoke);
		
		if (CurrentSmokeData.position[0] == pos[0] && CurrentSmokeData.position[1] == pos[1] && CurrentSmokeData.position[2] == pos[2])
		{
			return current_smoke;
		}
	}
	
	return -1;
}

void GiveClientCustomWeapon(int client, int weapon_index)
{
	int weapon = GivePlayerItem(client, g_CustomWeapons[weapon_index][Item_TagName]);
	if (weapon == -1)
	{
		return;
	}
	
	CustomWeapon custom_weapon = CustomWeapon(weapon);
	if (!custom_weapon)
	{
		return;
	}
	
	char path[PLATFORM_MAX_PATH];
	
	strcopy(path, sizeof(path), g_CustomWeapons[weapon_index][Item_ViewModelPath]);
	custom_weapon.SetModel(CustomWeaponModel_View, path);
	
	strcopy(path, sizeof(path), g_CustomWeapons[weapon_index][Item_WorldModelPath]);
	custom_weapon.SetModel(CustomWeaponModel_World, path);
	
	strcopy(path, sizeof(path), g_CustomWeapons[weapon_index][Item_DroppedModelPath]);
	custom_weapon.SetModel(CustomWeaponModel_Dropped, path);
	
	strcopy(path, sizeof(path), g_CustomWeapons[weapon_index][Item_FireSoundPath][6]);
	custom_weapon.SetShotSound(path);
}

void ResetClientCustomWeapons(int client, int weapon = -1)
{
	if (weapon != -1)
	{
		CustomWeapon custom_weapon = CustomWeapon(weapon);
		if (custom_weapon)
		{
			custom_weapon.SetModel(CustomWeaponModel_View, "");
			custom_weapon.SetModel(CustomWeaponModel_World, "");
			custom_weapon.SetModel(CustomWeaponModel_Dropped, "");
			
			custom_weapon.SetShotSound("");
		}
		
		return;
	}
	
	if ((weapon = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY)) != -1)
	{
		ResetClientCustomWeapons(client, weapon);
	}
	
	if ((weapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY)) != -1)
	{
		ResetClientCustomWeapons(client, weapon);
	}
	
	if ((weapon = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE)) != -1)
	{
		ResetClientCustomWeapons(client, weapon);
	}
}

int GetDefaultPrimaryIndex()
{
	for (int current_weapon; current_weapon < sizeof(g_CustomWeapons); current_weapon++)
	{
		if (StrEqual(g_CustomWeapons[current_weapon][Item_DisplayName], DEFAULT_PRIMARY_WEAPON))
		{
			return current_weapon;
		}
	}
	
	return 0;
}

void StartSmokeEffect(const char[] smokeParticle, const float origin[3])
{
	SmokeEffect data;
	
	data.m_vOrigin[0] = origin[0];
	data.m_vOrigin[1] = origin[1];
	data.m_vOrigin[2] = origin[2];
	
	float r = 90.0, g = 90.0, b = 90.0;
	
	HSV2RGB(GetRandomFloat(0.0, 360.0), SMOKE_SATURATION, SMOKE_BRIGHTNESS, r, g, b);
	r *= 255.0, g *= 255.0, b *= 255.0;
	
	data.m_vStart[0] = r;
	data.m_vStart[1] = g;
	data.m_vStart[2] = b;
	
	data.m_nHitBox = GetParticleSystemIndex(smokeParticle);
	
	DispatchEffect("ParticleEffect", data);
}

void StopParticleEffect(int entity, const char[] particleName)
{
	SmokeEffect data;
	
	data.m_nEntIndex = entity;
	data.m_nHitBox = GetParticleSystemIndex(particleName);
	
	DispatchEffect("ParticleEffectStop", data);
}

void DispatchEffect(const char[] effectName, SmokeEffect data)
{
	data.m_iEffectName = GetEffectIndex(effectName);
	
	TE_SetupEffectDispatch(data);
	TE_SendToAll();
}

int GetEffectIndex(const char[] effectName)
{
	static int table = INVALID_STRING_TABLE;
	
	if (table == INVALID_STRING_TABLE)
		table = FindStringTable("EffectDispatch");
	
	int index = FindStringIndex(table, effectName);
	
	if (index != INVALID_STRING_INDEX)
		return index;
	
	return 0;
}

int GetParticleSystemIndex(const char[] effectName)
{
	static int table = INVALID_STRING_TABLE;
	
	if (table == INVALID_STRING_TABLE)
		table = FindStringTable("ParticleEffectNames");
	
	int index = FindStringIndex(table, effectName);
	
	if (index != INVALID_STRING_INDEX)
		return index;
	
	return 0;
}

void TE_SetupEffectDispatch(SmokeEffect data)
{
	TE_Start("EffectDispatch");
	TE_WriteFloatArray("m_vOrigin.x", data.m_vOrigin, 3);
	TE_WriteFloatArray("m_vStart.x", data.m_vStart, 3);
	TE_WriteAngles("m_vAngles", data.m_vAngles);
	TE_WriteVector("m_vNormal", data.m_vNormal);
	TE_WriteNum("m_fFlags", data.m_fFlags);
	TE_WriteFloat("m_flMagnitude", data.m_flMagnitude);
	TE_WriteFloat("m_flScale", data.m_flScale);
	TE_WriteNum("m_nAttachmentIndex", data.m_nAttachmentIndex);
	TE_WriteNum("m_nSurfaceProp", data.m_nSurfaceProp);
	TE_WriteNum("m_iEffectName", data.m_iEffectName);
	TE_WriteNum("m_nMaterial", data.m_nMaterial);
	TE_WriteNum("m_nDamageType", data.m_nDamageType);
	TE_WriteNum("m_nHitBox", data.m_nHitBox);
	TE_WriteNum("entindex", data.m_nEntIndex);
	TE_WriteNum("m_nOtherEntIndex", data.m_nOtherEntIndex);
	TE_WriteNum("m_nColor", data.m_nColor);
	TE_WriteFloat("m_flRadius", data.m_flRadius);
	TE_WriteNum("m_bPositionsAreRelativeToEntity", data.m_bPositionsAreRelativeToEntity);
}

void HSV2RGB(float h, float s, float v, float &r, float &g, float &b)
{
	if (s == 0.0)
	{
		r = v, g = v, b = v;
		return;
	}
	
	if (h == 360.0)
		h = 0.0;
	
	int hi = RoundToFloor(h / 60.0);
	float f = (h / 60.0) - hi;
	float p = v * (1.0 - s);
	float q = v * (1.0 - s * f);
	float t = v * (1.0 - s * (1.0 - f));
	
	switch (hi)
	{
		case 0:r = v, g = t, b = p;
		case 1:r = q, g = v, b = p;
		case 2:r = p, g = v, b = t;
		case 3:r = p, g = q, b = v;
		case 4:r = t, g = p, b = v;
		default:r = v, g = p, b = q;
	}
}

char[] GetProgressBar(int value, int all)
{
	char szProgress[PROGRESS_BAR_LENGTH * 6];
	int iLength = PROGRESS_BAR_LENGTH;
	
	for (int iCurrentChar = 0; iCurrentChar <= (float(value) / float(all) * PROGRESS_BAR_LENGTH) - 1; iCurrentChar++)
	{
		iLength--;
		StrCat(szProgress, sizeof(szProgress), "⬛");
	}
	
	for (int iCurrentChar = 0; iCurrentChar < iLength; iCurrentChar++) {
		StrCat(szProgress, sizeof(szProgress), "•");
	}
	
	StripQuotes(szProgress);
	TrimString(szProgress);
	return szProgress;
}

void SetProgressBarFloat(int client, float progress_time)
{
	int iProgressTime = RoundToCeil(progress_time);
	float fGameTime = GetGameTime();
	
	SetEntDataFloat(client, g_flSimulationTime, fGameTime + progress_time, true);
	SetEntData(client, g_iProgressBarDuration, iProgressTime, 4, true);
	SetEntDataFloat(client, g_flProgressBarStartTime, fGameTime - (iProgressTime - progress_time), true);
	SetEntData(client, g_iBlockingUseActionInProgress, 0, 4, true);
}

void ResetProgressBar(int client)
{
	SetEntDataFloat(client, g_flProgressBarStartTime, 0.0, true);
	SetEntData(client, g_iProgressBarDuration, 0, 1, true);
}

int FindCustomWeaponBySound(const char[] sound)
{
	for (int current_wep; current_wep < sizeof(g_CustomWeapons); current_wep++)
	{
		if (StrEqual(g_CustomWeapons[current_wep][Item_FireSoundPath][6], sound))
		{
			return current_wep;
		}
	}
	
	return -1;
}

//================================================================//