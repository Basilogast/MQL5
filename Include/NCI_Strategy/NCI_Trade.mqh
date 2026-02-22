//+------------------------------------------------------------------+
//| NCI_Trade.mqh - Execution & Management                           |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh" 

datetime GlobalLastTradeTime = 0; // Master clock to prevent traffic jams
datetime LastPhoenixBuyTime  = 0; // [NEW] Phoenix Logic Tracker
datetime LastPhoenixSellTime = 0; // [NEW] Phoenix Logic Tracker

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

// --- NEW HELPER: PATTERN RECOGNITION BRAIN ---
bool CheckConfirmation(int type, double zoneStart, double zoneLimit) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Pull the last 2 closed candles from the Lower Timeframe (M15)
   if(CopyRates(_Symbol, TimeFrame_LTF, 1, 2, rates) != 2) return false;
   
   double c1_open = rates[0].open, c1_close = rates[0].close, c1_high = rates[0].high, c1_low = rates[0].low; // The just-closed candle
   double c2_open = rates[1].open, c2_close = rates[1].close; // The previous candle
   
   if (type == 1) { // BUY LOGIC
      // 1. Did the candle touch the zone, and safely close above invalidation?
      if (c1_low > zoneStart || c1_close < zoneLimit) return false;
      
      // 2. Pinbar Check (Long Lower Wick + Bullish/Neutral Close)
      bool isPinbar = false;
      double totalHeight = c1_high - c1_low;
      if (totalHeight > 0) {
          double lowerWick = MathMin(c1_open, c1_close) - c1_low;
          if ((lowerWick / totalHeight) >= MinWickPercent && c1_close >= c1_open) isPinbar = true;
      }
      
      // 3. Engulfing Check (C2 was Bearish, C1 is Bullish & Engulfs body)
      bool isEngulfing = false;
      if (c2_close < c2_open && c1_close > c1_open) {
          if (c1_close >= c2_open && c1_open <= c2_close) isEngulfing = true;
      }
      
      if (ConfirmationSignal == PATTERN_PINBAR && isPinbar) return true;
      if (ConfirmationSignal == PATTERN_ENGULFING && isEngulfing) return true;
      if (ConfirmationSignal == PATTERN_ANY && (isPinbar || isEngulfing)) return true;
      
   } else { // SELL LOGIC
      if (c1_high < zoneStart || c1_close > zoneLimit) return false;
      
      bool isPinbar = false;
      double totalHeight = c1_high - c1_low;
      if (totalHeight > 0) {
          double upperWick = c1_high - MathMax(c1_open, c1_close);
          if ((upperWick / totalHeight) >= MinWickPercent && c1_close <= c1_open) isPinbar = true;
      }
      
      bool isEngulfing = false;
      if (c2_close > c2_open && c1_close < c1_open) {
          if (c1_close <= c2_open && c1_open >= c2_close) isEngulfing = true;
      }
      
      if (ConfirmationSignal == PATTERN_PINBAR && isPinbar) return true;
      if (ConfirmationSignal == PATTERN_ENGULFING && isEngulfing) return true;
      if (ConfirmationSignal == PATTERN_ANY && (isPinbar || isEngulfing)) return true;
   }
   return false;
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
      ulong ticket = trade.ResultOrder();
      
      GlobalLastTradeTime = TimeCurrent();
      
      if (type == ORDER_TYPE_BUY) {
          CurrentOpenBuyTicket = ticket;
          CurrentBuyZoneTradeCount++;
      } else {
          CurrentOpenSellTicket = ticket;
          CurrentSellZoneTradeCount++;
      }
      
      Print(">>> TRADE OPENED | Ticket: ", ticket, 
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
   int currentTradeCount = 0;

   if (type == 1) { // BUY
       if (relevantTime != CurrentBuyZoneID) {
           CurrentBuyZoneID = relevantTime;
           BuyZoneIsBurned = false;        
           CurrentBuyZoneTradeCount = 0;
       }
       if (BuyZoneIsBurned) return false;
       currentTradeCount = CurrentBuyZoneTradeCount;
   } else if (type == -1) { // SELL
       if (relevantTime != CurrentSellZoneID) {
           CurrentSellZoneID = relevantTime;
           SellZoneIsBurned = false;        
           CurrentSellZoneTradeCount = 0;
       }
       if (SellZoneIsBurned) return false;
       currentTradeCount = CurrentSellZoneTradeCount;
   }

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
      if (currentTradeCount > 0) return false;
      tradeRisk = RiskPercent;
   }
   else if (EntryMode == MODE_DOUBLE) 
   {
      if (currentTradeCount == 0) tradeRisk = RiskPercent;
      else if (currentTradeCount == 1) tradeRisk = RiskPercent * 0.5;
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
   
   double activeEntryDepth = BaseEntryDepth;
   if (customEntryDepth > 0) activeEntryDepth = customEntryDepth;
   
   double dynamicEntryPct = activeEntryDepth * scalingFactor;
   if (isBreakout) dynamicEntryPct = 0.05; 

   double dynamicMaxPct   = BaseMaxDepth * scalingFactor;
   
   double maxAllowedEntry = (customEntryDepth > 0) ? Storm_Max_Entry_Clamp : Normal_Max_Entry_Clamp;
   double maxAllowedLimit = (customEntryDepth > 0) ? Storm_Max_Limit_Clamp : Normal_Max_Limit_Clamp;
   
   if (dynamicEntryPct < 0.05) dynamicEntryPct = 0.05;
   if (dynamicEntryPct > maxAllowedEntry) dynamicEntryPct = maxAllowedEntry;
   
   if (dynamicMaxPct < 0.10) dynamicMaxPct = 0.10;
   if (dynamicMaxPct > maxAllowedLimit) dynamicMaxPct = maxAllowedLimit;
   
   double finalBuffer = BaseBufferPoints;
   if (customBuffer > 0) {
       finalBuffer = customBuffer;
   } else if (UseDynamicBuffer) {
      finalBuffer = BaseBufferPoints * scalingFactor * (1.0 + dynamicEntryPct);
      if (finalBuffer < MinBufferPoints) finalBuffer = MinBufferPoints;
      if (finalBuffer > MaxBufferPoints) finalBuffer = MaxBufferPoints;
   }

   if (type == 1) // Buy
   {
      double entryPriceStart = entryZone.top - (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = entryZone.top - (zoneHeightPrice * dynamicMaxPct);   
      
      bool signalFired = false;
      
      // Router: Blind Touch vs Confirmation
      if (EntryStyle == STYLE_BLIND_TOUCH) {
          if (ask <= entryPriceStart && ask >= entryPriceLimit) signalFired = true;
      } 
      else if (EntryStyle == STYLE_CONFIRMATION) {
          if (CheckConfirmation(1, entryPriceStart, entryPriceLimit)) signalFired = true;
      }
      
      if (signalFired) 
      {
         double sl = slZone.bottom - (finalBuffer * point);
         double tp = opposingSupply.bottom + ((opposingSupply.top - opposingSupply.bottom) * TPZoneDepth); 
         double risk = ask - sl; 
         double reward = tp - ask;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            string prefix = isBreakout ? "Brk " : ""; 
            bool res = OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, prefix + commentTag, tradeRisk);
            if (res && Debug_Show_Spread) Print(">>> SUCCESS: Buy Entry Sent.");
            return res;
         }
      }
   }
   else if (type == -1) // Sell
   {
      double entryPriceStart = entryZone.bottom + (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = entryZone.bottom + (zoneHeightPrice * dynamicMaxPct);   
      
      bool signalFired = false;
      
      // Router: Blind Touch vs Confirmation
      if (EntryStyle == STYLE_BLIND_TOUCH) {
          if (bid >= entryPriceStart && bid <= entryPriceLimit) signalFired = true;
      } 
      else if (EntryStyle == STYLE_CONFIRMATION) {
          if (CheckConfirmation(-1, entryPriceStart, entryPriceLimit)) signalFired = true;
      }
      
      if (signalFired) 
      {
         double sl = slZone.top + (finalBuffer * point);
         double tp = opposingDemand.top - ((opposingDemand.top - opposingDemand.bottom) * TPZoneDepth);
         double risk = sl - bid; 
         double reward = bid - tp;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            string prefix = isBreakout ? "Brk " : "";
            bool res = OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, prefix + commentTag, tradeRisk);
            if (res && Debug_Show_Spread) Print(">>> SUCCESS: Sell Entry Sent.");
            return res;
         }
      }
   }
   return false;
}

// *** MAIN CHECK FUNCTION ***
void CheckTradeEntry()
{
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

   if (MinMinutesBetweenTrades > 0 && GlobalLastTradeTime > 0) {
       if (TimeCurrent() - GlobalLastTradeTime < (MinMinutesBetweenTrades * 60)) {
           return; 
       }
   }

   double currentADR = CalculateADR(ADR_Period);
   
   if (Use_ADR_Filter) {

       if (currentADR < SectorC_Max_ADR) {
           if (Enable_SectorC_Range) {
               if (activeDemand_LTF.isActive) {
                   ExecuteEntryLogic(activeDemand_LTF, activeDemand_HTF, activeSupply_HTF, activeDemand_LTF, 1, false, "Range-Fade", ReferenceZonePips_LTF);
               }
               if (activeSupply_LTF.isActive) {
                   ExecuteEntryLogic(activeSupply_LTF, activeSupply_HTF, activeSupply_LTF, activeDemand_HTF, -1, false, "Range-Fade", ReferenceZonePips_LTF);
               }
           }
           return;
       }
       
       else if (currentADR > SectorE_Min_ADR) {
           if (Enable_SectorE_Storm) {
               double activeDepth = Storm_Entry_Depth;
               double activeBuffer = Storm_Buffer_Pips * 10.0; 
               
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
           return;
       }
   }

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
             ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, true, "ZiZ-Brk", ReferenceZonePips_LTF);
         }
      }
      return;
   }

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
             else if (currentMarketTrend_LTF == -1 && allowSells) ExecuteEntryLogic(activeSupply_LTF, activeSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, false, "LTF", ReferenceZonePips_LTF);
          }
          if (Simple_Breakout_LTF) { 
             if (activeFlippedSupply_LTF.isActive && activeDemand_LTF.isActive && activeFlippedSupply_HTF.endTime == 0) {
                if (allowSells) ExecuteEntryLogic(activeFlippedSupply_LTF, activeFlippedSupply_LTF, activeSupply_LTF, activeDemand_HTF, -1, true, "LTF", ReferenceZonePips_LTF);
             }
             if (activeFlippedDemand_LTF.isActive && activeSupply_LTF.isActive && activeFlippedDemand_HTF.endTime == 0) {
                if (allowBuys) ExecuteEntryLogic(activeFlippedDemand_LTF, activeFlippedDemand_LTF, activeSupply_LTF, activeDemand_LTF, 1, true, "LTF", ReferenceZonePips_LTF);
             }
          }
      }
   }
}

void ManageOpenPositions() { 
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
      
      if (isFridayCloseTime) {
          double standardRiskAmount = Account_Initial_Balance * (RiskPercent / 100.0);
          double currentProfitMoney = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
          
          if (currentProfitMoney >= (standardRiskAmount * Friday_Min_RR)) {
              Print(">>> FRIDAY CLOSE: High RR Cash Hit. Ticket: ", ticket, " Profit: ", currentProfitMoney, " (Target: ", (standardRiskAmount * Friday_Min_RR), ")");
              trade.PositionClose(ticket);
              continue; 
          }
      }

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

      if (!trailMoved && EnableProfitLocking) {
         double activeTriggerPct = LockTriggerPercent;
         double activeLockPct    = LockPositionPercent; 
         
         if (StringFind(comment, "Step") >= 0) {
             activeTriggerPct = Step_LockTriggerPercent;
             activeLockPct    = Step_LockPositionPercent; 
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
      
      if (!trailMoved && Enable_RR_Locking) {
         if (RR_Lock_Step_Only && StringFind(comment, "Step") < 0) { } 
         else {
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
   // --- CHECK BUY TRADES ---
   if (CurrentOpenBuyTicket != 0 && !PositionSelectByTicket(CurrentOpenBuyTicket)) { 
      if (HistorySelectByPosition((long)CurrentOpenBuyTicket)) { 
         double totalProfit = 0;
         int deals = HistoryDealsTotal(); 
         for(int i = 0; i < deals; i++) { 
            ulong ticket = HistoryDealGetTicket(i);
            totalProfit += (HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION));
         } 
         if (totalProfit < 0) { 
            Print(">>> BUY Trade LOSS. Buy Zone BURNED.");
            BuyZoneIsBurned = true; 
         } else { 
            Print(">>> BUY Trade WIN. Buy Zone remains ACTIVE.");
            BuyZoneIsBurned = false; 
         } 
      } 
      CurrentOpenBuyTicket = 0;
   } 

   // [NEW] PHOENIX LOGIC FOR BUY
   if (BuyZoneIsBurned && Enable_Phoenix_Sweep && activeDemand_HTF.isActive) {
       MqlRates rates[];
       ArraySetAsSeries(rates, true);
       if(CopyRates(_Symbol, TimeFrame_HTF, 1, 1, rates) == 1) {
           if (rates[0].time != LastPhoenixBuyTime) {
               double checkBottom = activeDemand_LTF.isActive ? activeDemand_LTF.bottom : activeDemand_HTF.bottom;
               if (rates[0].close >= checkBottom) {
                   Print(">>> PHOENIX RECOVERY (BUY): 1H Candle swept but closed safe. Un-burning Zone!");
                   BuyZoneIsBurned = false;
                   CurrentBuyZoneTradeCount = 0; 
                   LastPhoenixBuyTime = rates[0].time; 
               }
           }
       }
   }

   // --- CHECK SELL TRADES ---
   if (CurrentOpenSellTicket != 0 && !PositionSelectByTicket(CurrentOpenSellTicket)) { 
      if (HistorySelectByPosition((long)CurrentOpenSellTicket)) { 
         double totalProfit = 0;
         int deals = HistoryDealsTotal(); 
         for(int i = 0; i < deals; i++) { 
            ulong ticket = HistoryDealGetTicket(i);
            totalProfit += (HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION));
         } 
         if (totalProfit < 0) { 
            Print(">>> SELL Trade LOSS. Sell Zone BURNED.");
            SellZoneIsBurned = true; 
         } else { 
            Print(">>> SELL Trade WIN. Sell Zone remains ACTIVE.");
            SellZoneIsBurned = false; 
         } 
      } 
      CurrentOpenSellTicket = 0;
   } 
   
   // [NEW] PHOENIX LOGIC FOR SELL
   if (SellZoneIsBurned && Enable_Phoenix_Sweep && activeSupply_HTF.isActive) {
       MqlRates rates[];
       ArraySetAsSeries(rates, true);
       if(CopyRates(_Symbol, TimeFrame_HTF, 1, 1, rates) == 1) {
           if (rates[0].time != LastPhoenixSellTime) {
               double checkTop = activeSupply_LTF.isActive ? activeSupply_LTF.top : activeSupply_HTF.top;
               if (rates[0].close <= checkTop) {
                   Print(">>> PHOENIX RECOVERY (SELL): 1H Candle swept but closed safe. Un-burning Zone!");
                   SellZoneIsBurned = false;
                   CurrentSellZoneTradeCount = 0; 
                   LastPhoenixSellTime = rates[0].time; 
               }
           }
       }
   }
}

void ExportTransactionsToCSV()
{
   string filename = "NCI_Journal_" + _Symbol + ".csv";
   int file_handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
   
   if(file_handle != INVALID_HANDLE)
   {
      FileWrite(file_handle, "Time", "Ticket", "Type", "Lots", "Price", "RawProfit", "Commission", "Swap", "NetProfit", "ADR", "Strategy", "Comment", "H1 Trend", "M15 Trend");
      HistorySelect(0, TimeCurrent());
      int total_deals = HistoryDealsTotal();
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket_deal = HistoryDealGetTicket(i);
         long type = HistoryDealGetInteger(ticket_deal, DEAL_TYPE);
         
         if(type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL) 
         {
            string sType = (type == DEAL_TYPE_BUY) ? "Buy" : "Sell";
            string rawComment = HistoryDealGetString(ticket_deal, DEAL_COMMENT);
            
            string strategyType = "OTHER";
            if (StringFind(rawComment, "Step") >= 0) strategyType = "STEP";
            else if (StringFind(rawComment, "Swing") >= 0) strategyType = "SWING";
            else if (StringFind(rawComment, "Scalp") >= 0) strategyType = "SCALP";
            else if (StringFind(rawComment, "HTF") >= 0) strategyType = "HTF-SIMPLE";
            else if (StringFind(rawComment, "Brk") >= 0) strategyType = "BREAKOUT";
            else if (StringFind(rawComment, "Range") >= 0) strategyType = "RANGE-FADE"; 
            else if (StringFind(rawComment, "Storm") >= 0) strategyType = "STORM-MODE";
            
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
                       if (closeBracket > 0) m15_trend = StringSubstr(sub2, 0, closeBracket);
                   }
               }
            }
            
            double historicalADR = 0;
            datetime dealTime = (datetime)HistoryDealGetInteger(ticket_deal, DEAL_TIME);
            int dayShift = iBarShift(_Symbol, PERIOD_D1, dealTime);
            
            if (dayShift >= 0) {
                double highBuffer[], lowBuffer[];
                if (CopyHigh(_Symbol, PERIOD_D1, dayShift + 1, ADR_Period, highBuffer) == ADR_Period &&
                    CopyLow(_Symbol, PERIOD_D1, dayShift + 1, ADR_Period, lowBuffer) == ADR_Period) {
                    
                    double sumPips = 0;
                    for(int j = 0; j < ADR_Period; j++) {
                        sumPips += (highBuffer[j] - lowBuffer[j]) / point;
                    }
                    historicalADR = (sumPips / ADR_Period) / 10.0;
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
      
      if (MQLInfoInteger(MQL_TESTER)) {
          FileWrite(file_handle, "");
          FileWrite(file_handle, "--- ADR STATISTICS REPORT (Daily) ---");
          
          int lowCount = 0;
          int midCount = 0;
          int highCount = 0;
          int totalDays = 0;
          
          datetime startTest = 0;
          datetime endTest = 0;
          
          if (total_deals > 0) {
              startTest = (datetime)HistoryDealGetInteger(HistoryDealGetTicket(0), DEAL_TIME);
              endTest   = (datetime)HistoryDealGetInteger(HistoryDealGetTicket(total_deals-1), DEAL_TIME);
          }
          
          if (startTest > 0 && endTest > 0) {
              datetime timeBuffer[];
              int copiedDays = CopyTime(_Symbol, PERIOD_D1, startTest, endTest, timeBuffer);
              
              if (copiedDays > 0) {
                  for (int i = 0; i < copiedDays; i++) {
                      datetime barTime = timeBuffer[i];
                      int shift = iBarShift(_Symbol, PERIOD_D1, barTime);
                      
                      if (shift >= 0) {
                          double hBuf[], lBuf[];
                          if (CopyHigh(_Symbol, PERIOD_D1, shift + 1, ADR_Period, hBuf) == ADR_Period &&
                              CopyLow(_Symbol, PERIOD_D1, shift + 1, ADR_Period, lBuf) == ADR_Period) {
                              
                              double sumPips = 0;
                              for(int j = 0; j < ADR_Period; j++) {
                                  sumPips += (hBuf[j] - lBuf[j]) / point;
                              }
                              double dailyADR = (sumPips / ADR_Period) / 10.0;
                              
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
              FileWrite(file_handle, "Total Days Analyzed", (string)totalDays);
              FileWrite(file_handle, "Zone", "Count", "Percent");
              
              string pLow = DoubleToString(((double)lowCount / totalDays) * 100.0, 1) + "%";
              FileWrite(file_handle, "Low (< " + DoubleToString(Stats_ADR_Low, 0) + ")", (string)lowCount, pLow);
              
              string pMid = DoubleToString(((double)midCount / totalDays) * 100.0, 1) + "%";
              FileWrite(file_handle, "Mid (" + DoubleToString(Stats_ADR_Low, 0) + "-" + DoubleToString(Stats_ADR_High, 0) + ")", (string)midCount, pMid);
              
              string pHigh = DoubleToString(((double)highCount / totalDays) * 100.0, 1) + "%";
              FileWrite(file_handle, "High (> " + DoubleToString(Stats_ADR_High, 0) + ")", (string)highCount, pHigh);
          } else {
              FileWrite(file_handle, "Error", "No daily data could be processed. Test period might be too short.");
          }
      }
      
      FileClose(file_handle);
   }
}