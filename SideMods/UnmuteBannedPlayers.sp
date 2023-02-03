#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

ConVar sv_mute_players_with_social_penalties;

public Plugin myinfo = 
{
	name = "[CS:GO] Unmute Banned Players", 
	author = "KoNLiG", 
	description = "Unmutes players with social panalties. Caused by players reporting other players for communication abuse.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	if (!(sv_mute_players_with_social_penalties = FindConVar("sv_mute_players_with_social_penalties")))
	{
		SetFailState("Failed to find 'sv_mute_players_with_social_penalties'");
	}
}

public void OnMapStart()
{
	sv_mute_players_with_social_penalties.BoolValue = true;
} 