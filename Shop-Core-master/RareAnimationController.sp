#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <anymap>
#include <studio_hdr>
#include <RareAnimationController>

#pragma newdecls required
#pragma semicolon 1

enum struct RareSequences
{
	int index[RARE_SEQUENCE_MAX];
	float duration[RARE_SEQUENCE_MAX];
}

AnyMap g_RareSequences;

GlobalForward g_OnRareAnimation;

public Plugin myinfo = 
{
	name = "[CS:GO] Rare Animation Controller", 
	author = "KoNLiG, Natanel 'LuqS'", 
	description = "Provides custom use of rare weapons inspect animations.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG || https://steamcommunity.com/id/luqsgood"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// Lock the use of this plugin for CS:GO only.
	if (GetEngineVersion() != Engine_CSGO)
	{
		strcopy(error, err_max, "This plugin was made for use with CS:GO only.");
		return APLRes_Failure;
	}
	
	g_OnRareAnimation = new GlobalForward("OnRareAnimation", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Float);
	
	RegPluginLibrary("RareAnimationController");
	
	return APLRes_Success;
}

Action Call_OnRareAnimation(int client, int weapon, int sequence_type, int sequence_index, float duration)
{
	Action result;
	
	Call_StartForward(g_OnRareAnimation);
	Call_PushCell(client);
	Call_PushCell(weapon);
	Call_PushCell(sequence_type);
	Call_PushCell(sequence_index);
	Call_PushFloat(duration);
	Call_Finish(result);
	
	return result;
}

public void OnPluginStart()
{
	// Hook '+lookatweapon' command.
	AddCommandListener(Listener_LookAtWeapon, "+lookatweapon");
	
	// Stores each weapon rare inspect sequence index by it's definition index.
	g_RareSequences = new AnyMap();
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPutInServer(current_client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, Hook_OnWeaponSwitch);
}

void Hook_OnWeaponSwitch(int client, int weapon)
{
	if (!(GetClientButtons(client) & IN_ATTACK2))
	{
		return;
	}
	
	int predicted_viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	
	RareSequences rare_sequences;
	if (!LoadWeaponSequences(weapon, GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"), rare_sequences) || rare_sequences.index[RARE_SEQUENCE_DRAW] == -1)
	{
		return;
	}
	
	if (Call_OnRareAnimation(client, weapon, RARE_SEQUENCE_DRAW, rare_sequences.index[RARE_SEQUENCE_DRAW], rare_sequences.duration[RARE_SEQUENCE_DRAW]) < Plugin_Handled)
	{
		SetWeaponAnimation(client, predicted_viewmodel, rare_sequences.index[RARE_SEQUENCE_DRAW], rare_sequences.duration[RARE_SEQUENCE_DRAW]);
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int switch_weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!(buttons & IN_RELOAD))
	{
		return;
	}
	
	int predicted_viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	
	// Get the client active weapon by 'predicted_viewmodel'.
	int weapon = GetEntPropEnt(predicted_viewmodel, Prop_Send, "m_hWeapon");
	if (weapon == -1)
	{
		return;
	}
	
	RareSequences rare_sequences;
	if (!LoadWeaponSequences(weapon, GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"), rare_sequences) || rare_sequences.index[RARE_SEQUENCE_IDLE] == -1)
	{
		return;
	}
	
	if (Call_OnRareAnimation(client, weapon, RARE_SEQUENCE_IDLE, rare_sequences.index[RARE_SEQUENCE_IDLE], rare_sequences.duration[RARE_SEQUENCE_IDLE]) < Plugin_Handled)
	{
		SetEntProp(predicted_viewmodel, Prop_Send, "m_nSequence", rare_sequences.index[RARE_SEQUENCE_IDLE]);
		SetEntPropFloat(weapon, Prop_Data, "m_flTimeWeaponIdle", GetGameTime() + rare_sequences.duration[RARE_SEQUENCE_IDLE]);
	}
}

Action Listener_LookAtWeapon(int client, const char[] command, int argc)
{
	static int last_lookatweapon[MAXPLAYERS + 1]; // Last time the player used '+lookatweapon' command.
	
	// Detect dobule button presses.
	if (GetTime() - last_lookatweapon[client] > 1)
	{
		last_lookatweapon[client] = GetTime();
		return;
	}
	
	int predicted_viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	
	// Get the client active weapon by 'predicted_viewmodel'.
	int weapon = GetEntPropEnt(predicted_viewmodel, Prop_Send, "m_hWeapon");
	if (weapon == -1)
	{
		return;
	}
	
	RareSequences rare_sequences;
	if (!LoadWeaponSequences(weapon, GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"), rare_sequences) || rare_sequences.index[RARE_SEQUENCE_INSPECT] == -1)
	{
		return;
	}
	
	if (Call_OnRareAnimation(client, weapon, RARE_SEQUENCE_INSPECT, rare_sequences.index[RARE_SEQUENCE_INSPECT], rare_sequences.duration[RARE_SEQUENCE_INSPECT]) >= Plugin_Handled)
	{
		return;
	}
	
	// If the client is available for sequence changes, apply the rare inspect sequence. 
	if (GetEntProp(client, Prop_Send, "m_bIsLookingAtWeapon", 1))
	{
		SetWeaponAnimation(client, predicted_viewmodel, rare_sequences.index[RARE_SEQUENCE_INSPECT], rare_sequences.duration[RARE_SEQUENCE_INSPECT]);
	}
}

bool LoadWeaponSequences(int weapon, int weapon_defindex, RareSequences rare_sequences)
{
	// If the weapon sequences already loaded, no need to continue.
	if (g_RareSequences.GetArray(weapon_defindex, rare_sequences, sizeof(rare_sequences)))
	{
		return true;
	}
	
	StudioHdr studio_hdr = GetEntityStudioHdr(weapon);
	if (studio_hdr == NULL_STUDIO_HDR)
	{
		return false;
	}
	
	// This check covers knives animations and redirects us to the right StudioHdr data.
	// Knives animations and sequences deperated to store in different file named (in most cases) 'Knife View Model + _anim.mdl'.
	// Here 'IncludeModel' methodmap becomes a good use for us.
	if (!studio_hdr.NumSequences && studio_hdr.NumIncludeModels)
	{
		char include_model[PLATFORM_MAX_PATH];
		studio_hdr.GetIncludeModel(0).GetName(include_model, sizeof(include_model));
		
		if ((studio_hdr = StudioHdr(include_model)) == NULL_STUDIO_HDR || !studio_hdr.NumSequences)
		{
			return false;
		}
	}
	
	// Prepare variables for the loop(s).
	Animation animation;
	Sequence sequence;
	char sequence_name[32];
	int num_sequecnes[RARE_SEQUENCE_MAX];
	
	// Loop through all the model sequences and find the rare one.
	for (int current_sequence, min_actweights[RARE_SEQUENCE_MAX] = { -1, ... }, sequence_type; current_sequence < studio_hdr.NumSequences; current_sequence++)
	{
		sequence = studio_hdr.GetSequence(current_sequence);
		sequence.GetLabelName(sequence_name, sizeof(sequence_name));
		
		sequence_type = StrContains(sequence_name, "draw") != -1 ? RARE_SEQUENCE_DRAW : 
						StrContains(sequence_name, "idle") != -1 ? RARE_SEQUENCE_IDLE : 
						StrContains(sequence_name, "lookat") != -1 ? RARE_SEQUENCE_INSPECT : RARE_SEQUENCE_NONE;
		
		// PrintToChatAll("[%d] %s, %d", current_sequence, sequence_name, sequence.actweight);
		
		if (sequence_type == RARE_SEQUENCE_NONE)
		{
			continue;
		}
		
		if (min_actweights[sequence_type] == -1 || sequence.actweight < min_actweights[sequence_type])
		{
			rare_sequences.index[sequence_type] = current_sequence;
			
			min_actweights[sequence_type] = sequence.actweight;
		}
		else if (sequence.actweight == min_actweights[sequence_type])
		{
			rare_sequences.index[sequence_type] = -1;
		}
		
		num_sequecnes[sequence_type]++;
	}
	
	for (int current_sequence; current_sequence < RARE_SEQUENCE_MAX; current_sequence++)
	{
		if (num_sequecnes[current_sequence] == 1)
		{
			rare_sequences.index[current_sequence] = -1;
		}
		
		if (rare_sequences.index[current_sequence] != -1)
		{
			sequence = studio_hdr.GetSequence(rare_sequences.index[current_sequence]);
			
			animation = studio_hdr.GetAnimation(LoadFromAddress(view_as<Address>(sequence) + view_as<Address>(sequence.animindexindex), NumberType_Int32));
			
			rare_sequences.duration[current_sequence] = float(animation.numframes) / animation.fps;
		}
	}
	
	// Store the result, rare_sequence will be -1 if this model doesn't have a rare animation.
	return g_RareSequences.SetArray(weapon_defindex, rare_sequences, sizeof(rare_sequences));
}

void SetWeaponAnimation(int client, int predicted_viewmodel, int sequence, float duration)
{
	SetEntProp(predicted_viewmodel, Prop_Send, "m_nSequence", sequence);
	
	float next_attack = GetGameTime() + duration;
	if (GetEntPropFloat(client, Prop_Send, "m_flNextAttack") < next_attack)
	{
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", next_attack);
	}
} 