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
   
   // --- 1. Update HTF (H1) Logic ---
   // We pass the H1 variables so they get filled with H1 data
   UpdateZigZagMap(TimeFrame_HTF, ZigZagPoints_HTF, currentMarketTrend_HTF, "_HTF");
   DrawParallelZones(TimeFrame_HTF, ZigZagPoints_HTF, activeSupply_HTF, activeDemand_HTF, activeFlippedSupply_HTF, activeFlippedDemand_HTF, "_HTF");

   // --- 2. Update LTF (M15) Logic ---
   // We pass the M15 variables so they get filled with M15 data
   UpdateZigZagMap(TimeFrame_LTF, ZigZagPoints_LTF, currentMarketTrend_LTF, "_LTF");
   DrawParallelZones(TimeFrame_LTF, ZigZagPoints_LTF, activeSupply_LTF, activeDemand_LTF, activeFlippedSupply_LTF, activeFlippedDemand_LTF, "_LTF");
   
   Print(">>> V79.0 DUAL TIMEFRAME INIT: Loaded Successfully.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageTradeState();       
   ManageOpenPositions();    
   
   if(IsNewBar()) {
      // Refresh HTF (H1)
      UpdateZigZagMap(TimeFrame_HTF, ZigZagPoints_HTF, currentMarketTrend_HTF, "_HTF");
      DrawParallelZones(TimeFrame_HTF, ZigZagPoints_HTF, activeSupply_HTF, activeDemand_HTF, activeFlippedSupply_HTF, activeFlippedDemand_HTF, "_HTF");
      
      // Refresh LTF (M15)
      UpdateZigZagMap(TimeFrame_LTF, ZigZagPoints_LTF, currentMarketTrend_LTF, "_LTF");
      DrawParallelZones(TimeFrame_LTF, ZigZagPoints_LTF, activeSupply_LTF, activeDemand_LTF, activeFlippedSupply_LTF, activeFlippedDemand_LTF, "_LTF");
   }

   // CheckTradeEntry now looks at BOTH lists inside NCI_Trade.mqh
   if(AllowTrading) CheckTradeEntry();
}
//+------------------------------------------------------------------+