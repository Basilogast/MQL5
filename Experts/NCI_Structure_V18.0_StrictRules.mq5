//+------------------------------------------------------------------+
//|         NCI_Structure_V78.7_CompleteLogic.mq5                    |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "78.70"
#property strict

#include <Trade\Trade.mqh>

// --- ENUMS ---
enum ENUM_REENTRY_MODE {
   MODE_SINGLE   = 0, // One Trade Only (Conservative)
   MODE_DOUBLE   = 1, // Two Trades (1st @ 1.0%, 2nd @ 0.5%) - DEFAULT
   MODE_INFINITE = 2  // Infinite Trades (Aggressive)
};

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 5000;
input int LineWidth         = 2;
input bool DrawZones        = true;

// ZONE COLORS (Fixed)
color SupplyColor     = clrMaroon; 
color DemandColor     = clrDarkGreen;
color FlippedColor    = clrGray; 

//--- 2. TREND COLORS (Fixed)
color ColorUp         = clrLimeGreen;
color ColorDown       = clrRed;
color ColorRange      = clrYellow;

//--- 3. STRUCTURE RULES
input group "Structure Rules"
input double MinBodyPercent = 0.50;  
input int MaxScanDistance   = 3;
input double BigCandleFactor = 1.3; 

//--- 4. TRADING SETTINGS
input group "Trading Logic"
input bool AllowTrading      = true;
input bool AllowTrendEntry    = true; 
input bool AllowBreakoutEntry = true; 
input double RiskPercent     = 1.0;  
input double MinRiskReward   = 2.0;  

// NEW: Re-Entry Mode (Default set to DOUBLE)
input group "Re-Entry Logic"
input ENUM_REENTRY_MODE EntryMode = MODE_DOUBLE; 

// NEW: Volatility Guard
input group "Volatility Guard"
input bool   UseVolatilityGuard = true; 
input int    MaxSpreadPoints   = 30; 
input int    MaxCandleSizePips = 80; // Optimized

//--- 5. SCALING & ENTRY
input group "Entry Logic"
input double ReferenceZonePips = 235.0;
input double BaseEntryDepth    = 0.40;  
input double BaseMaxDepth      = 0.75;
input double TPZoneDepth     = 0.0;

//--- 6. BUFFER SETTINGS
input group "Buffer Logic"
input bool   UseDynamicBuffer = false; 
input double BaseBufferPoints = 45.0;  
input double MinBufferPoints  = 20;   
input double MaxBufferPoints  = 200;  

//--- 7. RISK MANAGEMENT
input group "Risk Management"
input bool   EnableProfitLocking = true;
input double LockTriggerPercent  = 0.80; 
input double LockPositionPercent = 0.70; 

//--- GLOBALS
CTrade trade;
struct PointStruct {
   double price;
   datetime time;
   int type; 
   int barIndex;
   double zoneLimitTop;
   double zoneLimitBottom;
   int assignedTrend; 
};
PointStruct ZigZagPoints[];

struct MergedZoneState {
   bool isActive;
   double top;
   double bottom;
   datetime startTime; 
   datetime endTime; 
   int lastBarIndex;
};

MergedZoneState activeSupply;
MergedZoneState activeDemand;
MergedZoneState activeFlippedSupply; 
MergedZoneState activeFlippedDemand; 

int currentMarketTrend = 0;
ulong CurrentOpenTicket = 0;   
datetime CurrentZoneID = 0;
int CurrentZoneTradeCount = 0; 
bool ZoneIsBurned = false;    

// ==========================================================
//    FORWARD DECLARATIONS (MANIFEST)
// ==========================================================
// Basic Wrappers
double GetHigh(int index);
double GetLow(int index);
double GetOpen(int index);
double GetClose(int index);
datetime GetTime(int index);

// Trade Management
void ManageTradeState();
void ManageOpenPositions();
void CheckTradeEntry();
void ExecuteEntryLogic(MergedZoneState &zone, int type, bool isBreakout);
void OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp, string comment, double finalRiskPercent);

// Main Logic Engines
void UpdateZigZagMap();
void DrawParallelZones();
void CalculateTrendsAndLock();

// Zone & Breakout Helpers
double FindNextTarget(int currentIndex, int targetType);
datetime CheckZoneLife(int startBar, int type, double targetLevel, double selfBreakLevel);
bool CheckForBreakout(int startBarIdx, int endBarIdx, double level, int type);
datetime FindBreakoutTime(int startBar, int endBar, double level, int type); 

// Drawing & Math Helpers
void DrawFlippedZone(MergedZoneState &state, datetime endTime);
void MergeZone(MergedZoneState &state, PointStruct &p, int type);
void StartZone(MergedZoneState &state, PointStruct &p);
void DrawSingleZone(datetime t1, datetime t2, double top, double bottom, int type, int id);
void CalculateZoneLimits(PointStruct &p); 
void DrawZigZagLines();
bool IsBigCandle(int index);
void AddPoint(PointStruct &arr[], PointStruct &p);
bool IsStrongBody(int index);
bool IsGreen(int index);
bool IsRed(int index);
bool IsNewBar();
bool CheckVolatility(); 

// ==========================================================
//    CUSTOM WRAPPERS
// ==========================================================
double GetHigh(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyHigh(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetLow(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyLow(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetOpen(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyOpen(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetClose(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyClose(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
datetime GetTime(int index) {
   datetime buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyTime(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0;
}

// ==========================================================
//    MAIN PROGRAM
// ==========================================================
int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   ObjectsDeleteAll(0, "NCI_Zone_");
   UpdateZigZagMap();
   Print(">>> V78.7 INIT: Retro-Scan + Precise Timing + No Overlap.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ManageTradeState();       
   ManageOpenPositions();    
   
   if(IsNewBar()) UpdateZigZagMap();
   if(AllowTrading) CheckTradeEntry();
}

// ==========================================================
//    ENTRY LOGIC
// ==========================================================
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

bool CheckVolatility() 
{
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if (spread > MaxSpreadPoints) return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double size0 = (GetHigh(0) - GetLow(0)) / point / 10.0; 
   double size1 = (GetHigh(1) - GetLow(1)) / point / 10.0; 
   
   if (size0 > MaxCandleSizePips) return false;
   if (size1 > MaxCandleSizePips) return false;
   
   return true;
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
   
   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, "NCI V78.7 " + comment)) {
      CurrentOpenTicket = trade.ResultOrder();
      CurrentZoneTradeCount++; 
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

// ==========================================================
// V78.6: FIXED OVERLAP LOGIC (PRECISE HANDOFF)
// ==========================================================
void DrawParallelZones() { 
   ObjectsDeleteAll(0, "NCI_Zone_");
   ObjectsDeleteAll(0, "NCI_Flip_"); 
   
   activeFlippedSupply.isActive = false; 
   activeFlippedDemand.isActive = false; 
   
   int count = ArraySize(ZigZagPoints); 
   if (count == 0) return; 
   MergedZoneState supply; supply.isActive = false; 
   MergedZoneState demand; demand.isActive = false; 
   
   for (int i = 0; i < count; i++) { 
      PointStruct p = ZigZagPoints[i]; 
      
      if (p.type == 1) { 
         if (!supply.isActive) StartZone(supply, p); 
         else { 
            bool isBroken = CheckForBreakout(supply.lastBarIndex, p.barIndex, supply.top, 1);
            if (p.price > supply.top) isBroken = true; 

            if (isBroken) { 
               // *** FIX 1: FIND EXACT BREAK TIME ***
               datetime preciseBreakTime = FindBreakoutTime(supply.lastBarIndex, p.barIndex, supply.top, 1);
               if (preciseBreakTime == 0) preciseBreakTime = p.time; // Fallback

               // *** FIX 2: STOP OLD ZONE AT BREAK TIME (NO OVERLAP) ***
               DrawSingleZone(supply.startTime, preciseBreakTime, supply.top, supply.bottom, 1, i-1); 
               
               if (p.assignedTrend != 1) { 
                   MergedZoneState flip = supply;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; // START GRAY ZONE EXACTLY HERE
                   
                   double histTarget = FindNextTarget(i, 1); 
                   
                   datetime deathTime = CheckZoneLife(p.barIndex, 1, histTarget, supply.bottom);
                   
                   if (deathTime == 0) {
                      activeFlippedDemand = flip;
                      activeFlippedDemand.endTime = 0; 
                      DrawFlippedZone(flip, TimeCurrent()+PeriodSeconds()*50); 
                   } else {
                      DrawFlippedZone(flip, deathTime); 
                   }
               }
               StartZone(supply, p); 
            } else { 
               // Standard Merging Logic
               bool shouldMerge = false; 
               if (p.zoneLimitTop > supply.top) shouldMerge = true; 
               else { 
                  bool isOverlapping = (MathMax(supply.bottom, p.zoneLimitBottom) <= MathMin(supply.top, p.zoneLimitTop)); 
                  if (isOverlapping) shouldMerge = true; 
               } 
               if (shouldMerge) { 
                  DrawSingleZone(supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); 
                  MergeZone(supply, p, 1); 
               } else { 
                  DrawSingleZone(supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); 
                  StartZone(supply, p); 
               } 
            } 
         } 
      } 
      else if (p.type == -1) { 
         if (!demand.isActive) StartZone(demand, p); 
         else { 
            bool isBroken = CheckForBreakout(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            if (p.price < demand.bottom) isBroken = true; 

            if (isBroken) { 
               // *** FIX 1: FIND EXACT BREAK TIME ***
               datetime preciseBreakTime = FindBreakoutTime(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
               if (preciseBreakTime == 0) preciseBreakTime = p.time; // Fallback

               // *** FIX 2: STOP OLD ZONE AT BREAK TIME (NO OVERLAP) ***
               DrawSingleZone(demand.startTime, preciseBreakTime, demand.top, demand.bottom, -1, i-1); 
               
               if (p.assignedTrend != -1) { 
                   MergedZoneState flip = demand;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; // START GRAY ZONE EXACTLY HERE
                   
                   double histTarget = FindNextTarget(i, -1);
                   
                   datetime deathTime = CheckZoneLife(p.barIndex, -1, histTarget, demand.top);
                   
                   if (deathTime == 0) {
                      activeFlippedSupply = flip;
                      activeFlippedSupply.endTime = 0; 
                      DrawFlippedZone(flip, TimeCurrent()+PeriodSeconds()*50); 
                   } else {
                      DrawFlippedZone(flip, deathTime); 
                   }
               }
               StartZone(demand, p); 
            } else { 
               // Standard Merging Logic
               bool shouldMerge = false; 
               if (p.zoneLimitBottom < demand.bottom) shouldMerge = true; 
               else { 
                  bool isOverlapping = (MathMax(demand.bottom, p.zoneLimitBottom) <= MathMin(demand.top, p.zoneLimitTop)); 
                  if (isOverlapping) shouldMerge = true; 
               } 
               if (shouldMerge) { 
                  DrawSingleZone(demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); 
                  MergeZone(demand, p, -1); 
               } else { 
                  DrawSingleZone(demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); 
                  StartZone(demand, p); 
               } 
            } 
         } 
      } 
   } 
   
   if (supply.isActive) DrawSingleZone(supply.startTime, TimeCurrent()+PeriodSeconds()*50, supply.top, supply.bottom, 1, 999991); 
   if (demand.isActive) DrawSingleZone(demand.startTime, TimeCurrent()+PeriodSeconds()*50, demand.top, demand.bottom, -1, 999992); 
   
   activeSupply = supply; 
   activeDemand = demand; 
   ChartRedraw(); 
}

// *** HELPER: Scans range to find exact breakout candle ***
datetime FindBreakoutTime(int startBar, int endBar, double level, int type) {
   for (int i = startBar - 1; i >= endBar; i--) {
       if (i < 0) return 0;
       if (type == 1) { // Supply Break (Up)
           if (GetClose(i) > level) return GetTime(i);
       } else { // Demand Break (Down)
           if (GetClose(i) < level) return GetTime(i);
       }
   }
   return 0;
}

// ==========================================================
// V78.7: RETRO-SCAN TARGETS (LOOK BACKWARDS) - THE FIX
// ==========================================================
double FindNextTarget(int currentIndex, int targetType)
{
   // FIXED: Look BACKWARDS into history to find the previous structure
   for(int k = currentIndex - 1; k >= 0; k--) 
   {
      if (ZigZagPoints[k].type == targetType) {
         if (targetType == 1) return ZigZagPoints[k].zoneLimitBottom; 
         if (targetType == -1) return ZigZagPoints[k].zoneLimitTop;   
      }
   }
   return 0; 
}

// ==========================================================
// V78.4: SMART TARGETS (SIMPLE HIT, STRICT BREAK)
// ==========================================================
datetime CheckZoneLife(int startBar, int type, double targetLevel, double selfBreakLevel)
{
   for(int i = startBar - 1; i > 0; i--) 
   {
      double close = GetClose(i);

      if (targetLevel != 0) {
          if (type == 1) { 
             if (close > targetLevel) return GetTime(i);
          } else { 
             if (close < targetLevel) return GetTime(i);
          }
      }

      if (type == 1) { 
          if (CheckForBreakout(i+1, i, selfBreakLevel, -1)) return GetTime(i);
      } else { 
          if (CheckForBreakout(i+1, i, selfBreakLevel, 1)) return GetTime(i);
      }
   }
   return 0; 
}

void DrawFlippedZone(MergedZoneState &state, datetime endTime) {
   string name = "NCI_Flip_" + TimeToString(state.startTime);
   if(ObjectFind(0,name)<0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, state.startTime, state.top, endTime, state.bottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, FlippedColor); 
      ObjectSetInteger(0, name, OBJPROP_FILL, true); 
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   } else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, endTime);
   }
}

// ==========================================================
// V78.0: BLIND SPOT FIX (MANUAL CHECK IN TREND LOGIC)
// ==========================================================
void CalculateTrendsAndLock() { 
   int count = ArraySize(ZigZagPoints); 
   if (count < 2) return; 
   int runningTrend = 0; 
   double lastSupplyLevel = 0; int lastSupplyIdx = -1; 
   double lastDemandLevel = 0; int lastDemandIdx = -1; 
   double prevHigh = 0; double prevLow = 0; 
   for (int i = 1; i < count; i++) { 
      PointStruct p = ZigZagPoints[i]; 
      PointStruct prev = ZigZagPoints[i-1]; 
      if (prev.type == 1) { lastSupplyLevel = prev.zoneLimitTop; lastSupplyIdx = prev.barIndex; prevHigh = prev.price; } 
      if (prev.type == -1) { lastDemandLevel = prev.zoneLimitBottom; lastDemandIdx = prev.barIndex; prevLow = prev.price; } 
      
      bool brokenSupply = false; bool brokenDemand = false; 
      
      if (lastSupplyIdx != -1) {
          brokenSupply = CheckForBreakout(lastSupplyIdx, p.barIndex, lastSupplyLevel, 1);
          if (p.price > lastSupplyLevel) brokenSupply = true; 
      }
      
      if (lastDemandIdx != -1) {
          brokenDemand = CheckForBreakout(lastDemandIdx, p.barIndex, lastDemandLevel, -1);
          if (p.price < lastDemandLevel) brokenDemand = true; 
      }

      if (runningTrend == -1) { if (brokenSupply) runningTrend = 0; } 
      else if (runningTrend == 1) { if (brokenDemand) runningTrend = 0; } 
      else { 
         if (p.type == 1) { if (brokenSupply || (prevHigh != 0 && p.price > prevHigh)) { if (!brokenDemand) runningTrend = 1; } } 
         if (p.type == -1) { if (brokenDemand || (prevLow != 0 && p.price < prevLow)) { if (!brokenSupply) runningTrend = -1; } } 
         if (brokenSupply && p.type == 1 && prevHigh != 0 && p.price > prevHigh) runningTrend = 1; 
         if (brokenDemand && p.type == -1 && prevLow != 0 && p.price < prevLow) runningTrend = -1; 
      } 
      ZigZagPoints[i].assignedTrend = runningTrend; 
   } 
   currentMarketTrend = runningTrend; 
}

bool CheckForBreakout(int startBarIdx, int endBarIdx, double level, int type) { 
   for (int i = startBarIdx - 1; i >= endBarIdx; i--) { 
      if (i-1 < 0) return false; 
      if (type == 1) { 
         double c1 = GetClose(i); 
         double c2 = GetClose(i-1); 
         if (c1 > level && c2 > level && c2 > c1) return true; 
      } else { 
         double c1 = GetClose(i); 
         double c2 = GetClose(i-1); 
         if (c1 < level && c2 < level && c2 < c1) return true; 
      } 
   } 
   return false; 
}

void CalculateZoneLimits(PointStruct &p) { 
   p.zoneLimitTop = p.price; 
   p.zoneLimitBottom = p.price; 
   if (p.type == 1) { 
      int gI=-1, rI=-1; 
      for(int k=0;k<=5;k++){
         if(p.barIndex+k >= Bars(_Symbol,_Period)) break; 
         if(IsGreen(p.barIndex+k)){gI=p.barIndex+k;break;}
      } 
      if(gI!=-1) rI=gI-1; 
      if(gI!=-1) { 
         p.zoneLimitBottom = GetOpen(gI); 
         if(IsBigCandle(gI)){ 
            if(rI!=-1){ 
               p.zoneLimitBottom = GetOpen(rI); 
               if(IsBigCandle(rI)) p.zoneLimitBottom=(GetOpen(rI)+GetClose(rI))/2.0; 
            } else p.zoneLimitBottom=(GetOpen(gI)+GetClose(gI))/2.0; 
         } 
      } 
   } else { 
      int rI=-1, gI=-1; 
      for(int k=0;k<=5;k++){
         if(p.barIndex+k >= Bars(_Symbol,_Period)) break; 
         if(IsRed(p.barIndex+k)){rI=p.barIndex+k;break;}
      } 
      if(rI!=-1) gI=rI-1; 
      if(rI!=-1) { 
         p.zoneLimitTop = GetOpen(rI); 
         if(IsBigCandle(rI)){ 
            if(gI!=-1){ 
               p.zoneLimitTop = GetOpen(gI); 
               if(IsBigCandle(gI)) p.zoneLimitTop=(GetOpen(gI)+GetClose(gI))/2.0; 
            } else p.zoneLimitTop=(GetOpen(rI)+GetClose(rI))/2.0; 
         } 
      } 
   } 
}

bool IsBigCandle(int index) { 
   double b=MathAbs(GetOpen(index)-GetClose(index)); 
   double s=0; int c=0; 
   int bars = Bars(_Symbol, _Period); 
   for(int k=1;k<=10;k++){
      if(index+k>=bars)break;
      s+=MathAbs(GetOpen(index+k)-GetClose(index+k));
      c++;
   } 
   if(c==0)return false; return(b>(s/c)*BigCandleFactor); 
}

void DrawZigZagLines() { 
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   int c=ArraySize(ZigZagPoints); 
   if(c<2)return; 
   for(int i=1;i<c;i++){ 
      int t=ZigZagPoints[i].assignedTrend; 
      color cl=(t==1)?ColorUp:(t==-1)?ColorDown:ColorRange; 
      string n="NCI_ZZ_"+IntegerToString(i); 
      ObjectCreate(0,n,OBJ_TREND,0,ZigZagPoints[i-1].time,ZigZagPoints[i-1].price,ZigZagPoints[i].time,ZigZagPoints[i].price); 
      ObjectSetInteger(0,n,OBJPROP_COLOR,cl); 
      ObjectSetInteger(0,n,OBJPROP_WIDTH,LineWidth); 
      ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); 
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); 
   } 
   ChartRedraw(); 
}

void DrawZigZag() { /* Deprecated */ }

// ... (STANDARD HELPERS) ...
void AddPoint(PointStruct &arr[], PointStruct &p) { int s=ArraySize(arr); ArrayResize(arr,s+1); arr[s]=p; }
void StartZone(MergedZoneState &state, PointStruct &p) { state.isActive=true; state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex; }
void MergeZone(MergedZoneState &state, PointStruct &p, int type) { 
   if (type == 1) { state.top = MathMax(state.top, p.price); state.bottom = p.zoneLimitBottom; } 
   else { state.bottom = MathMin(state.bottom, p.price); state.top = p.zoneLimitTop; } 
   state.startTime = p.time; state.lastBarIndex = p.barIndex; 
}
void DrawSingleZone(datetime t1, datetime t2, double top, double bottom, int type, int id) { 
   if (top <= bottom) return; 
   string name = "NCI_Zone_M_" + IntegerToString(id) + "_" + TimeToString(t1); 
   color c = (type == 1) ? SupplyColor : DemandColor; 
   if(ObjectFind(0,name)<0) { ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom); ObjectSetInteger(0, name, OBJPROP_COLOR, c); ObjectSetInteger(0, name, OBJPROP_FILL, true); ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); } 
}

bool IsStrongBody(int index) { double h=GetHigh(index); double l=GetLow(index); if(h-l==0)return false; double b=MathAbs(GetOpen(index)-GetClose(index)); return(b>(h-l)*MinBodyPercent); }
bool IsGreen(int index) { return GetClose(index)>GetOpen(index); }
bool IsRed(int index) { return GetClose(index)<GetOpen(index); }
bool IsNewBar() { static datetime last; datetime curr=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); if(last!=curr){last=curr;return true;} return false; }

// ==========================================================
// V77: FLEXIBLE BREAKOUT LOGIC (THE ENGINE)
// ==========================================================
void UpdateZigZagMap() { 
   int totalBars = Bars(_Symbol, _Period); 
   if (totalBars < 500) return; 
   PointStruct Alarms[]; 
   int alarmCount = 0; 
   int startBar = MathMin(HistoryBars, totalBars - 10); 
   for (int i = startBar; i >= 5; i--) { 
      if (IsGreen(i)) { 
         int c1=i-1; int c2=i-2; 
         if(IsRed(c1)){ 
            if(IsStrongBody(c1)){ 
               bool confirm = false;
               if(IsRed(c2)) confirm = true;
               else if(GetClose(c2) < GetOpen(i)) confirm = true; 
               if(confirm) { 
                  ArrayResize(Alarms,alarmCount+1); 
                  Alarms[alarmCount].price=GetHigh(i); 
                  Alarms[alarmCount].time=GetTime(i); 
                  Alarms[alarmCount].type=1; 
                  Alarms[alarmCount].barIndex=i; 
                  alarmCount++; 
               } 
            } else { 
               double rl=GetLow(c1); 
               for(int k=1;k<=MaxScanDistance;k++){ 
                  int n=c1-k; 
                  if(n<0||GetHigh(n)>GetHigh(i))break; 
                  if(IsRed(n)&&IsStrongBody(n)&&GetClose(n)<rl){ 
                     ArrayResize(Alarms,alarmCount+1); 
                     Alarms[alarmCount].price=GetHigh(i); 
                     Alarms[alarmCount].time=GetTime(i); 
                     Alarms[alarmCount].type=1; 
                     Alarms[alarmCount].barIndex=i; 
                     alarmCount++; 
                     break;
                  } 
               } 
            } 
         } 
      } 
      if (IsRed(i)) { 
         int c1=i-1; int c2=i-2; 
         if(IsGreen(c1)){ 
            if(IsStrongBody(c1)){ 
               bool confirm = false;
               if(IsGreen(c2)) confirm = true;
               else if(GetClose(c2) > GetOpen(i)) confirm = true;
               if(confirm) { 
                  ArrayResize(Alarms,alarmCount+1); 
                  Alarms[alarmCount].price=GetLow(i); 
                  Alarms[alarmCount].time=GetTime(i); 
                  Alarms[alarmCount].type=-1; 
                  Alarms[alarmCount].barIndex=i; 
                  alarmCount++; 
               } 
            } else { 
               double rh=GetHigh(c1); 
               for(int k=1;k<=MaxScanDistance;k++){ 
                  int n=c1-k; 
                  if(n<0||GetLow(n)<GetLow(i))break; 
                  if(IsGreen(n)&&IsStrongBody(n)&&GetClose(n)>rh){ 
                     ArrayResize(Alarms,alarmCount+1); 
                     Alarms[alarmCount].price=GetLow(i); 
                     Alarms[alarmCount].time=GetTime(i); 
                     Alarms[alarmCount].type=-1; 
                     Alarms[alarmCount].barIndex=i; 
                     alarmCount++; 
                     break;
                  } 
               } 
            } 
         } 
      } 
   } 
   if (alarmCount < 2) return; 
   ArrayResize(ZigZagPoints, 0); 
   int state = 0; 
   PointStruct pendingPoint; 
   int lastCommittedIndex = startBar + 5; 
   if (Alarms[0].type == 1) { 
      AddPoint(ZigZagPoints, Alarms[0]); 
      lastCommittedIndex = Alarms[0].barIndex; 
      state = -1; 
      pendingPoint.price = 999999; 
   } else { 
      AddPoint(ZigZagPoints, Alarms[0]); 
      lastCommittedIndex = Alarms[0].barIndex; 
      state = 1; 
      pendingPoint.price = 0; 
   } 
   for (int i = 1; i < alarmCount; i++) { 
      int searchStart = Alarms[i].barIndex; 
      int searchEnd = lastCommittedIndex - 1; 
      int count = searchEnd - searchStart + 1; 
      if (count <= 0) continue; 
      if (state == 1) { 
         int hI = iHighest(_Symbol, _Period, MODE_HIGH, count, searchStart); 
         double hP = GetHigh(hI); 
         if (hP > pendingPoint.price) { 
            pendingPoint.price=hP; 
            pendingPoint.time=GetTime(hI); 
            pendingPoint.barIndex=hI; 
            pendingPoint.type=1; 
         } 
         if (Alarms[i].type == -1) { 
            AddPoint(ZigZagPoints, pendingPoint); 
            lastCommittedIndex=pendingPoint.barIndex; 
            state=-1; 
            pendingPoint.price=999999; 
            i--; 
         } 
      } else if (state == -1) { 
         int lI = iLowest(_Symbol, _Period, MODE_LOW, count, searchStart); 
         double lP = GetLow(lI); 
         if (lP < pendingPoint.price) { 
            pendingPoint.price=lP; 
            pendingPoint.time=GetTime(lI); 
            pendingPoint.barIndex=lI; 
            pendingPoint.type=-1; 
         } 
         if (Alarms[i].type == 1) { 
            AddPoint(ZigZagPoints, pendingPoint); 
            lastCommittedIndex=pendingPoint.barIndex; 
            state=1; 
            pendingPoint.price=0; 
            i--; 
         } 
      } 
   } 
   for(int i=0; i<ArraySize(ZigZagPoints); i++) CalculateZoneLimits(ZigZagPoints[i]); 
   CalculateTrendsAndLock(); 
   DrawZigZagLines(); 
   if(DrawZones) DrawParallelZones(); 
}