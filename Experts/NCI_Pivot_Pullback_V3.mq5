//+------------------------------------------------------------------+
//|                     NCI_Pivot_Pro_Swing_V8.0_Volume.mq5          |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "8.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input int TrendEMA_Period = 200;

//--- 2. PIVOT SETTINGS
input group "2. Pivot Settings"
input bool Trade_S1 = true;
input bool Trade_S2 = true;

//--- 3. VOLUME BURST (THE NEW EARLY ENTRY)
input group "3. Early Entry Logic"
input bool UseVolumeBurst   = true;  // Enter mid-candle if volume is high?
input double VolumeMultiplier = 1.5; // Current Vol must be 1.5x average to trigger
input double MaxEntryDistPips = 25;  // Safety: Don't enter if we missed it by > 25 pips

//--- 4. EXIT SETTINGS
input group "4. Exit Settings"
input bool UseStructuralTarget = true; 
input double HardFloorBuffer   = 50;   

//--- 5. RISK MANAGEMENT
input group "5. Structural Risk"
input double RiskPercent    = 1.0;   
input double SafetyBuffer   = 100;   
input double BackupTP_Pips  = 300;   

//--- 6. VISUAL SETTINGS
input bool ShowLines = true;      
input color Color_R1 = clrGreen;  
input color Color_P  = clrBlue;   
input color Color_S1 = clrRed;    
input color Color_S2 = clrDarkRed;

int TrendHandle;
CTrade trade;

// Global Variables
double R1, P, S1, S2, S3; 
datetime LastDay = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(555444);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   return (TrendHandle == INVALID_HANDLE) ? INIT_FAILED : INIT_SUCCEEDED;
}

void OnTick()
{
   CalculateDailyPivots();
   ManageOpenPositions(); 

   if (!IsNewBar() && !UseVolumeBurst) return; // If not using burst, only check on new bar

   //--- DATA FETCHING
   double TrendMA[], Close[], Open[], Low[];
   ArraySetAsSeries(TrendMA, true); 
   ArraySetAsSeries(Close, true);  
   ArraySetAsSeries(Open, true);
   ArraySetAsSeries(Low, true);

   if (CopyBuffer(TrendHandle, 0, 0, 3, TrendMA) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, Close) < 3 ||
       CopyOpen(_Symbol, _Period, 0, 3, Open) < 3 ||
       CopyLow(_Symbol, _Period, 0, 3, Low) < 3)
      return;

   //--- BASIC LOGIC
   bool IsUptrend = (Close[1] > TrendMA[1]);
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   //--- CHECK SIGNALS
   bool Signal_S1 = false;
   bool Signal_S2 = false;
   string triggerType = "";

   // 1. STANDARD ENTRY (Completed Candle)
   if (IsNewBar())
   {
      if (Low[1] <= S1 && Close[1] > S1 && Close[1] > Open[1]) 
      {
         Signal_S1 = true; 
         triggerType = "Candle Close";
      }
      if (Low[1] <= S2 && Close[1] > S2 && Close[1] > Open[1]) 
      {
         Signal_S2 = true;
         triggerType = "Candle Close";
      }
   }

   // 2. VOLUME BURST ENTRY (Mid-Candle)
   // We check this on EVERY TICK, not just New Bar
   if (UseVolumeBurst && !Signal_S1 && !Signal_S2)
   {
      if (IsHighVolume())
      {
         // Logic: Price is above line, Current Candle is Green, Volume is Pumping
         if (currentPrice > S1 && Open[0] < S1 && currentPrice > Open[0])
         {
            Signal_S1 = true;
            triggerType = "Volume Burst!";
         }
         if (currentPrice > S2 && Open[0] < S2 && currentPrice > Open[0])
         {
            Signal_S2 = true;
            triggerType = "Volume Burst!";
         }
      }
   }

   //--- EXECUTION (With Max Distance Filter)
   double dist_S1 = (currentPrice - S1) / _Point;
   double dist_S2 = (currentPrice - S2) / _Point;

   if (PositionsTotal() < 1 && IsUptrend && Trade_S1 && Signal_S1)
   {
      if (dist_S1 > (MaxEntryDistPips * 10)) return; // Too late
      
      double sl = S2 - (SafetyBuffer * _Point); 
      double tp = UseStructuralTarget ? R1 : (currentPrice + BackupTP_Pips * _Point);
      OpenDynamicTrade("S1 Buy [" + triggerType + "]", currentPrice, sl, tp);
   }
   else if (PositionsTotal() < 1 && IsUptrend && Trade_S2 && Signal_S2)
   {
      if (dist_S2 > (MaxEntryDistPips * 10)) return; // Too late

      double sl = S3 - (SafetyBuffer * _Point); 
      double tp = UseStructuralTarget ? P : (currentPrice + BackupTP_Pips * _Point);
      OpenDynamicTrade("S2 Buy [" + triggerType + "]", currentPrice, sl, tp);
   }
}

//--- NEW: CHECK FOR HIGH VOLUME
bool IsHighVolume()
{
   long volumes[];
   ArraySetAsSeries(volumes, true);
   
   // Get last 21 volume bars (0 is current)
   if (CopyTickVolume(_Symbol, _Period, 0, 21, volumes) < 21) return false;
   
   double total = 0;
   for(int i=1; i<=20; i++) total += (double)volumes[i];
   double average = total / 20.0;
   
   // Is CURRENT volume (0) already significantly higher than average?
   if (volumes[0] > (average * VolumeMultiplier)) return true;
   
   return false;
}

// ... [Rest of Helper Functions: ManageOpenPositions, CalculateDailyPivots, OpenDynamicTrade, etc.] ...
// (Copy them from V7.1)

void ManageOpenPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double sl = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         string comment = PositionGetString(POSITION_COMMENT);

         if (StringFind(comment, "S1 Buy") >= 0)
         {
            if (bid > P)
            {
               double new_floor = P - (HardFloorBuffer * _Point); 
               if (new_floor > sl + (_Point * 10))
               {
                  trade.PositionModify(ticket, new_floor, PositionGetDouble(POSITION_TP));
               }
            }
         }
      }
   }
}

void CalculateDailyPivots()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if (LastDay != currentDay)
   {
      LastDay = currentDay;
      double high = iHigh(_Symbol, PERIOD_D1, 1);
      double low  = iLow(_Symbol, PERIOD_D1, 1);
      double close= iClose(_Symbol, PERIOD_D1, 1);
      
      P = (high + low + close) / 3.0;
      S1 = (2 * P) - high;
      S2 = P - (high - low);
      S3 = low - 2 * (high - P); 
      R1 = (2 * P) - low; 
      
      if (ShowLines)
      {
         datetime endOfDay = currentDay + 86400; 
         DrawSegment("R1_" + TimeToString(currentDay), currentDay, endOfDay, R1, Color_R1, STYLE_SOLID);
         DrawSegment("P_" + TimeToString(currentDay), currentDay, endOfDay, P, Color_P, STYLE_SOLID);
         DrawSegment("S1_" + TimeToString(currentDay), currentDay, endOfDay, S1, Color_S1, STYLE_SOLID);
         DrawSegment("S2_" + TimeToString(currentDay), currentDay, endOfDay, S2, Color_S2, STYLE_DASH);
      }
   }
}

void DrawSegment(string name, datetime t1, datetime t2, double price, color col, ENUM_LINE_STYLE style)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); 
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void OpenDynamicTrade(string comment, double entry, double sl, double tp)
{
   double sl_distance = entry - sl;
   if (sl_distance <= 0) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (RiskPercent / 100.0);
   
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot_size = risk_money / ((sl_distance / tick_size) * tick_value);
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathFloor(lot_size / step) * step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   trade.Buy(lot_size, _Symbol, entry, sl, tp, comment);
}

bool IsNewBar()
{
   static datetime last_time;
   datetime curr_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last_time == curr_time) return false;
   last_time = curr_time;
   return true;
}