//+------------------------------------------------------------------+
//| NCI_Constants.mqh - Inputs, Enums & Settings                     |
//+------------------------------------------------------------------+
#property strict

enum ENUM_REENTRY_MODE {
   MODE_SINGLE   = 0, 
   MODE_DOUBLE   = 1, 
   MODE_INFINITE = 2  
};

//--- 0. TIMEFRAME SETTINGS (FIXED)
input group "Timeframe Settings"
input ENUM_TIMEFRAMES TimeFrame_HTF = PERIOD_H1;  // High Timeframe (e.g. 1H)
input ENUM_TIMEFRAMES TimeFrame_LTF = PERIOD_M15; // Low Timeframe (e.g. 15M)

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 5000;
input int LineWidth         = 2;
input bool DrawZones        = true;

color SupplyColor     = clrMaroon; 
color DemandColor     = clrDarkGreen;
color FlippedColor    = clrGray; 

//--- 2. TREND COLORS
color ColorUp         = clrLimeGreen;
color ColorDown       = clrRed;
color ColorRange      = clrYellow;

//--- 3. STRUCTURE RULES
input group "Structure Rules"
input double MinBodyPercent = 0.50;  
input int MaxScanDistance   = 3;
input double BigCandleFactor = 1.3; 

//--- 4. TRADING SETTINGS
input group "Trading Logic"
input bool AllowTrading      = true; // Master Switch

// HTF Specifics
input bool AllowTrade_HTF         = false; 
input bool AllowTrendEntry_HTF    = true; 
input bool AllowBreakoutEntry_HTF = true; 

// LTF Specifics
input bool AllowTrade_LTF         = true; 
input bool AllowTrendEntry_LTF    = true; 
input bool AllowBreakoutEntry_LTF = false; 

// NEW OPTION 1: TREND ALIGNMENT
input bool UseTrendAlignment      = true; // If true, LTF trades must match HTF Trend

input double RiskPercent     = 1.0;  
input double MinRiskReward   = 2.0;  

// Re-Entry Logic
input group "Re-Entry Logic"
input ENUM_REENTRY_MODE EntryMode = MODE_DOUBLE; 

// Volatility Guard
input group "Volatility Guard"
input bool   UseVolatilityGuard = true; 
input int    MaxSpreadPoints   = 30; 
input int    MaxCandleSizePips = 80; 

//--- 5. SCALING & ENTRY
input group "Entry Logic"
input double ReferenceZonePips_HTF = 235.0; // Reference size for H1
input double ReferenceZonePips_LTF = 60.0;  // Reference size for M15

input double BaseEntryDepth    = 0.40;  
input double BaseMaxDepth      = 0.75;
input double TPZoneDepth     = 0.0;

//--- 6. BUFFER SETTINGS
input group "Buffer Logic"
input bool   UseDynamicBuffer = false; 
input double BaseBufferPoints = 45.0;
input double MinBufferPoints  = 20;   
input double MaxBufferPoints  = 200;

//--- 7. RISK MANAGEMENT
input group "Risk Management"
input bool   EnableProfitLocking = true;
input double LockTriggerPercent  = 0.80;
input double LockPositionPercent = 0.70;