#if defined _Misc_Ghost_included
 #endinput
#endif
#define _Misc_Ghost_included

/**
 * Retrieves whether a certain client is a ghost. 
 *
 * @param client		Client index.
 *
 * @return 				True if the client is a ghost, false otherwise.
 */
native bool JB_IsClientGhost(int client);

#if !defined REQUIRE_PLUGIN
public void __pl_Misc_Ghost_SetNTVOptional()
{
	MarkNativeAsOptional("JB_IsClientGhost");
}
#endif

public SharedPlugin __pl_Misc_Ghost = 
{
	name = "Misc_Ghost", 
	file = "Misc_Ghost.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
}; 