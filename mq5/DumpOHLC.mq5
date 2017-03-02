//-------------------------------------------
//|                    ReverseOnLimit.mq5   |
//|      Copyright 2012, Maciej Brochocki   |
//|               http://www.bestideas.pl   |
//-------------------------------------------

#property			copyright "Copyright 2012, Maciej Brochocki"

input int			OrderMagic = 1; // order magic number
datetime			lastBarTime; // time of the last bar 
int					filehandle;
int   firstBar = 1;

//--------------------------------------
//|   Expert initialization function   |
//--------------------------------------
int OnInit()
{
	lastBarTime = D'01.01.1971';
	filehandle=FileOpen(_Symbol + IntegerToString(PeriodSeconds()/60) + ".csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
	FileSeek(filehandle, 0, SEEK_END);
	if(filehandle!=INVALID_HANDLE)
	{
		return(0);
	}
	else
	{
		return (-1);
	}
}

//----------------------------------------
//|   Expert deinitialization function   |
//----------------------------------------
void OnDeinit(const int reason)
{
	MqlRates rates[1];
	CopyRates(_Symbol, _Period, 0, 1, rates);
   FileWrite(filehandle, rates[0].time, rates[0].open, rates[0].high, rates[0].low, rates[0].close, rates[0].real_volume);
	FileClose(filehandle);
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

//----------------------------
//|   Expert tick function   |
//----------------------------
void OnTick()
{
	if (NewBar())
	{
		MqlRates rates[2];
		CopyRates(_Symbol, _Period, 0, 2, rates);
		if (firstBar == 0)
		   FileWrite(filehandle, rates[0].time, rates[0].open, rates[0].high, rates[0].low, rates[0].close, rates[0].real_volume);
		else firstBar = 0;
	}
	return;
}
