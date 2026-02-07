//+------------------------------------------------------------------+
//|         NCI_Structure_V66.0_HistoryFixed.mq5                     |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "66.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 5000;
input int LineWidth         = 2;
input bool DrawZones        = true;
input color SupplyColor     = clrMaroon; 
input color DemandColor     = clrDarkGreen;
input color FlippedColor    = clrGray; 

//--- 2. TREND COLORS
input group "Trend Colors"
input color ColorUp         = clrLimeGreen;
input color ColorDown       = clrRed;
input color ColorRange      = clrYellow;

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

//--- 5. SCALING & ENTRY (V51 Golden Settings)
input group "Entry Logic"
input double ReferenceZonePips = 235.0;
input double BaseEntryDepth    = 0.40;  
input double BaseMaxDepth      = 0.75;
input double TPZoneDepth     = 0.0;
input double SLBufferPoints  = 50;

//--- 6. RISK MANAGEMENT (V58 Profit Locking)
input group "Risk Management"
input bool   EnableProfitLocking = true;
input double LockTriggerPercent  = 0.80;  
input double LockPositionPercent = 0.50;  

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
bool ZoneIsBurned = false;    

int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   ObjectsDeleteAll(0, "NCI_Zone_");
   UpdateZigZagMap();
   Print(">>> V66 INIT: Time-Travel Logic Fix. Historical Targets are now accurate.");
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

   // 1. STANDARD ENTRIES
   if (AllowTrendEntry && activeSupply.isActive && activeDemand.isActive) 
   {
      if (currentMarketTrend == 1) ExecuteEntryLogic(activeDemand, 1, false);
      else if (currentMarketTrend == -1) ExecuteEntryLogic(activeSupply, -1, false);
   }

   // 2. BREAKOUT ENTRIES
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
   }
   if (ZoneIsBurned) return;

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

   if (type == 1) // Buy
   {
      double entryPriceStart = zone.top - (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = zone.top - (zoneHeightPrice * dynamicMaxPct);   
      
      if (ask <= entryPriceStart && ask >= entryPriceLimit) 
      {
         double sl = zone.bottom - (SLBufferPoints * point);
         double tp = activeSupply.bottom + ((activeSupply.top - activeSupply.bottom) * TPZoneDepth); 
         double risk = entryPriceStart - sl;
         double reward = tp - entryPriceStart;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            OpenTrade(ORDER_TYPE_BUY, ask, sl, tp, isBreakout ? "Breakout" : "Standard");
         }
      }
   }
   else if (type == -1) // Sell
   {
      double entryPriceStart = zone.bottom + (zoneHeightPrice * dynamicEntryPct);
      double entryPriceLimit = zone.bottom + (zoneHeightPrice * dynamicMaxPct);   
      
      if (bid >= entryPriceStart && bid <= entryPriceLimit) 
      {
         double sl = zone.top + (SLBufferPoints * point);
         double tp = activeDemand.top - ((activeDemand.top - activeDemand.bottom) * TPZoneDepth);
         double risk = sl - entryPriceStart;
         double reward = entryPriceStart - tp;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) {
            OpenTrade(ORDER_TYPE_SELL, bid, sl, tp, isBreakout ? "Breakout" : "Standard");
         }
      }
   }
}

void OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp, string comment)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);
   double riskPoints = MathAbs(price - sl) / _Point;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if (riskPoints <= 0 || tickValue == 0) return;
   double lotSize = NormalizeDouble(riskAmount / (riskPoints * tickValue), 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (lotSize < minLot) lotSize = minLot;
   if (lotSize > maxLot) lotSize = maxLot;
   if(trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, "NCI V66 " + comment)) {
      CurrentOpenTicket = trade.ResultOrder();
   }
}

// ... (Standard Helpers: ManageOpenPositions, ManageTradeState same as V65) ...
void ManageOpenPositions() { if (!EnableProfitLocking) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--) { ulong ticket = PositionGetTicket(i); if(ticket <= 0) continue;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue; if(PositionGetInteger(POSITION_MAGIC) != 111222) continue; long openTime = PositionGetInteger(POSITION_TIME); long updateTime = PositionGetInteger(POSITION_TIME_UPDATE);
   if (updateTime > openTime) continue; double openPrice = PositionGetDouble(POSITION_PRICE_OPEN); double currentTP = PositionGetDouble(POSITION_TP); double currentPrice = 0;
   long type = PositionGetInteger(POSITION_TYPE); if (currentTP == 0) continue; if (type == POSITION_TYPE_BUY) { currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double totalProfitDist = currentTP - openPrice; if (totalProfitDist <= 0) continue; double triggerPrice = openPrice + (totalProfitDist * LockTriggerPercent);
   if (currentPrice >= triggerPrice) { double newSL = openPrice + (totalProfitDist * LockPositionPercent);
   if (newSL > PositionGetDouble(POSITION_SL) + _Point) trade.PositionModify(ticket, newSL, currentTP); } } else if (type == POSITION_TYPE_SELL) { currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double totalProfitDist = openPrice - currentTP; if (totalProfitDist <= 0) continue; double triggerPrice = openPrice - (totalProfitDist * LockTriggerPercent);
   if (currentPrice <= triggerPrice) { double newSL = openPrice - (totalProfitDist * LockPositionPercent);
   if (newSL < PositionGetDouble(POSITION_SL) - _Point) trade.PositionModify(ticket, newSL, currentTP); } } } }
void ManageTradeState() { if (CurrentOpenTicket != 0 && !PositionSelectByTicket(CurrentOpenTicket)) { if (HistorySelectByPosition((long)CurrentOpenTicket)) { double totalProfit = 0;
   int deals = HistoryDealsTotal(); for(int i = 0; i < deals; i++) { ulong ticket = HistoryDealGetTicket(i);
   totalProfit += (HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION));
   } if (totalProfit < 0) { Print(">>> Trade LOSS on Zone ", TimeToString(CurrentZoneID), ". Zone BURNED."); ZoneIsBurned = true;
   } else { Print(">>> Trade WIN. Zone remains ACTIVE."); ZoneIsBurned = false; } } CurrentOpenTicket = 0;
   } }

// ==========================================================
//    ZONE DRAWING (V66 TIME TRAVEL FIX)
// ==========================================================
void DrawParallelZones() { 
   ObjectsDeleteAll(0, "NCI_Zone_");
   ObjectsDeleteAll(0, "NCI_Flip_"); 
   
   activeFlippedSupply.isActive = false; 
   activeFlippedDemand.isActive = false; 
   
   int count = ArraySize(ZigZagPoints); 
   if (count == 0) return; 
   MergedZoneState supply;
   supply.isActive = false; 
   MergedZoneState demand; demand.isActive = false; 
   
   for (int i = 0; i < count; i++) { 
      PointStruct p = ZigZagPoints[i];
      // --- SUPPLY LOGIC ---
      if (p.type == 1) { 
         if (!supply.isActive) StartZone(supply, p);
         else { 
            bool isBroken = CheckForBreakout(supply.lastBarIndex, p.barIndex, supply.top, 1);
            if (isBroken) { 
               DrawSingleZone(supply.startTime, p.time, supply.top, supply.bottom, 1, i-1);
               
               if (p.assignedTrend != 1) { // Reversal Only
                   MergedZoneState flip = supply;
                   flip.isActive = true;
                   flip.startTime = p.time;
                   
                   // *** V66 FIX: Find the SPECIFIC historical target ***
                   // Flip to Demand (Buy). Target is Supply.
                   double histTarget = FindNextTarget(i, 1); 
                   if (histTarget == 0) histTarget = activeSupply.bottom; // Fallback to current if no future history
                   
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
      // --- DEMAND LOGIC ---
      else if (p.type == -1) { 
         if (!demand.isActive) StartZone(demand, p);
         else { 
            bool isBroken = CheckForBreakout(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            if (isBroken) { 
               DrawSingleZone(demand.startTime, p.time, demand.top, demand.bottom, -1, i-1);
               
               if (p.assignedTrend != -1) { // Reversal Only
                   MergedZoneState flip = demand;
                   flip.isActive = true;
                   flip.startTime = p.time;
                   
                   // *** V66 FIX: Find the SPECIFIC historical target ***
                   // Flip to Supply (Sell). Target is Demand.
                   double histTarget = FindNextTarget(i, -1);
                   if (histTarget == 0) histTarget = activeDemand.top;
                   
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

// V66 NEW HELPER: Look Ahead in ZigZag History
double FindNextTarget(int currentIndex, int targetType)
{
   int total = ArraySize(ZigZagPoints);
   // Look forward in the array (future points relative to currentIndex)
   for(int k = currentIndex + 1; k < total; k++) 
   {
      if (ZigZagPoints[k].type == targetType) {
         // Found the next target!
         if (targetType == 1) return ZigZagPoints[k].zoneLimitBottom; // Supply Bottom
         if (targetType == -1) return ZigZagPoints[k].zoneLimitTop;   // Demand Top
      }
   }
   return 0; // No future target found (we are at live edge)
}

datetime CheckZoneLife(int startBar, int type, double targetLevel, double selfBreakLevel)
{
   for(int i = startBar - 1; i >= 0; i--) 
   {
      double close = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      if (i > 0) close = iClose(_Symbol, _Period, i);      
      
      if (type == 1) { 
         if ((close > targetLevel && targetLevel != 0) || (close < selfBreakLevel)) 
            return iTime(_Symbol, _Period, i);
      }
      else if (type == -1) { 
         if ((close < targetLevel && targetLevel != 0) || (close > selfBreakLevel)) 
            return iTime(_Symbol, _Period, i);
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

// ... (Standard Helpers: MergeZone, StartZone, etc. remain unchanged) ...
void MergeZone(MergedZoneState &state, PointStruct &p, int type) { if (type == 1) { state.top = MathMax(state.top, p.zoneLimitTop);
   state.bottom = MathMin(state.bottom, p.zoneLimitBottom); } else { state.bottom = MathMin(state.bottom, p.zoneLimitBottom); state.top = MathMax(state.top, p.zoneLimitTop); } state.startTime = p.time;
   state.lastBarIndex = p.barIndex; }
void StartZone(MergedZoneState &state, PointStruct &p) { state.isActive=true; state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex;
   }
void DrawSingleZone(datetime t1, datetime t2, double top, double bottom, int type, int id) { if (top <= bottom) return;
   string name = "NCI_Zone_M_" + IntegerToString(id) + "_" + TimeToString(t1); color c = (type == 1) ? SupplyColor : DemandColor;
   if(ObjectFind(0,name)<0) { ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom); ObjectSetInteger(0, name, OBJPROP_COLOR, c); ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); } }
void UpdateZigZagMap() { int totalBars = iBars(_Symbol, _Period);
   if (totalBars < 500) return; PointStruct Alarms[]; int alarmCount = 0; int startBar = MathMin(HistoryBars, totalBars - 10);
   for (int i = startBar; i >= 5; i--) { if (IsGreen(i)) { int c1=i-1; int c2=i-2;
   if(IsRed(c1)){ if(IsStrongBody(c1)){ if(IsRed(c2)) { ArrayResize(Alarms,alarmCount+1); Alarms[alarmCount].price=iHigh(_Symbol,_Period,i); Alarms[alarmCount].time=iTime(_Symbol,_Period,i); Alarms[alarmCount].type=1; Alarms[alarmCount].barIndex=i; alarmCount++; } } else{ double rl=iLow(_Symbol,_Period,c1); for(int k=1;k<=MaxScanDistance;k++){ int n=c1-k; if(n<0||iHigh(_Symbol,_Period,n)>iHigh(_Symbol,_Period,i))break;
   if(IsRed(n)&&IsStrongBody(n)&&iClose(_Symbol,_Period,n)<rl){ ArrayResize(Alarms,alarmCount+1); Alarms[alarmCount].price=iHigh(_Symbol,_Period,i); Alarms[alarmCount].time=iTime(_Symbol,_Period,i); Alarms[alarmCount].type=1; Alarms[alarmCount].barIndex=i; alarmCount++; break;} } } } } if (IsRed(i)) { int c1=i-1; int c2=i-2;
   if(IsGreen(c1)){ if(IsStrongBody(c1)){ if(IsGreen(c2)) { ArrayResize(Alarms,alarmCount+1); Alarms[alarmCount].price=iLow(_Symbol,_Period,i); Alarms[alarmCount].time=iTime(_Symbol,_Period,i); Alarms[alarmCount].type=-1; Alarms[alarmCount].barIndex=i; alarmCount++; } } else{ double rh=iHigh(_Symbol,_Period,c1); for(int k=1;k<=MaxScanDistance;k++){ int n=c1-k; if(n<0||iLow(_Symbol,_Period,n)<iLow(_Symbol,_Period,i))break;
   if(IsGreen(n)&&IsStrongBody(n)&&iClose(_Symbol,_Period,n)>rh){ ArrayResize(Alarms,alarmCount+1); Alarms[alarmCount].price=iLow(_Symbol,_Period,i); Alarms[alarmCount].time=iTime(_Symbol,_Period,i); Alarms[alarmCount].type=-1; Alarms[alarmCount].barIndex=i; alarmCount++; break;} } } } } } if (alarmCount < 2) return; ArrayResize(ZigZagPoints, 0);
   int state = 0; PointStruct pendingPoint; int lastCommittedIndex = startBar + 5; if (Alarms[0].type == 1) { AddPoint(ZigZagPoints, Alarms[0]);
   lastCommittedIndex = Alarms[0].barIndex; state = -1; pendingPoint.price = 999999; } else { AddPoint(ZigZagPoints, Alarms[0]); lastCommittedIndex = Alarms[0].barIndex; state = 1;
   pendingPoint.price = 0; } for (int i = 1; i < alarmCount; i++) { int searchStart = Alarms[i].barIndex;
   int searchEnd = lastCommittedIndex - 1; int count = searchEnd - searchStart + 1; if (count <= 0) continue;
   if (state == 1) { int hI = iHighest(_Symbol, _Period, MODE_HIGH, count, searchStart); double hP = iHigh(_Symbol, _Period, hI);
   if (hP > pendingPoint.price) { pendingPoint.price=hP; pendingPoint.time=iTime(_Symbol,_Period,hI); pendingPoint.barIndex=hI; pendingPoint.type=1; } if (Alarms[i].type == -1) { AddPoint(ZigZagPoints, pendingPoint); lastCommittedIndex=pendingPoint.barIndex; state=-1; pendingPoint.price=999999;
   i--; } } else if (state == -1) { int lI = iLowest(_Symbol, _Period, MODE_LOW, count, searchStart);
   double lP = iLow(_Symbol, _Period, lI); if (lP < pendingPoint.price) { pendingPoint.price=lP; pendingPoint.time=iTime(_Symbol,_Period,lI); pendingPoint.barIndex=lI; pendingPoint.type=-1;
   } if (Alarms[i].type == 1) { AddPoint(ZigZagPoints, pendingPoint); lastCommittedIndex=pendingPoint.barIndex; state=1; pendingPoint.price=0; i--; } } } for(int i=0; i<ArraySize(ZigZagPoints); i++) CalculateZoneLimits(ZigZagPoints[i]);
   CalculateTrendsAndLock(); DrawZigZagLines(); if(DrawZones) DrawParallelZones(); }
void CalculateTrendsAndLock() { int count = ArraySize(ZigZagPoints); if (count < 2) return; int runningTrend = 0;
   double lastSupplyLevel = 0; int lastSupplyIdx = -1; double lastDemandLevel = 0; int lastDemandIdx = -1; double prevHigh = 0;
   double prevLow = 0; for (int i = 1; i < count; i++) { PointStruct p = ZigZagPoints[i];
   PointStruct prev = ZigZagPoints[i-1]; if (prev.type == 1) { lastSupplyLevel = prev.zoneLimitTop; lastSupplyIdx = prev.barIndex; prevHigh = prev.price;
   } if (prev.type == -1) { lastDemandLevel = prev.zoneLimitBottom; lastDemandIdx = prev.barIndex; prevLow = prev.price; } bool brokenSupply = false;
   bool brokenDemand = false; if (lastSupplyIdx != -1) brokenSupply = CheckForBreakout(lastSupplyIdx, p.barIndex, lastSupplyLevel, 1);
   if (lastDemandIdx != -1) brokenDemand = CheckForBreakout(lastDemandIdx, p.barIndex, lastDemandLevel, -1); if (runningTrend == -1) { if (brokenSupply) runningTrend = 0;
   } else if (runningTrend == 1) { if (brokenDemand) runningTrend = 0;
   } else { if (p.type == 1) { if (brokenSupply || (prevHigh != 0 && p.price > prevHigh)) { if (!brokenDemand) runningTrend = 1;
   } } if (p.type == -1) { if (brokenDemand || (prevLow != 0 && p.price < prevLow)) { if (!brokenSupply) runningTrend = -1;
   } } if (brokenSupply && p.type == 1 && prevHigh != 0 && p.price > prevHigh) runningTrend = 1;
   if (brokenDemand && p.type == -1 && prevLow != 0 && p.price < prevLow) runningTrend = -1;
   } ZigZagPoints[i].assignedTrend = runningTrend; } currentMarketTrend = runningTrend; }
bool CheckForBreakout(int startBarIdx, int endBarIdx, double level, int type) { for (int i = startBarIdx - 1; i > endBarIdx; i--) { if (i-1 < 0) return false;
   if (type == 1) { double c1 = iClose(_Symbol, _Period, i); double c2 = iClose(_Symbol, _Period, i-1);
   if (c1 > level && c2 > level && c2 > c1) return true;
   } else { double c1 = iClose(_Symbol, _Period, i); double c2 = iClose(_Symbol, _Period, i-1);
   if (c1 < level && c2 < level && c2 < c1) return true; } } return false;
   }
void CalculateZoneLimits(PointStruct &p) { p.zoneLimitTop = p.price; p.zoneLimitBottom = p.price; if (p.type == 1) { int gI=-1, rI=-1;
   for(int k=0;k<=5;k++){if(p.barIndex+k >= iBars(_Symbol,_Period)) break; if(IsGreen(p.barIndex+k)){gI=p.barIndex+k;break;}} if(gI!=-1) rI=gI-1; if(gI!=-1) { p.zoneLimitBottom = iOpen(_Symbol,_Period,gI); if(IsBigCandle(gI)){ if(rI!=-1){ p.zoneLimitBottom = iOpen(_Symbol,_Period,rI); if(IsBigCandle(rI)) p.zoneLimitBottom=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0;
   } else p.zoneLimitBottom=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0; } } } else { int rI=-1, gI=-1; for(int k=0;k<=5;k++){if(p.barIndex+k >= iBars(_Symbol,_Period)) break; if(IsRed(p.barIndex+k)){rI=p.barIndex+k;break;}} if(rI!=-1) gI=rI-1;
   if(rI!=-1) { p.zoneLimitTop = iOpen(_Symbol,_Period,rI); if(IsBigCandle(rI)){ if(gI!=-1){ p.zoneLimitTop = iOpen(_Symbol,_Period,gI); if(IsBigCandle(gI)) p.zoneLimitTop=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0; } else p.zoneLimitTop=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0;
   } } } }
void DrawZigZagLines() { ObjectsDeleteAll(0, "NCI_ZZ_"); int c=ArraySize(ZigZagPoints); if(c<2)return; for(int i=1;i<c;i++){ int t=ZigZagPoints[i].assignedTrend; color cl=(t==1)?ColorUp:(t==-1)?ColorDown:ColorRange; string n="NCI_ZZ_"+IntegerToString(i); ObjectCreate(0,n,OBJ_TREND,0,ZigZagPoints[i-1].time,ZigZagPoints[i-1].price,ZigZagPoints[i].time,ZigZagPoints[i].price);
   ObjectSetInteger(0,n,OBJPROP_COLOR,cl); ObjectSetInteger(0,n,OBJPROP_WIDTH,LineWidth); ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); } ChartRedraw(); }
bool IsBigCandle(int index) { double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); double s=0; int c=0; for(int k=1;k<=10;k++){if(index+k>=iBars(_Symbol,_Period))break;s+=MathAbs(iOpen(_Symbol,_Period,index+k)-iClose(_Symbol,_Period,index+k));c++;} if(c==0)return false;
   return(b>(s/c)*BigCandleFactor); }
void DrawZigZag() { /* Deprecated */ }
void AddPoint(PointStruct &arr[], PointStruct &p) { int s=ArraySize(arr); ArrayResize(arr,s+1); arr[s]=p;
   }
bool IsStrongBody(int index) { double h=iHigh(_Symbol,_Period,index); double l=iLow(_Symbol,_Period,index); if(h-l==0)return false; double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); return(b>(h-l)*MinBodyPercent); }
bool IsGreen(int index) { return iClose(_Symbol,_Period,index)>iOpen(_Symbol,_Period,index);
   }
bool IsRed(int index) { return iClose(_Symbol,_Period,index)<iOpen(_Symbol,_Period,index); }
bool IsNewBar() { static datetime last; datetime curr=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); if(last!=curr){last=curr;return true;} return false; }