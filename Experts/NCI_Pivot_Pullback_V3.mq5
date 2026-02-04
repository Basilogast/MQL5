//+------------------------------------------------------------------+
//|         NCI_Pivot_Pro_Swing_V13.3_Delayed_Stop.mq5               |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "13.30"
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
input double GreenBufferPips = 0.0;  

//--- 4. PROTECTION
input group "4. Crash Protection"
input bool AvoidFallingKnife = true; 
input double MaxCandleSizeATR = 2.0; 

//--- 5. DYNAMIC STOP LOSS
input group "5. Dynamic Stop Loss"
input double CompressionThreshold = 50.0; 
input double SafetyBuffer   = 50;         

//--- 6. EXIT SETTINGS
input group "6. Exit Settings"
input bool UseStructuralTarget = true; 
input double HardFloorBuffer   = 50;   
input double BackupTP_Pips     = 300;   

//--- 7. RISK MANAGEMENT
input group "7. Structural Risk"
input double RiskPercent    = 1.0;   

//--- 8. VISUAL SETTINGS
input bool ShowLines = true;      
input color Color_R1 = clrGreen;  
input color Color_P  = clrBlue;   
input color Color_S1 = clrRed;    
input color Color_S2 = clrDarkRed;

int TrendHandle;
int ATRHandle; 
CTrade trade;

// Global Variables
double R1, P, S1, S2, S3; 
datetime LastDay = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(555444);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   ATRHandle   = iATR(_Symbol, _Period, 14); 
   
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
   string triggerType = ""; 

   //--- STANDARD ENTRY
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

   //--- VOLUME BURST ENTRY
   if (UseVolumeBurst && !Signal_S1 && !Signal_S2)
   {
      if (IsHighVolume())
      {
         double solidGreenPrice = Open[0] + (GreenBufferPips * 10 * _Point);
         if (currentPrice > S1 && Open[0] < S1 && currentPrice > solidGreenPrice)
         {
            Signal_S1 = true;
            triggerType = "Volume Burst";
         }
         if (currentPrice > S2 && Open[0] < S2 && currentPrice > solidGreenPrice)
         {
            Signal_S2 = true;
            triggerType = "Volume Burst";
         }
      }
   }
   
   //--- KNIFE PROTECTION
   if (AvoidFallingKnife)
   {
      double candleSize = High[1] - Low[1];
      double averageSize = ATR[1];
      if (Close[1] < Open[1] && candleSize > (averageSize * MaxCandleSizeATR)) return; 
   }

   //--- EXECUTION LOGIC
   if (PositionsTotal() < 1 && IsUptrend && Trade_S1 && Signal_S1)
   {
      double execution_sl;  
      double calculation_sl; 
      
      double dist_S1_S2_pips = (S1 - S2) / _Point / 10.0;

      calculation_sl = S2 - (SafetyBuffer * _Point);

      if (dist_S1_S2_pips > CompressionThreshold)
      {
          execution_sl = S1 - ((S1 - S2) / 2.0); 
          Print("High Volatility. Using Midpoint Stop (Phantom Risk).");
      }
      else
      {
          execution_sl = S2 - (SafetyBuffer * _Point);
      }

      double tp = UseStructuralTarget ? R1 : (currentPrice + BackupTP_Pips * _Point);
      double risk = currentPrice - execution_sl;
      double reward = tp - currentPrice;
      if (risk > 0 && (reward/risk) < MinRiskReward) return; 

      Print("OPENING S1 BUY. Trigger: ", triggerType, " | Price: ", currentPrice);
      
      // NEW: SAVE BOTH P AND R1 IN COMMENT FOR MANAGEMENT
      // Format: "S1_PivotPrice_TargetPrice"
      string clean_comment = "S1_" + DoubleToString(P, 5) + "_" + DoubleToString(R1, 5); 
      OpenDynamicTrade(clean_comment, currentPrice, calculation_sl, execution_sl, tp);
   }
   else if (PositionsTotal() < 1 && IsUptrend && Trade_S2 && Signal_S2)
   {
      double execution_sl;
      double calculation_sl;
      double dist_S2_S3_pips = (S2 - S3) / _Point / 10.0;

      calculation_sl = S3 - (SafetyBuffer * _Point);

      if (dist_S2_S3_pips > CompressionThreshold)
      {
          execution_sl = S2 - ((S2 - S3) / 2.0);
          Print("High Volatility. Using Midpoint Stop (Phantom Risk).");
      }
      else
      {
          execution_sl = S3 - (SafetyBuffer * _Point);
      }

      double tp = UseStructuralTarget ? P : (currentPrice + BackupTP_Pips * _Point);
      double risk = currentPrice - execution_sl;
      double reward = tp - currentPrice;
      if (risk > 0 && (reward/risk) < MinRiskReward) return; 

      Print("OPENING S2 BUY. Trigger: ", triggerType, " | Price: ", currentPrice);
      
      string clean_comment = "S2_" + DoubleToString(P, 5);
      OpenDynamicTrade(clean_comment, currentPrice, calculation_sl, execution_sl, tp);
   }
}

//--- NEW: 50% CONFIRMATION MANAGEMENT LOGIC
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

         // Only S1 Buys need the "Pass P then Trail" logic
         if (StringFind(comment, "S1_") >= 0)
         {
            // PARSE THE COMMENT: "S1_1.35000_1.35500"
            int first_sep = StringFind(comment, "_");
            int second_sep = StringFind(comment, "_", first_sep + 1);
            
            if (first_sep > 0 && second_sep > 0)
            {
               string p_string = StringSubstr(comment, first_sep + 1, second_sep - first_sep - 1);
               string r1_string = StringSubstr(comment, second_sep + 1);
               
               double Original_P = StringToDouble(p_string);
               double Original_R1 = StringToDouble(r1_string);
               
               if (Original_P > 0 && Original_R1 > 0)
               {
                  // CALCULATE 50% TRIGGER LINE
                  double distance = Original_R1 - Original_P;
                  double triggerPrice = Original_P + (distance * 0.5); // Halfway to R1
                  
                  // LOGIC: Only move SL to P if we cross the 50% mark
                  if (bid > triggerPrice)
                  {
                     double new_floor = Original_P - (HardFloorBuffer * _Point); 
                     
                     // Move SL up only if it's an improvement
                     if (new_floor > sl + (_Point * 10))
                     {
                        trade.PositionModify(ticket, new_floor, PositionGetDouble(POSITION_TP));
                        Print("Step Up! Price passed 50% to R1. Locked SL at Pivot.");
                     }
                  }
               }
            }
         }
      }
   }
}

//--- HELPERS
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

void OpenDynamicTrade(string comment, double entry, double calc_sl, double real_sl, double tp)
{
   double sl_distance_for_math = entry - calc_sl;
   if (sl_distance_for_math <= 0) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (RiskPercent / 100.0);
   
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lot_size = risk_money / ((sl_distance_for_math / tick_size) * tick_value);
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathFloor(lot_size / step) * step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   trade.Buy(lot_size, _Symbol, entry, real_sl, tp, comment);
}

bool IsNewBar()
{
   static datetime last_time;
   datetime curr_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last_time == curr_time) return false;
   last_time = curr_time;
   return true;
}