//+------------------------------------------------------------------+
//|         NCI_Structure_V17.2_CleanVisuals.mq5                     |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "17.20"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input bool UseTrendFilter   = true;  
input int TrendEMA_Period   = 200;

//--- 2. STRUCTURE SETTINGS
input group "2. Structure Settings"
input bool ShowHistory      = true;  // Show old levels as dashed lines?
input int Fractal_Depth     = 3;     

//--- 3. ENTRY LOGIC
input group "3. Entry Logic"
input double MagnetPips     = 3.0;   
input double MinRiskReward  = 1.5;   
input double StopBufferPips = 5.0;   

//--- 4. PROTECTION
input group "4. Protection"
input bool AvoidViolentMoves = true; 
input double MaxCandleSizeATR = 2.5; 

//--- 5. MANAGEMENT
input group "5. Trade Management"
input double Target_RiskMultiple = 3.0; 
input double BreakEvenTrigger    = 1.0; 

//--- 6. RISK
input group "6. Risk Profiles"
input double RiskPercent = 1.0; 

int TrendHandle;
int ATRHandle; 
int FractalHandle;
CTrade trade;

// GLOBAL VARIABLES
double Active_SupportLevel = 0;    
double Active_ResistanceLevel = 0; 
string Active_SupportName = "";
string Active_ResistanceName = "";

int OnInit()
{
   trade.SetExpertMagicNumber(777888); 
   TrendHandle   = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   ATRHandle     = iATR(_Symbol, _Period, 14); 
   FractalHandle = iFractals(_Symbol, _Period);
   
   if (TrendHandle == INVALID_HANDLE || ATRHandle == INVALID_HANDLE || FractalHandle == INVALID_HANDLE) 
      return INIT_FAILED;
   
   return INIT_SUCCEEDED;
}

void OnTick()
{
   UpdateKeyLevels(); 
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

   //--- VALIDATE ACTIVE LEVELS (Check for Breaks)
   if (Active_SupportLevel > 0 && Close[1] < Active_SupportLevel) {
      // Support Broken! Kill it.
      if (ShowHistory) StyleAsBroken(Active_SupportName); 
      else ObjectDelete(0, Active_SupportName);
      Active_SupportLevel = 0; 
      Active_SupportName = "";
      Print(">>> LEVEL BROKEN: Support Failed.");
   }

   if (Active_ResistanceLevel > 0 && Close[1] > Active_ResistanceLevel) {
      // Resistance Broken! Kill it.
      if (ShowHistory) StyleAsBroken(Active_ResistanceName);
      else ObjectDelete(0, Active_ResistanceName);
      Active_ResistanceLevel = 0;
      Active_ResistanceName = "";
      Print(">>> LEVEL BROKEN: Resistance Failed.");
   }

   //--- ENTRY LOGIC
   if (IsNewBar() && PositionsTotal() < 1)
   {
      double magnet = MagnetPips * 10 * _Point;

      // BUY SIGNAL (Retest of Support)
      if (Active_SupportLevel > 0 && IsUptrend)
      {
         bool Touched = (Low[1] <= Active_SupportLevel + magnet);
         bool Respect = (Close[1] > Active_SupportLevel);
         bool isGreen = (Close[1] > Open[1]);
         
         if (Touched && Respect && isGreen)
         {
            Print(">>> BUY SIGNAL: Retest of Support Level ", Active_SupportLevel);
            OpenTrade(ORDER_TYPE_BUY, Active_SupportLevel);
         }
      }

      // SELL SIGNAL (Retest of Resistance)
      if (Active_ResistanceLevel > 0 && IsDowntrend)
      {
         bool Touched = (High[1] >= Active_ResistanceLevel - magnet);
         bool Respect = (Close[1] < Active_ResistanceLevel);
         bool isRed   = (Close[1] < Open[1]);
         
         if (Touched && Respect && isRed)
         {
            Print(">>> SELL SIGNAL: Retest of Resistance Level ", Active_ResistanceLevel);
            OpenTrade(ORDER_TYPE_SELL, Active_ResistanceLevel);
         }
      }
   }
}

//--- THE ENGINE: IDENTIFY BOS ---
void UpdateKeyLevels()
{
   if(!IsNewBar()) return; 

   double UpFractals[], DownFractals[], Close[];
   ArraySetAsSeries(UpFractals, true); ArraySetAsSeries(DownFractals, true);
   ArraySetAsSeries(Close, true);
   
   CopyBuffer(FractalHandle, 0, 0, 50, UpFractals);   
   CopyBuffer(FractalHandle, 1, 0, 50, DownFractals); 
   CopyClose(_Symbol, _Period, 0, 50, Close);

   double lastFractalHigh = 0;
   double lastFractalLow = 0;
   
   for(int i=3; i<50; i++) {
      if(UpFractals[i] != EMPTY_VALUE && lastFractalHigh == 0) lastFractalHigh = UpFractals[i];
      if(DownFractals[i] != EMPTY_VALUE && lastFractalLow == 0) lastFractalLow = DownFractals[i];
      if(lastFractalHigh > 0 && lastFractalLow > 0) break;
   }

   // 1. BULLISH BREAK (New Support Created)
   if (lastFractalHigh > 0 && Close[1] > lastFractalHigh && Close[2] <= lastFractalHigh)
   {
      if (MathAbs(Active_SupportLevel - lastFractalHigh) > _Point)
      {
         // Downgrade old level before replacing
         if(Active_SupportName != "") StyleAsHistory(Active_SupportName);
         
         Active_SupportLevel = lastFractalHigh;
         Active_SupportName = "Sup_" + TimeToString(iTime(_Symbol, _Period, 1));
         Print(">>> NEW LEVEL: Support at ", Active_SupportLevel);
         DrawActiveSegment(Active_SupportName, Active_SupportLevel, iTime(_Symbol, _Period, 1), clrGreen);
      }
   }

   // 2. BEARISH BREAK (New Resistance Created)
   if (lastFractalLow > 0 && Close[1] < lastFractalLow && Close[2] >= lastFractalLow)
   {
      if (MathAbs(Active_ResistanceLevel - lastFractalLow) > _Point)
      {
         // Downgrade old level before replacing
         if(Active_ResistanceName != "") StyleAsHistory(Active_ResistanceName);
         
         Active_ResistanceLevel = lastFractalLow;
         Active_ResistanceName = "Res_" + TimeToString(iTime(_Symbol, _Period, 1));
         Print(">>> NEW LEVEL: Resistance at ", Active_ResistanceLevel);
         DrawActiveSegment(Active_ResistanceName, Active_ResistanceLevel, iTime(_Symbol, _Period, 1), clrRed);
      }
   }
}

//--- VISUAL FUNCTIONS ---
void DrawActiveSegment(string name, double price, datetime start, color col)
{
   if (ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TREND, 0, start, price, TimeCurrent(), price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2); // Thick
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); 
   }
   ChartRedraw();
}

void StyleAsHistory(string name)
{
   if (ObjectFind(0, name) >= 0) {
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT); // Dashed
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); // Thin
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); // Stop extending
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, TimeCurrent()); // End line here
   }
   ChartRedraw();
}

void StyleAsBroken(string name)
{
   if (ObjectFind(0, name) >= 0) {
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray); // Grey out
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, TimeCurrent()); 
   }
   ChartRedraw();
}

void OpenTrade(ENUM_ORDER_TYPE type, double keyLevel)
{
   double currentPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   
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

   if (MathAbs(currentPrice - sl) < 10*_Point) return; 

   trade.PositionOpen(_Symbol, type, CalculateLotSize(sl), currentPrice, sl, tp, "Struct_V17.2");
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
      
      if (total_dist > 0 && (current_dist / MathAbs(open-sl)) > BreakEvenTrigger) {
         if (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && sl < open) 
            trade.PositionModify(ticket, open + 10*_Point, tp);
         if (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && sl > open) 
            trade.PositionModify(ticket, open - 10*_Point, tp);
      }
   }
}

bool IsNewBar() {
   static datetime last;
   datetime curr = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last != curr) { last = curr; return true; }
   return false;
}