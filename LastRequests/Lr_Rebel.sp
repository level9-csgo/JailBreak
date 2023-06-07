#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_SettingsSystem>
#include <JB_LrSystem>

#define PLUGIN_AUTHOR "KoNLiG"

/* Settings */

#define LR_NAME "Rebel [Rambo Mode]"
#define LR_WEAPON "weapon_negev"
#define LR_ICON "domination"

#define HEALTH_PER_GUARD 100

#define START_SOUND "rambomode_activated.wav"

/*  */

bool g_bIsLrActivated;

int g_iSettingId = -1;
int g_iPrisonerIndex = -1;
int g_iLrId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...LR_NAME..." Lr", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	if (LibraryExists(JB_LRSYSTEM_LIBNAME))
	{
		OnLibraryAdded(JB_LRSYSTEM_LIBNAME);
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, JB_LRSYSTEM_LIBNAME))
	{
		g_iLrId = JB_AddLr(LR_NAME, true, true, false, true, 4);
	}
	else if (StrEqual(name, "JB_SettingsSystem"))
	{
		JB_CreateSettingCategory("Sound Settings", "This category is associated with sound in general, as well as music settings.");
		g_iSettingId = JB_CreateSetting("setting_lr_general_sounds", "Controls the last request general sounds volume. (Float setting)", "Last Request General Sounds", "Sound Settings", Setting_Float, 1.0, "0.5");
	}
}

public void JB_OnLrSelected(int client, int lrId)
{
	if (g_iLrId == lrId)
	{
		g_iPrisonerIndex = client;
		StartLr();
	}
}

public void JB_OnRandomLrSelected(int client, int lrId)
{
	if (g_iLrId == lrId)
	{
		g_iPrisonerIndex = client;
		StartLr();
	}
}

public void JB_OnLrEnd(int currentLr, const char[] lrName, int winner, int loser, bool aborted)
{
	if (g_bIsLrActivated && g_iLrId == currentLr)
	{
		g_bIsLrActivated = false;
	}
}

public void JB_OnShowLrInfoMenu(Panel panel, int currentLr)
{
	if (g_iLrId == currentLr)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "• Prisoner: %N (%d HP) Is A Rebel!", 
			g_iPrisonerIndex, 
			GetClientHealth(g_iPrisonerIndex)
			);
		panel.DrawText(szMessage);
	}
}

/*  */

/* Functions */

void StartLr()
{
	DisarmPlayer(g_iPrisonerIndex);
	GivePlayerItem(g_iPrisonerIndex, LR_WEAPON);
	GivePlayerItem(g_iPrisonerIndex, "weapon_knife");
	SetEntityHealth(g_iPrisonerIndex, GetOnlineTeamCount(CS_TEAM_CT) * HEALTH_PER_GUARD);
	
	char szSettingValue[16], szSoundPath[PLATFORM_MAX_PATH];
	Format(szSoundPath, sizeof(szSoundPath), "%s/%s/%s", PARENT_SOUNDS_DIR, LRS_PARENT_SOUNDS_DIR, START_SOUND);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			JB_GetClientSetting(iCurrentClient, g_iSettingId, szSettingValue, sizeof(szSettingValue));
			float fSettingVolume = StringToFloat(szSettingValue);
			if (fSettingVolume != 0.0) {
				EmitSoundToClient(iCurrentClient, szSoundPath, _, _, _, _, fSettingVolume);
			}
		}
	}
	
	PrintToChatAll("Prisoner \x10%N\x01 is a \x02Rebel\x01!", g_iPrisonerIndex);
	g_bIsLrActivated = true;
	JB_StartLr(g_iPrisonerIndex, INVALID_LR_WINNER, LR_ICON, true);
}

/* */