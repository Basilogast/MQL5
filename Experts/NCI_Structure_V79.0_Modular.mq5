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
// REMOVED: Dashboard is no longer needed

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   ObjectsDeleteAll(0, "NCI_Zone_");
   ObjectsDeleteAll(0, "NCI_Flip_");
   
   // --- OPTION B: Initialize Global Variables (F3 Menu) ---
   // If they don't exist yet, create them and set to 1 (ON)
   if(!GlobalVariableCheck("NCI_Show_HTF")) GlobalVariableSet("NCI_Show_HTF", 1);
   if(!GlobalVariableCheck("NCI_Show_LTF")) GlobalVariableSet("NCI_Show_LTF", 1);
   
   // --- 1. Update HTF (H1) Logic ---
   UpdateZigZagMap(TimeFrame_HTF, ZigZagPoints_HTF, currentMarketTrend_HTF, "_HTF");
   DrawParallelZones(TimeFrame_HTF, ZigZagPoints_HTF, activeSupply_HTF, activeDemand_HTF, activeFlippedSupply_HTF, activeFlippedDemand_HTF, "_HTF");

   // --- 2. Update LTF (M15) Logic ---
   UpdateZigZagMap(TimeFrame_LTF, ZigZagPoints_LTF, currentMarketTrend_LTF, "_LTF");
   DrawParallelZones(TimeFrame_LTF, ZigZagPoints_LTF, activeSupply_LTF, activeDemand_LTF, activeFlippedSupply_LTF, activeFlippedDemand_LTF, "_LTF");
   
   Print(">>> V79.0 GLOBAL VAR CONTROL: Loaded. Press F3 to toggle NCI_Show_HTF/LTF.");
   return(INIT_SUCCEEDED);
}

// REMOVED: OnChartEvent is not needed for Option B

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageTradeState();       
   ManageOpenPositions();    
   
   // --- OPTION B: Check for F3 Menu Changes ---
   bool newShowHTF = (GlobalVariableGet("NCI_Show_HTF") != 0);
   bool newShowLTF = (GlobalVariableGet("NCI_Show_LTF") != 0);
   
   // Detect if you changed the F3 value since the last tick
   if (newShowHTF != ShowHTF || newShowLTF != ShowLTF) {
      ShowHTF = newShowHTF;
      ShowLTF = newShowLTF;
      
      // Force Redraw immediately
      DrawZigZagLines("_HTF", ZigZagPoints_HTF);
      DrawParallelZones(TimeFrame_HTF, ZigZagPoints_HTF, activeSupply_HTF, activeDemand_HTF, activeFlippedSupply_HTF, activeFlippedDemand_HTF, "_HTF");
      
      DrawZigZagLines("_LTF", ZigZagPoints_LTF);
      DrawParallelZones(TimeFrame_LTF, ZigZagPoints_LTF, activeSupply_LTF, activeDemand_LTF, activeFlippedSupply_LTF, activeFlippedDemand_LTF, "_LTF");
      
      ChartRedraw();
   }
   
   if(IsNewBar()) {
      // Refresh HTF (H1)
      UpdateZigZagMap(TimeFrame_HTF, ZigZagPoints_HTF, currentMarketTrend_HTF, "_HTF");
      DrawParallelZones(TimeFrame_HTF, ZigZagPoints_HTF, activeSupply_HTF, activeDemand_HTF, activeFlippedSupply_HTF, activeFlippedDemand_HTF, "_HTF");
      
      // Refresh LTF (M15)
      UpdateZigZagMap(TimeFrame_LTF, ZigZagPoints_LTF, currentMarketTrend_LTF, "_LTF");
      DrawParallelZones(TimeFrame_LTF, ZigZagPoints_LTF, activeSupply_LTF, activeDemand_LTF, activeFlippedSupply_LTF, activeFlippedDemand_LTF, "_LTF");
   }

   if(AllowTrading) CheckTradeEntry();
}
//+------------------------------------------------------------------+