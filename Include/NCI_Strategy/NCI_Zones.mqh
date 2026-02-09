//+------------------------------------------------------------------+
//| NCI_Zones.mqh - Zone Logic & Painting                            |
//+------------------------------------------------------------------+
#property strict

// Includes
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

// --- ZONE HELPERS ---
void StartZone(MergedZoneState &state, PointStruct &p) { 
   state.isActive=true; state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex; 
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
double FindNextTarget(int currentIndex, int targetType)
{
   // RETRO-SCAN: Look BACKWARDS for past structure
   for(int k = currentIndex - 1; k >= 0; k--) 
   {
      if (ZigZagPoints[k].type == targetType) {
         if (targetType == 1) return ZigZagPoints[k].zoneLimitBottom; 
         if (targetType == -1) return ZigZagPoints[k].zoneLimitTop;   
      }
   }
   return 0; 
}

datetime CheckZoneLife(int startBar, int type, double targetLevel, double selfBreakLevel)
{
   for(int i = startBar - 1; i > 0; i--) 
   {
      double close = GetClose(i);
      // 1. Target Hit (Simple)
      if (targetLevel != 0) {
          if (type == 1) { if (close > targetLevel) return GetTime(i); } 
          else { if (close < targetLevel) return GetTime(i); }
      }
      // 2. Self Break (Strict)
      if (type == 1) { if (CheckForBreakout(i+1, i, selfBreakLevel, -1)) return GetTime(i); } 
      else { if (CheckForBreakout(i+1, i, selfBreakLevel, 1)) return GetTime(i); }
   }
   return 0; 
}

void DrawParallelZones() { 
   ObjectsDeleteAll(0, "NCI_Zone_");
   ObjectsDeleteAll(0, "NCI_Flip_"); 
   
   // Reset Flipped Globals
   activeFlippedSupply.isActive = false; 
   activeFlippedDemand.isActive = false; 
   
   int count = ArraySize(ZigZagPoints); 
   if (count == 0) return; 
   
   // Local State Variables
   MergedZoneState supply; supply.isActive = false; 
   MergedZoneState demand; demand.isActive = false; 
   
   for (int i = 0; i < count; i++) { 
      PointStruct p = ZigZagPoints[i]; 
      
      if (p.type == 1) { // SUPPLY ZONE LOGIC
         if (!supply.isActive) StartZone(supply, p); 
         else { 
            bool isBroken = CheckForBreakout(supply.lastBarIndex, p.barIndex, supply.top, 1);
            if (p.price > supply.top) isBroken = true; 

            if (isBroken) { 
               datetime preciseBreakTime = FindBreakoutTime(supply.lastBarIndex, p.barIndex, supply.top, 1);
               if (preciseBreakTime == 0) preciseBreakTime = p.time; 

               DrawSingleZone(supply.startTime, preciseBreakTime, supply.top, supply.bottom, 1, i-1); 
               
               if (p.assignedTrend != 1) { 
                   MergedZoneState flip = supply;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   
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
      else if (p.type == -1) { // DEMAND ZONE LOGIC
         if (!demand.isActive) StartZone(demand, p); 
         else { 
            bool isBroken = CheckForBreakout(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            if (p.price < demand.bottom) isBroken = true; 

            if (isBroken) { 
               datetime preciseBreakTime = FindBreakoutTime(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
               if (preciseBreakTime == 0) preciseBreakTime = p.time; 

               DrawSingleZone(demand.startTime, preciseBreakTime, demand.top, demand.bottom, -1, i-1); 
               
               if (p.assignedTrend != -1) { 
                   MergedZoneState flip = demand;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   
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
   
   // Draw Live Zones
   if (supply.isActive) DrawSingleZone(supply.startTime, TimeCurrent()+PeriodSeconds()*50, supply.top, supply.bottom, 1, 999991); 
   if (demand.isActive) DrawSingleZone(demand.startTime, TimeCurrent()+PeriodSeconds()*50, demand.top, demand.bottom, -1, 999992); 
   
   // *** CRITICAL FIX: UPDATE GLOBAL STATE FOR TRADING LOGIC ***
   activeSupply = supply;
   activeDemand = demand;
   
   if(DrawZones) ChartRedraw(); 
}