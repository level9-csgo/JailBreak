#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <JailBreak>
#include <JB_SettingsSystem>

#define FLASHLIGHT_SOUND "items/flashlight1.wav"

int g_EnableFlashlightSettingIndex = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Flashlight", 
	author = "KoNLiG", 
	description = "Replaces +lookatweapon with a toggleable flashlight. Also adds the command: sm_flashlight", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Hooks CS:GO's flashlight replacement 'look at weapon'.
	AddCommandListener(Listener_LookAtWeapon, "+lookatweapon");
}

public void OnMapStart()
{
	PrecacheSound(FLASHLIGHT_SOUND);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SettingsSystem"))
	{
		JB_CreateSettingCategory("Gameplay Settings", "This category is associated with settings that belongs to your gameplay.");
		g_EnableFlashlightSettingIndex = JB_CreateSetting("setting_charged_fl_batteries", "Decides whenther the flashlight will work. (Bool setting)", "Charged Flashlight Batteries", "Gameplay Settings", Setting_Bool, 1, "1");
	}
}

Action Listener_LookAtWeapon(int client, const char[] command, int argc)
{
	ToggleFlashlight(client);
}

void ToggleFlashlight(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}
	
	char setting_value[2];
	JB_GetClientSetting(client, g_EnableFlashlightSettingIndex, setting_value, sizeof(setting_value));
	
	if (setting_value[0] == '0')
	{
		return;
	}
	
	SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") ^ 4);
} 