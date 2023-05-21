@echo off
forfiles /S /M "*.sp" /C "cmd /C C:\Users\omerb\AppData\Roaming\spcode\sourcepawn\configs\sm_1_11_0_6924\spcomp -O 0 @PATH" >> log.txt
pause