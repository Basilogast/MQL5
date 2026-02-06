//+------------------------------------------------------------------+
//|         NCI_Structure_V42.0_MomentumBreak.mq5                    |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "42.00"
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

int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   ObjectsDeleteAll(0, "NCI_Zone_");
   UpdateZigZagMap();
   Print(">>> V42 INIT: Momentum Breakout Logic (2-Candle Follow Through) Loaded.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(IsNewBar()) UpdateZigZagMap();
}

// ==========================================================
//    MAIN ENGINE
// ==========================================================
void UpdateZigZagMap()
{
   // --- STEP 1: GATHER RAW ALARMS (Unchanged) ---
   PointStruct Alarms[];
   int alarmCount = 0;
   int startBar = MathMin(HistoryBars, iBars(_Symbol, _Period)-10);
   
   for (int i = startBar; i >= 5; i--) 
   {
      if (IsGreen(i)) {
         int c1=i-1; int c2=i-2;
         if(IsRed(c1)){
            bool v=false;
            if(IsStrongBody(c1)){ if(IsRed(c2)) v=true; }
            else{
               double rl=iLow(_Symbol,_Period,c1);
               for(int k=1;k<=MaxScanDistance;k++){
                  int n=c1-k; if(n<0||iHigh(_Symbol,_Period,n)>iHigh(_Symbol,_Period,i))break;
                  if(IsRed(n)&&IsStrongBody(n)&&iClose(_Symbol,_Period,n)<rl){v=true;break;}
               }
            }
            if(v){ArrayResize(Alarms,alarmCount+1);Alarms[alarmCount].price=iHigh(_Symbol,_Period,i);Alarms[alarmCount].time=iTime(_Symbol,_Period,i);Alarms[alarmCount].type=1;Alarms[alarmCount].barIndex=i;alarmCount++;}
         }
      }
      if (IsRed(i)) {
         int c1=i-1; int c2=i-2;
         if(IsGreen(c1)){
            bool v=false;
            if(IsStrongBody(c1)){ if(IsGreen(c2)) v=true; }
            else{
               double rh=iHigh(_Symbol,_Period,c1);
               for(int k=1;k<=MaxScanDistance;k++){
                  int n=c1-k; if(n<0||iLow(_Symbol,_Period,n)<iLow(_Symbol,_Period,i))break;
                  if(IsGreen(n)&&IsStrongBody(n)&&iClose(_Symbol,_Period,n)>rh){v=true;break;}
               }
            }
            if(v){ArrayResize(Alarms,alarmCount+1);Alarms[alarmCount].price=iLow(_Symbol,_Period,i);Alarms[alarmCount].time=iTime(_Symbol,_Period,i);Alarms[alarmCount].type=-1;Alarms[alarmCount].barIndex=i;alarmCount++;}
         }
      }
   }
   
   if (alarmCount < 2) return;
   
   // --- STEP 2: GREEDY ZIGZAG (Unchanged) ---
   ArrayResize(ZigZagPoints, 0);
   int state = 0; 
   PointStruct pendingPoint; 
   int lastCommittedIndex = startBar + 5;
   
   if (Alarms[0].type == 1) { 
       AddPoint(ZigZagPoints, Alarms[0]); lastCommittedIndex = Alarms[0].barIndex; state = -1; pendingPoint.price = 999999;
   } else {
       AddPoint(ZigZagPoints, Alarms[0]); lastCommittedIndex = Alarms[0].barIndex; state = 1; pendingPoint.price = 0;
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
         if (hP > pendingPoint.price) { pendingPoint.price=hP; pendingPoint.time=iTime(_Symbol,_Period,hI); pendingPoint.barIndex=hI; pendingPoint.type=1; }
         if (Alarms[i].type == -1) { AddPoint(ZigZagPoints, pendingPoint); lastCommittedIndex=pendingPoint.barIndex; state=-1; pendingPoint.price=999999; i--; }
      }
      else if (state == -1) {
         int lI = iLowest(_Symbol, _Period, MODE_LOW, count, searchStart);
         double lP = iLow(_Symbol, _Period, lI);
         if (lP < pendingPoint.price) { pendingPoint.price=lP; pendingPoint.time=iTime(_Symbol,_Period,lI); pendingPoint.barIndex=lI; pendingPoint.type=-1; }
         if (Alarms[i].type == 1) { AddPoint(ZigZagPoints, pendingPoint); lastCommittedIndex=pendingPoint.barIndex; state=1; pendingPoint.price=0; i--; }
      }
   }
   
   // Pre-calc limits
   for(int i=0; i<ArraySize(ZigZagPoints); i++) CalculateZoneLimits(ZigZagPoints[i]);

   // Calculate Trends Logic and Lock it
   CalculateTrendsAndLock();
   
   // Draw Lines based on Locked Trends
   DrawZigZagLines(); 
   
   if(DrawZones) DrawParallelZones(); 
}

// ==========================================================
//    NEW: LOGIC ENGINE (V42 Momentum)
// ==========================================================
void CalculateTrendsAndLock()
{
   int count = ArraySize(ZigZagPoints);
   if (count < 2) return;
   
   int runningTrend = 0; 
   
   double lastSupplyLevel = 0; int lastSupplyIdx = -1;
   double lastDemandLevel = 0; int lastDemandIdx = -1;
   
   double prevHigh = 0;
   double prevLow = 0;
   
   for (int i = 1; i < count; i++)
   {
      PointStruct p = ZigZagPoints[i];     
      PointStruct prev = ZigZagPoints[i-1];
      
      // 1. UPDATE STRUCTURE MEMORY
      if (prev.type == 1) { 
         lastSupplyLevel = prev.zoneLimitTop; 
         lastSupplyIdx = prev.barIndex;
         prevHigh = prev.price; 
      }
      if (prev.type == -1) {
         lastDemandLevel = prev.zoneLimitBottom; 
         lastDemandIdx = prev.barIndex;
         prevLow = prev.price; 
      }

      // 2. CHECK BREAKOUTS (V42: MOMENTUM LOGIC)
      bool brokenSupply = false;
      bool brokenDemand = false;
      
      // We ONLY check strictly now. No "Safety Net" based on ZigZag Wicks.
      if (lastSupplyIdx != -1) brokenSupply = CheckForBreakout(lastSupplyIdx, p.barIndex, lastSupplyLevel, 1);
      if (lastDemandIdx != -1) brokenDemand = CheckForBreakout(lastDemandIdx, p.barIndex, lastDemandLevel, -1);

      // 3. STATE MACHINE TRANSITIONS
      
      // --- STATE: DOWN (Red) ---
      if (runningTrend == -1) 
      {
         if (brokenSupply) {
            runningTrend = 0; // Supply Broken -> Switch to YELLOW
         }
      }
      
      // --- STATE: UP (Green) ---
      else if (runningTrend == 1)
      {
         if (brokenDemand) {
            runningTrend = 0; // Demand Broken -> Switch to YELLOW
         }
      }
      
      // --- STATE: FLUCTUATE (Yellow) ---
      else 
      {
         // Wait for Pattern Confirmation
         
         // A. Check for GREEN Transition
         if (p.type == 1) { 
             // If we broke Supply AND we are making Higher Highs
             if (brokenSupply || (prevHigh != 0 && p.price > prevHigh)) {
                 if (!brokenDemand) runningTrend = 1;
             }
         }
         
         // B. Check for RED Transition
         if (p.type == -1) { 
             // If we broke Demand AND we are making Lower Lows
             if (brokenDemand || (prevLow != 0 && p.price < prevLow)) {
                 if (!brokenSupply) runningTrend = -1;
             }
         }
         
         // C. Fallback: Immediate breakout follow-through
         if (brokenSupply && p.type == 1 && prevHigh != 0 && p.price > prevHigh) runningTrend = 1;
         if (brokenDemand && p.type == -1 && prevLow != 0 && p.price < prevLow) runningTrend = -1;
      }
      
      // 4. LOCK STATE
      ZigZagPoints[i].assignedTrend = runningTrend;
   }
}

// ==========================================================
//    NEW BREAKOUT CHECK (V42 MOMENTUM)
// ==========================================================
bool CheckForBreakout(int startBarIdx, int endBarIdx, double level, int type)
{
   // Scan candles between the old zone and new point
   // Note: i is older (Candle 1), i-1 is newer (Candle 2)
   for (int i = startBarIdx - 1; i > endBarIdx; i--) 
   {
      // --- SUPPLY BREAK (UP) ---
      if (type == 1) 
      { 
         double c1 = iClose(_Symbol, _Period, i);
         double c2 = iClose(_Symbol, _Period, i-1);
         
         // RULE 1: Candle 1 Close > Zone
         if (c1 > level) {
            // RULE 2: Candle 2 Close > Zone
            if (c2 > level) {
               // RULE 3: Momentum (Candle 2 Higher than Candle 1)
               if (c2 > c1) return true;
            }
         }
      }
      
      // --- DEMAND BREAK (DOWN) ---
      else 
      { 
         double c1 = iClose(_Symbol, _Period, i);
         double c2 = iClose(_Symbol, _Period, i-1);
         
         // RULE 1: Candle 1 Close < Zone
         if (c1 < level) {
            // RULE 2: Candle 2 Close < Zone
            if (c2 < level) {
               // RULE 3: Momentum (Candle 2 Lower than Candle 1)
               if (c2 < c1) return true;
            }
         }
      }
   }
   return false;
}

// ==========================================================
//    DRAWING (Unchanged)
// ==========================================================
void DrawZigZagLines()
{
   ObjectsDeleteAll(0, "NCI_ZZ_");
   int count = ArraySize(ZigZagPoints);
   if (count < 2) return;
   
   for (int i = 1; i < count; i++)
   {
      int trend = ZigZagPoints[i].assignedTrend;
      color segmentColor = ColorRange;
      if (trend == 1) segmentColor = ColorUp;
      else if (trend == -1) segmentColor = ColorDown;
      
      string name = "NCI_ZZ_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, ZigZagPoints[i-1].time, ZigZagPoints[i-1].price, ZigZagPoints[i].time, ZigZagPoints[i].price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, segmentColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ChartRedraw();
}

// --- PARALLEL ZONES (Unchanged) ---
void DrawParallelZones()
{
   ObjectsDeleteAll(0, "NCI_Zone_");
   int count = ArraySize(ZigZagPoints);
   if (count == 0) return;
   MergedZoneState supplyState; supplyState.isActive = false;
   MergedZoneState demandState; demandState.isActive = false;
   for (int i = 0; i < count; i++)
   {
      PointStruct p = ZigZagPoints[i];
      if (p.type == 1) {
         if (!supplyState.isActive) StartZone(supplyState, p);
         else {
            bool isOverlapping = (MathMax(supplyState.bottom, p.zoneLimitBottom) <= MathMin(supplyState.top, p.zoneLimitTop));
            if (!isOverlapping) { DrawSingleZone(supplyState.startTime, p.time, supplyState.top, supplyState.bottom, 1, i-1); StartZone(supplyState, p); }
            else {
               bool isBroken = CheckForBreakout(supplyState.lastBarIndex, p.barIndex, supplyState.top, 1);
               if (isBroken) { DrawSingleZone(supplyState.startTime, p.time, supplyState.top, supplyState.bottom, 1, i-1); StartZone(supplyState, p); }
               else { supplyState.top = MathMax(supplyState.top, p.zoneLimitTop); supplyState.bottom = MathMin(supplyState.bottom, p.zoneLimitBottom); supplyState.lastBarIndex = p.barIndex; }
            }
         }
      }
      else if (p.type == -1) {
         if (!demandState.isActive) StartZone(demandState, p);
         else {
            bool isOverlapping = (MathMax(demandState.bottom, p.zoneLimitBottom) <= MathMin(demandState.top, p.zoneLimitTop));
            if (!isOverlapping) { DrawSingleZone(demandState.startTime, p.time, demandState.top, demandState.bottom, -1, i-1); StartZone(demandState, p); }
            else {
               bool isBroken = CheckForBreakout(demandState.lastBarIndex, p.barIndex, demandState.bottom, -1);
               if (isBroken) { DrawSingleZone(demandState.startTime, p.time, demandState.top, demandState.bottom, -1, i-1); StartZone(demandState, p); }
               else { demandState.bottom = MathMin(demandState.bottom, p.zoneLimitBottom); demandState.top = MathMax(demandState.top, p.zoneLimitTop); demandState.lastBarIndex = p.barIndex; }
            }
         }
      }
   }
   if (supplyState.isActive) DrawSingleZone(supplyState.startTime, TimeCurrent()+PeriodSeconds()*50, supplyState.top, supplyState.bottom, 1, 999991);
   if (demandState.isActive) DrawSingleZone(demandState.startTime, TimeCurrent()+PeriodSeconds()*50, demandState.top, demandState.bottom, -1, 999992);
   ChartRedraw();
}

// --- HELPERS (Unchanged) ---
void StartZone(MergedZoneState &state, PointStruct &p) { state.isActive=true; state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex; }
void CalculateZoneLimits(PointStruct &p) {
   p.zoneLimitTop = p.price; p.zoneLimitBottom = p.price; 
   if (p.type == 1) { int gI=-1, rI=-1; for(int k=0;k<=5;k++){if(IsGreen(p.barIndex+k)){gI=p.barIndex+k;break;}} if(gI!=-1) rI=gI-1; if(gI!=-1) { p.zoneLimitBottom = iOpen(_Symbol,_Period,gI); if(IsBigCandle(gI)){ if(rI!=-1){ p.zoneLimitBottom = iOpen(_Symbol,_Period,rI); if(IsBigCandle(rI)) p.zoneLimitBottom=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0; } else p.zoneLimitBottom=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0; } } } 
   else { int rI=-1, gI=-1; for(int k=0;k<=5;k++){if(IsRed(p.barIndex+k)){rI=p.barIndex+k;break;}} if(rI!=-1) gI=rI-1; if(rI!=-1) { p.zoneLimitTop = iOpen(_Symbol,_Period,rI); if(IsBigCandle(rI)){ if(gI!=-1){ p.zoneLimitTop = iOpen(_Symbol,_Period,gI); if(IsBigCandle(gI)) p.zoneLimitTop=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0; } else p.zoneLimitTop=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0; } } }
}
void DrawSingleZone(datetime t1, datetime t2, double top, double bottom, int type, int id) { if (top <= bottom) return; string name = "NCI_Zone_M_" + IntegerToString(id) + "_" + TimeToString(t1); color c = (type == 1) ? SupplyColor : DemandColor; if(ObjectFind(0,name)<0) { ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom); ObjectSetInteger(0, name, OBJPROP_COLOR, c); ObjectSetInteger(0, name, OBJPROP_FILL, true); ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); } }
bool IsBigCandle(int index) { double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); double s=0; int c=0; for(int k=1;k<=10;k++){if(index+k>=iBars(_Symbol,_Period))break;s+=MathAbs(iOpen(_Symbol,_Period,index+k)-iClose(_Symbol,_Period,index+k));c++;} if(c==0)return false; return(b>(s/c)*BigCandleFactor); }
void DrawZigZag() { /* Deprecated */ }
void AddPoint(PointStruct &arr[], PointStruct &p) { int s=ArraySize(arr); ArrayResize(arr,s+1); arr[s]=p; }
bool IsStrongBody(int index) { double h=iHigh(_Symbol,_Period,index); double l=iLow(_Symbol,_Period,index); if(h-l==0)return false; double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); return(b>(h-l)*MinBodyPercent); }
bool IsGreen(int index) { return iClose(_Symbol,_Period,index)>iOpen(_Symbol,_Period,index); }
bool IsRed(int index) { return iClose(_Symbol,_Period,index)<iOpen(_Symbol,_Period,index); }
bool IsNewBar() { static datetime last; datetime curr=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); if(last!=curr){last=curr;return true;} return false; }