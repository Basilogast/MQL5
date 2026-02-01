//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.00"
#property strict

// --- Inputs for Optimization
input int      FastMAPeriod = 9;      // Fast EMA Period
input int      SlowMAPeriod = 21;     // Slow EMA Period
input int      TrendMAPeriod = 200;   // Trend Filter (EMA 200)
input double   StopLossPips = 200;    // SL in Points
input double   TakeProfitPips = 400;  // TP in Points
input double   LotSize      = 0.1;    // Fixed Lot Size

// --- Global Variables
int FastHandle, SlowHandle, TrendHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Link the indicators to "Handles" so the script can read them
   FastHandle  = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle  = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE || TrendHandle == INVALID_HANDLE)
   {
      Print("Error: Failed to create indicator handles.");
      return(INIT_FAILED); // This shuts down the EA safely
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. New Bar Check (The Filter)
   if(!IsNewBar()) return;

   // 2. Data Buffers
   double FastEMA[], SlowEMA[], TrendEMA[];
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendEMA, true);

   // 3. Copy indicator values to buffers
   if(CopyBuffer(FastHandle, 0, 0, 3, FastEMA) < 3) return;
   if(CopyBuffer(SlowHandle, 0, 0, 3, SlowEMA) < 3) return;
   if(CopyBuffer(TrendHandle, 0, 0, 3, TrendEMA) < 3) return;

   // 4. LOGIC: Identify the Crossover on the PREVIOUSly closed candles
   // Current Candle = Index 0 (Ignore)
   // Last Closed Candle = Index 1
   // Candle before last = Index 2
   
   bool BuyCondition = (FastEMA[2] < SlowEMA[2]) && (FastEMA[1] > SlowEMA[1]);
   bool TrendFilter  = (iClose(_Symbol, _Period, 1) > TrendEMA[1]);

   // 5. Execution
   if(BuyCondition && TrendFilter)
   {
      Print("BUY SIGNAL: Fast EMA crossed above Slow EMA + Trend is Bullish");
      // Execution Code (Step 4 will cover how to send the order safely)
   }
}

//+------------------------------------------------------------------+
//| Helper: New Bar Detection                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime last_time=0;
   datetime lastbar_time=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE);
   if(last_time==lastbar_time) return(false);
   last_time=lastbar_time;
   return(true);
}