//+------------------------------------------------------------------+
//|         NCI_SupplyDemand_V16.1_NameFix.mq5                       |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "16.10"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input bool UseTrendFilter   = true;  
input int TrendEMA_Period   = 200;

//--- 2. SUPPLY & DEMAND SETTINGS
input group "2. S&D Settings"
input int LookbackPeriod    = 100;   // How far back to scan for zones
input double ImpulseFactor  = 1.5;   // How much bigger the candle must be (vs ATR) to create a zone
input bool DrawZones        = true;  // Draw boxes on chart?

//--- 3. ENTRY LOGIC
input group "3. Entry Logic"
input double MagnetPips     = 2.0;   // Tolerance for touching the zone edge
input double MinRiskReward  = 1.5;   // S&D allows for higher RR
input double BufferPips     = 3.0;   // Space to put SL outside the zone

//--- 4. PROTECTION
input group "4. Crash/Rocket Protection"
input bool AvoidViolentMoves = true; 
input double MaxCandleSizeATR = 2.0; 

//--- 5. MANAGEMENT
input group "5. Trade Management"
input bool UseOppositeZoneTarget = true; // Target the next Supply/Demand zone?
input double BackupTP_Pips     = 500;    // Fallback if no zone found
input double BreakEvenTrigger  = 0.5;    // % of way to target to move SL to BE

//--- 6. RISK
input group "6. Risk Profiles"
input double RiskPercent = 1.0; 

//--- 7. VISUALS
input color Color_Supply = clrMistyRose;
input color Color_Demand = clrMintCream;

int TrendHandle;
int ATRHandle; 
CTrade trade;

// GLOBAL VARIABLES FOR ZONES
double Supply_Top = 0, Supply_Bot = 0;
double Demand_Top = 0, Demand_Bot = 0;
datetime Supply_Time = 0, Demand_Time = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(666777); 
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   ATRHandle   = iATR(_Symbol, _Period, 14); 
   
   if (TrendHandle == INVALID_HANDLE || ATRHandle == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // 1. UPDATE ZONES 
   FindSupplyDemandZones(); 
   ManageOpenPositions(); 

   double TrendMA[], Close[], Open[], Low[], High[], ATR[];
   ArraySetAsSeries(TrendMA, true); 
   ArraySetAsSeries(Close, true);  
   ArraySetAsSeries(Open, true);
   ArraySetAsSeries(Low, true);
   ArraySetAsSeries(High, true);
   ArraySetAsSeries(ATR, true);

   if (CopyBuffer(TrendHandle, 0, 0, 3, TrendMA) < 3 ||
       CopyBuffer(ATRHandle, 0, 0, 3, ATR) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, Close) < 3 ||
       CopyOpen(_Symbol, _Period, 0, 3, Open) < 3 ||
       CopyLow(_Symbol, _Period, 0, 3, Low) < 3 ||
       CopyHigh(_Symbol, _Period, 0, 3, High) < 3)
      return;

   //--- TREND DIRECTION
   bool IsUptrend = true;
   bool IsDowntrend = true;
   if (UseTrendFilter) 
   {
      IsUptrend   = (Close[1] > TrendMA[1]);
      IsDowntrend = (Close[1] < TrendMA[1]);
   }

   //--- CHECK IF ZONES EXIST
   if (Demand_Top == 0 && Supply_Bot == 0) return;

   //--- ENTRY LOGIC (REJECTION OFF ZONE)
   if (IsNewBar() && PositionsTotal() < 1)
   {
      double magnet = MagnetPips * 10 * _Point;

      // --- BUY AT DEMAND ---
      if (IsUptrend && Demand_Top > 0)
      {
         bool Touched = (Low[1] <= Demand_Top + magnet);
         bool Valid   = (Close[1] > Demand_Bot); // Didn't close below zone
         
         // FIXED: Changed 'Green' to 'isGreen' to avoid name conflict
         bool isGreen   = (Close[1] > Open[1]);
         
         if (Touched && Valid && isGreen)
         {
            Print("BUY SIGNAL: Rejection off Demand Zone at ", Demand_Top);
            OpenTrade(ORDER_TYPE_BUY, Demand_Top, Demand_Bot, Supply_Bot);
         }
      }

      // --- SELL AT SUPPLY ---
      if (IsDowntrend && Supply_Bot > 0)
      {
         bool Touched = (High[1] >= Supply_Bot - magnet);
         bool Valid   = (Close[1] < Supply_Top); // Didn't close above zone
         
         // FIXED: Changed 'Red' to 'isRed' to avoid name conflict
         bool isRed     = (Close[1] < Open[1]);
         
         if (Touched && Valid && isRed)
         {
            Print("SELL SIGNAL: Rejection off Supply Zone at ", Supply_Bot);
            OpenTrade(ORDER_TYPE_SELL, Supply_Bot, Supply_Top, Demand_Top);
         }
      }
   }
}

//--- THE NEW ENGINE: ZONE FINDER ---
void FindSupplyDemandZones()
{
   double Open[], Close[], High[], Low[], ATR[];
   ArraySetAsSeries(Open, true); ArraySetAsSeries(Close, true);
   ArraySetAsSeries(High, true); ArraySetAsSeries(Low, true);
   ArraySetAsSeries(ATR, true);
   
   if (CopyOpen(_Symbol,_Period,0,LookbackPeriod,Open)<LookbackPeriod || 
       CopyATR(_Symbol,_Period,0,LookbackPeriod,ATR)<LookbackPeriod) return;
       
   // Reset Zones
   Supply_Top = 0; Supply_Bot = 0;
   Demand_Top = 0; Demand_Bot = 0;
   
   // 1. SCAN FOR DEMAND (Bullish Impulse)
   for (int i=1; i<LookbackPeriod-5; i++)
   {
      double body = MathAbs(Close[i] - Open[i]);
      // Condition: Massive Green Candle
      if (Close[i] > Open[i] && body > (ATR[i] * ImpulseFactor))
      {
         // The Zone is the Candle BEFORE the explosion (i+1)
         // Only if that candle was Red or small
         if (Close[i+1] < Open[i+1]) 
         {
            double zone_top = High[i+1];
            double zone_bot = Low[i+1];
            
            // Check if broken by future price
            bool broken = false;
            for (int k=i-1; k>=0; k--) {
               if (Close[k] < zone_bot) { broken = true; break; } 
            }
            
            if (!broken) {
               Demand_Top = zone_top;
               Demand_Bot = zone_bot;
               Demand_Time = iTime(_Symbol, _Period, i+1);
               if(DrawZones) DrawRect("DemandZone", Demand_Time, Demand_Top, Demand_Bot, Color_Demand);
               break; 
            }
         }
      }
   }

   // 2. SCAN FOR SUPPLY (Bearish Impulse)
   for (int i=1; i<LookbackPeriod-5; i++)
   {
      double body = MathAbs(Close[i] - Open[i]);
      // Condition: Massive Red Candle
      if (Close[i] < Open[i] && body > (ATR[i] * ImpulseFactor))
      {
         // The Zone is the Candle BEFORE the explosion (i+1)
         // Only if that candle was Green or small
         if (Close[i+1] > Open[i+1]) 
         {
            double zone_top = High[i+1];
            double zone_bot = Low[i+1];
            
            // Check if broken
            bool broken = false;
            for (int k=i-1; k>=0; k--) {
               if (Close[k] > zone_top) { broken = true; break; }
            }
            
            if (!broken) {
               Supply_Top = zone_top;
               Supply_Bot = zone_bot;
               Supply_Time = iTime(_Symbol, _Period, i+1);
               if(DrawZones) DrawRect("SupplyZone", Supply_Time, Supply_Top, Supply_Bot, Color_Supply);
               break; 
            }
         }
      }
   }
}

void OpenTrade(ENUM_ORDER_TYPE type, double entry, double zone_limit, double target_zone)
{
   double currentPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   
   // Tight Stops based on Zone Edge
   if (type == ORDER_TYPE_BUY) {
      sl = zone_limit - (BufferPips * 10 * _Point);
      tp = (UseOppositeZoneTarget && target_zone > 0) ? target_zone : currentPrice + (BackupTP_Pips * _Point);
   }
   else {
      sl = zone_limit + (BufferPips * 10 * _Point);
      tp = (UseOppositeZoneTarget && target_zone > 0) ? target_zone : currentPrice - (BackupTP_Pips * _Point);
   }

   // R:R Filter
   double risk = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   if (risk > 0 && (reward/risk) < MinRiskReward) {
      Print("Skipped Trade: Poor R:R Ratio ", (reward/risk));
      return;
   }

   trade.PositionOpen(_Symbol, type, CalculateLotSize(sl), currentPrice, sl, tp, "S&D Entry");
}

double CalculateLotSize(double sl_price)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (RiskPercent / 100.0);
   double currentPrice = (sl_price < SymbolInfoDouble(_Symbol, SYMBOL_BID)) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = MathAbs(currentPrice - sl_price);
   if (dist == 0) return 0;
   
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot = risk_money / ((dist / tick_sz) * tick_val);
   
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathMax(min, MathFloor(lot/step)*step);
}

void ManageOpenPositions()
{
   if (PositionsTotal() == 0) return;
   for (int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double current = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double total_dist = MathAbs(tp - open);
      double current_dist = MathAbs(current - open);
      
      if (total_dist > 0 && (current_dist / total_dist) > BreakEvenTrigger) {
         if (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && sl < open) 
            trade.PositionModify(ticket, open + 10*_Point, tp);
         if (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && sl > open) 
            trade.PositionModify(ticket, open - 10*_Point, tp);
      }
   }
}

void DrawRect(string name, datetime t1, double top, double bot, color col)
{
   string objName = name + "_" + TimeToString(t1);
   if (ObjectFind(0, objName) < 0) {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, t1, top, TimeCurrent(), bot);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, col);
      ObjectSetInteger(0, objName, OBJPROP_FILL, true); 
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true); 
   }
}

int CopyATR(string symbol, ENUM_TIMEFRAMES period, int start, int count, double &buffer[]) {
   return CopyBuffer(iATR(symbol, period, 14), 0, start, count, buffer);
}

bool IsNewBar() {
   static datetime last;
   datetime curr = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last != curr) { last = curr; return true; }
   return false;
}