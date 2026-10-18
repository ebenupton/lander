10 VDU6:MODE7:VDU23,1,0;0;0;0;
20 REM The VideoNULA test: the ULA's CRTC clock at 2MHz (&FE20 bit 4),
30 REM then &44 to &FE22: without a NULA, &FE22 is &FE20 and the clock goes
40 REM back to 1MHz, the frames twice as long; a NULA takes it (a reset).
45 REM The display is off meanwhile, and flashing (the MOS rewrites &FE20 at
46 REM each flash) too; ESCAPE puts both back.
47 ON ERROR VDU6:MODE7:OSCLI"FX9,25":OSCLI"FX10,25":REPORT:PRINT:END
50 VDU23,0,8,&30,0;0;0;
60 *FX9
70 *FX10
80 *FX151,32,16
90 E%=FNT
100 *FX151,34,68
110 N%=E%*4>FNT*3
120 MODE7:VDU23,1,0;0;0;0;
130 *FX9,25
140 *FX10,25
145 ON ERROR OFF
150 PRINT''"  LANDER (32K)"''"  1  MODE 1: 4 colours, dithered"'"  2  MODE 2: 27 colours (CPC palette)"
160 IF N% THEN PRINT"  3  MODE 2: 16 colours (VideoNULA)"'"  4  MODE 2: Archimedes colours (NULA)"
165 IF N% THEN PRINT'"  Press 1, 2, 3 or 4" ELSE PRINT'"  Press 1 or 2"
170 *FX15
180 REPEAT K%=GET-48:UNTIL K%=1 OR K%=2 OR (K%=3 OR K%=4) AND N%
185 IF N% THEN OSCLI"FX151,34,64"
186 REM (the NULA reset: its palette back to the ULA's, after a NULA version)
190 MODE1:VDU23,1,0;0;0;0;19,1,0;0;19,2,0;0;19,3,0;0;
200 OSCLI"DIR "+MID$("MCNA",K%,1)
210 OSCLI"RUN LANDER"
220 END
240 DEFFNT:LOCALI%:OSCLI"FX19":TIME=0:FORI%=1TO5:OSCLI"FX19":NEXT:=TIME
