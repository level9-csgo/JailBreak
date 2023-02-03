#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <JailBreak>
#include <JB_SettingsSystem>

#define SPECMODE_FREELOOK 6

int setting_enable_speed_display;

int m_iObserverModeOffset;
int m_hObserverTargetOffset;
int m_vecVelocityOffset;

Handle HudSynchronizer;

public Plugin myinfo = 
{
	name = "[CS:GO] Speed Display", 
	author = "KoNLiG", 
	description = "Replicates the speed part in cl_showpos command.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	if ((m_iObserverModeOffset = FindSendPropInfo("CCSPlayer", "m_iObserverMode")) <= 0)
	{
		SetFailState("Failed to find 'm_iObserverMode' offset");
	}
	
	if ((m_hObserverTargetOffset = FindSendPropInfo("CCSPlayer", "m_hObserverTarget")) <= 0)
	{
		SetFailState("Failed to find 'm_hObserverTarget' offset");
	}
	
	if ((m_vecVelocityOffset = FindSendPropInfo("CCSPlayer", "m_vecVelocity[0]")) <= 0)
	{
		SetFailState("Failed to find 'm_vecBaseVelocity' offset");
	}
	
	HudSynchronizer = CreateHudSynchronizer();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SettingsSystem"))
	{
		JB_CreateSettingCategory("Gameplay Settings", "This category is associated with settings that belongs to your gameplay.");
		setting_enable_speed_display = JB_CreateSetting("setting_enable_speed_display", "Toggle speed display. (Bool setting)", "Speed Display", "Gameplay Settings", Setting_Bool, 1, "1");
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	char setting_value[2];
	JB_GetClientSetting(client, setting_enable_speed_display, setting_value, sizeof(setting_value));
	
	if (setting_value[0] == '0')
	{
		return;
	}
	
	int target = client, m_hObserverTarget = GetEntDataEnt2(client, m_hObserverTargetOffset);
	if (m_hObserverTarget != -1 && GetEntData(client, m_iObserverModeOffset) != SPECMODE_FREELOOK)
	{
		target = m_hObserverTarget;
	}
	
	float m_vecVelocity[3];
	GetEntDataVector(target, m_vecVelocityOffset, m_vecVelocity);
	
	SetHudTextParams(0.0, 0.0, 2.0, 255, 105, 180, 180, 1, 0.0, 0.1, 0.2);
	// ShowHudText(client, 7, "Speed: %d", RoundToFloor(GetVectorLength(m_vecVelocity)));
	
	ShowSyncHudText(client, HudSynchronizer, "Speed: %d", RoundToFloor(GetVectorLength(m_vecVelocity)));
} 