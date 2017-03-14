/*  SM Cs 1.6 HnS Style
 *
 *  Copyright (C) 2017 Francisco 'Franc1sco' García
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

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <flashtools>

new Handle:CT_Time;
new Handle:CT_TimeF;
new Handle:Countdown;
new bool:tiempo_activo = false;
new Veces;

#define VERSION "b2.8"

#define SOUND_FREEZE	"physics/glass/glass_impact_bullet4.wav"
#define SOUND_FREEZE_EXPLODE	"ui/freeze_cam.wav"

#define SmokeColor	{75,255,75,255}
#define FreezeColor	{75,75,255,255}

new BeamSprite, GlowSprite, g_beamsprite, g_halosprite;

new maxents;


new Handle:Trails;
new Handle:SmokeFreeze;
new Handle:SmokeFreezeDistance;
new Handle:SmokeFreezeDuration;
new Handle:FreezeTimer[MAXPLAYERS+1];

new bool:g_Noweapons[MAXPLAYERS+1] = {false, ...};

new bool:IsFreezed[MAXPLAYERS+1];
new bool:trails, bool:freezegren;

new Float:freezedistance, Float:freezeduration;




public Plugin:myinfo = 
{
	name = "SM Cs 1.6 HnS Style",
	author = "Franc1sco Steam: franug",
	description = "Cs 1.6 HnS Style",
	version = VERSION,
	url = "http://steamcommunity.com/id/franug"
};

public OnPluginStart()
{

	CreateConVar("sm_cshns_version", VERSION, "version del plugin", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);

        // code of freeze grenades by http://forums.alliedmods.net/showthread.php?t=159579
	Trails = CreateConVar("hns_greneffect_trails", "1", "Enables/Disables Grenade Trails", 0, true, 0.0, true, 1.0);
	SmokeFreeze = CreateConVar("cshns_greneffect_smoke_freeze", "1", "Enables/Disables a smoke grenade to be a freeze grenade", 0, true, 0.0, true, 1.0);
	SmokeFreezeDistance = CreateConVar("cshns_greneffect_smoke_freeze_distance", "600.0", "Freeze grenade distance", 0, true, 100.0);
	SmokeFreezeDuration = CreateConVar("cshns_greneffect_smoke_freeze_duration", "7.0", "Freeze grenade duration in seconds", 0, true, 1.0);
	
        CT_Time = CreateConVar("sm_cshns_time", "180.0", "Time for slay all CT");
        CT_TimeF = CreateConVar("sm_cshns_time_freeze", "10.0", "Time freeze for CT in round start");
        Countdown = CreateConVar("sm_cshns_countdown", "10", "Time for the countdown");
	HookEvent("smokegrenade_detonate", SmokeDetonate);
	AddNormalSoundHook(NormalSHook);

        HookEvent("round_start", Event_RoundStart);

	HookEvent("round_end", EventRoundEnd);

	HookEvent("player_spawn", Event_Player_Spawn, EventHookMode_Post);
}


public OnMapStart() 
{
	BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	GlowSprite = PrecacheModel("sprites/blueglow2.vmt");
	g_beamsprite = PrecacheModel("materials/sprites/lgtning.vmt");
	g_halosprite = PrecacheModel("materials/sprites/halo01.vmt");
	
	PrecacheSound(SOUND_FREEZE);
	PrecacheSound(SOUND_FREEZE_EXPLODE);

	decl String:szClass[65];
        for (new i = MaxClients; i <= GetMaxEntities(); i++)
        {
          if(IsValidEdict(i) && IsValidEntity(i))
          {
            GetEdictClassname(i, szClass, sizeof(szClass));
            if(StrEqual("func_buyzone", szClass) || StrEqual("hostage_entity", szClass) || StrEqual("func_bomb_target", szClass))
            {
                RemoveEdict(i);
            }
          }
        }

        // simple force cvars
        ServerCommand("mp_freezetime 0"); 
        ServerCommand("mp_roundtime %i", GetConVarInt(CT_Time)/60); 


}

public OnConfigsExecuted()
{
	trails = GetConVarBool(Trails);
	freezegren = GetConVarBool(SmokeFreeze);

	freezedistance = GetConVarFloat(SmokeFreezeDistance);
	freezeduration = GetConVarFloat(SmokeFreezeDuration);
}

public OnClientDisconnect_Post(client)
{
	IsFreezed[client] = false;
	if (FreezeTimer[client] != INVALID_HANDLE)
	{
		KillTimer(FreezeTimer[client]);
		FreezeTimer[client] = INVALID_HANDLE;
	}
}


public Action:SmokeDetonate(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if (!freezegren)
		return;
	
	decl String:EdictName[64];
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	maxents = GetMaxEntities();
	
	for (new edict = MaxClients; edict <= maxents; edict++)
	{
		if (IsValidEdict(edict))
		{
			GetEdictClassname(edict, EdictName, sizeof(EdictName));
			if (!strcmp(EdictName, "smokegrenade_projectile", false))
				if (GetEntPropEnt(edict, Prop_Send, "m_hThrower") == client)
					AcceptEntityInput(edict, "Kill");
		}
	}
	
	new Float:DetonateOrigin[3];
	DetonateOrigin[0] = GetEventFloat(event, "x"); 
	DetonateOrigin[1] = GetEventFloat(event, "y"); 
	DetonateOrigin[2] = GetEventFloat(event, "z");
	
	DetonateOrigin[2] += 30.0;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(client) != GetClientTeam(i))
		{
			new Float:targetOrigin[3];
			GetClientAbsOrigin(i, targetOrigin);
			
			if (GetVectorDistance(DetonateOrigin, targetOrigin) <= freezedistance)
			{
				new Handle:trace = TR_TraceRayFilterEx(DetonateOrigin, targetOrigin, MASK_SHOT, RayType_EndPoint, FilterTarget, i);
			
				if (TR_DidHit(trace))
				{
					if (TR_GetEntityIndex(trace) == i)
						Freeze(i, freezeduration);
				}
				else
				{
					GetClientEyePosition(i, targetOrigin);
					targetOrigin[2] -= 1.0;
			
					if (GetVectorDistance(DetonateOrigin, targetOrigin) <= freezedistance)
					{
						new Handle:trace2 = TR_TraceRayFilterEx(DetonateOrigin, targetOrigin, MASK_SHOT, RayType_EndPoint, FilterTarget, i);
				
						if (TR_DidHit(trace2))
						{
							if (TR_GetEntityIndex(trace2) == i)
								Freeze(i, freezeduration);
						}
						CloseHandle(trace2);
					}
				}
				CloseHandle(trace);
			}
		}
	}
	
	TE_SetupBeamRingPoint(DetonateOrigin, 10.0, freezedistance, g_beamsprite, g_halosprite, 1, 10, 1.0, 5.0, 1.0, FreezeColor, 0, 0);
	TE_SendToAll();
	LightCreate(DetonateOrigin);
}

public bool:FilterTarget(entity, contentsMask, any:data)
{
	return (data == entity);
} 

Freeze(client, Float:time)
{
	if (FreezeTimer[client] != INVALID_HANDLE)
	{
		KillTimer(FreezeTimer[client]);
		FreezeTimer[client] = INVALID_HANDLE;
	}
		
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.0);
	
	new Float:vec[3];
	GetClientEyePosition(client, vec);
	EmitAmbientSound(SOUND_FREEZE, vec, client, SNDLEVEL_RAIDSIREN);

	TE_SetupGlowSprite(vec, GlowSprite, time, 1.5, 50);
	TE_SendToAll();
	IsFreezed[client] = true;
	FreezeTimer[client] = CreateTimer(time, Unfreeze, client);
}


public Action:Unfreeze(Handle:timer, any:client)
{
	if (IsFreezed[client])
	{
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
		IsFreezed[client] = false;
		FreezeTimer[client] = INVALID_HANDLE;
	}
}

public OnEntityCreated(Entity, const String:Classname[])
{

		
	if(StrEqual(Classname, "smokegrenade_projectile"))
	{
		if (freezegren)
		{
			BeamFollowCreate(Entity, FreezeColor);
			CreateTimer(2.0, SmokeCreateEvent, Entity, TIMER_FLAG_NO_MAPCHANGE);
		}
		else
			BeamFollowCreate(Entity, SmokeColor);
	}
	else if(freezegren && StrEqual(Classname, "env_particlesmokegrenade") && freezegren)
		AcceptEntityInput(Entity, "Kill");
}

public Action:SmokeCreateEvent(Handle:timer, any:entity)
{
	if (IsValidEdict(entity) && IsValidEntity(entity))
	{
		decl String:clsname[64];
		GetEdictClassname(entity, clsname, sizeof(clsname));
		if (!strcmp(clsname, "smokegrenade_projectile", false))
		{
			new Float:SmokeOrigin[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", SmokeOrigin);
			new client = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
                        new userid = 0;
                        if(IsValidClient(client))
                        {
			    userid = GetClientUserId(client);
                        }
//                        else
//                        {

                        //}
		
			new Handle:event = CreateEvent("smokegrenade_detonate");
		
			SetEventInt(event, "userid", userid);
			SetEventFloat(event, "x", SmokeOrigin[0]);
			SetEventFloat(event, "y", SmokeOrigin[1]);
			SetEventFloat(event, "z", SmokeOrigin[2]);
			FireEvent(event);
		}
	}
}
		
BeamFollowCreate(Entity, Color[4])
{
	if (trails)
	{
		TE_SetupBeamFollow(Entity, BeamSprite,	0, Float:1.0, Float:10.0, Float:10.0, 5, Color);
		TE_SendToAll();	
	}
}


public Action:Delete(Handle:timer, any:entity)
{
	if(IsValidEdict(entity))
		AcceptEntityInput(entity, "kill");
}

public Action:NormalSHook(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
	if(freezegren && StrEqual(sample, "^weapons/smokegrenade/sg_explode.wav"))
		return Plugin_Handled;
	return Plugin_Continue;
}

LightCreate(Float:Pos[3])   
{  
	new iEntity = CreateEntityByName("light_dynamic");
	DispatchKeyValue(iEntity, "inner_cone", "0");
	DispatchKeyValue(iEntity, "cone", "80");
	DispatchKeyValue(iEntity, "brightness", "1");
	DispatchKeyValueFloat(iEntity, "spotlight_radius", 150.0);
	DispatchKeyValue(iEntity, "pitch", "90");
	DispatchKeyValue(iEntity, "style", "1");

	DispatchKeyValue(iEntity, "_light", "75 75 255 255");
	DispatchKeyValueFloat(iEntity, "distance", freezedistance);
	EmitSoundToAll(SOUND_FREEZE_EXPLODE, iEntity, SNDCHAN_WEAPON);
	CreateTimer(1.0, Delete, iEntity, TIMER_FLAG_NO_MAPCHANGE);

	DispatchSpawn(iEntity);
	TeleportEntity(iEntity, Pos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(iEntity, "TurnOn");
}

public Action:Event_Player_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
        new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (GetClientTeam(client) != 1 && IsPlayerAlive(client))
	{
                if (GetClientTeam(client) == CS_TEAM_CT)
                {
                    g_Noweapons[client] = false;



                    new wepIdx;

                    // strip all weapons
                    for (new s = 0; s < 4; s++)
                    {
                        if ((wepIdx = GetPlayerWeaponSlot(client, s)) != -1)
                        {
		                 RemovePlayerItem(client, wepIdx);
		                 RemoveEdict(wepIdx);
                        }
                    }
                    GivePlayerItem(client, "weapon_knife");
                    g_Noweapons[client] = true;

                    Freeze(client, GetConVarInt(CT_TimeF) * 1.0);
                    Blinded_Vision(client);
                    CreateTimer(GetConVarInt(CT_TimeF) * 1.0, NoBlind, client);

                }
                else if (GetClientTeam(client) == CS_TEAM_T)
                {
                    g_Noweapons[client] = false;

                    new wepIdx;

                    // strip all weapons
                    for (new s = 0; s < 4; s++)
                    {
                        if ((wepIdx = GetPlayerWeaponSlot(client, s)) != -1)
                        {
		                 RemovePlayerItem(client, wepIdx);
		                 RemoveEdict(wepIdx);
                        }
                    }
                    GivePlayerItem(client, "weapon_knife");
                    GivePlayerItem(client, "weapon_flashbang");
                    GivePlayerItem(client, "weapon_flashbang");
                    GivePlayerItem(client, "weapon_smokegrenade");
                    g_Noweapons[client] = true;
                }
	}
}


public OnClientPutInServer(client)
{
   SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
   SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
}

public Action:OnWeaponCanUse(client, weapon)
{
  if (g_Noweapons[client])
  {
      return Plugin_Handled;
  }
  return Plugin_Continue;
}

public IsValidClient( client ) 
{ 
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) 
        return false; 
     
    return true; 
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
      if (IsValidClient(attacker))
      {
          //if (GetClientTeam(attacker) == CS_TEAM_CT && GetClientTeam(victim) == CS_TEAM_T)
          //{
//
//                        damage = 50.0;
//                        return Plugin_Changed;
//	  }
          if (GetClientTeam(attacker) == CS_TEAM_T && GetClientTeam(victim) == CS_TEAM_CT)
          {
                        return Plugin_Handled;
	  }
      }

      return Plugin_Continue;
}

public Action:EventRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
                tiempo_activo = false;
		new winner = GetEventInt(event, "winner");
		if (winner == CS_TEAM_CT)
		{
                     for(new i = 1; i <= MaxClients; i++) 
                     if(IsValidClient(i))
                     {
                         if (GetClientTeam(i) == CS_TEAM_T)
                         {
                             CS_SwitchTeam(i, 3);
                         }
                         else if (GetClientTeam(i) == CS_TEAM_CT)
                         {
                             CS_SwitchTeam(i, 2);
                         }
                     } 
		}
                
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
        tiempo_activo = true;

        Veces = GetConVarInt(CT_Time);
        CreateTimer(1.0, Repetidor, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	decl String:szClass[65];
        for (new i = MaxClients; i <= GetMaxEntities(); i++)
        {
          if(IsValidEdict(i) && IsValidEntity(i))
          {
            GetEdictClassname(i, szClass, sizeof(szClass));
            if(StrEqual("func_buyzone", szClass) || StrEqual("hostage_entity", szClass) || StrEqual("func_bomb_target", szClass))
            {
                RemoveEdict(i);
            }
          }
        } 

        // simple force cvars :)
        ServerCommand("mp_freezetime 0"); 
        ServerCommand("mp_roundtime %i", GetConVarInt(CT_Time)/60);

        // test
        //PrintToChatAll("%i", GetConVarInt(CT_Time)/60);
}

public Action:NoBlind(Handle:timer, any:client)
{

             Normal_Vision(client);
}

public Action:Repetidor(Handle:timer)
{
        if (Veces == 0)
	{
                tiempo_activo = false;
                Win_Ts_Call();
		return Plugin_Stop;
	}

        else if(!tiempo_activo)
        {
	        return Plugin_Stop;
        }
        else if(Veces < GetConVarInt(Countdown))
        {
	        PrintCenterTextAll("Ts wins in %d seconds! hurry up CTs!", Veces);
        }

        Veces -= 1;

	return Plugin_Continue;
}

public Action:Win_Ts_Call()
{
      for (new i = 1; i < GetMaxClients(); i++)
      {
	if (IsValidClient(i) && IsPlayerAlive(i))
	{
            if(GetClientTeam(i) == CS_TEAM_T)
            {
                 new kills = GetEntProp(i, Prop_Data, "m_iFrags");
		 SetEntProp(i, Prop_Data, "m_iFrags", kills+1);
            }
            else if(GetClientTeam(i) == CS_TEAM_CT)
            {
                 ForcePlayerSuicide(i);
            }
        }
      }
      PrintToChatAll("\x04[CsHnS] \x01The terrorists win");
}

  

public Action:OnGetPercentageOfFlashForPlayer(client, entity, Float:pos[3], &Float:percent)
{
    new team = GetClientTeam(client);
    //Dont team flash but flash the owner
    if(team == 2)
    {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}


//public Action:OnPlayerRunCmd(iClient, &iButtons, &Impulse, Float:fVelocity[3], Float:fAngles[3], &iWeapon)
//{
//	if(IsValidClient(iClient) && IsPlayerAlive(iClient) && GetClientTeam(iClient) == CS_TEAM_CT && iButtons  & IN_ATTACK)
//	{
//		return Plugin_Handled;
//	}
//        return Plugin_Continue;
//}

stock Blinded_Vision(const any:client)
{
	if(IsValidClient(client))
	{

	        new Handle:message = StartMessageOne("Fade", client, 1);
	


		
		
	        BfWriteShort(message, 1536);
	        BfWriteShort(message, 1536);
		BfWriteShort(message, (0x0002 | 0x0008));
		BfWriteByte(message, 0); //fade red
		BfWriteByte(message, 0); //fade green
		BfWriteByte(message, 0); //fade blue
		BfWriteByte(message, 255); //fade alpha
		EndMessage();
	}
}

stock Normal_Vision(const any:client)
{
	if(IsValidClient(client))
	{
	        new Handle:message = StartMessageOne("Fade", client, 1);
	

		
		
	        BfWriteShort(message, 1536);
	        BfWriteShort(message, 1536);
                BfWriteShort(message, (0x0001 | 0x0010));
		BfWriteByte(message, 0); //fade red
		BfWriteByte(message, 0); //fade green
		BfWriteByte(message, 0); //fade blue
		BfWriteByte(message, 0); //fade alpha
		EndMessage();
	}
}


