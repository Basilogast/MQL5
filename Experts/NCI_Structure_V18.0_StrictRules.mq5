//+------------------------------------------------------------------+
//|         NCI_Structure_V45.0_CrashProof.mq5                       |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "45.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 5000; 
input int LineWidth         = 2;
input bool DrawZones        = true;
input color SupplyColor     = clrMaroon; 
input color DemandColor     = clrDarkGreen;

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
input bool AllowTrading     = true;
input double RiskPercent    = 1.0;
input double MinRiskReward  = 2.0;
input double EntryZoneDepth = 0.30;
input double TPZoneDepth    = 0.0;
input double SLBufferPoints = 50;

//--- GLOBALS
CTrade trade;
struct PointStruct {
   double price;
   datetime time;
   int type; // 1=High, -1=Low
   int barIndex;
   double zoneLimitTop;
   double zoneLimitBottom;
   int assignedTrend; // 1=Up, -1=Down, 0=Fluctuate
};
PointStruct ZigZagPoints[];

struct MergedZoneState {
   bool isActive;
   double top;
   double bottom;
   datetime startTime;
   int lastBarIndex;
};

MergedZoneState activeSupply;
MergedZoneState activeDemand;
int currentMarketTrend = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   ObjectsDeleteAll(0, "NCI_Zone_");
   UpdateZigZagMap();
   Print(">>> V45 INIT: Crash Proof Engine (Safe Arrays) Loaded.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(IsNewBar()) UpdateZigZagMap();
   if(AllowTrading) CheckTradeEntry();
}

// ==========================================================
//    MAIN ENGINE (Uncompressed & Safe)
// ==========================================================
void UpdateZigZagMap()
{
   // SAFETY: Don't run if history is not ready
   int totalBars = iBars(_Symbol, _Period);
   if (totalBars < 500) return;

   // --- STEP 1: GATHER RAW ALARMS ---
   PointStruct Alarms[];
   int alarmCount = 0;
   int startBar = MathMin(HistoryBars, totalBars - 10);
   
   for (int i = startBar; i >= 5; i--) 
   {
      // Check Highs
      if (IsGreen(i)) {
         int c1=i-1; int c2=i-2;
         if(IsRed(c1)){
            bool v=false;
            if(IsStrongBody(c1)){ 
               if(IsRed(c2)) v=true; 
            }
            else{
               double rl=iLow(_Symbol,_Period,c1);
               for(int k=1;k<=MaxScanDistance;k++){
                  int n=c1-k; 
                  if(n<0||iHigh(_Symbol,_Period,n)>iHigh(_Symbol,_Period,i))break;
                  if(IsRed(n)&&IsStrongBody(n)&&iClose(_Symbol,_Period,n)<rl){v=true;break;}
               }
            }
            if(v){
               ArrayResize(Alarms, alarmCount+1);
               Alarms[alarmCount].price=iHigh(_Symbol,_Period,i);
               Alarms[alarmCount].time=iTime(_Symbol,_Period,i);
               Alarms[alarmCount].type=1;
               Alarms[alarmCount].barIndex=i;
               alarmCount++;
            }
         }
      }
      // Check Lows
      if (IsRed(i)) {
         int c1=i-1; int c2=i-2;
         if(IsGreen(c1)){
            bool v=false;
            if(IsStrongBody(c1)){ 
               if(IsGreen(c2)) v=true; 
            }
            else{
               double rh=iHigh(_Symbol,_Period,c1);
               for(int k=1;k<=MaxScanDistance;k++){
                  int n=c1-k; 
                  if(n<0||iLow(_Symbol,_Period,n)<iLow(_Symbol,_Period,i))break;
                  if(IsGreen(n)&&IsStrongBody(n)&&iClose(_Symbol,_Period,n)>rh){v=true;break;}
               }
            }
            if(v){
               ArrayResize(Alarms, alarmCount+1);
               Alarms[alarmCount].price=iLow(_Symbol,_Period,i);
               Alarms[alarmCount].time=iTime(_Symbol,_Period,i);
               Alarms[alarmCount].type=-1;
               Alarms[alarmCount].barIndex=i;
               alarmCount++;
            }
         }
      }
   }
   
   if (alarmCount < 2) return;
   
   // --- STEP 2: GREEDY ZIGZAG ---
   ArrayResize(ZigZagPoints, 0);
   int state = 0; 
   PointStruct pendingPoint; 
   int lastCommittedIndex = startBar + 5;
   
   // Init State
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

   for (int i = 1; i < alarmCount; i++)
   {
      int searchStart = Alarms[i].barIndex;
      int searchEnd   = lastCommittedIndex - 1; 
      int count       = searchEnd - searchStart + 1;
      
      if (count <= 0) continue;

      if (state == 1) {
         int hI = iHighest(_Symbol, _Period, MODE_HIGH, count, searchStart);
         double hP = iHigh(_Symbol, _Period, hI);
         
         if (hP > pendingPoint.price) { 
            pendingPoint.price=hP; 
            pendingPoint.time=iTime(_Symbol,_Period,hI); 
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
      }
      else if (state == -1) {
         int lI = iLowest(_Symbol, _Period, MODE_LOW, count, searchStart);
         double lP = iLow(_Symbol, _Period, lI);
         
         if (lP < pendingPoint.price) { 
            pendingPoint.price=lP; 
            pendingPoint.time=iTime(_Symbol,_Period,lI); 
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
   
   // Pre-calc limits
   int zzCount = ArraySize(ZigZagPoints);
   for(int i=0; i<zzCount; i++) CalculateZoneLimits(ZigZagPoints[i]);

   CalculateTrendsAndLock();
   DrawZigZagLines(); 
   if(DrawZones) DrawParallelZones(); 
}

// ==========================================================
//    TREND LOGIC (V42 Momentum)
// ==========================================================
void CalculateTrendsAndLock()
{
   int count = ArraySize(ZigZagPoints);
   if (count < 2) return;
   
   int runningTrend = 0; 
   double lastSupplyLevel = 0; int lastSupplyIdx = -1;
   double lastDemandLevel = 0; int lastDemandIdx = -1;
   double prevHigh = 0; double prevLow = 0;
   
   for (int i = 1; i < count; i++)
   {
      PointStruct p = ZigZagPoints[i];     
      PointStruct prev = ZigZagPoints[i-1];
      
      if (prev.type == 1) { lastSupplyLevel = prev.zoneLimitTop; lastSupplyIdx = prev.barIndex; prevHigh = prev.price; }
      if (prev.type == -1) { lastDemandLevel = prev.zoneLimitBottom; lastDemandIdx = prev.barIndex; prevLow = prev.price; }

      bool brokenSupply = false; bool brokenDemand = false;
      if (lastSupplyIdx != -1) brokenSupply = CheckForBreakout(lastSupplyIdx, p.barIndex, lastSupplyLevel, 1);
      if (lastDemandIdx != -1) brokenDemand = CheckForBreakout(lastDemandIdx, p.barIndex, lastDemandLevel, -1);

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

// ==========================================================
//    TRADING LOGIC
// ==========================================================
void CheckTradeEntry()
{
   if (!activeSupply.isActive || !activeDemand.isActive) return;
   if (PositionsTotal() > 0) return; 

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (currentMarketTrend == 1) 
   {
      double zoneHeight = activeDemand.top - activeDemand.bottom;
      double entryPrice = activeDemand.top - (zoneHeight * EntryZoneDepth); 
      
      if (ask <= entryPrice && ask >= activeDemand.bottom) 
      {
         double sl = activeDemand.bottom - (SLBufferPoints * _Point);
         double tp = activeSupply.bottom + ((activeSupply.top - activeSupply.bottom) * TPZoneDepth); 
         
         double risk = entryPrice - sl;
         double reward = tp - entryPrice;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) OpenTrade(ORDER_TYPE_BUY, ask, sl, tp);
      }
   }
   else if (currentMarketTrend == -1) 
   {
      double zoneHeight = activeSupply.top - activeSupply.bottom;
      double entryPrice = activeSupply.bottom + (zoneHeight * EntryZoneDepth);
      
      if (bid >= entryPrice && bid <= activeSupply.top) 
      {
         double sl = activeSupply.top + (SLBufferPoints * _Point);
         double tp = activeDemand.top - ((activeDemand.top - activeDemand.bottom) * TPZoneDepth);
         
         double risk = sl - entryPrice;
         double reward = entryPrice - tp;
         
         if (risk > 0 && (reward / risk) >= MinRiskReward) OpenTrade(ORDER_TYPE_SELL, bid, sl, tp);
      }
   }
}

void OpenTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp)
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
   
   trade.PositionOpen(_Symbol, type, lotSize, price, sl, tp, "NCI V45 Auto");
}

// ==========================================================
//    DRAWING PARALLEL ZONES (V43 SMART)
// ==========================================================
void DrawParallelZones()
{
   ObjectsDeleteAll(0, "NCI_Zone_");
   int count = ArraySize(ZigZagPoints);
   if (count == 0) return;
   MergedZoneState supply; supply.isActive = false;
   MergedZoneState demand; demand.isActive = false;
   
   for (int i = 0; i < count; i++)
   {
      PointStruct p = ZigZagPoints[i];
      if (p.type == 1) {
         if (!supply.isActive) StartZone(supply, p);
         else {
            bool isBroken = CheckForBreakout(supply.lastBarIndex, p.barIndex, supply.top, 1);
            if (isBroken) { DrawSingleZone(supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); StartZone(supply, p); }
            else {
               if (p.zoneLimitTop > supply.top) MergeZone(supply, p, 1);
               else {
                  bool isOverlapping = (MathMax(supply.bottom, p.zoneLimitBottom) <= MathMin(supply.top, p.zoneLimitTop));
                  if (isOverlapping) MergeZone(supply, p, 1);
                  else { DrawSingleZone(supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); StartZone(supply, p); }
               }
            }
         }
      }
      else if (p.type == -1) {
         if (!demand.isActive) StartZone(demand, p);
         else {
            bool isBroken = CheckForBreakout(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            if (isBroken) { DrawSingleZone(demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); StartZone(demand, p); }
            else {
               if (p.zoneLimitBottom < demand.bottom) MergeZone(demand, p, -1);
               else {
                  bool isOverlapping = (MathMax(demand.bottom, p.zoneLimitBottom) <= MathMin(demand.top, p.zoneLimitTop));
                  if (isOverlapping) MergeZone(demand, p, -1);
                  else { DrawSingleZone(demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); StartZone(demand, p); }
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

// --- HELPERS ---
void MergeZone(MergedZoneState &state, PointStruct &p, int type) { if (type == 1) { state.top = MathMax(state.top, p.zoneLimitTop); state.bottom = MathMin(state.bottom, p.zoneLimitBottom); } else { state.bottom = MathMin(state.bottom, p.zoneLimitBottom); state.top = MathMax(state.top, p.zoneLimitTop); } state.lastBarIndex = p.barIndex; }
void StartZone(MergedZoneState &state, PointStruct &p) { state.isActive=true; state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex; }
bool CheckForBreakout(int startBarIdx, int endBarIdx, double level, int type) { for (int i = startBarIdx - 1; i > endBarIdx; i--) { if (i-1 < 0) return false; if (type == 1) { double c1 = iClose(_Symbol, _Period, i); double c2 = iClose(_Symbol, _Period, i-1); if (c1 > level && c2 > level && c2 > c1) return true; } else { double c1 = iClose(_Symbol, _Period, i); double c2 = iClose(_Symbol, _Period, i-1); if (c1 < level && c2 < level && c2 < c1) return true; } } return false; }
void CalculateZoneLimits(PointStruct &p) { p.zoneLimitTop = p.price; p.zoneLimitBottom = p.price; if (p.type == 1) { int gI=-1, rI=-1; for(int k=0;k<=5;k++){if(p.barIndex+k >= iBars(_Symbol,_Period)) break; if(IsGreen(p.barIndex+k)){gI=p.barIndex+k;break;}} if(gI!=-1) rI=gI-1; if(gI!=-1) { p.zoneLimitBottom = iOpen(_Symbol,_Period,gI); if(IsBigCandle(gI)){ if(rI!=-1){ p.zoneLimitBottom = iOpen(_Symbol,_Period,rI); if(IsBigCandle(rI)) p.zoneLimitBottom=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0; } else p.zoneLimitBottom=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0; } } } else { int rI=-1, gI=-1; for(int k=0;k<=5;k++){if(p.barIndex+k >= iBars(_Symbol,_Period)) break; if(IsRed(p.barIndex+k)){rI=p.barIndex+k;break;}} if(rI!=-1) gI=rI-1; if(rI!=-1) { p.zoneLimitTop = iOpen(_Symbol,_Period,rI); if(IsBigCandle(rI)){ if(gI!=-1){ p.zoneLimitTop = iOpen(_Symbol,_Period,gI); if(IsBigCandle(gI)) p.zoneLimitTop=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0; } else p.zoneLimitTop=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0; } } } }
void DrawSingleZone(datetime t1, datetime t2, double top, double bottom, int type, int id) { if (top <= bottom) return; string name = "NCI_Zone_M_" + IntegerToString(id) + "_" + TimeToString(t1); color c = (type == 1) ? SupplyColor : DemandColor; if(ObjectFind(0,name)<0) { ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom); ObjectSetInteger(0, name, OBJPROP_COLOR, c); ObjectSetInteger(0, name, OBJPROP_FILL, true); ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); } }
void DrawZigZagLines() { ObjectsDeleteAll(0, "NCI_ZZ_"); int c=ArraySize(ZigZagPoints); if(c<2)return; for(int i=1;i<c;i++){ int t=ZigZagPoints[i].assignedTrend; color cl=(t==1)?ColorUp:(t==-1)?ColorDown:ColorRange; string n="NCI_ZZ_"+IntegerToString(i); ObjectCreate(0,n,OBJ_TREND,0,ZigZagPoints[i-1].time,ZigZagPoints[i-1].price,ZigZagPoints[i].time,ZigZagPoints[i].price); ObjectSetInteger(0,n,OBJPROP_COLOR,cl); ObjectSetInteger(0,n,OBJPROP_WIDTH,LineWidth); ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); } ChartRedraw(); }
bool IsBigCandle(int index) { double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); double s=0; int c=0; for(int k=1;k<=10;k++){if(index+k>=iBars(_Symbol,_Period))break;s+=MathAbs(iOpen(_Symbol,_Period,index+k)-iClose(_Symbol,_Period,index+k));c++;} if(c==0)return false; return(b>(s/c)*BigCandleFactor); }
void DrawZigZag() { /* Deprecated */ }
void AddPoint(PointStruct &arr[], PointStruct &p) { int s=ArraySize(arr); ArrayResize(arr,s+1); arr[s]=p; }
bool IsStrongBody(int index) { double h=iHigh(_Symbol,_Period,index); double l=iLow(_Symbol,_Period,index); if(h-l==0)return false; double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); return(b>(h-l)*MinBodyPercent); }
bool IsGreen(int index) { return iClose(_Symbol,_Period,index)>iOpen(_Symbol,_Period,index); }
bool IsRed(int index) { return iClose(_Symbol,_Period,index)<iOpen(_Symbol,_Period,index); }
bool IsNewBar() { static datetime last; datetime curr=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); if(last!=curr){last=curr;return true;} return false; }