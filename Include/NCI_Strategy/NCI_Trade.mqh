//+------------------------------------------------------------------+
//| NCI_Trade.mqh - Execution & Management                           |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh" 

// --- HELPER: CHECK ZONE OVERLAP ---
bool IsOverlapping(MergedZoneState &z1, MergedZoneState &z2) {
   if (!z1.isActive || !z2.isActive) return false;
   return (MathMax(z1.bottom, z2.bottom) <= MathMin(z1.top, z2.top));
}

void OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp, string comment, double finalRiskPercent)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (finalRiskPercent / 100.0); 
   double riskPoints = MathAbs(price - sl) / _Point;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if (riskPoints <= 0 || tickValue == 0) return;
   double lotSize = NormalizeDouble(riskAmount / (riskPoints * tickValue), 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if (lotSize < minLot) lotSize = minLot;
   if (lotSize > maxLot) lotSize = maxLot;
   
   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, "NCI V79.0 " + comment)) {
      CurrentOpenTicket = trade.ResultOrder();
      CurrentZoneTradeCount++; 
   }
}

// *** UPDATED: Now accepts 'slZone' to separate Entry Zone from Stop Loss Zone ***
void ExecuteEntryLogic(MergedZoneState &entryZone, MergedZoneState &slZone, MergedZoneState &opposingSupply, MergedZoneState &opposingDemand, int type, bool isBreakout, string commentTag, double refPips)
{
   datetime relevantTime = entryZone.startTime;
   if (relevantTime != CurrentZoneID) {
      CurrentZoneID = relevantTime; 
      ZoneIsBurned = false;        
      CurrentZoneTradeCount = 0;
   }
   
   if (ZoneIsBurned) return; 

   double tradeRisk = RiskPercent;
   if (EntryMode == MODE_SINGLE) 
   {
      if (CurrentZoneTradeCount > 0) return;
      tradeRisk = RiskPercent;
   }
   else if (EntryMode == MODE_DOUBLE) 
   {
      if (CurrentZoneTradeCount == 0) tradeRisk = RiskPercent;
      else if (CurrentZoneTradeCount == 1) tradeRisk = RiskPercent * 0.5;
      else return;
   }
   else if (EntryMode == MODE_INFINITE) tradeRisk = RiskPercent;

   if (UseVolatilityGuard) { if (!CheckVolatility()) return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // --- 1. Calculate ENTRY based on the ENTRY ZONE (Sniper) ---
   double zoneHeightPrice = entryZone.top - entryZone.bottom;
   double zoneHeightPips = zoneHeightPrice / point;
   if (zoneHeightPips <= 0) zoneHeightPips = 1;
   
   double scalingFactor = refPips / zoneHeightPips;
   
   double dynamicEntryPct = BaseEntryDepth * scalingFactor;
   double dynamicMaxPct   = BaseMaxDepth * scalingFactor;
   if (dynamicEntryPct < 0.05) dynamicEntryPct = 0.05;
   if (dynamicEntryPct > 0.60) dynamicEntryPct = 0.60;
   if (dynamicMaxPct < 0.10) dynamicMaxPct = 0.10;
   if (dynamicMaxPct > 0.80) dynamicMaxPct = 0.80;

   // --- 2. Calculate BUFFER ---
   double finalBuffer = BaseBufferPoints;
   if (UseDynamicBuffer) {
      finalBuffer = BaseBufferPoints * scalingFactor * (1.0 + dynamicEntryPct);
      if (finalBuffer < MinBufferPoints) finalBuffer = MinBufferPoints;
      if (finalBuffer > MaxBufferPoints) finalBuffer = MaxBufferPoints;
   }

   if (type == 1) // Buy
   {
      double entryPriceStart = entryZone.top - (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = entryZone.top - (zoneHeightPrice * dynamicMaxPct);   
      
      if (ask <= entryPriceStart && ask >= entryPriceLimit) 
      {
         // *** FIX: SL is now calculated based on the SL ZONE (HTF or LTF) ***
         double sl = slZone.bottom - (finalBuffer * point);
         
         double tp = opposingSupply.bottom + ((opposingSupply.top - opposingSupply.bottom) * TPZoneDepth); 
         double risk = entryPriceStart - sl;
         double reward = tp - entryPriceStart;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, isBreakout ? "Breakout " + commentTag : "Standard " + commentTag, tradeRisk);
         }
      }
   }
   else if (type == -1) // Sell
   {
      double entryPriceStart = entryZone.bottom + (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = entryZone.bottom + (zoneHeightPrice * dynamicMaxPct);   
      
      if (bid >= entryPriceStart && bid <= entryPriceLimit) 
      {
         // *** FIX: SL is now calculated based on the SL ZONE (HTF or LTF) ***
         double sl = slZone.top + (finalBuffer * point);
         
         double tp = opposingDemand.top - ((opposingDemand.top - opposingDemand.bottom) * TPZoneDepth);
         double risk = sl - entryPriceStart;
         double reward = entryPriceStart - tp;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, isBreakout ? "Breakout " + commentTag : "Standard " + commentTag, tradeRisk);
         }
      }
   }
}

void CheckTradeEntry()
{
   if (PositionsTotal() > 0) return;
   if (!AllowTrading) return;

   // =========================================================
   // SECTOR B: ADVANCED STRATEGY (ZiZ SNIPER MODE)
   // =========================================================
   if (Enable_ZiZ_Mode) {
      
      // 1. ZiZ TREND ENTRIES
      if (ZiZ_AllowTrend) {
         // BUY: LTF Demand inside HTF Demand
         if (activeDemand_LTF.isActive && IsOverlapping(activeDemand_LTF, activeDemand_HTF)) {
             
             // DYNAMIC SL LOGIC (HTF DOMINANCE):
             if (currentMarketTrend_HTF == 1) {
                 // CASE A: HTF Swing (Aligned) -> Target HTF Supply, PROTECT with HTF Demand (Safe SL)
                 // Entry: LTF Zone | SL: HTF Zone | TP: HTF Zone
                 ExecuteEntryLogic(activeDemand_LTF, activeDemand_HTF, activeSupply_HTF, activeDemand_LTF, 1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
             } else {
                 // CASE B: Scalp (Misaligned) -> Target LTF Supply, Protect with LTF Demand (Tight SL)
                 ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
         
         // SELL: LTF Supply inside HTF Supply
         if (activeSupply_LTF.isActive && IsOverlapping(activeSupply_LTF, activeSupply_HTF)) {
             
             // DYNAMIC SL LOGIC (HTF DOMINANCE):
             if (currentMarketTrend_HTF == -1) {
                 // CASE A: HTF Swing (Aligned) -> Target HTF Demand, PROTECT with HTF Supply (Safe SL)
                 // Entry: LTF Zone | SL: HTF Zone | TP: HTF Zone
                 ExecuteEntryLogic(activeSupply_LTF, activeSupply_HTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
             } else {
                 // CASE B: Scalp (Misaligned) -> Target LTF Demand, Protect with LTF Supply (Tight SL)
                 ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
      }
      
      // 2. ZiZ BREAKOUT ENTRIES (Flip Zone inside HTF Zone)
      if (ZiZ_AllowBreakout) {
         // Breakouts remain standard (LTF SL / LTF TP)
         if (activeFlippedDemand_LTF.isActive && activeFlippedDemand_LTF.endTime == 0 && IsOverlapping(activeFlippedDemand_LTF, activeDemand_HTF)) {
             ExecuteEntryLogic(activeFlippedDemand_LTF, activeFlippedDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, true, "ZiZ-Breakout", ReferenceZonePips_LTF);
         }
         if (activeFlippedSupply_LTF.isActive && activeFlippedSupply_LTF.endTime == 0 && IsOverlapping(activeFlippedSupply_LTF, activeSupply_HTF)) {
             ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, true, "ZiZ-Breakout", ReferenceZonePips_LTF);
         }
      }
      return; 
   }

   // =========================================================
   // SECTOR A: SIMPLE STRATEGY (SCATTERGUN MODE)
   // =========================================================
   if (Enable_Simple_Mode) {
      // NOTE: In Simple Mode, SL Zone is always the same as Entry Zone.
      
      // --- 1. SIMPLE HTF TRADES ---
      if (Simple_Trade_HTF) { 
          if (Simple_Trend_HTF && activeSupply_HTF.isActive && activeDemand_HTF.isActive) { 
             if (currentMarketTrend_HTF == 1) ExecuteEntryLogic(activeDemand_HTF, activeDemand_HTF, activeSupply_HTF, activeDemand_HTF, 1, false, "HTF", ReferenceZonePips_HTF);
             else if (currentMarketTrend_HTF == -1) ExecuteEntryLogic(activeSupply_HTF, activeSupply_HTF, activeSupply_HTF, activeDemand_HTF, -1, false, "HTF", ReferenceZonePips_HTF);
          }
          if (Simple_Breakout_HTF) { 
             if (activeFlippedSupply_HTF.isActive && activeDemand_HTF.isActive && activeFlippedSupply_HTF.endTime == 0) 
                ExecuteEntryLogic(activeFlippedSupply_HTF, activeFlippedSupply_HTF, activeSupply_HTF, activeDemand_HTF, -1, true, "HTF", ReferenceZonePips_HTF);
             if (activeFlippedDemand_HTF.isActive && activeSupply_HTF.isActive && activeFlippedDemand_HTF.endTime == 0) 
                ExecuteEntryLogic(activeFlippedDemand_HTF, activeFlippedDemand_HTF, activeSupply_HTF, activeDemand_HTF, 1, true, "HTF", ReferenceZonePips_HTF);
          }
      }

      // --- 2. SIMPLE LTF TRADES ---
      if (Simple_Trade_LTF) { 
          bool allowBuys = true;
          bool allowSells = true;
          
          if (Simple_UseTrendAlign) {
              if (currentMarketTrend_HTF == 1) { allowBuys = true; allowSells = false; } 
              else if (currentMarketTrend_HTF == -1) { allowBuys = false; allowSells = true; } 
              else { allowBuys = false; allowSells = false; }
          }

          if (Simple_Trend_LTF && activeSupply_LTF.isActive && activeDemand_LTF.isActive) { 
             if (currentMarketTrend_LTF == 1 && allowBuys) 
                 ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "LTF", ReferenceZonePips_LTF);
             else if (currentMarketTrend_LTF == -1 && allowSells) 
                 ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, false, "LTF", ReferenceZonePips_LTF);
          }
          if (Simple_Breakout_LTF) { 
             if (activeFlippedSupply_LTF.isActive && activeDemand_LTF.isActive && activeFlippedSupply_LTF.endTime == 0) {
                if (allowSells)
                    ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, true, "LTF", ReferenceZonePips_LTF);
             }
             if (activeFlippedDemand_LTF.isActive && activeSupply_LTF.isActive && activeFlippedDemand_LTF.endTime == 0) {
                if (allowBuys)
                    ExecuteEntryLogic(activeFlippedDemand_LTF, activeFlippedDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, true, "LTF", ReferenceZonePips_LTF);
             }
          }
      }
   }
}

void ManageOpenPositions() { 
   if (!EnableProfitLocking) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--) { 
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue; 
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue; 
      if(PositionGetInteger(POSITION_MAGIC) != 111222) continue; 
      long openTime = PositionGetInteger(POSITION_TIME); 
      long updateTime = PositionGetInteger(POSITION_TIME_UPDATE);
      if (updateTime > openTime) continue; 
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN); 
      double currentTP = PositionGetDouble(POSITION_TP); 
      double currentPrice = 0;
      long type = PositionGetInteger(POSITION_TYPE); 
      if (currentTP == 0) continue; 
      if (type == POSITION_TYPE_BUY) { 
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double totalProfitDist = currentTP - openPrice; 
         if (totalProfitDist <= 0) continue; 
         double triggerPrice = openPrice + (totalProfitDist * LockTriggerPercent);
         if (currentPrice >= triggerPrice) { 
            double newSL = openPrice + (totalProfitDist * LockPositionPercent);
            if (newSL > PositionGetDouble(POSITION_SL) + _Point) trade.PositionModify(ticket, newSL, currentTP); 
         } 
      } else if (type == POSITION_TYPE_SELL) { 
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double totalProfitDist = openPrice - currentTP; 
         if (totalProfitDist <= 0) continue; 
         double triggerPrice = openPrice - (totalProfitDist * LockTriggerPercent);
         if (currentPrice <= triggerPrice) { 
            double newSL = openPrice - (totalProfitDist * LockPositionPercent);
            if (newSL < PositionGetDouble(POSITION_SL) - _Point) trade.PositionModify(ticket, newSL, currentTP); 
         } 
      } 
   } 
}

void ManageTradeState() { 
   if (CurrentOpenTicket != 0 && !PositionSelectByTicket(CurrentOpenTicket)) { 
      if (HistorySelectByPosition((long)CurrentOpenTicket)) { 
         double totalProfit = 0;
         int deals = HistoryDealsTotal(); 
         for(int i = 0; i < deals; i++) { 
            ulong ticket = HistoryDealGetTicket(i);
            totalProfit += (HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION));
         } 
         if (totalProfit < 0) { 
            Print(">>> Trade LOSS. Zone BURNED.");
            ZoneIsBurned = true; 
         } else { 
            Print(">>> Trade WIN. Zone remains ACTIVE.");
            ZoneIsBurned = false; 
         } 
      } 
      CurrentOpenTicket = 0;
   } 
}