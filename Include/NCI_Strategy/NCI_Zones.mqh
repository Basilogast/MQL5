//+------------------------------------------------------------------+
//| NCI_Zones.mqh - Zone Logic & Painting                            |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

void StartZone(MergedZoneState &state, PointStruct &p) { 
   state.isActive=true; 
   state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex; 
}

void MergeZone(MergedZoneState &state, PointStruct &p, int type) { 
   if (type == 1) { state.top = MathMax(state.top, p.price); state.bottom = p.zoneLimitBottom; } 
   else { state.bottom = MathMin(state.bottom, p.price); state.top = p.zoneLimitTop; } 
   state.startTime = p.time; state.lastBarIndex = p.barIndex; 
}

// *** UPDATED: VISUAL TOGGLE & SPEED FIX (MQL5 COMPLIANT) ***
void DrawSingleZone(string suffix, datetime t1, datetime t2, double top, double bottom, int type, int id) { 
   if (top <= bottom) return; 
   
   // 1. GLOBAL SPEED TOGGLE
   if (!Show_Zone_Boxes) return;

   // 2. SPEED FIX: Stop here if optimizing
   if (MQLInfoInteger(MQL_OPTIMIZATION)) return;

   // 3. DASHBOARD CHECK (Preserved)
   if (suffix == "_HTF" && !ShowHTF) return;
   if (suffix == "_LTF" && !ShowLTF) return;

   string name = "NCI_Zone_" + suffix + IntegerToString(id) + "_" + TimeToString(t1); 
   
   color c;
   if (suffix == "_HTF") {
       c = (type == 1) ? clrIndianRed : clrMediumSeaGreen; 
   } else {
       c = (type == 1) ? SupplyColor : DemandColor; 
   }

   // MQL5 Fix: Changed OBJPROP_TIME2 to OBJPROP_TIME, 1
   if(ObjectFind(0,name)<0) { 
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, (t2==0)?TimeCurrent():t2, bottom); 
      ObjectSetInteger(0, name, OBJPROP_COLOR, c); 
      ObjectSetInteger(0, name, OBJPROP_FILL, true); 
      ObjectSetInteger(0, name, OBJPROP_BACK, true); 
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); 
   } else {
      // Update End Time if object exists
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, (t2==0)?TimeCurrent():t2);
   }
}

// *** UPDATED: VISUAL TOGGLE & SPEED FIX ***
void DrawFlippedZone(string suffix, MergedZoneState &state, datetime endTime) {
   // 1. GLOBAL SPEED TOGGLE
   if (!Show_Zone_Boxes) return;

   // 2. SPEED FIX: Stop here if optimizing
   if (MQLInfoInteger(MQL_OPTIMIZATION)) return;

   // 3. DASHBOARD CHECK (Preserved)
   if (suffix == "_HTF" && !ShowHTF) return;
   if (suffix == "_LTF" && !ShowLTF) return;

   string name = "NCI_Flip_" + suffix + TimeToString(state.startTime);
   color c = FlippedColor;
   if (suffix == "_HTF") c = clrSilver; 

   // MQL5 Fix: Changed OBJPROP_TIME2 to OBJPROP_TIME, 1
   if(ObjectFind(0,name)<0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, state.startTime, state.top, endTime, state.bottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c); 
      ObjectSetInteger(0, name, OBJPROP_FILL, true); 
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   } else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, endTime);
   }
}

// [Keep Logic Functions: FindFutureTarget, CheckZoneLife ... unchanged]
double FindFutureTarget(PointStruct &points[], int currentIndex, int targetType, double referencePrice)
{
   int totalPoints = ArraySize(points);
   for(int k = currentIndex + 1; k < totalPoints; k++) 
   {
      if (points[k].type == targetType) {
         if (targetType == 1) { 
            if (points[k].zoneLimitBottom > referencePrice) return points[k].zoneLimitTop; 
         }
         if (targetType == -1) { 
            if (points[k].zoneLimitTop < referencePrice) return points[k].zoneLimitBottom; 
         }
      }
   }
   return 0; 
}

datetime CheckZoneLife(ENUM_TIMEFRAMES tf, int startBar, int type, double targetLevel, double selfBreakLevel)
{
   for(int i = startBar - 1; i > 0; i--) 
   {
      if (targetLevel != 0) {
          if (type == 1) { if (CheckForBreakout(tf, i+1, i, targetLevel, 1)) return GetTime(tf, i); } 
          else { if (CheckForBreakout(tf, i+1, i, targetLevel, -1)) return GetTime(tf, i); }
      }
      if (type == 1) { if (CheckForBreakout(tf, i+1, i, selfBreakLevel, -1)) return GetTime(tf, i); } 
      else { if (CheckForBreakout(tf, i+1, i, selfBreakLevel, 1)) return GetTime(tf, i); }
   }
   return 0; 
}

// *** UPDATED: VISUAL TOGGLE & SPEED FIX ***
void DrawParallelZones(ENUM_TIMEFRAMES tf, PointStruct &points[], MergedZoneState &activeSup, MergedZoneState &activeDem, MergedZoneState &activeFlipSup, MergedZoneState &activeFlipDem, string suffix) { 
   // 1. SPEED FIX: Only delete objects if NOT optimizing AND Global Toggle is ON
   if (!MQLInfoInteger(MQL_OPTIMIZATION) && Show_Zone_Boxes) {
       ObjectsDeleteAll(0, "NCI_Zone_" + suffix);
       ObjectsDeleteAll(0, "NCI_Flip_" + suffix); 
   }
   
   activeFlipSup.isActive = false; 
   activeFlipDem.isActive = false; 
   
   int count = ArraySize(points); 
   if (count == 0) return; 
   
   MergedZoneState supply; supply.isActive = false; 
   MergedZoneState demand; demand.isActive = false; 
   
   for (int i = 0; i < count; i++) { 
      PointStruct p = points[i]; 
      
      if (p.type == 1) { // SUPPLY
         if (!supply.isActive) StartZone(supply, p); 
         else { 
            datetime preciseBreakTime = FindBreakoutTime(tf, supply.lastBarIndex, p.barIndex, supply.top, 1);
            if (preciseBreakTime > 0) { 
               DrawSingleZone(suffix, supply.startTime, preciseBreakTime, supply.top, supply.bottom, 1, i-1); 
               
               if (p.assignedTrend != 1) { 
                   if (activeFlipDem.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipDem.endTime > 0 && activeFlipDem.endTime < preciseBreakTime) end = activeFlipDem.endTime;
                       DrawFlippedZone(suffix, activeFlipDem, end); 
                       activeFlipDem.isActive = false; 
                   }
                   if (activeFlipSup.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipSup.endTime > 0 && activeFlipSup.endTime < preciseBreakTime) end = activeFlipSup.endTime;
                       DrawFlippedZone(suffix, activeFlipSup, end); 
                       activeFlipSup.isActive = false; 
                   }

                   MergedZoneState flip = supply;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   double futureTarget = FindFutureTarget(points, i, 1, supply.top); 
                   datetime deathTime = CheckZoneLife(tf, p.barIndex, 1, futureTarget, supply.bottom);
                   
                   activeFlipDem = flip;
                   if (deathTime == 0) {
                      activeFlipDem.endTime = 0; 
                      DrawFlippedZone(suffix, flip, TimeCurrent()+PeriodSeconds(tf)*50); 
                   } else {
                      activeFlipDem.endTime = deathTime;
                      DrawFlippedZone(suffix, flip, deathTime); 
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
                  DrawSingleZone(suffix, supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); 
                  MergeZone(supply, p, 1); 
               } else { 
                  DrawSingleZone(suffix, supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); 
                  StartZone(supply, p); 
               } 
            } 
         } 
      } 
      else if (p.type == -1) { // DEMAND
         if (!demand.isActive) StartZone(demand, p); 
         else { 
            datetime preciseBreakTime = FindBreakoutTime(tf, demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            if (preciseBreakTime > 0) { 
               DrawSingleZone(suffix, demand.startTime, preciseBreakTime, demand.top, demand.bottom, -1, i-1); 
               
               if (p.assignedTrend != -1) { 
                   if (activeFlipDem.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipDem.endTime > 0 && activeFlipDem.endTime < preciseBreakTime) end = activeFlipDem.endTime;
                       DrawFlippedZone(suffix, activeFlipDem, end); 
                       activeFlipDem.isActive = false; 
                   }
                   if (activeFlipSup.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipSup.endTime > 0 && activeFlipSup.endTime < preciseBreakTime) end = activeFlipSup.endTime;
                       DrawFlippedZone(suffix, activeFlipSup, end); 
                       activeFlipSup.isActive = false; 
                   }

                   MergedZoneState flip = demand;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   double futureTarget = FindFutureTarget(points, i, -1, demand.bottom); 
                   datetime deathTime = CheckZoneLife(tf, p.barIndex, -1, futureTarget, demand.top);
                   
                   activeFlipSup = flip;
                   if (deathTime == 0) {
                      activeFlipSup.endTime = 0; 
                      DrawFlippedZone(suffix, flip, TimeCurrent()+PeriodSeconds(tf)*50); 
                   } else {
                      activeFlipSup.endTime = deathTime;
                      DrawFlippedZone(suffix, flip, deathTime); 
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
                  DrawSingleZone(suffix, demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); 
                  MergeZone(demand, p, -1); 
               } else { 
                  DrawSingleZone(suffix, demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); 
                  StartZone(demand, p); 
               } 
            } 
         } 
      } 
   } 
   
   // --- ZOMBIE FIX: SCAN HISTORY WITH STRICT RULES ---
   if (supply.isActive) {
      int startBar = iBarShift(_Symbol, tf, supply.startTime);
      datetime deadTime = FindBreakoutTime(tf, startBar, 0, supply.top, 1);
      if(deadTime > 0) {
         supply.isActive = false;
         DrawSingleZone(suffix, supply.startTime, deadTime, supply.top, supply.bottom, 1, 999991); 
      }
   }
   if (demand.isActive) {
      int startBar = iBarShift(_Symbol, tf, demand.startTime);
      datetime deadTime = FindBreakoutTime(tf, startBar, 0, demand.bottom, -1);
      if(deadTime > 0) {
         demand.isActive = false;
         DrawSingleZone(suffix, demand.startTime, deadTime, demand.top, demand.bottom, -1, 999992); 
      }
   }
   
   if (supply.isActive) DrawSingleZone(suffix, supply.startTime, TimeCurrent()+PeriodSeconds(tf)*50, supply.top, supply.bottom, 1, 999991); 
   if (demand.isActive) DrawSingleZone(suffix, demand.startTime, TimeCurrent()+PeriodSeconds(tf)*50, demand.top, demand.bottom, -1, 999992); 
   
   activeSup = supply; 
   activeDem = demand; 
   
   // FIX: Changed 'DrawZones' to 'Show_Zone_Boxes'
   if(!MQLInfoInteger(MQL_OPTIMIZATION) && Show_Zone_Boxes) ChartRedraw(); 
}