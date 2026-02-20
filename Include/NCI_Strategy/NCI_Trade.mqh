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
   if (MathMax(z1.bottom, z2.bottom) <= MathMin(z1.top, z2.top)) return true;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point == 0) return false;
   double dist = 0;
   if (z1.top < z2.bottom) dist = (z2.bottom - z1.top);
   else if (z2.top < z1.bottom) dist = (z1.bottom - z2.top);
   return ((dist / point) <= maxPips);
}

// --- HELPER: CONVERT TREND TO SHORT STRING ---
string GetTrendLabel(int trendVal) {
   if (trendVal == 1) return "U"; 
   if (trendVal == -1) return "D"; 
   return "Y"; 
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
   
   string trendStamp = StringFormat(" [H:%s M:%s]", GetTrendLabel(currentMarketTrend_HTF), GetTrendLabel(currentMarketTrend_LTF));
   string finalComment = comment + trendStamp;
   
   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, finalComment)) {
      CurrentOpenTicket = trade.ResultOrder();
      CurrentZoneTradeCount++; 
      
      // EXPLICIT LOGGING TO JOURNAL TAB
      Print(">>> TRADE OPENED | Ticket: ", CurrentOpenTicket, 
            " | Strategy: ", comment, 
            " | Type: ", (type==ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " | Price: ", DoubleToString(price, 5));
      
      return true;
   }
   return false;
}

// *** ENTRY LOGIC ***
bool ExecuteEntryLogic(MergedZoneState &entryZone, MergedZoneState &slZone, MergedZoneState &opposingSupply, MergedZoneState &opposingDemand, int type, bool isBreakout, string commentTag, double refPips, double customEntryDepth = -1.0, double customBuffer = -1.0)
{
   datetime relevantTime = entryZone.startTime;
   if (relevantTime != CurrentZoneID) {
      CurrentZoneID = relevantTime; 
      ZoneIsBurned = false;        
      CurrentZoneTradeCount = 0;
   }
   
   if (ZoneIsBurned) return false; 

   // [NEW] SPREAD DEBUG & FILTER
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if (Debug_Show_Spread) {
       Print(">>> DEBUG SPREAD: Signal Detected. Current: ", currentSpread, " pts | Max: ", MaxSpreadPoints);
   }

   if (currentSpread > MaxSpreadPoints) {
       if (Debug_Show_Spread) Print(">>> BLOCKED: Spread (", currentSpread, ") too high.");
       return false;
   }

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
   
   // STANDARD TOUCH / LIMIT ENTRY LOGIC
   double zoneHeightPrice = entryZone.top - entryZone.bottom;
   double zoneHeightPips = zoneHeightPrice / point;
   if (zoneHeightPips <= 0) zoneHeightPips = 1;
   
   double scalingFactor = refPips / zoneHeightPips;
   
   // --- DEPTH CALCULATION (Normal vs Storm) ---
   double activeEntryDepth = BaseEntryDepth;
   if (customEntryDepth > 0) activeEntryDepth = customEntryDepth; // Override for Storm Mode
   
   double dynamicEntryPct = activeEntryDepth * scalingFactor;
   
   if (isBreakout) dynamicEntryPct = 0.05; 

   double dynamicMaxPct   = BaseMaxDepth * scalingFactor;
   
   // --- DYNAMIC CLAMPING (Isolating Storm Mode limits from Normal Mode) ---
   // If customEntryDepth > 0, it means Storm Mode is calling this function.
   double maxAllowedEntry = (customEntryDepth > 0) ? 0.85 : 0.60;
   double maxAllowedLimit = (customEntryDepth > 0) ? 0.90 : 0.80;

   // Clamp percentages
   if (dynamicEntryPct < 0.05) dynamicEntryPct = 0.05;
   if (dynamicEntryPct > maxAllowedEntry) dynamicEntryPct = maxAllowedEntry; 
   if (dynamicMaxPct < 0.10) dynamicMaxPct = 0.10;
   if (dynamicMaxPct > maxAllowedLimit) dynamicMaxPct = maxAllowedLimit;

   // --- BUFFER CALCULATION (Normal vs Storm) ---
   double finalBuffer = BaseBufferPoints;
   if (customBuffer > 0) {
       finalBuffer = customBuffer; // Override for Storm Mode
   } else if (UseDynamicBuffer) {
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
            bool res = OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, prefix + commentTag, tradeRisk);
            if (res && Debug_Show_Spread) Print(">>> SUCCESS: Trade Sent.");
            return res;
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
            bool res = OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, prefix + commentTag, tradeRisk);
            if (res && Debug_Show_Spread) Print(">>> SUCCESS: Trade Sent.");
            return res;
         }
      }
   }
   return false;
}

// *** MAIN CHECK FUNCTION ***
void CheckTradeEntry()
{
   // --- TIME FILTER CHECK ---
   if (UseTimeFilter) {
      datetime currentTime = TimeCurrent();
      MqlDateTime tm;
      TimeToStruct(currentTime, tm);
      
      if (StartHour < EndHour) {
         if (tm.hour < StartHour || tm.hour >= EndHour) return; 
      }
      else {
         if (tm.hour < StartHour && tm.hour >= EndHour) return;
      }
   }

   if (PositionsTotal() >= MaxOpenTrades) return;
   
   if (!AllowTrading) return;

   // -----------------------------------------------------------------
   // STRICT MODULAR REGIME SWITCHING 
   // -----------------------------------------------------------------
   double currentADR = CalculateADR(ADR_Period);
   
   if (Use_ADR_Filter) {

       // =============================================================
       // REGIME 1: RANGE FADE (< 70 ADR)
       // =============================================================
       if (currentADR < SectorC_Max_ADR) {
           if (Enable_SectorC_Range) {
               if (activeDemand_LTF.isActive) {
                   ExecuteEntryLogic(activeDemand_LTF, activeDemand_HTF, activeSupply_HTF, activeDemand_LTF, 1, false, "Range-Fade", ReferenceZonePips_LTF);
               }
               if (activeSupply_LTF.isActive) {
                   ExecuteEntryLogic(activeSupply_LTF, activeSupply_HTF, activeSupply_LTF, activeDemand_HTF, -1, false, "Range-Fade", ReferenceZonePips_LTF);
               }
           }
           return; // Strictly block normal Trend and Storm logic from running here
       }
       
       // =============================================================
       // REGIME 3: STORM MODE (> 85 ADR)
       // =============================================================
       else if (currentADR > SectorE_Min_ADR) {
           if (Enable_SectorE_Storm) {
               double activeDepth = Storm_Entry_Depth; 
               double activeBuffer = Storm_Buffer_Pips * 10.0; 
               
               // Storm Trend Logic (Mirror of ZiZ, but strict overrides)
               if (ZiZ_AllowTrend) {
                   if (activeDemand_LTF.isActive && IsOverlapping(activeDemand_LTF, activeDemand_HTF)) {
                       if (currentMarketTrend_HTF == 1) {
                           bool swingSuccess = ExecuteEntryLogic(activeDemand_LTF, activeDemand_HTF, activeSupply_HTF, activeDemand_LTF, 1, false, "Storm-Swing", ReferenceZonePips_LTF, activeDepth, activeBuffer);
                           if (!swingSuccess) ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "Storm-Scalp", ReferenceZonePips_LTF, activeDepth, activeBuffer);
                       } 
                   }
                   if (activeSupply_LTF.isActive && IsOverlapping(activeSupply_LTF, activeSupply_HTF)) {
                       if (currentMarketTrend_HTF == -1) {
                           bool swingSuccess = ExecuteEntryLogic(activeSupply_LTF, activeSupply_HTF, activeSupply_LTF, activeDemand_HTF, -1, false, "Storm-Swing", ReferenceZonePips_LTF, activeDepth, activeBuffer);
                           if (!swingSuccess) ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, false, "Storm-Scalp", ReferenceZonePips_LTF, activeDepth, activeBuffer);
                       }
                   }
               }
               if (ZiZ_AllowStairStep) {
                   if (currentMarketTrend_HTF == 1 && activeDemand_LTF.isActive) {
                       ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_HTF, activeDemand_LTF, 1, false, "Storm-Step", ReferenceZonePips_LTF, activeDepth, activeBuffer);
                   }
                   if (currentMarketTrend_HTF == -1 && activeSupply_LTF.isActive) {
                       if (ZiZ_AllowStepSell) {
                           ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, false, "Storm-Step", ReferenceZonePips_LTF, activeDepth, activeBuffer);
                       }
                   }
               }
           }
           return; // Strictly block normal Trend and Range logic from running here
       }
   }

   // =============================================================
   // REGIME 2: NORMAL TREND (70-85 ADR or ADR Filter Disabled)
   // =============================================================
   
   if (Enable_ZiZ_Mode) {
      if (ZiZ_AllowTrend) {
         if (activeDemand_LTF.isActive && IsOverlapping(activeDemand_LTF, activeDemand_HTF)) {
             if (currentMarketTrend_HTF == 1) {
                 bool swingSuccess = ExecuteEntryLogic(activeDemand_LTF, activeDemand_HTF, activeSupply_HTF, activeDemand_LTF, 1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
                 if (!swingSuccess) ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "ZiZ-Scalp-FB", ReferenceZonePips_LTF);
             } else {
                 bool allowTrade = true;
                 if (UseToxicFilter && currentMarketTrend_LTF == 1) allowTrade = false;
                 if (allowTrade) ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
         if (activeSupply_LTF.isActive && IsOverlapping(activeSupply_LTF, activeSupply_HTF)) {
             if (currentMarketTrend_HTF == -1) {
                 bool swingSuccess = ExecuteEntryLogic(activeSupply_LTF, activeSupply_HTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Swing", ReferenceZonePips_LTF);
                 if (!swingSuccess) ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Scalp-FB", ReferenceZonePips_LTF);
             } else {
                 bool allowTrade = true;
                 if (UseToxicFilter && currentMarketTrend_LTF != 1) allowTrade = false;
                 if (allowTrade) ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Scalp", ReferenceZonePips_LTF);
             }
         }
      }

      if (ZiZ_AllowStairStep) {
         if (currentMarketTrend_HTF == 1 && activeDemand_LTF.isActive) {
             ExecuteEntryLogic(activeDemand_LTF, activeDemand_LTF, activeSupply_HTF, activeDemand_LTF, 1, false, "ZiZ-Step", ReferenceZonePips_LTF);
         }
         if (currentMarketTrend_HTF == -1 && activeSupply_LTF.isActive) {
             if (ZiZ_AllowStepSell) {
                 ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, false, "ZiZ-Step", ReferenceZonePips_LTF);
             }
         }
      }
      
      if (ZiZ_AllowBreakout) {
         if (activeFlippedDemand_LTF.isActive && activeFlippedDemand_LTF.endTime == 0) {
             ExecuteEntryLogic(activeFlippedDemand_LTF, activeFlippedDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, true, "ZiZ-Brk", ReferenceZonePips_LTF);
         }
         if (activeFlippedSupply_LTF.isActive && activeFlippedSupply_LTF.endTime == 0) {
             ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_LTF, -1, true, "ZiZ-Brk", ReferenceZonePips_LTF);
         }
      }
      return; 
   }

   // [Fallback] SIMPLE MODE
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

// *** UPDATED MANAGE POSITIONS (With Cash RR & Breakout-Confirmation Trail) ***
void ManageOpenPositions() { 
   
   // 1. Get Current Time for Friday Check
   datetime currentTime = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(currentTime, tm);
   bool isFridayCloseTime = (Enable_Friday_Close && tm.day_of_week == 5 && tm.hour >= Friday_Close_Hour);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) { 
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue; 
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue; 
      if(PositionGetInteger(POSITION_MAGIC) != 111222) continue; 
      
      long openTime = PositionGetInteger(POSITION_TIME); 
      long updateTime = PositionGetInteger(POSITION_TIME_UPDATE);
      if (updateTime > openTime) continue; 
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN); 
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP); 
      long type = PositionGetInteger(POSITION_TYPE); 
      string comment = PositionGetString(POSITION_COMMENT);
      
      if (currentTP == 0) continue; 

      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      // ==================================================================
      // LOGIC 1: FRIDAY "CASH RR" CLOSE
      // ==================================================================
      if (isFridayCloseTime) {
          double standardRiskAmount = Account_Initial_Balance * (RiskPercent / 100.0);
          double currentProfitMoney = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
          
          if (currentProfitMoney >= (standardRiskAmount * Friday_Min_RR)) {
              Print(">>> FRIDAY CLOSE: High RR Cash Hit. Ticket: ", ticket, " Profit: ", currentProfitMoney, " (Target: ", (standardRiskAmount * Friday_Min_RR), ")");
              trade.PositionClose(ticket);
              continue; 
          }
      }

      // ==================================================================
      // LOGIC 2: SMART STRUCTURE TRAIL (Stair-Step)
      // Confirmed by BREAKOUT of opposing structure
      // ==================================================================
      bool isH1Target = (StringFind(comment, "Swing") >= 0 || StringFind(comment, "HTF") >= 0 || StringFind(comment, "Step") >= 0);
      bool trailMoved = false;

      if (Enable_Smart_Trail && isH1Target) {
         if (type == POSITION_TYPE_BUY && activeDemand_LTF.isActive) {
             double proposedSL = activeDemand_LTF.bottom - (Smart_Trail_Buffer_Pips * point);
             if (proposedSL > currentSL + point) {
                 if (activeFlippedSupply_LTF.isActive) {
                     trade.PositionModify(ticket, proposedSL, currentTP);
                     trailMoved = true;
                     Print(">>> SMART TRAIL (BUY): Breakout Confirmed. Moved SL below new M15 Demand.");
                 }
             }
         }
         else if (type == POSITION_TYPE_SELL && activeSupply_LTF.isActive) {
             double proposedSL = activeSupply_LTF.top + (Smart_Trail_Buffer_Pips * point);
             if (proposedSL < currentSL - point) {
                 if (activeFlippedDemand_LTF.isActive) {
                     trade.PositionModify(ticket, proposedSL, currentTP);
                     trailMoved = true;
                     Print(">>> SMART TRAIL (SELL): Breakout Confirmed. Moved SL above new M15 Supply.");
                 }
             }
         }
      }

      // ==================================================================
      // LOGIC 3: PERCENTAGE LOCKING (Fallback)
      // ==================================================================
      if (!trailMoved && EnableProfitLocking) {
         
         // DEFINE LOCK PARAMETERS BASED ON STRATEGY TYPE
         double activeTriggerPct = LockTriggerPercent; // Default (0.80)
         double activeLockPct    = LockPositionPercent; // Default (0.70)
         
         // If it is a Stair-Step Trade (Step), use tighter locking
         if (StringFind(comment, "Step") >= 0) {
             activeTriggerPct = Step_LockTriggerPercent; // (0.62)
             activeLockPct    = Step_LockPositionPercent; // (0.60)
         }

         if (type == POSITION_TYPE_BUY) { 
             double totalProfitDist = currentTP - openPrice; 
             if (totalProfitDist > 0) {
                 double triggerPrice = openPrice + (totalProfitDist * activeTriggerPct);
                 if (currentBid >= triggerPrice) { 
                    double newSL = openPrice + (totalProfitDist * activeLockPct);
                    if (newSL > currentSL + point) trade.PositionModify(ticket, newSL, currentTP); 
                 }
             }
         } else if (type == POSITION_TYPE_SELL) { 
             double totalProfitDist = openPrice - currentTP; 
             if (totalProfitDist > 0) {
                 double triggerPrice = openPrice - (totalProfitDist * activeTriggerPct);
                 if (currentAsk <= triggerPrice) { 
                    double newSL = openPrice - (totalProfitDist * activeLockPct);
                    if (newSL < currentSL - point) trade.PositionModify(ticket, newSL, currentTP); 
                 }
             }
         }
      }
      
      // ==================================================================
      // LOGIC 4: RR LOCKING (Backup - Now Step-Specific capable)
      // ==================================================================
      if (!trailMoved && Enable_RR_Locking) {
         
         // [NEW] CHECK: If toggle is ON, limit this logic to Step trades only
         if (RR_Lock_Step_Only && StringFind(comment, "Step") < 0) {
            // Do nothing: This is NOT a step trade, so we skip RR locking
         } 
         else {
            // EXECUTE RR LOGIC
            double newSL_RR = 0;
            if (type == POSITION_TYPE_BUY) {
                if (currentSL < openPrice) { 
                    double riskDist = openPrice - currentSL;
                    if (riskDist > 0) {
                        double profitDist = currentBid - openPrice;
                        if ((profitDist / riskDist) >= RR_Lock_Trigger) {
                            newSL_RR = openPrice + (riskDist * RR_Lock_Target);
                            if (newSL_RR > currentSL + point) trade.PositionModify(ticket, newSL_RR, currentTP);
                        }
                    }
                }
            }
            else if (type == POSITION_TYPE_SELL) {
                if (currentSL > openPrice) { 
                    double riskDist = currentSL - openPrice;
                    if (riskDist > 0) {
                        double profitDist = openPrice - currentAsk;
                        if ((profitDist / riskDist) >= RR_Lock_Trigger) {
                            newSL_RR = openPrice - (riskDist * RR_Lock_Target);
                            if (newSL_RR < currentSL - point) trade.PositionModify(ticket, newSL_RR, currentTP);
                        }
                    }
                }
            }
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

// *** UPDATED EXPORT FUNCTION (With Commission, Swap & ADR Stats) ***
void ExportTransactionsToCSV()
{
   string filename = "NCI_Journal_" + _Symbol + ".csv";
   int file_handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
   
   if(file_handle != INVALID_HANDLE)
   {
      // [NEW] Added "ADR" Column
      FileWrite(file_handle, "Time", "Ticket", "Type", "Lots", "Price", "RawProfit", "Commission", "Swap", "NetProfit", "ADR", "Strategy", "Comment", "H1 Trend", "M15 Trend");
      
      HistorySelect(0, TimeCurrent());
      int total_deals = HistoryDealsTotal();
      
      // Initialize ADR Handle for historical calculation
      int atr_handle = iATR(_Symbol, PERIOD_D1, ADR_Period);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket_deal = HistoryDealGetTicket(i);
         long type = HistoryDealGetInteger(ticket_deal, DEAL_TYPE);
         
         if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL) 
         {
            string sType = (type == DEAL_TYPE_BUY) ? "Buy" : "Sell";
            string rawComment = HistoryDealGetString(ticket_deal, DEAL_COMMENT);
            
            // Extract Strategy Type
            string strategyType = "OTHER";
            if (StringFind(rawComment, "Step") >= 0) strategyType = "STEP";
            else if (StringFind(rawComment, "Swing") >= 0) strategyType = "SWING";
            else if (StringFind(rawComment, "Scalp") >= 0) strategyType = "SCALP";
            else if (StringFind(rawComment, "HTF") >= 0) strategyType = "HTF-SIMPLE";
            else if (StringFind(rawComment, "Brk") >= 0) strategyType = "BREAKOUT";
            else if (StringFind(rawComment, "Range") >= 0) strategyType = "RANGE-FADE"; 
            else if (StringFind(rawComment, "Storm") >= 0) strategyType = "STORM-MODE"; // [NEW] Label
            
            string h1_trend = "N/A";
            string m15_trend = "N/A";
            
            // Extract Trend Tags
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
                       if (closeBracket > 0) m15_trend = StringSubstr(sub2, 0, closeBracket); 
                   }
               }
            }
            
            // --- HISTORICAL ADR CALCULATION ---
            double historicalADR = 0;
            if (atr_handle != INVALID_HANDLE) {
                datetime dealTime = (datetime)HistoryDealGetInteger(ticket_deal, DEAL_TIME);
                int dayShift = iBarShift(_Symbol, PERIOD_D1, dealTime);
                if (dayShift >= 0) {
                    double atrValues[];
                    if(CopyBuffer(atr_handle, 0, dayShift + 1, 1, atrValues) > 0) {
                        historicalADR = (atrValues[0] / point) / 10.0;
                    }
                }
            }

            double rawProfit = HistoryDealGetDouble(ticket_deal, DEAL_PROFIT);
            double comm = HistoryDealGetDouble(ticket_deal, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(ticket_deal, DEAL_SWAP);
            double netProfit = rawProfit + comm + swap;

            FileWrite(file_handle, 
               (string)HistoryDealGetInteger(ticket_deal, DEAL_TIME),
               (string)ticket_deal,
               sType,
               DoubleToString(HistoryDealGetDouble(ticket_deal, DEAL_VOLUME), 2),
               DoubleToString(HistoryDealGetDouble(ticket_deal, DEAL_PRICE), 5),
               DoubleToString(rawProfit, 2),
               DoubleToString(comm, 2),    
               DoubleToString(swap, 2),    
               DoubleToString(netProfit, 2), 
               DoubleToString(historicalADR, 1), 
               strategyType, 
               rawComment, 
               h1_trend,   
               m15_trend   
            );
         }
      }
      
      // =================================================================================
      // [FIXED] ADR MARKET STATS REPORT (Restricted to Test Period Only)
      // =================================================================================
      if (MQLInfoInteger(MQL_TESTER)) {
          FileWrite(file_handle, "");
          FileWrite(file_handle, "--- ADR STATISTICS REPORT (Daily) ---");
          
          int lowCount = 0;
          int midCount = 0;
          int highCount = 0;
          int totalDays = 0;
          
          // 1. Determine the actual Start and End time of the test
          datetime startTest = 0;
          datetime endTest = 0;
          
          if (HistorySelect(0, TimeCurrent())) {
              int deals = HistoryDealsTotal();
              if (deals > 0) {
                  startTest = (datetime)HistoryDealGetInteger(HistoryDealGetTicket(0), DEAL_TIME);
                  endTest   = (datetime)HistoryDealGetInteger(HistoryDealGetTicket(deals-1), DEAL_TIME);
              }
          }
          
          // 2. Iterate through Daily Bars, but FILTER by date
          int bars = Bars(_Symbol, PERIOD_D1);
          if (atr_handle != INVALID_HANDLE && bars > 0) {
              double atrBuffer[];
              datetime timeBuffer[]; // We need the time of each bar
              
              if (CopyBuffer(atr_handle, 0, 0, bars, atrBuffer) > 0) {
                  if (CopyTime(_Symbol, PERIOD_D1, 0, bars, timeBuffer) > 0) {
                      
                      for(int i=0; i < ArraySize(atrBuffer)-1; i++) {
                          datetime barTime = timeBuffer[i];
                          
                          // FILTER: Only count this day if it is within our testing window
                          if (barTime >= startTest && barTime <= endTest) {
                              double dailyADR = (atrBuffer[i] / point) / 10.0;
                              
                              if (dailyADR < Stats_ADR_Low) lowCount++;
                              else if (dailyADR > Stats_ADR_High) highCount++;
                              else midCount++;
                              
                              totalDays++;
                          }
                      }
                  }
              }
          }
          
          if (totalDays > 0) {
              FileWrite(file_handle, "Period Analyzed", TimeToString(startTest) + " to " + TimeToString(endTest));
              FileWrite(file_handle, "Total Days", (string)totalDays);
              FileWrite(file_handle, "Zone", "Count", "Percent");
              
              string pLow = DoubleToString(((double)lowCount / totalDays) * 100.0, 1) + "%";
              FileWrite(file_handle, "Low (< " + DoubleToString(Stats_ADR_Low, 0) + ")", (string)lowCount, pLow);
              
              string pMid = DoubleToString(((double)midCount / totalDays) * 100.0, 1) + "%";
              FileWrite(file_handle, "Mid (" + DoubleToString(Stats_ADR_Low, 0) + "-" + DoubleToString(Stats_ADR_High, 0) + ")", (string)midCount, pMid);
              
              string pHigh = DoubleToString(((double)highCount / totalDays) * 100.0, 1) + "%";
              FileWrite(file_handle, "High (> " + DoubleToString(Stats_ADR_High, 0) + ")", (string)highCount, pHigh);
          }
      }
      
      FileClose(file_handle);
   }
}