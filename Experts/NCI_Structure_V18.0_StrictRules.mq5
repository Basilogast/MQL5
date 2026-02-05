//+------------------------------------------------------------------+
//|         NCI_Structure_V34.1_Fixed.mq5                            |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "34.10"
#property strict

#include <Trade\Trade.mqh>

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 10000;
input color LineColor       = clrWhite;
input int LineWidth         = 2;
input bool DrawZones        = true;
input color SupplyColor     = clrMaroon; 
input color DemandColor     = clrDarkGreen;

//--- 2. STRUCTURE RULES
input group "Structure Rules"
input double MinBodyPercent = 0.50;  
input int MaxScanDistance   = 3;

//--- 3. SPECIAL CASE RULES
input group "Special Cases"
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
};
PointStruct ZigZagPoints[];

// Struct to track a running Merged Zone
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
   Print(">>> V34.1 INIT: Parallel Zones Fixed (Typo Corrected).");
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
   // --- STEP 1: GATHER RAW ALARMS ---
   PointStruct Alarms[];
   int alarmCount = 0;
   int startBar = MathMin(HistoryBars, iBars(_Symbol, _Period)-10);
   
   for (int i = startBar; i >= 5; i--) 
   {
      // [Candidate Logic]
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
   
   // --- STEP 2: GREEDY ZIGZAG ---
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
   
   DrawZigZag();
   if(DrawZones) DrawParallelZones(); 
}

// ==========================================================
//    STEP 3: SMART PARALLEL ZONE LOGIC
// ==========================================================
void DrawParallelZones()
{
   ObjectsDeleteAll(0, "NCI_Zone_");
   int count = ArraySize(ZigZagPoints);
   if (count == 0) return;

   // 1. Pre-calculate limits
   for(int i=0; i<count; i++) CalculateZoneLimits(ZigZagPoints[i]);
   
   // 2. Initialize Two Separate Trackers
   MergedZoneState supplyState; supplyState.isActive = false;
   MergedZoneState demandState; demandState.isActive = false;
   
   // 3. Loop through points
   for (int i = 0; i < count; i++)
   {
      PointStruct p = ZigZagPoints[i];
      
      // --- HANDLE SUPPLY ZONES ---
      if (p.type == 1) 
      {
         if (!supplyState.isActive) {
            StartZone(supplyState, p);
         } 
         else {
            // FIX (Fixed Typo Here): Use supplyState.bottom/.top, NOT .zoneLimit...
            // Check Overlap: Range1 [StateBot, StateTop], Range2 [PBot, PTop]
            // Overlap if Max(StateBot, PBot) <= Min(StateTop, PTop)
            
            bool isOverlapping = (MathMax(supplyState.bottom, p.zoneLimitBottom) <= MathMin(supplyState.top, p.zoneLimitTop));
            
            // If NOT overlapping, simply Close Old -> Start New (Step Logic)
            if (!isOverlapping) {
               DrawSingleZone(supplyState.startTime, p.time, supplyState.top, supplyState.bottom, 1, i-1);
               StartZone(supplyState, p);
            }
            else {
               // If Overlapping, check for Breakout (Fakeout logic)
               bool isBroken = CheckForBreakout(supplyState.lastBarIndex, p.barIndex, supplyState.top, 1);
               
               if (isBroken) {
                  DrawSingleZone(supplyState.startTime, p.time, supplyState.top, supplyState.bottom, 1, i-1);
                  StartZone(supplyState, p);
               } else {
                  // Merge (Expand Range)
                  supplyState.top = MathMax(supplyState.top, p.zoneLimitTop);
                  supplyState.bottom = MathMin(supplyState.bottom, p.zoneLimitBottom);
                  supplyState.lastBarIndex = p.barIndex;
               }
            }
         }
      }
      
      // --- HANDLE DEMAND ZONES ---
      else if (p.type == -1) 
      {
         if (!demandState.isActive) {
            StartZone(demandState, p);
         } 
         else {
            // Check Overlap
            bool isOverlapping = (MathMax(demandState.bottom, p.zoneLimitBottom) <= MathMin(demandState.top, p.zoneLimitTop));

            if (!isOverlapping) {
               // Distinct Level -> Close Old, Start New
               DrawSingleZone(demandState.startTime, p.time, demandState.top, demandState.bottom, -1, i-1);
               StartZone(demandState, p);
            } 
            else {
               // Overlapping -> Check Breakout
               bool isBroken = CheckForBreakout(demandState.lastBarIndex, p.barIndex, demandState.bottom, -1);
               
               if (isBroken) {
                  DrawSingleZone(demandState.startTime, p.time, demandState.top, demandState.bottom, -1, i-1);
                  StartZone(demandState, p);
               } else {
                  // Merge
                  demandState.bottom = MathMin(demandState.bottom, p.zoneLimitBottom);
                  demandState.top = MathMax(demandState.top, p.zoneLimitTop);
                  demandState.lastBarIndex = p.barIndex;
               }
            }
         }
      }
   }
   
   // 4. Draw Remaining Active Zones (Extend to Future)
   if (supplyState.isActive) {
      DrawSingleZone(supplyState.startTime, TimeCurrent()+PeriodSeconds()*50, supplyState.top, supplyState.bottom, 1, 999991);
   }
   if (demandState.isActive) {
      DrawSingleZone(demandState.startTime, TimeCurrent()+PeriodSeconds()*50, demandState.top, demandState.bottom, -1, 999992);
   }
   
   ChartRedraw();
}

// --- HELPER: Struct Updater ---
void StartZone(MergedZoneState &state, PointStruct &p) {
   state.isActive = true;
   state.top = p.zoneLimitTop;
   state.bottom = p.zoneLimitBottom;
   state.startTime = p.time;
   state.lastBarIndex = p.barIndex;
}

// --- HELPER: Breakout Check ---
bool CheckForBreakout(int startBarIdx, int endBarIdx, double level, int type)
{
   for (int i = startBarIdx - 1; i > endBarIdx; i--) 
   {
      if (i-1 < 0) return false;
      if (type == 1) { // Supply Break
         if (iClose(_Symbol, _Period, i) > level && IsStrongBody(i) && IsGreen(i)) {
            if (iClose(_Symbol, _Period, i-1) > level && IsStrongBody(i-1) && IsGreen(i-1)) return true;
         }
      }
      else { // Demand Break
         if (iClose(_Symbol, _Period, i) < level && IsStrongBody(i) && IsRed(i)) {
            if (iClose(_Symbol, _Period, i-1) < level && IsStrongBody(i-1) && IsRed(i-1)) return true;
         }
      }
   }
   return false;
}

// --- HELPER: Calculate Limits ---
void CalculateZoneLimits(PointStruct &p) {
   p.zoneLimitTop = p.price; p.zoneLimitBottom = p.price; 
   if (p.type == 1) { // SUPPLY
      int gI=-1, rI=-1; for(int k=0;k<=5;k++){if(IsGreen(p.barIndex+k)){gI=p.barIndex+k;break;}}
      if(gI!=-1) rI=gI-1;
      if(gI!=-1) {
         p.zoneLimitBottom = iOpen(_Symbol,_Period,gI);
         if(IsBigCandle(gI)){
            if(rI!=-1){ p.zoneLimitBottom = iOpen(_Symbol,_Period,rI); if(IsBigCandle(rI)) p.zoneLimitBottom=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0; } 
            else p.zoneLimitBottom=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0;
         }
      }
   } else { // DEMAND
      int rI=-1, gI=-1; for(int k=0;k<=5;k++){if(IsRed(p.barIndex+k)){rI=p.barIndex+k;break;}}
      if(rI!=-1) gI=rI-1;
      if(rI!=-1) {
         p.zoneLimitTop = iOpen(_Symbol,_Period,rI);
         if(IsBigCandle(rI)){
            if(gI!=-1){ p.zoneLimitTop = iOpen(_Symbol,_Period,gI); if(IsBigCandle(gI)) p.zoneLimitTop=(iOpen(_Symbol,_Period,gI)+iClose(_Symbol,_Period,gI))/2.0; }
            else p.zoneLimitTop=(iOpen(_Symbol,_Period,rI)+iClose(_Symbol,_Period,rI))/2.0;
         }
      }
   }
}

// --- HELPERS (Unchanged) ---
void DrawSingleZone(datetime t1, datetime t2, double top, double bottom, int type, int id) {
   if (top <= bottom) return;
   string name = "NCI_Zone_M_" + IntegerToString(id) + "_" + TimeToString(t1);
   color c = (type == 1) ? SupplyColor : DemandColor;
   if(ObjectFind(0,name)<0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true); 
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
}
bool IsBigCandle(int index) { double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); double s=0; int c=0; for(int k=1;k<=10;k++){if(index+k>=iBars(_Symbol,_Period))break;s+=MathAbs(iOpen(_Symbol,_Period,index+k)-iClose(_Symbol,_Period,index+k));c++;} if(c==0)return false; return(b>(s/c)*BigCandleFactor); }
void DrawZigZag() { ObjectsDeleteAll(0, "NCI_ZZ_"); int c=ArraySize(ZigZagPoints); if(c<2)return; for(int i=1;i<c;i++){ string n="NCI_ZZ_"+IntegerToString(i); ObjectCreate(0,n,OBJ_TREND,0,ZigZagPoints[i-1].time,ZigZagPoints[i-1].price,ZigZagPoints[i].time,ZigZagPoints[i].price); ObjectSetInteger(0,n,OBJPROP_COLOR,LineColor); ObjectSetInteger(0,n,OBJPROP_WIDTH,LineWidth); ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); } ChartRedraw(); }
void AddPoint(PointStruct &arr[], PointStruct &p) { int s=ArraySize(arr); ArrayResize(arr,s+1); arr[s]=p; }
bool IsStrongBody(int index) { double h=iHigh(_Symbol,_Period,index); double l=iLow(_Symbol,_Period,index); if(h-l==0)return false; double b=MathAbs(iOpen(_Symbol,_Period,index)-iClose(_Symbol,_Period,index)); return(b>(h-l)*MinBodyPercent); }
bool IsGreen(int index) { return iClose(_Symbol,_Period,index)>iOpen(_Symbol,_Period,index); }
bool IsRed(int index) { return iClose(_Symbol,_Period,index)<iOpen(_Symbol,_Period,index); }
bool IsNewBar() { static datetime last; datetime curr=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); if(last!=curr){last=curr;return true;} return false; }