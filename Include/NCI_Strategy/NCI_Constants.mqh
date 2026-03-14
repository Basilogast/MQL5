//+------------------------------------------------------------------+
//| NCI_Constants.mqh - Inputs, Enums & Settings                     |
//+------------------------------------------------------------------+
#property strict

enum ENUM_REENTRY_MODE {
   MODE_SINGLE   = 0, 
   MODE_DOUBLE   = 1, 
   MODE_INFINITE = 2  
};
enum ENUM_ENTRY_STYLE {
   STYLE_BLIND_TOUCH      = 0, 
   STYLE_CONFIRMATION     = 1, 
   STYLE_STRUCTURAL_SHIFT = 2  
};
enum ENUM_CONFIRM_PATTERN {
   PATTERN_PINBAR    = 0,  
   PATTERN_ENGULFING = 1,  
   PATTERN_ANY       = 2   
};

// ==============================================================================
// GROUP 1: STRATEGY & TIMEFRAMES 
// ==============================================================================
input group "Timeframe Settings"
input ENUM_TIMEFRAMES TimeFrame_HTF = PERIOD_H1;  
input ENUM_TIMEFRAMES TimeFrame_LTF = PERIOD_M15; 

input group "Sector A: Simple Strategy"
input bool Enable_Simple_Mode     = false; 
input bool Simple_Trade_HTF       = false; 
input bool Simple_Trend_HTF       = true;  
input bool Simple_Breakout_HTF    = true;  
input bool Simple_Trade_LTF       = true;  
input bool Simple_Trend_LTF       = true;  
input bool Simple_Breakout_LTF    = false; 
input bool Simple_UseTrendAlign   = true;  

input group "Sector B: Zone-in-Zone (ZiZ)"
input bool Enable_ZiZ_Mode        = true;  
input bool ZiZ_AllowTrend         = true;  
input bool ZiZ_AllowStairStep     = true;  
input bool ZiZ_AllowBreakout      = false; 
input bool UseToxicFilter         = false; 
input bool ZiZ_BlockStepSell      = true;  

// ==============================================================================
// GROUP 2: ENTRY LOGIC 
// ==============================================================================
input group "Risk & Sizing Settings"
input double RiskPercent          = 1.0;
input ENUM_REENTRY_MODE EntryMode = MODE_DOUBLE;

input group "Entry & Confirmation Logic"
input bool                 Enable_Phoenix_Sweep = true;  
input ENUM_ENTRY_STYLE     EntryStyle         = STYLE_CONFIRMATION;
input ENUM_CONFIRM_PATTERN ConfirmationSignal = PATTERN_ANY;
input double               MinWickPercent     = 0.60;    
input double ReferenceZonePips_HTF = 235.0; 
input double ReferenceZonePips_LTF = 60.0;  
input double BaseEntryDepth        = 0.40;  
input double BaseMaxDepth          = 0.75;  
input double Normal_Max_Entry_Clamp = 0.60; 
input double Normal_Max_Limit_Clamp = 0.80; 
input double Breakout_HTF_Buffer_Pips = 50.0; 

input group "Buffer Settings"
input bool   UseDynamicBuffer = false;
input double BaseBufferPoints = 45.0;
input double MinBufferPoints  = 20;   
input double MaxBufferPoints  = 200;

// ==============================================================================
// GROUP 3: TAKE PROFIT LOGIC 
// ==============================================================================
input group "Take Profit Target Logic"
input double MinRiskReward       = 2.0; 
input double TPZoneDepth         = 0.0; 

input group "Profit Locking (Percentages)"
input bool   EnableProfitLocking = true;
input double LockTriggerPercent  = 0.80;  
input double LockPositionPercent = 0.70;  
input double Step_LockTriggerPercent  = 0.60; 
input double Step_LockPositionPercent = 0.55; 

input group "Profit Locking (Risk-Reward)"
input bool   Enable_RR_Locking   = true;  
input bool   RR_Lock_Step_Only   = false; 
input double RR_Lock_Trigger     = 4.0;   
input double RR_Lock_Target      = 3.5;   

input group "Smart Trailing & Exits"
input bool   Enable_Smart_Trail      = false; 
input double Smart_Trail_Buffer_Pips = 10.0;  
input bool   Enable_Friday_Close     = true;  
input int    Friday_Close_Hour       = 20;    
input double Account_Initial_Balance = 10000.0; 
input double Friday_Min_RR           = 3.0;   

// ==============================================================================
// GROUP 4: FILTERS 
// ==============================================================================
input group "Traffic Control"
input bool   AllowTrading            = true; 
input int    MaxOpenTrades           = 2;    
input int    MinMinutesBetweenTrades = 60;   

input group "Time Filter Settings"
input bool   UseTimeFilter = true; 
input int    StartHour     = 7;    
input int    EndHour       = 16;   

input group "Structure Rules"
input bool   Use_Strict_SMC_Zones = true; 
input bool   Enable_FVG_Zones     = true; // [NEW] Master toggle for FVG Logic
input int    FVG_Max_Scan_Bars    = 5;    // [NEW] Max candles to scan for FVG gap
input double MinBodyPercent       = 0.50;
input int    MaxScanDistance      = 3;
input double BigCandleFactor      = 1.3;

input group "Spread & Candle Filters"
input bool   UseVolatilityGuard = true;
input int    MaxSpreadPoints    = 25; 
input int    MaxCandleSizePips  = 25; 

input group "ADR Market Regimes"
input bool   Use_ADR_Filter        = true; 
input int    ADR_Period            = 5;    
input double ADR_Min_Pips          = 70.0; 
input double ADR_Max_Pips          = 85.0; 
input bool   Enable_SectorC_Range  = true; 
input double SectorC_Max_ADR       = 70.0; 
input bool   Enable_SectorE_Storm  = true; 
input double SectorE_Min_ADR       = 85.0; 
input double Storm_Entry_Depth     = 0.70; 
input double Storm_Buffer_Pips     = 15.0; 
input double Storm_Max_Entry_Clamp = 0.85; 
input double Storm_Max_Limit_Clamp = 0.90; 

// ==============================================================================
// GROUP 5: VISUALS & STATISTICS 
// ==============================================================================
input group "Visual Settings"
input bool Show_ZigZag_Lines = true; 
input bool Show_Zone_Boxes   = true; 
input bool Show_FVG_Boxes    = true; // [NEW] Toggle to draw separate FVG boxes
input bool Debug_Show_Spread = true; 
input int  HistoryBars       = 5000;
input int  LineWidth         = 2;
color SupplyColor     = clrMaroon; 
color DemandColor     = clrDarkGreen;
color FlippedColor    = clrGray; 
color FVG_Bull_Color  = clrMediumSeaGreen; // [NEW] Color for Bullish FVG
color FVG_Bear_Color  = clrLightCoral;     // [NEW] Color for Bearish FVG
color ColorUp         = clrLimeGreen;
color ColorDown       = clrRed;
color ColorRange      = clrYellow;

input group "Statistics Report"
input double Stats_ADR_Low   = 70.0;  
input double Stats_ADR_High  = 85.0;