//+------------------------------------------------------------------+
//|       NCI_Pivot_Pro_Swing_V15.5_Robust_Management.mq5            |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "15.50"
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
input bool Trade_R1 = true; 
input bool Trade_R2 = true; 

//--- 3. ENTRY LOGIC
input group "3. Entry Logic"
input double MagnetPips     = 2.0;   // Tolerance for "Touching" the line
input bool UseVolumeBurst   = true;  
input double VolumeMultiplier = 1.2; 
input double MinRiskReward  = 0.6;   
input double GreenBufferPips = 0.0;  

//--- 4. PROTECTION
input group "4. Crash/Rocket Protection"
input bool AvoidViolentMoves = true; 
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

//--- 7. SPLIT RISK MANAGEMENT
input group "7. Risk Profiles"
input double RiskPercent_Standard = 1.0; 
input double RiskPercent_Burst    = 0.5; 

//--- 8. VISUAL SETTINGS
input bool ShowLines = true;      
input color Color_R2 = clrDarkGreen;
input color Color_R1 = clrGreen;  
input color Color_P  = clrBlue;   
input color Color_S1 = clrRed;    
input color Color_S2 = clrDarkRed;

int TrendHandle;
int ATRHandle; 
CTrade trade;

// Global Variables (For Display Only)
double R1, R2, R3, P, S1, S2, S3; 
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
   CalculateDisplayPivots(); // Updated function name to clarify purpose
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

   //--- TREND DIRECTION
   bool IsUptrend = true;
   bool IsDowntrend = true;
   if (UseTrendFilter) 
   {
      IsUptrend   = (Close[1] > TrendMA[1]);
      IsDowntrend = (Close[1] < TrendMA[1]);
   }

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
   double currentBid   = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
   double magnet = MagnetPips * 10 * _Point; 

   bool Signal_S1 = false, Signal_S2 = false;
   bool Signal_R1 = false, Signal_R2 = false;
   string triggerType = ""; 

   //--- 1. STANDARD ENTRY
   if (IsNewBar())
   {
      // BUY LOGIC (S1)
      bool S1_Touch = (Low[1] <= S1 + magnet);
      bool S1_Green = (Close[1] > Open[1]);
      bool S1_Above = (Close[1] > S1);
      if (S1_Touch && S1_Green && S1_Above) { Signal_S1 = true; triggerType = "Candle Close"; }
      
      bool S1_PrevTouch = (Low[2] <= S1 + magnet);
      if (!Signal_S1 && S1_PrevTouch && S1_Green && S1_Above) { Signal_S1 = true; triggerType = "Candle Close (2-Bar)"; }
      
      if (S1_Touch && !Signal_S1) PrintDebug("S1", IsUptrend, S1_Green, S1_Above, "BUY");

      // BUY LOGIC (S2)
      bool S2_Touch = (Low[1] <= S2 + magnet);
      bool S2_Green = (Close[1] > Open[1]);
      bool S2_Above = (Close[1] > S2);
      if (S2_Touch && S2_Green && S2_Above) { Signal_S2 = true; triggerType = "Candle Close"; }
      
      bool S2_PrevTouch = (Low[2] <= S2 + magnet);
      if (!Signal_S2 && S2_PrevTouch && S2_Green && S2_Above) { Signal_S2 = true; triggerType = "Candle Close (2-Bar)"; }

      // SELL LOGIC (R1)
      bool R1_Touch = (High[1] >= R1 - magnet);
      bool R1_Red   = (Close[1] < Open[1]);
      bool R1_Below = (Close[1] < R1);
      if (R1_Touch && R1_Red && R1_Below) { Signal_R1 = true; triggerType = "Candle Close"; }
      
      bool R1_PrevTouch = (High[2] >= R1 - magnet);
      if (!Signal_R1 && R1_PrevTouch && R1_Red && R1_Below) { Signal_R1 = true; triggerType = "Candle Close (2-Bar)"; }

      if (R1_Touch && !Signal_R1) PrintDebug("R1", IsDowntrend, R1_Red, R1_Below, "SELL");

      // SELL LOGIC (R2)
      bool R2_Touch = (High[1] >= R2 - magnet);
      bool R2_Red   = (Close[1] < Open[1]);
      bool R2_Below = (Close[1] < R2);
      if (R2_Touch && R2_Red && R2_Below) { Signal_R2 = true; triggerType = "Candle Close"; }
      
      bool R2_PrevTouch = (High[2] >= R2 - magnet);
      if (!Signal_R2 && R2_PrevTouch && R2_Red && R2_Below) { Signal_R2 = true; triggerType = "Candle Close (2-Bar)"; }
   }

   //--- 2. VOLUME BURST ENTRY
   if (UseVolumeBurst && !Signal_S1 && !Signal_S2 && !Signal_R1 && !Signal_R2)
   {
      if (IsHighVolume())
      {
         // BUY BURST
         double solidGreen = Open[0] + (GreenBufferPips * 10 * _Point);
         if (currentPrice > S1 && Open[0] < S1 + magnet && currentPrice > solidGreen) { Signal_S1 = true; triggerType = "Volume Burst"; }
         if (currentPrice > S2 && Open[0] < S2 + magnet && currentPrice > solidGreen) { Signal_S2 = true; triggerType = "Volume Burst"; }

         // SELL BURST
         double solidRed = Open[0] - (GreenBufferPips * 10 * _Point);
         if (currentBid < R1 && Open[0] > R1 - magnet && currentBid < solidRed) { Signal_R1 = true; triggerType = "Volume Burst"; }
         if (currentBid < R2 && Open[0] > R2 - magnet && currentBid < solidRed) { Signal_R2 = true; triggerType = "Volume Burst"; }
      }
   }
   
   //--- 3. PROTECTION
   if (AvoidViolentMoves)
   {
      double candleSize = High[1] - Low[1];
      double averageSize = ATR[1];
      
      if ((Signal_S1 || Signal_S2) && Close[1] < Open[1] && candleSize > (averageSize * MaxCandleSizeATR)) 
      {
         Print("DEBUG SKIP: Valid Buy Signal, but SKIPPED due to Violent Drop (Falling Knife).");
         return;
      }
      if ((Signal_R1 || Signal_R2) && Close[1] > Open[1] && candleSize > (averageSize * MaxCandleSizeATR))
      {
         Print("DEBUG SKIP: Valid Sell Signal, but SKIPPED due to Violent Rally (Rocket).");
         return;
      }
   }

   // EXECUTION
   if (PositionsTotal() < 1 && IsUptrend)
   {
      if (Trade_S1 && Signal_S1) ProcessEntry(ORDER_TYPE_BUY, S1, S2, R1, P, triggerType, "S1");
      else if (Trade_S2 && Signal_S2) ProcessEntry(ORDER_TYPE_BUY, S2, S3, P, P, triggerType, "S2");
   }
   else if (PositionsTotal() < 1 && !IsUptrend && (Signal_S1 || Signal_S2))
   {
      Print("DEBUG SKIP: Buy blocked by GLOBAL TREND FILTER (Close < EMA 200).");
   }

   if (PositionsTotal() < 1 && IsDowntrend)
   {
      if (Trade_R1 && Signal_R1) ProcessEntry(ORDER_TYPE_SELL, R1, R2, S1, P, triggerType, "R1");
      else if (Trade_R2 && Signal_R2) ProcessEntry(ORDER_TYPE_SELL, R2, R3, P, P, triggerType, "R2");
   }
   else if (PositionsTotal() < 1 && !IsDowntrend && (Signal_R1 || Signal_R2))
   {
      Print("DEBUG SKIP: Sell blocked by GLOBAL TREND FILTER (Close > EMA 200).");
   }
}

//--- NEW ROBUST MANAGEMENT (NO COMMENTS NEEDED)
void ManageOpenPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double sl = PositionGetDouble(POSITION_SL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME); // Get Entry Time
         double vol = PositionGetDouble(POSITION_VOLUME);
         long type = PositionGetInteger(POSITION_TYPE);
         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         // 1. RECONSTRUCT PIVOTS FROM HISTORY (Based on Entry Time)
         double Rec_P, Rec_S1, Rec_S2, Rec_R1, Rec_R2;
         if (!GetPivotsForTime(openTime, Rec_P, Rec_S1, Rec_S2, Rec_R1, Rec_R2)) continue;

         // 2. IDENTIFY TRADE TYPE (By Proximity)
         string tradeID = IdentifyTradeType(type, openPrice, Rec_S1, Rec_S2, Rec_R1, Rec_R2);
         
         double TargetLevel = 0;
         double PivotLevel  = Rec_P;
         
         // 3. SET TARGETS
         if (tradeID == "S1") TargetLevel = Rec_R1;
         if (tradeID == "S2") TargetLevel = Rec_P;
         if (tradeID == "R1") TargetLevel = Rec_S1;
         if (tradeID == "R2") TargetLevel = Rec_P;
         
         if (TargetLevel == 0) continue; // Safety check

         // 4. APPLY LOGIC
         double dist = MathAbs(TargetLevel - PivotLevel);
         bool hitPivot = false;
         bool hit50 = false;
         
         if (type == POSITION_TYPE_BUY)
         {
             // Scale Out Trigger: Price > Pivot
             if (currentBid > PivotLevel) hitPivot = true;
             // Trail Trigger: Price > 50% way to Target
             if (currentBid > (PivotLevel + dist * 0.5)) hit50 = true;
             
             if (hitPivot && !HasPartiallyClosed(ticket)) DoScaleOut(ticket, vol);
             if (hit50)
             {
                 // Move Stop UP to Pivot (or Hard Floor)
                 double new_sl = PivotLevel - (HardFloorBuffer * _Point);
                 if (new_sl > sl + _Point) trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
             }
         }
         else if (type == POSITION_TYPE_SELL)
         {
             // Scale Out Trigger: Price < Pivot
             if (currentAsk < PivotLevel) hitPivot = true;
             // Trail Trigger: Price < 50% way to Target
             if (currentAsk < (PivotLevel - dist * 0.5)) hit50 = true;
             
             if (hitPivot && !HasPartiallyClosed(ticket)) DoScaleOut(ticket, vol);
             if (hit50)
             {
                 // Move Stop DOWN to Pivot (or Hard Floor)
                 double new_sl = PivotLevel + (HardFloorBuffer * _Point);
                 if (new_sl < sl - _Point || sl == 0) trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
             }
         }
      }
   }
}

//--- NEW HELPER: RECONSTRUCT PIVOTS
bool GetPivotsForTime(datetime entryTime, double &p, double &s1, double &s2, double &r1, double &r2)
{
   // Find the Day Index for the entry time
   int shift = iBarShift(_Symbol, PERIOD_D1, entryTime);
   if (shift < 0) return false;
   
   // Pivots are calculated from the PREVIOUS day relative to entry
   // So we need High/Low/Close of (shift + 1)
   double h = iHigh(_Symbol, PERIOD_D1, shift + 1);
   double l = iLow(_Symbol, PERIOD_D1, shift + 1);
   double c = iClose(_Symbol, PERIOD_D1, shift + 1);
   
   if (h == 0 || l == 0 || c == 0) return false;
   
   p = (h + l + c) / 3.0;
   r1 = (2 * p) - l;
   s1 = (2 * p) - h;
   r2 = p + (h - l);
   s2 = p - (h - l);
   return true;
}

//--- NEW HELPER: IDENTIFY TRADE TYPE
string IdentifyTradeType(long type, double entry, double s1, double s2, double r1, double r2)
{
   if (type == POSITION_TYPE_BUY)
   {
      double distS1 = MathAbs(entry - s1);
      double distS2 = MathAbs(entry - s2);
      if (distS1 < distS2) return "S1";
      else return "S2";
   }
   else // SELL
   {
      double distR1 = MathAbs(entry - r1);
      double distR2 = MathAbs(entry - r2);
      if (distR1 < distR2) return "R1";
      else return "R2";
   }
}

//--- ENTRY PROCESSING
void ProcessEntry(ENUM_ORDER_TYPE type, double level, double next_level, double target, double pivot, string trigger, string label)
{
   double currentPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double activeRisk = (StringFind(trigger, "Volume Burst") >= 0) ? RiskPercent_Burst : RiskPercent_Standard;
   
   double dist_pips = MathAbs(level - next_level) / _Point / 10.0;
   double execution_sl, calculation_sl;

   if (type == ORDER_TYPE_BUY)
   {
      calculation_sl = next_level - (SafetyBuffer * _Point); 
      if (dist_pips > CompressionThreshold) execution_sl = level - ((level - next_level) / 2.0); 
      else execution_sl = calculation_sl;
   }
   else 
   {
      calculation_sl = next_level + (SafetyBuffer * _Point); 
      if (dist_pips > CompressionThreshold) execution_sl = level + ((next_level - level) / 2.0); 
      else execution_sl = calculation_sl;
   }

   double tp = UseStructuralTarget ? target : (type == ORDER_TYPE_BUY ? currentPrice + BackupTP_Pips*_Point : currentPrice - BackupTP_Pips*_Point);

   double risk = MathAbs(currentPrice - execution_sl);
   double reward = MathAbs(tp - currentPrice);
   if (risk > 0 && (reward/risk) < MinRiskReward) return;

   // Comment is less critical now, but we keep it for visual reference
   string clean_comment = label + "_Entry"; 
   Print("OPENING ", label, " ", EnumToString(type), ". Type: ", trigger);
   OpenDynamicTrade(type, clean_comment, currentPrice, calculation_sl, execution_sl, tp, activeRisk);
}

//--- HELPERS
void DoScaleOut(ulong ticket, double vol)
{
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if (vol > min_vol)
   {
      double half = MathFloor((vol/2.0) / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)) * SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if (half >= min_vol) {
         trade.PositionClosePartial(ticket, half);
         Print("Hit Pivot! Scaled Out 50%.");
      }
   }
}

bool HasPartiallyClosed(ulong position_ticket)
{
   if(HistorySelectByPosition(position_ticket))
   {
      for(int i=0; i<HistoryDealsTotal(); i++)
         if(HistoryDealGetInteger(HistoryDealGetTicket(i), DEAL_ENTRY) == DEAL_ENTRY_OUT) return true;
   }
   return false;
}

bool IsHighVolume()
{
   long volumes[];
   ArraySetAsSeries(volumes, true);
   if (CopyTickVolume(_Symbol, _Period, 0, 21, volumes) < 21) return false;
   double total = 0;
   for(int i=1; i<=20; i++) total += (double)volumes[i]; 
   double average = total / 20.0;
   return ((double)volumes[0] > (average * VolumeMultiplier));
}

void CalculateDisplayPivots()
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
      R2 = P + (high - low); 
      R3 = high + 2 * (P - low);
      
      if (ShowLines)
      {
         datetime end = currentDay + 86400; 
         DrawSegment("R2_"+TimeToString(currentDay), currentDay, end, R2, Color_R2, STYLE_DASH);
         DrawSegment("R1_"+TimeToString(currentDay), currentDay, end, R1, Color_R1, STYLE_SOLID);
         DrawSegment("P_"+TimeToString(currentDay), currentDay, end, P, Color_P, STYLE_SOLID);
         DrawSegment("S1_"+TimeToString(currentDay), currentDay, end, S1, Color_S1, STYLE_SOLID);
         DrawSegment("S2_"+TimeToString(currentDay), currentDay, end, S2, Color_S2, STYLE_DASH);
      }
   }
}

void DrawSegment(string name, datetime t1, datetime t2, double price, color col, ENUM_LINE_STYLE style)
{
   if (ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); 
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void OpenDynamicTrade(ENUM_ORDER_TYPE type, string comment, double entry, double calc_sl, double real_sl, double tp, double risk_pct)
{
   double sl_dist = MathAbs(entry - calc_sl);
   if (sl_dist <= 0) return;

   double risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * (risk_pct / 100.0);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot = risk_money / ((sl_dist / tick_sz) * tick_val);
   
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(min, MathMin(max, MathFloor(lot/step)*step));

   if (type == ORDER_TYPE_BUY) trade.Buy(lot, _Symbol, entry, real_sl, tp, comment);
   else trade.Sell(lot, _Symbol, entry, real_sl, tp, comment);
}

void PrintDebug(string level, bool trendOk, bool colorOk, bool closeOk, string type)
{
   if(!trendOk) Print("DEBUG SKIP ", level, ": Touched Line, but Trend Filter Blocked.");
   else if(!colorOk) Print("DEBUG SKIP ", level, ": Touched Line, but Candle Color Wrong.");
   else if(!closeOk) Print("DEBUG SKIP ", level, ": Touched Line, but Failed to close past line.");
}

bool IsNewBar()
{
   static datetime last;
   datetime curr = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last == curr) return false;
   last = curr;
   return true;
}