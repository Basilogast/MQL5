//+------------------------------------------------------------------+
//| NCI_Trade.mqh - Execution & Management                           |
//+------------------------------------------------------------------+
#property strict

// *** CRITICAL FIX: Include dependencies so this file sees the variables ***
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh" // For CheckVolatility, GetHigh, etc.

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

void ExecuteEntryLogic(MergedZoneState &zone, int type, bool isBreakout)
{
   datetime relevantTime = zone.startTime;
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
   else if (EntryMode == MODE_INFINITE) 
   {
      tradeRisk = RiskPercent; 
   }

   if (UseVolatilityGuard)
   {
       if (!CheckVolatility()) return; 
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double zoneHeightPrice = zone.top - zone.bottom;
   double zoneHeightPips = zoneHeightPrice / point;
   if (zoneHeightPips <= 0) zoneHeightPips = 1; 
   
   double scalingFactor = ReferenceZonePips / zoneHeightPips;
   double dynamicEntryPct = BaseEntryDepth * scalingFactor;
   double dynamicMaxPct   = BaseMaxDepth * scalingFactor;
   
   if (dynamicEntryPct < 0.05) dynamicEntryPct = 0.05;
   if (dynamicEntryPct > 0.60) dynamicEntryPct = 0.60;
   if (dynamicMaxPct < 0.10) dynamicMaxPct = 0.10;
   if (dynamicMaxPct > 0.80) dynamicMaxPct = 0.80;

   double finalBuffer = BaseBufferPoints; 
   if (UseDynamicBuffer) 
   {
      finalBuffer = BaseBufferPoints * scalingFactor * (1.0 + dynamicEntryPct);
      if (finalBuffer < MinBufferPoints) finalBuffer = MinBufferPoints;
      if (finalBuffer > MaxBufferPoints) finalBuffer = MaxBufferPoints;
   }

   if (type == 1) // Buy
   {
      double entryPriceStart = zone.top - (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = zone.top - (zoneHeightPrice * dynamicMaxPct);   
      
      if (ask <= entryPriceStart && ask >= entryPriceLimit) 
      {
         double sl = zone.bottom - (finalBuffer * point);
         double tp = activeSupply.bottom + ((activeSupply.top - activeSupply.bottom) * TPZoneDepth); 
         double risk = entryPriceStart - sl; 
         double reward = tp - entryPriceStart;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, isBreakout ? "Breakout" : "Standard", tradeRisk);
         }
      }
   }
   else if (type == -1) // Sell
   {
      double entryPriceStart = zone.bottom + (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = zone.bottom + (zoneHeightPrice * dynamicMaxPct);   
      
      if (bid >= entryPriceStart && bid <= entryPriceLimit) 
      {
         double sl = zone.top + (finalBuffer * point);
         double tp = activeDemand.top - ((activeDemand.top - activeDemand.bottom) * TPZoneDepth);
         double risk = sl - entryPriceStart;
         double reward = entryPriceStart - tp;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, isBreakout ? "Breakout" : "Standard", tradeRisk);
         }
      }
   }
}

void CheckTradeEntry()
{
   if (PositionsTotal() > 0) return;

   if (AllowTrendEntry && activeSupply.isActive && activeDemand.isActive) 
   {
      if (currentMarketTrend == 1) ExecuteEntryLogic(activeDemand, 1, false);
      else if (currentMarketTrend == -1) ExecuteEntryLogic(activeSupply, -1, false);
   }

   if (AllowBreakoutEntry) 
   {
      if (activeFlippedSupply.isActive && activeDemand.isActive) {
         if (activeFlippedSupply.endTime == 0) {
            ExecuteEntryLogic(activeFlippedSupply, -1, true);
         }
      }
      if (activeFlippedDemand.isActive && activeSupply.isActive) {
         if (activeFlippedDemand.endTime == 0) {
            ExecuteEntryLogic(activeFlippedDemand, 1, true);
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
            Print(">>> Trade LOSS on Zone ", TimeToString(CurrentZoneID), ". Zone BURNED."); 
            ZoneIsBurned = true; 
         } else { 
            Print(">>> Trade WIN. Zone remains ACTIVE for Re-Entry (Count: ", CurrentZoneTradeCount, ")"); 
            ZoneIsBurned = false; 
         } 
      } 
      CurrentOpenTicket = 0; 
   } 
}