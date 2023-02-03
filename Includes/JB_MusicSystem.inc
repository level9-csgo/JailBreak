#if defined _JB_MusicSystem_included
 #endinput
#endif
#define _JB_MusicSystem_included

/**
 * Plays a random song from the music system.
 * 
 * @return            True if the song played successfully, false if there is no song exists.
 */
native bool JB_PlayRandomSong(bool broadcast = true);

/**
 * Stops the running songs for a certain client.
 * 
 * @param client 	   Client index.
 */
native void JB_StopMusicToClient(int client);

stock void StopMusicToAll()
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			JB_StopMusicToClient(iCurrentClient);
		}
	}
}

#if !defined REQUIRE_PLUGIN
public void __pl_JB_MusicSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_PlayRandomSong");
	MarkNativeAsOptional("JB_StopMusicToClient");
}
#endif

public SharedPlugin __pl_JB_MusicSystem = 
{
	name = "JB_MusicSystem", 
	file = "JB_MusicSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};
