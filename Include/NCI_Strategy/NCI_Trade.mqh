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

// --- HELPER: CONVERT TREND TO SHORT STRING (To fit 31 char limit) ---
string GetTrendLabel(int trendVal) {
   if (trendVal == 1) return "U"; // Up
   if (trendVal == -1) return "D"; // Down
   return "Y"; // Yellow/Flat
}

// *** UPDATED: Returns bool to indicate success ***
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
   
   // *** NEW COMPACT FORMAT: "ZiZ-Swing [H:U M:D]" ***
   string trendStamp = StringFormat(" [H:%s M:%s]", GetTrendLabel(currentMarketTrend_HTF), GetTrendLabel(currentMarketTrend_LTF));
   
   // Removed "NCI V79.0" prefix to save space (Max 31 chars allowed)
   string finalComment = comment + trendStamp;
   
   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, finalComment)) {
      CurrentOpenTicket = trade.ResultOrder();
      CurrentZoneTradeCount++; 
      return true;
   }
   return false;
}

// *** UPDATED: Returns bool to let CheckTradeEntry know if RR passed ***
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
         // SL is calculated based on the SL ZONE (HTF or LTF)
         double sl = slZone.bottom - (finalBuffer * point);
         
         double tp = opposingSupply.bottom + ((opposingSupply.top - opposingSupply.bottom) * TPZoneDepth); 
         double risk = entryPriceStart - sl;
         double reward = tp - entryPriceStart;
         
         // Standard Check: Must meet MinRiskReward
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            // Shortened "Standard" to "" and "Breakout" to "Brk" to save space
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
         // SL is calculated based on the SL ZONE (HTF or LTF)
         double sl = slZone.top + (finalBuffer * point);
         
         double tp = opposingDemand.top - ((opposingDemand.top - opposingDemand.bottom) * TPZoneDepth);
         double risk = sl - entryPriceStart;
         double reward = entryPriceStart - tp;
         
         // Standard Check: Must meet MinRiskReward
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            // Shortened "Standard" to "" and "Breakout" to "Brk" to save space
            string prefix = isBreakout ? "Brk " : "";
            return OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, prefix + commentTag, tradeRisk);
         }
      }
   }
   return false;
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
             
             // *** UPDATED LOGIC: HTF DOMINANCE WITH FALLBACK ***
             // We only care if 1H is UP. We ignore the 15M trend.
             if (currentMarketTrend_HTF == 1) {
                 
                 // ATTEMPT 1: SWING TRADE (Target HTF, Protect HTF)
                 bool swingSuccess = ExecuteEntryLogic(activeDemand_LTF, activeDemand_HTF, activeSupply_HTF, activeDemand_LTF, 1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
                 
                 // ATTEMPT 2: FALLBACK TO SCALP (If Swing failed due to RR)
                 if (!swingSuccess) {
                     ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "ZiZ-Scalp-FB", ReferenceZonePips_LTF);
                 }
                 
             } else {
                 // CASE B: Standard Scalp (1H is Flat/Down, but we are in a ZiZ so we scalp)
                 ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
         
         // SELL: LTF Supply inside HTF Supply
         if (activeSupply_LTF.isActive && IsOverlapping(activeSupply_LTF, activeSupply_HTF)) {
             
             // *** UPDATED LOGIC: HTF DOMINANCE WITH FALLBACK ***
             // We only care if 1H is DOWN. We ignore the 15M trend.
             if (currentMarketTrend_HTF == -1) {
                 
                 // ATTEMPT 1: SWING TRADE (Target HTF, Protect HTF)
                 bool swingSuccess = ExecuteEntryLogic(activeSupply_LTF, activeSupply_HTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
                 
                 // ATTEMPT 2: FALLBACK TO SCALP (If Swing failed due to RR)
                 if (!swingSuccess) {
                     ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, false, "ZiZ-Scalp-FB", ReferenceZonePips_LTF);
                 }
                 
             } else {
                 // CASE B: Standard Scalp (1H is Flat/Up, but we are in a ZiZ so we scalp)
                 ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
      }
      
      // 2. ZiZ BREAKOUT ENTRIES (Flip Zone inside HTF Zone)
      if (ZiZ_AllowBreakout) {
         if (activeFlippedDemand_LTF.isActive && activeFlippedDemand_LTF.endTime == 0 && IsOverlapping(activeFlippedDemand_LTF, activeDemand_HTF)) {
             ExecuteEntryLogic(activeFlippedDemand_LTF, activeFlippedDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, true, "ZiZ-Brk", ReferenceZonePips_LTF);
         }
         if (activeFlippedSupply_LTF.isActive && activeFlippedSupply_LTF.endTime == 0 && IsOverlapping(activeFlippedSupply_LTF, activeSupply_HTF)) {
             ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, true, "ZiZ-Brk", ReferenceZonePips_LTF);
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

// ==========================================================================
// UPDATED FUNCTION: Export Trade Journal + Trend Data
// ==========================================================================
void ExportTransactionsToCSV()
{
   string filename = "NCI_Journal_" + _Symbol + ".csv";
   
   // Added FILE_COMMON flag to ensure it goes to the Common/Files folder
   int file_handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
   
   if(file_handle != INVALID_HANDLE)
   {
      // 1. Write Header with NEW Columns
      FileWrite(file_handle, "Time", "Ticket", "Type", "Lots", "Price", "Profit", "Comment", "H1 Trend", "M15 Trend");
      
      // 2. Select All History
      HistorySelect(0, TimeCurrent());
      int total_deals = HistoryDealsTotal();
      
      // 3. Loop through deals and write to file
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket_deal = HistoryDealGetTicket(i);
         long type = HistoryDealGetInteger(ticket_deal, DEAL_TYPE);
         
         if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL) 
         {
            string sType = (type == DEAL_TYPE_BUY) ? "Buy" : "Sell";
            string rawComment = HistoryDealGetString(ticket_deal, DEAL_COMMENT);
            
            // --- Parse Trend Data from Comment ---
            // Pattern: "... [H:U M:D]"
            string h1_trend = "N/A";
            string m15_trend = "N/A";
            
            // Updated Parser for Short Codes [H:U M:D]
            int startIdx = StringFind(rawComment, "[H:");
            if (startIdx >= 0) {
               // Extract substring starting after "[H:"
               string sub = StringSubstr(rawComment, startIdx + 3); 
               int spaceIdx = StringFind(sub, " ");
               if (spaceIdx > 0) {
                   h1_trend = StringSubstr(sub, 0, spaceIdx); // Get H1 Value (U, D, Y)
                   
                   int m15Idx = StringFind(sub, "M:");
                   if (m15Idx > 0) {
                       string sub2 = StringSubstr(sub, m15Idx + 2);
                       int closeBracket = StringFind(sub2, "]");
                       if (closeBracket > 0) {
                           m15_trend = StringSubstr(sub2, 0, closeBracket); // Get M15 Value (U, D, Y)
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
               rawComment, // Full Comment
               h1_trend,   // Extracted H1 Trend
               m15_trend   // Extracted M15 Trend
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