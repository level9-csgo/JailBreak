/*  SM First Person View Models Interface
 *
 *  Copyright (C) 2017-2021 Francisco 'Franc1sco' García
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define MAX_WEAPONS 48
#define DATA "3.2"

Handle trie_weapons[MAXPLAYERS + 1];

int g_PVMid[MAXPLAYERS + 1];

Handle OnClientView, OnClientWorld, OnClientDrop;

new OldSequence[MAXPLAYERS + 1];
new Float:OldCycle[MAXPLAYERS + 1];

char g_classname[MAXPLAYERS + 1][64];

bool hook[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "SM First Person View Models Interface", 
	author = "Franc1sco franug", 
	description = "", 
	version = DATA, 
	url = "http://steamcommunity.com/id/franug"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("FPVMI_AddViewModelToClient", Native_AddViewWeapon);
	CreateNative("FPVMI_AddWorldModelToClient", Native_AddWorldWeapon);
	CreateNative("FPVMI_AddDropModelToClient", Native_AddDropWeapon);
	
	CreateNative("FPVMI_SetClientModel", Native_SetWeapon);
	
	CreateNative("FPVMI_GetClientViewModel", Native_GetWeaponView);
	CreateNative("FPVMI_GetClientWorldModel", Native_GetWeaponWorld);
	CreateNative("FPVMI_GetClientDropModel", Native_GetWeaponWorld);
	
	CreateNative("FPVMI_RemoveViewModelToClient", Native_RemoveViewWeapon);
	CreateNative("FPVMI_RemoveWorldModelToClient", Native_RemoveWorldWeapon);
	CreateNative("FPVMI_RemoveDropModelToClient", Native_RemoveWorldWeapon);
	
	OnClientView = CreateGlobalForward("FPVMI_OnClientViewModel", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	OnClientWorld = CreateGlobalForward("FPVMI_OnClientWorldModel", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	OnClientDrop = CreateGlobalForward("FPVMI_OnClientDropModel", ET_Ignore, Param_Cell, Param_String, Param_String);
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_fpvmi_version", DATA, "", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY);
	
	HookEvent("player_death", PlayerDeath, EventHookMode_Pre);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public OnPostThinkPostAnimationFix(client)
{
	new clientview = EntRefToEntIndex(g_PVMid[client]);
	if (clientview == INVALID_ENT_REFERENCE)
	{
		SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPostAnimationFix);
		//PrintToChat(client, "quitado");
		hook[client] = false;
		return;
	}
	
	new Sequence = GetEntProp(clientview, Prop_Send, "m_nSequence");
	new Float:Cycle = GetEntPropFloat(clientview, Prop_Data, "m_flCycle");
	if ((Cycle < OldCycle[client]) && (Sequence == OldSequence[client]))
	{
		if (StrEqual(g_classname[client], "weapon_knife"))
		{
			//PrintToConsole(client, "FIX = secuencia %i",Sequence);
			switch (Sequence)
			{
				case 3:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 4);
				case 4:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 3);
				case 5:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 6);
				case 6:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 5);
				case 7:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 8);
				case 8:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 7);
				case 9:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 10);
				case 10:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 11);
				case 11:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 10);
			}
		}
		else if (StrEqual(g_classname[client], "weapon_ak47"))
		{
			switch (Sequence)
			{
				case 3:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 2);
				case 2:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 1);
				case 1:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 3);
			}
		}
		else if (StrEqual(g_classname[client], "weapon_mp7"))
		{
			switch (Sequence)
			{
				case 3:
				{
					SetEntProp(clientview, Prop_Send, "m_nSequence", -1);
				}
			}
		}
		else if (StrEqual(g_classname[client], "weapon_awp"))
		{
			switch (Sequence)
			{
				case 1:
				{
					SetEntProp(clientview, Prop_Send, "m_nSequence", -1);
				}
			}
		}
		else if (StrEqual(g_classname[client], "weapon_deagle"))
		{
			switch (Sequence)
			{
				case 3:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 2);
				case 2:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 1);
				case 1:
				SetEntProp(clientview, Prop_Send, "m_nSequence", 3);
			}
		}
		//SetEntProp(clientview, Prop_Send, "m_nSequence", Sequence);
	}
	
	OldSequence[client] = Sequence;
	OldCycle[client] = Cycle;
}

public Action Hook_WeaponDrop(int client, int wpnid)
{
	if (wpnid < 1)
	{
		return;
	}
	
	CreateTimer(0.0, SetWorldModel, EntIndexToEntRef(wpnid));
}

public Action SetWorldModel(Handle tmr, any ref)
{
	new wpnid = EntRefToEntIndex(ref);
	
	if (wpnid == INVALID_ENT_REFERENCE || !IsValidEntity(wpnid) || !IsValidEdict(wpnid))
	{
		return;
	}
	
	char globalName[128];
	GetEntPropString(wpnid, Prop_Data, "m_iGlobalname", globalName, sizeof(globalName));
	
	if (StrContains(globalName, "custom", false) != 0)
	{
		return;
	}
	
	ReplaceString(globalName, 64, "custom", "");
	
	char bit[2][128];
	
	ExplodeString(globalName, ";", bit, sizeof(bit), sizeof(bit[]));
	
	if (!StrEqual(bit[1], "none") && strlen(bit[1]) > 2 && IsModelPrecached(bit[1]))
	{
		SetEntityModel(wpnid, bit[1]);
	}
	
	//SetEntProp(wpnid, Prop_Send, "m_hPrevOwner", -1);
	//if(!StrEqual(bit[1], "none")) SetEntProp(wpnid, Prop_Send, "m_iWorldDroppedModelIndex", PrecacheModel(bit[1])); 
	//if(!StrEqual(bit[1], "none")) SetEntPropString(wpnid, Prop_Data, "m_ModelName", bit[1]);
	//PrintToChatAll("model dado %s", bit[1]);	
}

public Action:OnPostWeaponEquip(client, weapon)
{
	if (trie_weapons[client] == null)
	{
		return;
	}
	
	if (weapon < 1 || !IsValidEdict(weapon) || !IsValidEntity(weapon))return;
	
	if (GetEntProp(weapon, Prop_Send, "m_hPrevOwner") > 0)
		return;
	
	decl String:classname[64];
	if (!GetEdictClassname(weapon, classname, 64))return;
	
	char globalName[128];
	GetEntPropString(weapon, Prop_Data, "m_iGlobalname", globalName, sizeof(globalName));
	if (StrContains(globalName, "custom", false) == 0)
	{
		return;
	}
	
	new model_index;
	
	new weaponindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	switch (weaponindex)
	{
		case 60:strcopy(classname, 64, "weapon_m4a1_silencer");
		case 61:strcopy(classname, 64, "weapon_usp_silencer");
		case 63:strcopy(classname, 64, "weapon_cz75a");
		case 64:strcopy(classname, 64, "weapon_revolver");
	}
	
	char classname_world[64];
	Format(classname_world, sizeof(classname_world), "%s_world", classname);
	new model_world;
	if (GetTrieValue(trie_weapons[client], classname_world, model_world) && model_world != -1)
	{
		int iWorldModel = GetEntPropEnt(weapon, Prop_Send, "m_hWeaponWorldModel");
		if (IsValidEdict(iWorldModel))
		{
			SetEntProp(iWorldModel, Prop_Send, "m_nModelIndex", model_world);
		}
	}
	
	char classname_drop[64];
	Format(classname_drop, sizeof(classname_world), "%s_drop", classname);
	char model_drop[128];
	if (GetTrieString(trie_weapons[client], classname_drop, model_drop, 128) && !StrEqual(model_drop, "none"))
	{
		if (!IsModelPrecached(model_drop))PrecacheModel(model_drop);
		
		//SetEntProp(weapon, Prop_Send, "m_iWorldDroppedModelIndex", PrecacheModel(model_drop)); 
		//SetEntPropString(weapon, Prop_Data, "m_ModelName", model_drop);
		//PrintToChatAll("model dado %s", model_drop);
		//Entity_SetModel(weapon, model_drop);
		
		
	}
	
	if (!GetTrieValue(trie_weapons[client], classname, model_index) || model_index == -1)
	{
		return;
	}
	
	Format(globalName, sizeof(globalName), "custom%i;%s", model_index, model_drop)
	DispatchKeyValue(weapon, "globalname", globalName);
}

public void OnClientPutInServer(int client)
{
	//if(IsFakeClient(client)) return;
	
	g_PVMid[client] = INVALID_ENT_REFERENCE;
	hook[client] = false;
	
	trie_weapons[client] = CreateTrie();
	
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);
	SDKHook(client, SDKHook_WeaponSwitch, OnClientWeaponSwitch);
	SDKHook(client, SDKHook_WeaponEquip, OnPostWeaponEquip);
	SDKHook(client, SDKHook_WeaponDropPost, Hook_WeaponDrop);
}

public Action PlayerDeath(Handle event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (hook[client])
	{
		//PrintToChat(client, "quitado");
		SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPostAnimationFix);
		hook[client] = false;
	}
}

public void OnClientWeaponSwitch(int client, int wpnid)
{
	if (hook[client])
	{
		//PrintToChat(client, "quitado");
		SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPostAnimationFix);
		hook[client] = false;
	}
}

public void OnClientWeaponSwitchPost(int client, int wpnid)
{
	if (wpnid < 1)
	{
		return;
	}
	char classname[64];
	
	if (!GetEdictClassname(wpnid, classname, sizeof(classname)))
	{
		return;
	}
	
	if (StrContains(classname, "item", false) == 0)return;
	
	new model_index;
	char globalName[64];
	GetEntPropString(wpnid, Prop_Data, "m_iGlobalname", globalName, sizeof(globalName));
	
	if (StrContains(globalName, "custom", false) != 0)
	{
		return;
	}
	
	ReplaceString(globalName, 64, "custom", "");
	
	decl String:bit[2][128];
	
	ExplodeString(globalName, ";", bit, sizeof bit, sizeof bit[]);
	
	model_index = StringToInt(bit[0]);
	
	SetEntProp(wpnid, Prop_Send, "m_nModelIndex", 0);
	
	new clientview = EntRefToEntIndex(g_PVMid[client]);
	if (clientview == INVALID_ENT_REFERENCE)
	{
		g_PVMid[client] = GetClientPredictedViewmodel(client);
		clientview = EntRefToEntIndex(g_PVMid[client]);
		if (clientview == INVALID_ENT_REFERENCE)
		{
			return;
		}
	}
	
	SetEntProp(clientview, Prop_Send, "m_nModelIndex", model_index);
	
	hook[client] = true;
	
	new weaponindex = GetEntProp(wpnid, Prop_Send, "m_iItemDefinitionIndex");
	switch (weaponindex)
	{
		case 60:strcopy(classname, 64, "weapon_m4a1_silencer");
		case 61:strcopy(classname, 64, "weapon_usp_silencer");
		case 63:strcopy(classname, 64, "weapon_cz75a");
		case 64:strcopy(classname, 64, "weapon_revolver");
	}
	
	Format(g_classname[client], 64, classname);
	SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPostAnimationFix);
}

public void OnClientDisconnect(int client)
{
	if (trie_weapons[client] != INVALID_HANDLE)CloseHandle(trie_weapons[client]);
	
	trie_weapons[client] = INVALID_HANDLE;
}

public Native_AddViewWeapon(Handle:plugin, argc)
{
	char name[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	int model_index = GetNativeCell(3);
	
	if (trie_weapons[client] == INVALID_HANDLE)
		trie_weapons[client] = CreateTrie();
	
	SetTrieValue(trie_weapons[client], name, model_index);
	
	RefreshWeapon(client, name);
	
	Call_StartForward(OnClientView);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushCell(model_index);
	Call_Finish();
}

public Native_AddWorldWeapon(Handle:plugin, argc)
{
	char name[64], world[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	int model_world = GetNativeCell(3);
	
	
	Format(world, 64, "%s_world", name);
	
	if (trie_weapons[client] == INVALID_HANDLE)
		trie_weapons[client] = CreateTrie();
	
	SetTrieValue(trie_weapons[client], world, model_world);
	
	RefreshWeapon(client, name);
	
	Call_StartForward(OnClientWorld);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushCell(model_world);
	Call_Finish();
}

public Native_AddDropWeapon(Handle:plugin, argc)
{
	char name[64], drop[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	
	char model_drop[128]
	GetNativeString(3, model_drop, 64);
	
	
	Format(drop, 64, "%s_drop", name);
	
	if (trie_weapons[client] == INVALID_HANDLE)
		trie_weapons[client] = CreateTrie();
	
	SetTrieString(trie_weapons[client], drop, model_drop);
	
	RefreshWeapon(client, name);
	
	Call_StartForward(OnClientDrop);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushString(model_drop);
	Call_Finish();
}

public int Native_GetWeaponView(Handle:plugin, argc)
{
	char name[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	
	if (trie_weapons[client] == INVALID_HANDLE)
		trie_weapons[client] = CreateTrie();
	
	int arrayindex;
	if (!GetTrieValue(trie_weapons[client], name, arrayindex) || arrayindex == -1)
	{
		return -1;
	}
	
	return arrayindex;
}

public int Native_GetWeaponWorld(Handle:plugin, argc)
{
	char name[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	Format(name, 64, "%s_world", name);
	int arrayindex;
	
	if (trie_weapons[client] == INVALID_HANDLE)
		trie_weapons[client] = CreateTrie();
	
	if (!GetTrieValue(trie_weapons[client], name, arrayindex) || arrayindex == -1)
	{
		return -1;
	}
	
	return arrayindex;
}

public void Native_GetWeaponDrop(Handle:plugin, argc)
{
	char name[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	
	Format(name, 64, "%s_drop", name);
	char arrayindex[128];
	
	if (trie_weapons[client] == INVALID_HANDLE)
		trie_weapons[client] = CreateTrie();
	
	if (!GetTrieString(trie_weapons[client], name, arrayindex, 128))
	{
		SetNativeString(3, "none", 64);
	}
	else SetNativeString(3, arrayindex, 64);
}

public Native_SetWeapon(Handle:plugin, argc)
{
	char name[64], world[64], drop[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	int model_index = GetNativeCell(3);
	int model_world = GetNativeCell(4);
	char model_drop[128];
	GetNativeString(5, model_drop, 128);
	Format(world, 64, "%s_world", name);
	Format(drop, 64, "%s_drop", name);
	
	if (trie_weapons[client] == INVALID_HANDLE)
		trie_weapons[client] = CreateTrie();
	
	SetTrieValue(trie_weapons[client], name, model_index);
	SetTrieValue(trie_weapons[client], world, model_world);
	SetTrieString(trie_weapons[client], drop, model_drop);
	
	RefreshWeapon(client, name);
	
	Call_StartForward(OnClientView);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushCell(model_index);
	Call_Finish();
	
	Call_StartForward(OnClientWorld);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushCell(model_world);
	Call_Finish();
	
	Call_StartForward(OnClientDrop);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushString(model_drop);
	Call_Finish();
}

public Native_RemoveViewWeapon(Handle:plugin, argc)
{
	char name[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	
	if (trie_weapons[client] != INVALID_HANDLE)
		SetTrieValue(trie_weapons[client], name, -1);
	
	RefreshWeapon(client, name);
	
	Call_StartForward(OnClientView);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushCell(-1);
	Call_Finish();
}

public Native_RemoveWorldWeapon(Handle:plugin, argc)
{
	char name[64], world[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	
	Format(world, 64, "%s_world", name);
	if (trie_weapons[client] != INVALID_HANDLE)
		SetTrieValue(trie_weapons[client], world, -1);
	
	RefreshWeapon(client, name);
	
	Call_StartForward(OnClientWorld);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushCell(-1);
	Call_Finish();
}

public Native_RemoveDropWeapon(Handle:plugin, argc)
{
	char name[64], drop[64];
	
	int client = GetNativeCell(1);
	GetNativeString(2, name, 64);
	
	Format(drop, 64, "%s_drop", name);
	if (trie_weapons[client] != INVALID_HANDLE)
		SetTrieString(trie_weapons[client], drop, "none");
	
	RefreshWeapon(client, name);
	
	Call_StartForward(OnClientDrop);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushString("none");
	Call_Finish();
}

void RefreshWeapon(int client, char[] name)
{
	if (!IsPlayerAlive(client))
	{
		return;
	}
	
	int weapon = Client_GetWeapon(client, name);
	
	if (weapon != INVALID_ENT_REFERENCE)
	{
		int ammo1 = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoCount");
		int ammo2 = GetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoCount");
		int clip1 = GetEntProp(weapon, Prop_Data, "m_iClip1");
		int clip2 = GetEntProp(weapon, Prop_Data, "m_iClip2");
		
		RemovePlayerItem(client, weapon);
		AcceptEntityInput(weapon, "Kill");
		
		if (StrEqual(name, "weapon_knife"))
		{
			int zeus = GetPlayerWeaponSlot(client, 2);
			if (zeus != -1)
			{
				RemovePlayerItem(client, zeus);
				AcceptEntityInput(zeus, "Kill");
				weapon = GivePlayerItem(client, name);
				GivePlayerItem(client, "weapon_taser");
			}
			else weapon = GivePlayerItem(client, name);
			
		}
		else {
			weapon = GivePlayerItem(client, name);
		}
		
		if (ammo1 > -1)SetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoCount", ammo1);
		if (ammo2 > -1)SetEntProp(weapon, Prop_Data, "m_iSecondaryAmmoCount", ammo2);
		if (clip1 > -1)SetEntProp(weapon, Prop_Data, "m_iClip1", clip1);
		if (clip2 > -1)SetEntProp(weapon, Prop_Data, "m_iClip2", clip2);
	}
}

int Client_GetWeaponsOffset(int client)
{
	static int offset = -1;
	
	if (offset == -1)
	{
		offset = FindDataMapInfo(client, "m_hMyWeapons");
	}
	
	return offset;
}

int Client_GetWeapon(int client, const char[] className)
{
	int offset = Client_GetWeaponsOffset(client) - 4;
	int weapon = INVALID_ENT_REFERENCE;
	
	for (int i = 0; i < MAX_WEAPONS; i++)
	{
		offset += 4;
		
		weapon = GetEntDataEnt2(client, offset);
		
		if (!Weapon_IsValid(weapon)) {
			continue;
		}
		
		if (Entity_ClassNameMatches(weapon, className)) {
			return weapon;
		}
	}
	
	return INVALID_ENT_REFERENCE;
}

bool Weapon_IsValid(int weapon)
{
	if (!IsValidEdict(weapon)) {
		return false;
	}
	
	return Entity_ClassNameMatches(weapon, "weapon_", true);
}

bool Entity_ClassNameMatches(int entity, const char[] className, bool partialMatch = false)
{
	char entity_className[64];
	GetEntPropString(entity, Prop_Data, "m_iClassname", entity_className, sizeof(entity_className));
	
	if (partialMatch) {
		return (StrContains(entity_className, className) != -1);
	}
	
	return StrEqual(entity_className, className);
}

int GetClientPredictedViewmodel(int client)
{
	static int m_hOwnerOffset;
	if (!m_hOwnerOffset)
	{
		m_hOwnerOffset = FindSendPropInfo("CCSPlayer", "m_hOwner");
	}
	
	int ent = -1;
	while ((ent = FindEntityByClassnameEx(ent, "predicted_viewmodel")) != -1)
	{
		if (GetEntDataEnt2(ent, m_hOwnerOffset) == client)
		{
			return EntIndexToEntRef(ent);
		}
	}
	
	return INVALID_ENT_REFERENCE;
}

int FindEntityByClassnameEx(int startEnt, char[] classname)
{
	while (startEnt > -1 && !IsValidEntity(startEnt))
	{
		startEnt--;
	}
	
	return FindEntityByClassname(startEnt, classname);
}
