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

// --- NEW HELPER: CHECK IF ZONES ARE NEAR (WITH BUFFER) ---
bool IsNear(MergedZoneState &z1, MergedZoneState &z2, double maxPips) {
   if (!z1.isActive || !z2.isActive) return false;
   
   // 1. Strict Overlap (The original check)
   if (MathMax(z1.bottom, z2.bottom) <= MathMin(z1.top, z2.top)) return true;
   
   // 2. Proximity Check (The relaxed check)
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point == 0) return false;
   
   double dist = 0;
   // Case A: z1 is strictly below z2
   if (z1.top < z2.bottom) dist = (z2.bottom - z1.top);
   // Case B: z2 is strictly below z1
   else if (z2.top < z1.bottom) dist = (z1.bottom - z2.top);
   
   // Return true if distance is within the allowed buffer
   return ((dist / point) <= maxPips);
}

// --- HELPER: CONVERT TREND TO SHORT STRING ---
string GetTrendLabel(int trendVal) {
   if (trendVal == 1) return "U"; // Up
   if (trendVal == -1) return "D"; // Down
   return "Y"; // Yellow/Flat
}

// *** OPEN TRADE FUNCTION ***
bool OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp, string comment, double finalRiskPercent)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (finalRiskPercent / 100.0); 
   double riskPoints = MathAbs(price - sl) / _Point;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if (riskPoints <= 0 || tickValue == 0) return false;
   double lotSize = NormalizeDouble(riskAmount / (riskPoints * tickValue), 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if (lotSize < minLot) lotSize = minLot;
   if (lotSize > maxLot) lotSize = maxLot;
   
   // Trend Stamp
   string trendStamp = StringFormat(" [H:%s M:%s]", GetTrendLabel(currentMarketTrend_HTF), GetTrendLabel(currentMarketTrend_LTF));
   string finalComment = comment + trendStamp;
   
   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, finalComment)) {
      CurrentOpenTicket = trade.ResultOrder();
      CurrentZoneTradeCount++; 
      return true;
   }
   return false;
}

// *** ENTRY LOGIC ***
bool ExecuteEntryLogic(MergedZoneState &entryZone, MergedZoneState &slZone, MergedZoneState &opposingSupply, MergedZoneState &opposingDemand, int type, bool isBreakout, string commentTag, double refPips)
{
   datetime relevantTime = entryZone.startTime;
   if (relevantTime != CurrentZoneID) {
      CurrentZoneID = relevantTime; 
      ZoneIsBurned = false;        
      CurrentZoneTradeCount = 0;
   }
   
   if (ZoneIsBurned) return false; 

   double tradeRisk = RiskPercent;
   if (EntryMode == MODE_SINGLE) 
   {
      if (CurrentZoneTradeCount > 0) return false;
      tradeRisk = RiskPercent;
   }
   else if (EntryMode == MODE_DOUBLE) 
   {
      if (CurrentZoneTradeCount == 0) tradeRisk = RiskPercent;
      else if (CurrentZoneTradeCount == 1) tradeRisk = RiskPercent * 0.5;
      else return false;
   }
   else if (EntryMode == MODE_INFINITE) tradeRisk = RiskPercent;

   if (UseVolatilityGuard) { if (!CheckVolatility()) return false; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double zoneHeightPrice = entryZone.top - entryZone.bottom;
   double zoneHeightPips = zoneHeightPrice / point;
   if (zoneHeightPips <= 0) zoneHeightPips = 1;
   
   double scalingFactor = refPips / zoneHeightPips;
   
   double dynamicEntryPct = BaseEntryDepth * scalingFactor;
   
   // *** CHANGE: Force shallow entry for Breakouts (Edge of zone) ***
   if (isBreakout) dynamicEntryPct = 0.05; 

   double dynamicMaxPct   = BaseMaxDepth * scalingFactor;
   if (dynamicEntryPct < 0.05) dynamicEntryPct = 0.05;
   if (dynamicEntryPct > 0.60) dynamicEntryPct = 0.60;
   if (dynamicMaxPct < 0.10) dynamicMaxPct = 0.10;
   if (dynamicMaxPct > 0.80) dynamicMaxPct = 0.80;

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
         double sl = slZone.bottom - (finalBuffer * point);
         double tp = opposingSupply.bottom + ((opposingSupply.top - opposingSupply.bottom) * TPZoneDepth); 
         double risk = entryPriceStart - sl;
         double reward = tp - entryPriceStart;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            string prefix = isBreakout ? "Brk " : ""; 
            return OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, prefix + commentTag, tradeRisk);
         }
      }
   }
   else if (type == -1) // Sell
   {
      double entryPriceStart = entryZone.bottom + (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = entryZone.bottom + (zoneHeightPrice * dynamicMaxPct);   
      
      if (bid >= entryPriceStart && bid <= entryPriceLimit) 
      {
         double sl = slZone.top + (finalBuffer * point);
         double tp = opposingDemand.top - ((opposingDemand.top - opposingDemand.bottom) * TPZoneDepth);
         double risk = sl - entryPriceStart;
         double reward = entryPriceStart - tp;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            string prefix = isBreakout ? "Brk " : "";
            return OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, prefix + commentTag, tradeRisk);
         }
      }
   }
   return false;
}

// *** MAIN CHECK FUNCTION ***
void CheckTradeEntry()
{
   if (PositionsTotal() > 0) return;
   if (!AllowTrading) return;

   // =========================================================
   // SECTOR B: ADVANCED STRATEGY (ZiZ SNIPER MODE)
   // =========================================================
   if (Enable_ZiZ_Mode) {
      
      // 1. ZiZ TREND ENTRIES (Standard Overlap)
      if (ZiZ_AllowTrend) {
         // BUY
         if (activeDemand_LTF.isActive && IsOverlapping(activeDemand_LTF, activeDemand_HTF)) {
             if (currentMarketTrend_HTF == 1) {
                 bool swingSuccess = ExecuteEntryLogic(activeDemand_LTF, activeDemand_HTF, activeSupply_HTF, activeDemand_LTF, 1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
                 if (!swingSuccess) ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "ZiZ-Scalp-FB", ReferenceZonePips_LTF);
             } else {
                 ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
         // SELL
         if (activeSupply_LTF.isActive && IsOverlapping(activeSupply_LTF, activeSupply_HTF)) {
             if (currentMarketTrend_HTF == -1) {
                 bool swingSuccess = ExecuteEntryLogic(activeSupply_LTF, activeSupply_HTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
                 if (!swingSuccess) ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, false, "ZiZ-Scalp-FB", ReferenceZonePips_LTF);
             } else {
                 ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
      }

      // 2. ZiZ STAIR-STEP ENTRIES (Floating Zones in Trend Direction) [NEW]
      if (ZiZ_AllowStairStep) {
         // BUY: Trend is UP + M15 Demand Exists
         if (currentMarketTrend_HTF == 1 && activeDemand_LTF.isActive) {
             // We do NOT check IsOverlapping here. We trust the trend.
             // We use HTF Supply as the hard ceiling (Exit).
             ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_HTF, activeDemand_LTF, 1, false, "ZiZ-Step", ReferenceZonePips_LTF);
         }
         
         // SELL: Trend is DOWN + M15 Supply Exists
         if (currentMarketTrend_HTF == -1 && activeSupply_LTF.isActive) {
             // We do NOT check IsOverlapping here. We trust the trend.
             // We use HTF Demand as the hard floor (Exit).
             ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Step", ReferenceZonePips_LTF);
         }
      }
      
      // 3. ZiZ BREAKOUT ENTRIES (Flip Zones)
      if (ZiZ_AllowBreakout) {
         // BUY Breakout: Removed IsNear constraint for unconstrained breakouts
         if (activeFlippedDemand_LTF.isActive && activeFlippedDemand_LTF.endTime == 0) 
         {
             ExecuteEntryLogic(activeFlippedDemand_LTF, activeFlippedDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, true, "ZiZ-Brk", ReferenceZonePips_LTF);
         }
         
         // SELL Breakout: Removed IsNear constraint for unconstrained breakouts
         if (activeFlippedSupply_LTF.isActive && activeFlippedSupply_LTF.endTime == 0) 
         {
             ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, true, "ZiZ-Brk", ReferenceZonePips_LTF);
         }
      }
      return; 
   }

   // =========================================================
   // SECTOR A: SIMPLE STRATEGY
   // =========================================================
   if (Enable_Simple_Mode) {
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

      if (Simple_Trade_LTF) { 
          bool allowBuys = true;
          bool allowSells = true;
          if (Simple_UseTrendAlign) {
              if (currentMarketTrend_HTF == 1) { allowBuys = true; allowSells = false; } 
              else if (currentMarketTrend_HTF == -1) { allowBuys = false; allowSells = true; } 
              else { allowBuys = false; allowSells = false; }
          }
          if (Simple_Trend_LTF && activeSupply_LTF.isActive && activeDemand_LTF.isActive) { 
             if (currentMarketTrend_LTF == 1 && allowBuys) ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "LTF", ReferenceZonePips_LTF);
             else if (currentMarketTrend_LTF == -1 && allowSells) ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, false, "LTF", ReferenceZonePips_LTF);
          }
          if (Simple_Breakout_LTF) { 
             if (activeFlippedSupply_LTF.isActive && activeDemand_LTF.isActive && activeFlippedSupply_LTF.endTime == 0) {
                if (allowSells) ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, true, "LTF", ReferenceZonePips_LTF);
             }
             if (activeFlippedDemand_LTF.isActive && activeSupply_LTF.isActive && activeFlippedDemand_LTF.endTime == 0) {
                if (allowBuys) ExecuteEntryLogic(activeFlippedDemand_LTF, activeFlippedDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, true, "LTF", ReferenceZonePips_LTF);
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

void ExportTransactionsToCSV()
{
   string filename = "NCI_Journal_" + _Symbol + ".csv";
   int file_handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
   
   if(file_handle != INVALID_HANDLE)
   {
      FileWrite(file_handle, "Time", "Ticket", "Type", "Lots", "Price", "Profit", "Comment", "H1 Trend", "M15 Trend");
      
      HistorySelect(0, TimeCurrent());
      int total_deals = HistoryDealsTotal();
      
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket_deal = HistoryDealGetTicket(i);
         long type = HistoryDealGetInteger(ticket_deal, DEAL_TYPE);
         
         if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL) 
         {
            string sType = (type == DEAL_TYPE_BUY) ? "Buy" : "Sell";
            string rawComment = HistoryDealGetString(ticket_deal, DEAL_COMMENT);
            
            string h1_trend = "N/A";
            string m15_trend = "N/A";
            
            int startIdx = StringFind(rawComment, "[H:");
            if (startIdx >= 0) {
               string sub = StringSubstr(rawComment, startIdx + 3); 
               int spaceIdx = StringFind(sub, " ");
               if (spaceIdx > 0) {
                   h1_trend = StringSubstr(sub, 0, spaceIdx); 
                   
                   int m15Idx = StringFind(sub, "M:");
                   if (m15Idx > 0) {
                       string sub2 = StringSubstr(sub, m15Idx + 2);
                       int closeBracket = StringFind(sub2, "]");
                       if (closeBracket > 0) {
                           m15_trend = StringSubstr(sub2, 0, closeBracket); 
                       }
                   }
               }
            }

            FileWrite(file_handle, 
               (string)HistoryDealGetInteger(ticket_deal, DEAL_TIME),
               (string)ticket_deal,
               sType,
               DoubleToString(HistoryDealGetDouble(ticket_deal, DEAL_VOLUME), 2),
               DoubleToString(HistoryDealGetDouble(ticket_deal, DEAL_PRICE), 5),
               DoubleToString(HistoryDealGetDouble(ticket_deal, DEAL_PROFIT), 2),
               rawComment, 
               h1_trend,   
               m15_trend   
            );
         }
      }
      
      FileClose(file_handle);
      Print(">> Exported Trade Journal to: " + filename);
   }
   else
   {
      Print(">> Error opening file for export: ", GetLastError());
   }
}