//+------------------------------------------------------------------+
//|         NCI_Structure_V79.0_Modular.mq5                          |
//|         Copyright 2024, NCI Strategy                             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "79.01"
#property strict

// 1. Include Standard Library
#include <Trade\Trade.mqh>

// 2. Include Modules (Sequence is Critical)
#include <NCI_Strategy\NCI_Constants.mqh>
#include <NCI_Strategy\NCI_Structs.mqh>
#include <NCI_Strategy\NCI_Helpers.mqh>
#include <NCI_Strategy\NCI_ZigZag.mqh>
#include <NCI_Strategy\NCI_Zones.mqh>
#include <NCI_Strategy\NCI_Trade.mqh>

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   ObjectsDeleteAll(0, "NCI_Zone_");
   ObjectsDeleteAll(0, "NCI_Flip_");
   
   // --- CRITICAL FIX: Run BOTH calculations on startup ---
   UpdateZigZagMap();   // 1. Calculate Points
   DrawParallelZones(); // 2. Draw Zones & Update Logic State
   
   Print(">>> V79.0 MODULAR INIT: System Loaded Successfully.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageTradeState();       
   ManageOpenPositions();    
   
   // --- CRITICAL FIX: Run BOTH calculations on new bar ---
   if(IsNewBar()) {
      UpdateZigZagMap();   // 1. Calculate new ZigZag points
      DrawParallelZones(); // 2. Update Zones based on new points
   }
   
   if(AllowTrading) CheckTradeEntry();
}
//+------------------------------------------------------------------+