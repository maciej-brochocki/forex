#pragma once
#include <time.h>

struct MqlRates
{
	time_t   time;         // Period start time
	double   open;         // Open price
	double   high;         // The highest price of the period
	double   low;          // The lowest price of the period
	double   close;        // Close price
	long     tick_volume;  // Tick volume
	int      spread;       // Spread
	long     real_volume;  // Trade volume
};

double NormalizeDouble(double a, int prec);
double MathMin(double a, double b);
double MathMax(double a, double b);
double MathAbs(double a);
