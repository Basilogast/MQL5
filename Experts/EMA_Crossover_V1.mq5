//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.03" 
#property strict

#include <Trade\Trade.mqh>

input group "Indicator Settings"
input int      FastMAPeriod = 9;
input int      SlowMAPeriod = 21;
input int      TrendMAPeriod = 200;

input group "Risk Management"
input double   StopLossPips = 200;
input double   TakeProfitPips = 400;
input double   LotSize      = 0.1;
input int      TrailingPips = 100;
input int      BreakEvenPips = 150;

int    FastHandle, SlowHandle, TrendHandle;
CTrade trade;

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
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // --- POSITION MANAGEMENT: Optimization Logic ---
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         ulong  ticket = PositionGetInteger(POSITION_TICKET);
         double current_sl = PositionGetDouble(POSITION_SL);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // 1. Break Even Logic
         if(current_sl < open_price && bid >= open_price + (BreakEvenPips * _Point))
         {
            trade.PositionModify(ticket, open_price + (10 * _Point), PositionGetDouble(POSITION_TP));
         }

         // 2. Trailing Stop Logic
         double new_sl = bid - (TrailingPips * _Point);
         if(new_sl > current_sl + (_Point * 10)) 
         {
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
         }
      }
   }

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

   if(PositionsTotal() < 1 && BuyCondition && TrendFilter) 
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      trade.Buy(LotSize, _Symbol, ask, ask-(StopLossPips*_Point), ask+(TakeProfitPips*_Point), "EMA Cross V1");
   }
}

bool IsNewBar()
{
   static datetime last_time=0;
   datetime lastbar_time=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE);
   if(last_time==lastbar_time) return(false);
   last_time=lastbar_time;
   return(true);
}