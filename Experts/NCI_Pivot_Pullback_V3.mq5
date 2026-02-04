//+------------------------------------------------------------------+
//|             NCI_Pivot_Pro_Swing_V11.0_Knife_Protection.mq5       |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "11.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input bool UseTrendFilter   = true;  
input int TrendEMA_Period   = 200;

//--- 2. PIVOT SETTINGS
input group "2. Pivot Settings"
input bool Trade_S1 = true;
input bool Trade_S2 = true;

//--- 3. ENTRY LOGIC
input group "3. Entry Logic"
input bool UseVolumeBurst   = true;  
input double VolumeMultiplier = 1.2; 
input double MinRiskReward  = 0.6;   

//--- 4. KNIFE PROTECTION (NEW)
input group "4. Crash Protection"
input bool AvoidFallingKnife = true; // Skip if drop is too violent?
input double MaxCandleSizeATR = 2.0; // If drop candle is > 2x ATR, don't buy.

//--- 5. EXIT SETTINGS
input group "5. Exit Settings"
input bool UseStructuralTarget = true; 
input double HardFloorBuffer   = 50;   

//--- 6. RISK MANAGEMENT
input group "6. Structural Risk"
input double RiskPercent    = 1.0;   
input double SafetyBuffer   = 50;    
input double BackupTP_Pips  = 300;   

//--- 7. VISUAL SETTINGS
input bool ShowLines = true;      
input color Color_R1 = clrGreen;  
input color Color_P  = clrBlue;   
input color Color_S1 = clrRed;    
input color Color_S2 = clrDarkRed;

int TrendHandle;
int ATRHandle; // NEW
CTrade trade;

// Global Variables
double R1, P, S1, S2, S3; 
datetime LastDay = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(555444);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   ATRHandle   = iATR(_Symbol, _Period, 14); // Standard ATR
   
   if (TrendHandle == INVALID_HANDLE || ATRHandle == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   CalculateDailyPivots();
   ManageOpenPositions(); 

   if (!IsNewBar() && !UseVolumeBurst) return; 

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

   //--- TREND
   bool IsUptrend = true;
   if (UseTrendFilter) IsUptrend = (Close[1] > TrendMA[1]);

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool Signal_S1 = false;
   bool Signal_S2 = false;

   //--- STANDARD ENTRY
   if (IsNewBar())
   {
      if (Low[1] <= S1 && Close[1] > S1 && Close[1] > Open[1]) Signal_S1 = true; 
      if (Low[1] <= S2 && Close[1] > S2 && Close[1] > Open[1]) Signal_S2 = true;
   }

   //--- VOLUME BURST ENTRY
   if (UseVolumeBurst && !Signal_S1 && !Signal_S2)
   {
      if (IsHighVolume())
      {
         if (currentPrice > S1 && Open[0] < S1 && currentPrice > Open[0]) Signal_S1 = true;
         if (currentPrice > S2 && Open[0] < S2 && currentPrice > Open[0]) Signal_S2 = true;
      }
   }
   
   //--- NEW: KNIFE PROTECTION CHECK
   // We look at Candle [1] (the completed one) or Candle [0] (current).
   // If the body is HUGE, we assume panic.
   if (AvoidFallingKnife)
   {
      double candleSize = High[1] - Low[1];
      double averageSize = ATR[1];
      
      // If the candle before our entry was a monster drop
      if (Close[1] < Open[1] && candleSize > (averageSize * MaxCandleSizeATR))
      {
         Print("Skipped Trade: Falling Knife Detected! Candle size: ", candleSize, " vs ATR: ", averageSize);
         return; 
      }
   }

   //--- EXECUTION
   if (PositionsTotal() < 1 && IsUptrend && Trade_S1 && Signal_S1)
   {
      double sl = S2 - (SafetyBuffer * _Point); 
      double tp = UseStructuralTarget ? R1 : (currentPrice + BackupTP_Pips * _Point);
      
      double risk   = currentPrice - sl;
      double reward = tp - currentPrice;
      double rr_ratio = (risk > 0) ? reward/risk : 0;

      if (risk > 0 && rr_ratio < MinRiskReward) return; 
      
      string clean_comment = "S1_" + DoubleToString(P, 5); 
      OpenDynamicTrade(clean_comment, currentPrice, sl, tp);
   }
   else if (PositionsTotal() < 1 && IsUptrend && Trade_S2 && Signal_S2)
   {
      double sl = S3 - (SafetyBuffer * _Point); 
      double tp = UseStructuralTarget ? P : (currentPrice + BackupTP_Pips * _Point);
      
      double risk   = currentPrice - sl;
      double reward = tp - currentPrice;
      double rr_ratio = (risk > 0) ? reward/risk : 0;

      if (risk > 0 && rr_ratio < MinRiskReward) return; 
      
      string clean_comment = "S2_" + DoubleToString(P, 5);
      OpenDynamicTrade(clean_comment, currentPrice, sl, tp);
   }
}

//--- FIXED MANAGEMENT LOGIC
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

         if (StringFind(comment, "S1_") >= 0)
         {
            string p_string = StringSubstr(comment, 3, 7); 
            double Original_P = StringToDouble(p_string);
            
            if (Original_P > 0)
            {
               if (bid > Original_P)
               {
                  double new_floor = Original_P - (HardFloorBuffer * _Point); 
                  if (new_floor > sl + (_Point * 10))
                  {
                     trade.PositionModify(ticket, new_floor, PositionGetDouble(POSITION_TP));
                  }
               }
            }
         }
      }
   }
}

//--- HELPERS ---
bool IsHighVolume()
{
   long volumes[];
   ArraySetAsSeries(volumes, true);
   if (CopyTickVolume(_Symbol, _Period, 0, 21, volumes) < 21) return false;
   double total = 0;
   for(int i=1; i<=20; i++) total += (double)volumes[i]; 
   double average = total / 20.0;
   if ((double)volumes[0] > (average * VolumeMultiplier)) return true;
   return false;
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