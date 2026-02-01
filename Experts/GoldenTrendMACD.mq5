//+------------------------------------------------------------------+
//|                                              GoldenTrendMACD.mq5 |
//|                                Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.01" // Updated version
//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Expert\Expert.mqh>
//--- available signals
#include <Expert\Signal\SignalMACD.mqh>
#include <Expert\Signal\SignalMA.mqh> // <--- NEW: Added MA Signal
//--- available trailing
#include <Expert\Trailing\TrailingNone.mqh>
//--- available money management
#include <Expert\Money\MoneyFixedLot.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
//--- inputs for expert
input string             Expert_Title             ="GoldenTrendMACD"; // Document name
ulong                    Expert_MagicNumber       =2144060332;        //
bool                     Expert_EveryTick         =false;             //
//--- inputs for main signal
input int                Signal_ThresholdOpen     =10;                // Signal threshold value to open [0...100]
input int                Signal_ThresholdClose    =10;                // Signal threshold value to close [0...100]
input double             Signal_PriceLevel        =0.0;               // Price level to execute a deal
input double             Signal_StopLevel         =400;              // Stop Loss level (in points)
input double             Signal_TakeLevel         =800;              // Take Profit level (in points)
input int                Signal_Expiration        =4;                 // Expiration of pending orders (in bars)

//--- Inputs for MACD (The Entry Trigger)
input int                Signal_MACD_PeriodFast   =12;                // MACD: Period of fast EMA
input int                Signal_MACD_PeriodSlow   =24;                // MACD: Period of slow EMA
input int                Signal_MACD_PeriodSignal =9;                 // MACD: Period of averaging of difference
input ENUM_APPLIED_PRICE Signal_MACD_Applied      =PRICE_CLOSE;       // MACD: Prices series
input double             Signal_MACD_Weight       =1.0;               // MACD: Weight [0...1.0]

//--- Inputs for Moving Average (The Trend Filter) <--- NEW SECTION
input int                Signal_MA_Period         =200;               // MA: Period (Trend Filter)
input int                Signal_MA_Shift          =0;                 // MA: Shift
input ENUM_MA_METHOD     Signal_MA_Method         =MODE_EMA;          // MA: Method (EMA is best for trend)
input ENUM_APPLIED_PRICE Signal_MA_Applied        =PRICE_CLOSE;       // MA: Applied Price
input double             Signal_MA_Weight         =1.0;               // MA: Weight (Keep at 1.0 to balance MACD)

//--- inputs for money
input double             Money_FixLot_Percent     =10.0;              // Percent
input double             Money_FixLot_Lots        =0.1;               // Fixed volume

//+------------------------------------------------------------------+
//| DEBUG VARIABLES                                                  |
//+------------------------------------------------------------------+
int debug_macd_handle = INVALID_HANDLE; 
int debug_ema_handle  = INVALID_HANDLE; // <--- NEW: Debug Handle for EMA

//+------------------------------------------------------------------+
//| Global expert object                                             |
//+------------------------------------------------------------------+
CExpert ExtExpert;
//+------------------------------------------------------------------+
//| Initialization function of the expert                            |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initializing expert
   if(!ExtExpert.Init(Symbol(),Period(),Expert_EveryTick,Expert_MagicNumber))
     {
      printf(__FUNCTION__+": error initializing expert");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Creating signal
   CExpertSignal *signal=new CExpertSignal;
   if(signal==NULL)
     {
      printf(__FUNCTION__+": error creating signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
   ExtExpert.InitSignal(signal);
   signal.ThresholdOpen(Signal_ThresholdOpen);
   signal.ThresholdClose(Signal_ThresholdClose);
   signal.PriceLevel(Signal_PriceLevel);
   signal.StopLevel(Signal_StopLevel);
   signal.TakeLevel(Signal_TakeLevel);
   signal.Expiration(Signal_Expiration);

//--- 1. Creating filter CSignalMACD (Your Trigger)
   CSignalMACD *filter0=new CSignalMACD;
   if(filter0==NULL)
     {
      printf(__FUNCTION__+": error creating filter0 (MACD)");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
   signal.AddFilter(filter0);
   filter0.PeriodFast(Signal_MACD_PeriodFast);
   filter0.PeriodSlow(Signal_MACD_PeriodSlow);
   filter0.PeriodSignal(Signal_MACD_PeriodSignal);
   filter0.Applied(Signal_MACD_Applied);
   filter0.Weight(Signal_MACD_Weight);

//--- 2. Creating filter CSignalMA (Your "Whipsaw" Blocker) <--- NEW BLOCK
   CSignalMA *filter1=new CSignalMA;
   if(filter1==NULL)
     {
      printf(__FUNCTION__+": error creating filter1 (MA)");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
   signal.AddFilter(filter1);
   filter1.PeriodMA(Signal_MA_Period);
   filter1.Shift(Signal_MA_Shift);
   filter1.Method(Signal_MA_Method);
   filter1.Applied(Signal_MA_Applied);
   filter1.Weight(Signal_MA_Weight);

//--- Creation of trailing object
   CTrailingNone *trailing=new CTrailingNone;
   if(trailing==NULL)
     {
      printf(__FUNCTION__+": error creating trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
   if(!ExtExpert.InitTrailing(trailing))
     {
      printf(__FUNCTION__+": error initializing trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

//--- Creation of money object
   CMoneyFixedLot *money=new CMoneyFixedLot;
   if(money==NULL)
     {
      printf(__FUNCTION__+": error creating money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
   if(!ExtExpert.InitMoney(money))
     {
      printf(__FUNCTION__+": error initializing money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
   money.Percent(Money_FixLot_Percent);
   money.Lots(Money_FixLot_Lots);

//--- Check all trading objects parameters
   if(!ExtExpert.ValidationSettings())
     {
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Tuning of all necessary indicators
   if(!ExtExpert.InitIndicators())
     {
      printf(__FUNCTION__+": error initializing indicators");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   //=========================================================
   // DEBUG INIT: Create separate handles to verify logic
   //=========================================================
   debug_macd_handle = iMACD(Symbol(), Period(), 
                             Signal_MACD_PeriodFast, 
                             Signal_MACD_PeriodSlow, 
                             Signal_MACD_PeriodSignal, 
                             Signal_MACD_Applied);
                             
   debug_ema_handle = iMA(Symbol(), Period(), 
                          Signal_MA_Period, 
                          Signal_MA_Shift, 
                          Signal_MA_Method, 
                          Signal_MA_Applied); // <--- NEW
   
   if(debug_macd_handle == INVALID_HANDLE || debug_ema_handle == INVALID_HANDLE) {
      Print("CRITICAL ERROR: Failed to create Debug Handles.");
   }

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Deinitialization function of the expert                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ExtExpert.Deinit();
   if(debug_macd_handle != INVALID_HANDLE) IndicatorRelease(debug_macd_handle);
   if(debug_ema_handle != INVALID_HANDLE) IndicatorRelease(debug_ema_handle);
  }
//+------------------------------------------------------------------+
//| "Tick" event handler function                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   ExtExpert.OnTick();
   
   //=========================================================
   // DEBUG PRINTING LOGIC
   //=========================================================
   if(debug_macd_handle != INVALID_HANDLE && debug_ema_handle != INVALID_HANDLE)
     {
      double macd_main[], macd_signal[], ema_value[];
      
      ArraySetAsSeries(macd_main, true);
      ArraySetAsSeries(macd_signal, true);
      ArraySetAsSeries(ema_value, true);
      
      if(CopyBuffer(debug_macd_handle, 0, 0, 2, macd_main) > 0 && 
         CopyBuffer(debug_macd_handle, 1, 0, 2, macd_signal) > 0 &&
         CopyBuffer(debug_ema_handle, 0, 0, 1, ema_value) > 0) // <--- Get EMA
        {
         double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         
         // Print to Journal
         Print("DEBUG >> ",
               " Price: ", DoubleToString(current_price, 5),
               " | EMA(200): ", DoubleToString(ema_value[0], 5),
               " | MACD Main: ", DoubleToString(macd_main[1], 6), 
               " | Trend: ", (current_price > ema_value[0] ? "BULLISH (Buy Only)" : "BEARISH (Sell Only)")
               );
        }
     }
  }
//+------------------------------------------------------------------+
//| "Trade" event handler function                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
   ExtExpert.OnTrade();
  }
//+------------------------------------------------------------------+
//| "Timer" event handler function                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ExtExpert.OnTimer();
  }
//+------------------------------------------------------------------+