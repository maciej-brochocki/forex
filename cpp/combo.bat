@echo off
FOR %%P IN (0 1 4 5) DO FOR %%T IN (0 1) DO FOR %%A IN (0 2) DO Release\forex.exe %%P 10080 %%T 0 1 %%A -1 >sim%%P_W1_%%T01%%A.csv
