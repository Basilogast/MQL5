//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.05" 
#property strict

#include <Trade\Trade.mqh>

// 1. INDICATOR SETTINGS (LOCKED TO SWEET SPOT)
input group "Indicator Settings (Robust Values)"
input int      FastMAPeriod = 6;      // Hardcoded Robust Fast EMA
input int      SlowMAPeriod = 86;     // Hardcoded Robust Slow EMA
input int      TrendMAPeriod = 200;

// 2. RISK MANAGEMENT (1% RISK PER TRADE)
input group "Risk Management"
input double   RiskPercent  = 1.0;    // Risk 1% of account balance per trade
input double   StopLossPips = 200;    // Used for lot size calculation
input double   TakeProfitPips = 400;
input int      TrailingPips = 100;    // To be optimized in final phase
input int      BreakEvenPips = 150;   // To be optimized in final phase

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
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage existing trades (Trailing Stop and Break Even)
   ManageOpenPositions();

   if(!IsNewBar()) return;

   double FastEMA[], SlowEMA[], TrendEMA[];
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendEMA, true);

   if(CopyBuffer(FastHandle, 0, 0, 3, FastEMA) < 3 || 
      CopyBuffer(SlowHandle, 0, 0, 3, SlowEMA) < 3 || 
      CopyBuffer(TrendHandle, 0, 0, 3, TrendEMA) < 3) return;

   // Entry Logic
   bool BuyCondition = (FastEMA[2] < SlowEMA[2]) && (FastEMA[1] > SlowEMA[1]);
   bool TrendFilter  = (iClose(_Symbol, _Period, 1) > TrendEMA[1]);

   if(PositionsTotal() < 1 && BuyCondition && TrendFilter) 
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl_price = ask - (StopLossPips * _Point);
      double tp_price = ask + (TakeProfitPips * _Point);
      
      // Calculate Lot Size based on 1% Risk
      double lot = CalculateLotSize(StopLossPips); 
      
      trade.Buy(lot, _Symbol, ask, sl_price, tp_price, "EMA Cross Robust 6-86");
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Account Risk                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_pips)
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (RiskPercent / 100.0);
   
   // Formula: Risk Amount / (Stop Loss in Points * Tick Value)
   double lot = risk_amount / (sl_pips * 10 * tick_value); 
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   lot = NormalizeDouble(lot, 2);
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Manage Open Positions: BE and Trailing Stop                      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
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
}

//+------------------------------------------------------------------+
//| Check for New Bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar() 
{ 
   static datetime last; 
   datetime cur=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); 
   if(last==cur) return false; 
   last=cur; 
   return true; 
}