//+------------------------------------------------------------------+
//|         NCI_Structure_V17.0_FractalBOS.mq5                       |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "17.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input bool UseTrendFilter   = true;  
input int TrendEMA_Period   = 200;

//--- 2. STRUCTURE SETTINGS
input group "2. Structure Settings"
input bool DrawLevels       = true;  // Draw the Key Levels on chart?
input int Fractal_Depth     = 3;     // Bars required to confirm a fractal (Default 3)

//--- 3. ENTRY LOGIC
input group "3. Entry Logic"
input double MagnetPips     = 3.0;   // Tolerance for touching the line
input double MinRiskReward  = 1.5;   
input double StopBufferPips = 5.0;   // Place SL this far below the key level

//--- 4. PROTECTION
input group "4. Protection"
input bool AvoidViolentMoves = true; 
input double MaxCandleSizeATR = 2.5; 

//--- 5. MANAGEMENT
input group "5. Trade Management"
input double Target_RiskMultiple = 3.0; // Target is 3x Risk (1:3 RR)
input double BreakEvenTrigger    = 1.0; // Move to BE when price moves 1x Risk

//--- 6. RISK
input group "6. Risk Profiles"
input double RiskPercent = 1.0; 

int TrendHandle;
int ATRHandle; 
int FractalHandle;
CTrade trade;

// GLOBAL VARIABLES TO STORE KEY LEVELS
double Active_SupportLevel = 0;    // The "Buy Line" (Broken Resistance)
double Active_ResistanceLevel = 0; // The "Sell Line" (Broken Support)
datetime Support_Time = 0;
datetime Resistance_Time = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(777888); 
   TrendHandle   = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   ATRHandle     = iATR(_Symbol, _Period, 14); 
   FractalHandle = iFractals(_Symbol, _Period);
   
   if (TrendHandle == INVALID_HANDLE || ATRHandle == INVALID_HANDLE || FractalHandle == INVALID_HANDLE) 
      return INIT_FAILED;
   
   Print(">>> V17 INIT: Fractal Structure Strategy Started.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   UpdateKeyLevels(); // Scan for BOS
   ManageOpenPositions(); 

   double TrendMA[], Close[], Open[], Low[], High[], ATR[];
   ArraySetAsSeries(TrendMA, true); ArraySetAsSeries(Close, true);  
   ArraySetAsSeries(Open, true);    ArraySetAsSeries(Low, true);
   ArraySetAsSeries(High, true);    ArraySetAsSeries(ATR, true);

   if (CopyBuffer(TrendHandle, 0, 0, 3, TrendMA) < 3 ||
       CopyBuffer(ATRHandle, 0, 0, 3, ATR) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, Close) < 3 ||
       CopyOpen(_Symbol, _Period, 0, 3, Open) < 3 ||
       CopyLow(_Symbol, _Period, 0, 3, Low) < 3 ||
       CopyHigh(_Symbol, _Period, 0, 3, High) < 3)
      return;

   //--- TREND FILTER
   bool IsUptrend   = (Close[1] > TrendMA[1]);
   bool IsDowntrend = (Close[1] < TrendMA[1]);
   if (!UseTrendFilter) { IsUptrend = true; IsDowntrend = true; }

   //--- ENTRY LOGIC (RETEST OF KEY LEVEL)
   if (IsNewBar() && PositionsTotal() < 1)
   {
      double magnet = MagnetPips * 10 * _Point;

      // --- BUY SIGNAL (Retest of Active Support) ---
      if (Active_SupportLevel > 0 && IsUptrend)
      {
         // 1. Did we touch/dip near the level?
         bool Touched = (Low[1] <= Active_SupportLevel + magnet);
         // 2. Did we close back ABOVE the level? (Respect)
         bool Respect = (Close[1] > Active_SupportLevel);
         // 3. Is the signal candle GREEN?
         bool isGreen = (Close[1] > Open[1]);
         
         if (Touched && Respect && isGreen)
         {
            Print(">>> BUY SIGNAL: Retest of Support Level ", Active_SupportLevel);
            OpenTrade(ORDER_TYPE_BUY, Active_SupportLevel);
            Active_SupportLevel = 0; // Reset level after use (One shot)
         }
      }

      // --- SELL SIGNAL (Retest of Active Resistance) ---
      if (Active_ResistanceLevel > 0 && IsDowntrend)
      {
         // 1. Did we touch/rally near the level?
         bool Touched = (High[1] >= Active_ResistanceLevel - magnet);
         // 2. Did we close back BELOW the level? (Respect)
         bool Respect = (Close[1] < Active_ResistanceLevel);
         // 3. Is the signal candle RED?
         bool isRed   = (Close[1] < Open[1]);
         
         if (Touched && Respect && isRed)
         {
            Print(">>> SELL SIGNAL: Retest of Resistance Level ", Active_ResistanceLevel);
            OpenTrade(ORDER_TYPE_SELL, Active_ResistanceLevel);
            Active_ResistanceLevel = 0; // Reset level after use
         }
      }
   }
}

//--- THE ENGINE: IDENTIFY BOS (Break of Structure) ---
void UpdateKeyLevels()
{
   if(!IsNewBar()) return; // Only scan on bar close

   double UpFractals[], DownFractals[], Close[];
   ArraySetAsSeries(UpFractals, true); ArraySetAsSeries(DownFractals, true);
   ArraySetAsSeries(Close, true);
   
   CopyBuffer(FractalHandle, 0, 0, 50, UpFractals);   // Upper Fractals
   CopyBuffer(FractalHandle, 1, 0, 50, DownFractals); // Lower Fractals
   CopyClose(_Symbol, _Period, 0, 50, Close);

   // 1. FIND RECENT FRACTALS
   double lastFractalHigh = 0;
   double lastFractalLow = 0;
   
   // Loop skipping index 0-2 (Fractals need time to form/confirm)
   for(int i=3; i<50; i++) {
      if(UpFractals[i] != EMPTY_VALUE && lastFractalHigh == 0) lastFractalHigh = UpFractals[i];
      if(DownFractals[i] != EMPTY_VALUE && lastFractalLow == 0) lastFractalLow = DownFractals[i];
      if(lastFractalHigh > 0 && lastFractalLow > 0) break;
   }

   // 2. CHECK FOR BULLISH BREAK (Resistance becomes Support)
   // If Close[1] broke above the last Fractal High...
   if (lastFractalHigh > 0 && Close[1] > lastFractalHigh && Close[2] <= lastFractalHigh)
   {
      Active_SupportLevel = lastFractalHigh; // NEW KEY LEVEL
      Support_Time = iTime(_Symbol, _Period, 1);
      Print(">>> STRUCTURE BREAK (BOS): Resistance ", lastFractalHigh, " Broken. Now SUPPORT.");
      if(DrawLevels) DrawLine("Key_Support", Active_SupportLevel, clrGreen);
   }

   // 3. CHECK FOR BEARISH BREAK (Support becomes Resistance)
   // If Close[1] broke below the last Fractal Low...
   if (lastFractalLow > 0 && Close[1] < lastFractalLow && Close[2] >= lastFractalLow)
   {
      Active_ResistanceLevel = lastFractalLow; // NEW KEY LEVEL
      Resistance_Time = iTime(_Symbol, _Period, 1);
      Print(">>> STRUCTURE BREAK (BOS): Support ", lastFractalLow, " Broken. Now RESISTANCE.");
      if(DrawLevels) DrawLine("Key_Resistance", Active_ResistanceLevel, clrRed);
   }
}

void OpenTrade(ENUM_ORDER_TYPE type, double keyLevel)
{
   double currentPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   
   // SL placed behind the Key Level
   if (type == ORDER_TYPE_BUY) {
      sl = keyLevel - (StopBufferPips * 10 * _Point);
      double risk = currentPrice - sl;
      tp = currentPrice + (risk * Target_RiskMultiple);
   }
   else {
      sl = keyLevel + (StopBufferPips * 10 * _Point);
      double risk = sl - currentPrice;
      tp = currentPrice - (risk * Target_RiskMultiple);
   }

   // Check Risk Reward (Safety)
   if (MathAbs(currentPrice - sl) < 10*_Point) return; // Too close

   trade.PositionOpen(_Symbol, type, CalculateLotSize(sl), currentPrice, sl, tp, "Struct_V17");
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
      
      // Break Even Logic
      if (total_dist > 0 && (current_dist / MathAbs(open-sl)) > BreakEvenTrigger) {
         if (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && sl < open) 
            trade.PositionModify(ticket, open + 10*_Point, tp);
         if (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && sl > open) 
            trade.PositionModify(ticket, open - 10*_Point, tp);
      }
   }
}

void DrawLine(string name, double price, color col)
{
   string objName = name;
   ObjectDelete(0, objName); // Delete old one
   ObjectCreate(0, objName, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, col);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ChartRedraw();
}

bool IsNewBar() {
   static datetime last;
   datetime curr = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last != curr) { last = curr; return true; }
   return false;
}