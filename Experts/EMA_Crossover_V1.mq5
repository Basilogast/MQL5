//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.02" 
#property strict

// 1. INCLUDE THE TRADE CLASS
#include <Trade\Trade.mqh>

// 2. INPUT PARAMETERS (Optimization Ready)
input group "Indicator Settings"
input int      FastMAPeriod = 9;
input int      SlowMAPeriod = 21;
input int      TrendMAPeriod = 200;

input group "Risk Management"
input double   StopLossPips = 200;
input double   TakeProfitPips = 400;
input double   LotSize      = 0.1;
input int      TrailingPips = 100; // New: Distance to trail in points

// 3. GLOBAL VARIABLES
int    FastHandle, SlowHandle, TrendHandle;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(123456);

   FastHandle  = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle  = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE || TrendHandle == INVALID_HANDLE)
   {
      Print("Error initializing handles");
      return(INIT_FAILED);
   }

   Print("EA Initialized Successfully: ", _Symbol, " ", _Period);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- MINIMAL CHANGE: Trailing Stop Logic (Every Tick) ---
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         ulong  ticket = PositionGetInteger(POSITION_TICKET);
         double current_sl = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double new_sl = bid - (TrailingPips * _Point);

         // Only modify if new_sl is higher than current_sl (Locking in profit)
         if(new_sl > current_sl + (_Point * 10)) 
         {
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
         }
      }
   }
   // --- End of Trailing Stop ---

   if(!IsNewBar()) return;

   double FastEMA[], SlowEMA[], TrendEMA[];
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendEMA, true);

   if(CopyBuffer(FastHandle, 0, 0, 3, FastEMA) < 3) return;
   if(CopyBuffer(SlowHandle, 0, 0, 3, SlowEMA) < 3) return;
   if(CopyBuffer(TrendHandle, 0, 0, 3, TrendEMA) < 3) return;

   bool BuyCondition = (FastEMA[2] < SlowEMA[2]) && (FastEMA[1] > SlowEMA[1]);
   bool TrendFilter  = (iClose(_Symbol, _Period, 1) > TrendEMA[1]);
   
   Print("New Bar - Checking Signal: Fast[1]=", FastEMA[1], " Slow[1]=", SlowEMA[1], " Close[1]=", iClose(_Symbol, _Period, 1));

   if(PositionsTotal() < 1) 
   {
      if(BuyCondition)
      {
         Print(">> Strategy Trigger: EMA Crossover detected.");
         
         if(TrendFilter)
         {
            Print(">> Trend Filter Passed: Price is above EMA 200. Executing Buy...");
            
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl  = ask - (StopLossPips * _Point);
            double tp  = ask + (TakeProfitPips * _Point);

            if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "EMA Cross V1"))
               Print(">> SUCCESS: Buy order placed at ", ask);
            else
               Print(">> ERROR: Order failed. Code: ", GetLastError());
         }
         else 
         {
            Print(">> BLOCK: Crossover detected but Trend is Bearish (Price < EMA 200).");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Check for New Bar                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime last_time=0;
   datetime lastbar_time=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE);
   if(last_time==lastbar_time) return(false);
   last_time=lastbar_time;
   return(true);
}