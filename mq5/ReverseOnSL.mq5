//----------------------------------------
//|                    ReverseOnSL.mq5   |
//|   Copyright 2012, Maciej Brochocki   |
//|            http://www.bestideas.pl   |
//----------------------------------------

#property			copyright "Copyright 2012, Maciej Brochocki"

input int			OrderMagic = 1; // order magic number
input int			SL = 500; // trailing stop in pips

datetime			lastBarTime =  D'01.01.1971'; // time of the last bar 
enum				lastDealEnum {none, buy, sell};
lastDealEnum		lastDeal = sell; // variable for storing the direction of the last trade (buy or sell)
int					digits; // number of digits after the decimal point in the price
double				pip = 1;

//--------------------------------------
//|   Expert initialization function   |
//--------------------------------------
int OnInit()
{
	SymbolSelect(_Symbol, true);
	digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
	for (int i=0; i<digits; i++)
	{
	   pip = pip / 10;
	}
	return(0);
}

//----------------------------------------
//|   Expert deinitialization function   |
//----------------------------------------
void OnDeinit(const int reason)
{
	return;
}

//----------------------------
//|   Expert tick function   |
//----------------------------
void OnTick()
{
	if(!PositionSelect(Symbol()))
	{
		PlaceOrder(Direction(), Bet());
	}
	if(NewBar())
	{
		UpdateSL();
	}
	return;
}

//-----------------------------------------------
//|   Returns true, if the bar has just begun   |
//-----------------------------------------------
bool NewBar()
{
	datetime New_Time[1];
	int copied = CopyTime(_Symbol, _Period, 0, 1, New_Time);

	if(copied>0)
	{
		if(lastBarTime != New_Time[0])
		{
			lastBarTime = New_Time[0];
			return(true);
		}
	}
	else
	{
		Alert(__FUNCTION__, "- CopyTime error: ", GetLastError());
		ResetLastError();
		return(false);
	}
	return(false);
}

//-----------------------------------------------------------------------
//|   Returns the direction to enter the market (true=buy, false=sell)  |
//-----------------------------------------------------------------------
bool Direction()
{
	if(lastDeal == buy)
	{
		lastDeal = sell;
		return(false);
	}
	lastDeal = buy;
	return(true);
}

//-------------------------------------------
//|   Returns size of the position to open  |
//-------------------------------------------
double Bet()
{
	return(0.1);
}

//-------------------------------
//|   Returns true on success   |
//-------------------------------
bool executeOrder(MqlTradeRequest& request, string errInfoPrefix)
{
	MqlTradeCheckResult checkResult;
	ZeroMemory(checkResult);
	if(OrderCheck(request, checkResult))
	{
		MqlTradeResult result;
		ZeroMemory(result);
		if (!OrderSend(request, result))
		{
			Print(errInfoPrefix, " - OrderSend error:", result.comment);
			return(false);
		}
	}
	else
	{
		Print(errInfoPrefix, " - OrderCheck error:", checkResult.comment);
		return(false);
	}
	return(true);
}

//----------------------------------
//|   UpdateSL - moves stop loss   |
//----------------------------------
void UpdateSL()
{
	double lastPrice[1];
	CopyOpen(Symbol(), Period(), 0, 1, lastPrice);

	MqlTradeRequest request;

	if(PositionSelect(Symbol()))
	{
		// placing an SL modify order
		ZeroMemory(request);
		request.action = TRADE_ACTION_SLTP;
		request.symbol = Symbol();
		request.tp = 0;
		if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
		{
			request.sl = NormalizeDouble(lastPrice[0] - SL * pip, digits);
		}
		else
		{
			request.sl = NormalizeDouble(lastPrice[0] + SL * pip, digits);
		}
		executeOrder(request, __FUNCTION__);
	}
	
	ulong ticket;
	if ((ticket=OrderGetTicket(0))>0)
	{
		// modifying a pending order
		ZeroMemory(request);
	   request.action = TRADE_ACTION_MODIFY;
		request.order = ticket;
		request.sl = 0;
		request.tp = 0;
		if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
		{
			request.price = NormalizeDouble(lastPrice[0] - SL * pip, digits);
		}
		else
		{
			request.price = NormalizeDouble(lastPrice[0] + SL * pip, digits);
		}
		executeOrder(request, __FUNCTION__);
	}
	else
	{
		// placing a pending order
		ZeroMemory(request);
	   request.action = TRADE_ACTION_PENDING;
		request.magic = OrderMagic;
		request.symbol = _Symbol;
		request.volume = Bet();
		request.sl = 0;
		request.tp = 0;
		request.type_filling = ORDER_FILLING_IOC;
		if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
		{
			request.price = NormalizeDouble(lastPrice[0] - SL * pip, digits);
			request.type = ORDER_TYPE_SELL_STOP;
		}
		else
		{
			request.price = NormalizeDouble(lastPrice[0] + SL * pip, digits);
			request.type = ORDER_TYPE_BUY_STOP;
		}
		executeOrder(request, __FUNCTION__);
	}
	
	return;
}

//-------------------------------------
//|   PlaceOrder - placing an order   |
//-------------------------------------
void PlaceOrder(bool direction, double bet)
{
	MqlTick last_tick;
	if(SymbolInfoTick(Symbol(), last_tick))
	{
		// placing an immediate order
		MqlTradeRequest request;
		ZeroMemory(request);
		request.action = TRADE_ACTION_DEAL;
		request.magic = OrderMagic;
		request.symbol = _Symbol;
		request.volume = bet;
		request.sl = 0;
		request.tp = 0;
		if (direction)
		{
			request.price = last_tick.ask;
			request.type = ORDER_TYPE_BUY;
		}
		else
		{
			request.price = last_tick.bid;
			request.type = ORDER_TYPE_SELL;
		}
		executeOrder(request, __FUNCTION__);
	}
	else
	{
		Print(__FUNCTION__, "- SymbolInfoTick error: ", GetLastError());
	}
	return;
}
