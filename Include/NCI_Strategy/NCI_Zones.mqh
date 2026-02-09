//+------------------------------------------------------------------+
//| NCI_Zones.mqh - Zone Logic & Painting                            |
//+------------------------------------------------------------------+
#property strict

#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

// --- ZONE HELPERS ---
void StartZone(MergedZoneState &state, PointStruct &p) { 
   state.isActive=true; 
   state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex; 
}

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

// --- LOGIC FUNCTIONS ---

double FindFutureTarget(int currentIndex, int targetType, double referencePrice)
{
   int totalPoints = ArraySize(ZigZagPoints);
   for(int k = currentIndex + 1; k < totalPoints; k++) 
   {
      if (ZigZagPoints[k].type == targetType) {
         if (targetType == 1) { 
            if (ZigZagPoints[k].zoneLimitBottom > referencePrice) return ZigZagPoints[k].zoneLimitTop; 
         }
         if (targetType == -1) { 
            if (ZigZagPoints[k].zoneLimitTop < referencePrice) return ZigZagPoints[k].zoneLimitBottom; 
         }
      }
   }
   return 0; 
}

datetime CheckZoneLife(int startBar, int type, double targetLevel, double selfBreakLevel)
{
   for(int i = startBar - 1; i > 0; i--) 
   {
      // A. Profit Side
      if (targetLevel != 0) {
          if (type == 1) { if (CheckForBreakout(i+1, i, targetLevel, 1)) return GetTime(i); } 
          else { if (CheckForBreakout(i+1, i, targetLevel, -1)) return GetTime(i); }
      }
      // B. Loss Side (Self Break) - Uses Strict Helper Logic
      if (type == 1) { if (CheckForBreakout(i+1, i, selfBreakLevel, -1)) return GetTime(i); } 
      else { if (CheckForBreakout(i+1, i, selfBreakLevel, 1)) return GetTime(i); }
   }
   return 0; 
}

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
      
      if (p.type == 1) { // SUPPLY
         if (!supply.isActive) StartZone(supply, p); 
         else { 
            // Use Strict Helper Logic for Breakout
            datetime preciseBreakTime = FindBreakoutTime(supply.lastBarIndex, p.barIndex, supply.top, 1);
            
            if (p.price > supply.top && preciseBreakTime == 0) preciseBreakTime = p.time; // Gap protection

            if (preciseBreakTime > 0) { 
               DrawSingleZone(supply.startTime, preciseBreakTime, supply.top, supply.bottom, 1, i-1); 
               
               if (p.assignedTrend != 1) { 
                   if (activeFlippedDemand.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlippedDemand.endTime > 0 && activeFlippedDemand.endTime < preciseBreakTime) end = activeFlippedDemand.endTime;
                       DrawFlippedZone(activeFlippedDemand, end); 
                       activeFlippedDemand.isActive = false; 
                   }
                   if (activeFlippedSupply.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlippedSupply.endTime > 0 && activeFlippedSupply.endTime < preciseBreakTime) end = activeFlippedSupply.endTime;
                       DrawFlippedZone(activeFlippedSupply, end); 
                       activeFlippedSupply.isActive = false; 
                   }

                   MergedZoneState flip = supply;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   double futureTarget = FindFutureTarget(i, 1, supply.top); 
                   datetime deathTime = CheckZoneLife(p.barIndex, 1, futureTarget, supply.bottom);
                   
                   activeFlippedDemand = flip;
                   if (deathTime == 0) {
                      activeFlippedDemand.endTime = 0; 
                      DrawFlippedZone(flip, TimeCurrent()+PeriodSeconds()*50); 
                   } else {
                      activeFlippedDemand.endTime = deathTime;
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
      else if (p.type == -1) { // DEMAND
         if (!demand.isActive) StartZone(demand, p); 
         else { 
            datetime preciseBreakTime = FindBreakoutTime(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            
            if (p.price < demand.bottom && preciseBreakTime == 0) preciseBreakTime = p.time; // Gap protection

            if (preciseBreakTime > 0) { 
               DrawSingleZone(demand.startTime, preciseBreakTime, demand.top, demand.bottom, -1, i-1); 
               
               if (p.assignedTrend != -1) { 
                   if (activeFlippedDemand.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlippedDemand.endTime > 0 && activeFlippedDemand.endTime < preciseBreakTime) end = activeFlippedDemand.endTime;
                       DrawFlippedZone(activeFlippedDemand, end); 
                       activeFlippedDemand.isActive = false; 
                   }
                   if (activeFlippedSupply.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlippedSupply.endTime > 0 && activeFlippedSupply.endTime < preciseBreakTime) end = activeFlippedSupply.endTime;
                       DrawFlippedZone(activeFlippedSupply, end); 
                       activeFlippedSupply.isActive = false; 
                   }

                   MergedZoneState flip = demand;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   double futureTarget = FindFutureTarget(i, -1, demand.bottom); 
                   datetime deathTime = CheckZoneLife(p.barIndex, -1, futureTarget, demand.top);
                   
                   activeFlippedSupply = flip;
                   if (deathTime == 0) {
                      activeFlippedSupply.endTime = 0; 
                      DrawFlippedZone(flip, TimeCurrent()+PeriodSeconds()*50); 
                   } else {
                      activeFlippedSupply.endTime = deathTime;
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
   
   // --- ZOMBIE FIX: SCAN HISTORY WITH STRICT RULES ---
   
   // 1. Validate Supply
   if (supply.isActive) {
      int startBar = iBarShift(_Symbol, _Period, supply.startTime);
      // Use the SHARED Strict Helper to check if it died in the "Blind Spot"
      datetime deadTime = FindBreakoutTime(startBar, 0, supply.top, 1);
      
      if(deadTime > 0) {
         supply.isActive = false;
         // Draw it as dead ending at the confirmation candle
         DrawSingleZone(supply.startTime, deadTime, supply.top, supply.bottom, 1, 999991); 
      }
   }

   // 2. Validate Demand
   if (demand.isActive) {
      int startBar = iBarShift(_Symbol, _Period, demand.startTime);
      // Use the SHARED Strict Helper
      datetime deadTime = FindBreakoutTime(startBar, 0, demand.bottom, -1);
      
      if(deadTime > 0) {
         demand.isActive = false;
         DrawSingleZone(demand.startTime, deadTime, demand.top, demand.bottom, -1, 999992); 
      }
   }
   
   if (supply.isActive) DrawSingleZone(supply.startTime, TimeCurrent()+PeriodSeconds()*50, supply.top, supply.bottom, 1, 999991); 
   if (demand.isActive) DrawSingleZone(demand.startTime, TimeCurrent()+PeriodSeconds()*50, demand.top, demand.bottom, -1, 999992); 
   
   activeSupply = supply; 
   activeDemand = demand; 
   
   if(DrawZones) ChartRedraw(); 
}