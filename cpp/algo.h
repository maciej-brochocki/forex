#pragma once
#include "mql_sim.h"

#define PAIRS 6
//#define PRINT_PLAYRES
//#define PRINT_P_M_RES
#define SLIP 2

#define N 5
#define DEPTH 75
#define MAX_M 200
#define REQUIRED_HISTORY (N + DEPTH + MAX_M)

struct Quality
{
	double curr_profit;
	double curr_max;
	double max_dd;
	double quality;
};
struct State
{
// platform specific config
   int            currPos; // variable for storing the direction of the last trade (buy or sell)
   double         currPosSize; //value of current position size
   double         pendPosSize; //value of pending position size
   double         currLimit;

// algorithm config
   // static config
   int            mode; // algorithm used by agent: reverse on SL(0) or on TP(1)
   int            tMode; // algorithm's config parameter
   int			  qMode; // algorithm's config parameter
   int            w; // algorithm's config parameter
   int            adaptMode; // algorithm's config parameter
   int            stupidity; // money management config parameter
   // derived config
   int				digits; // number of digits after the decimal point in the price
   double			pip; // calculated pip
   int			  spread;
   int            minLimit; // algorithm's config parameter
   int            pairDir; // money management config parameter
   int            avg; // money management config parameter
   int            dev; // money management config parameter
   int            min_p; // algorithm's config parameter
   int            max_p; // algorithm's config parameter
   int            p_count; // algorithm's config parameter
   // dynamic state
   MqlRates*      history;
   int*           history_oldest_item_idx;
   double         agentCash;
   Quality        q;
   // adaptation
   Quality*       q_matrix;
   int            q_max_m_row;
   int*           p_currPos;
   double*        p_currLimit;
   Quality*       p_q; //only for per p results
   int            m_currPos[MAX_M]; //only for per m results
   double         m_currLimit[MAX_M]; //only for per m results
   Quality        m_q[MAX_M]; //only for per m results
};

void InitAgentData(State& s, int sym, int period, int m, int tM, int qM, int w, int aM, int stup);
int NewPos(State& s, int currPos, double limit, MqlRates& rates);
int InitPos(State& s, int p);
double NewLimit(State&s, int tMode, int currPos, double openPrice, int p, int past, double lastLimit);
double Limit(State& s, int tMode, double open, int dir, int p, int past, double lastLimit);
double Bet(State& s, double open);
double NewProfit(State& s, int currPos, double limit, MqlRates& rates, double openPrice, double bet, double& D);
void UpdateQuality(State& s, Quality& q, double part_profit, double D);
int AdaptInitPos(State& s, double openPrice);
double AdaptNewLimit(State&s, int currPos, double openPrice, double lastLimit);
