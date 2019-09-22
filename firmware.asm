; Zdrojove kody mozete pouzivat k akemukolvek ucelu.
; Za mozne sposobene skody nenesiem zodpovednost.
;
; You can use the source codes for anything you want.
; I am not responsible for any damages.
	
; Firmware prevodniku pre programovanie mikrokontrolerov
; Vykonava prevod medzi seriovymi signalmi pre programovanie
; mikrokontroleru AT89S51 a paralelnymi signalmi pre programovanie
; mikrokontroleru AT89C1051, AT89C2051 alebo AT89C4051.


; ----------------------------------------------------------------------
; hardware
; ----------------------------------------------------------------------
green 	equ	p3.6		; zelena led
red	equ	p3.5		; cervena led
up	equ	p3.7		; upload led
down	equ	p3.4		; download led
				; definice paralelneho rozhrania
rstsw	equ	p2.1		; spinac rst signalu
vccsw	equ	p2.0		; spinac napajacieho napatia
pdata	equ	p0		; paralelne data
xtal	equ	p2.6		; xtal
prog	equ	p2.5		; prog
m0	equ	p2.4		; prvy bit modu
m1	equ	p2.3		; druhy bit modu
m2	equ	p2.2		; treti a stvrty bit modu
				; definicie fram
frwp	equ	p1.0		; write protect
frscl	equ	p1.1		; hodinovy signal
frsda	equ	p1.2		; datovy signal
				; signaly serioveho rozhrania
mosi	equ	p1.5		; master in slave out
miso	equ	p1.6		; master out slave in
sck	equ	p1.7		; hodinovy signal
rst	equ	p3.2		; resetovaci signal
btn	equ	p3.3		; ovladacie tlacitko	
; ----------------------------------------------------------------------
; premenne a konstanty
; ----------------------------------------------------------------------
	bseg	at 20h
lock:	dbit	1		; zamok modelu
spe:	dbit	1		; vlajka serial programming enabled
taskerr:dbit	1		; vlajka chyby ulohy
	
	dseg	at 30h
				; premenne modelu
vlocks:	ds	1		; lock bity 
vsign:	ds	3		; bajty signatury
vchange:ds	1		; bity zmeny
				; 0. bit - chip erase
				; 1. bit - write program memory
				; 2. bit - write lock bits
				; premenne fram
frct:	ds	1		; pocitadlo pre fram podprogramy
frerr:	ds	1		; pocet opakovani pri chybe prenosu
frtmp:	ds	1		; docasne ulozenie dat fram

				; pwm konstanty
volt	equ	30		; trvanie aktivnej casti periody pwm
period	equ	2200		; trvanie periody pwm

vmargin equ	08h		; velkost pamate programu at89cx051 mcu
				; velkost pamate v bajtoch je ziskana
				; vynasobenim tohoto cisla cislom 256
				; 04h je pre at89c1051
				; 08h je pre at89c2051
				; 10h je pre at89c4051
; ----------------------------------------------------------------------
; kod programu
; ----------------------------------------------------------------------
	cseg
	
	org	00h
	ajmp	main		; skok na zaciatok programu
	
	org	03h
	ajmp	serial		; obsluha serioveho programatoru
	
	org	0bh
	ajmp	rstpwm		; obsluha pwm kanalu
	
	org	13h
	ajmp	button		; obsluha ovladacieho tlacitka
; ----------------------------------------------------------------------
; hlavny program
; ----------------------------------------------------------------------
main:	clr	green		; zasviet vsetky led
	clr	red
	clr	up
	clr	down		; ok
	
	setb	frwp		; signaly fram do kludoveho stavu
	setb	frscl
	setb	frsda		; ok
	
	anl	tmod,#0fh	; 16 bitovy casovac 1
	orl	tmod,#10h
	setb	tr1		; spust
				; signaly paralelneho rozhrania do
	acall	poff		; kludoveho stavu
	
	anl	tmod,#0f0h	; 16 bitovy casovac 0
	orl	tmod,#01h
	setb	tr0		; spust
	setb	pt0		; vysoka priorita

	mov	a,#0		; vychodzie hodnoty premennych modelu
	mov	vlocks,a	; deaktivovane lock bity
	mov	a,#1eh		; platna signatura at89s51
	mov	vsign,a		
	mov	a,#51h
	mov	vsign+1,a
	mov	a,#06h
	mov	vsign+2,a	; ok
	mov	vchange,a	; ziadne zmeny
		
	clr	it0		; int0 citlive na log. 0
	setb	ex0
	
	clr	it1		; int1 citlive na zostupnu hranu
	setb	ex1
	
	setb	red		; led do pohotovostneho stavu
	setb	green
	setb	down
	clr	up		; ok
	setb	ea		; povolene vsetky prerusenia
		
task:	clr	lock		; odomkni pamat
	mov	r0,#100		; cakaj 2 s
task_wait:
	clr	tf1
	mov	tl1,#low (65535 - 40000)
	mov	th1,#high (65535 - 40000)
	jnb	tf1,$
	djnz	r0,task_wait
	setb	lock		; zamkni pamat a detekuj zmenu
	mov	a,vchange
	jz	task		; ak nie je zmena, odomkni a cakaj
	clr	green		; je zmena, zasviet oranzovu led
	clr	red
	clr	taskerr		; zhod priznak zmeny
task_select:
	mov	a,vchange	; zisti kde je zmena
	jb	acc.0,task_perasechip
	jb	acc.1,task_pcodewrite
	jb	acc.2,task_plockwrite
	jb	taskerr,task_error
	setb	red		; nie je chyba, zasviet zelenu led
	clr	green
	ajmp	task		; cakaj na dalsie zmeny
task_error:
	setb	green		; je chyba, zasviet cervenu led
	clr	red
	mov	vchange,#0	; zrus vsetky zmeny
	ajmp	task		; cakaj na dalsie zmeny 
task_perasechip:
	acall	perasechip	; zmaz at89cx8051
	mov	a,vchange	; zhod priznak zmeny
	clr	acc.0
	mov	vchange,a	; ok
	ajmp	task_select	; pokracuj dalsou ulohou
task_pcodewrite:
	acall	pcodewrite	; zapis pamat programu at89cx051
	mov	taskerr,c	; nastav vlajku chyby
	mov	a,vchange	; nie je chyba, zhod priznak zmeny
	clr	acc.1
	mov	vchange,a	; ok
	ajmp	task_select	; pokracuj dalsou ulohou
task_plockwrite:
	acall	plockwrite	; zapis lock bity at89cx501
	mov	a,vchange	; zhod priznak zmeny
	clr	acc.2
	mov	vchange,a	; ok
	ajmp	task_select	; pokracuj dalsou ulohou
	
; ----------------------------------------------------------------------
; obsluzne procedury
; ----------------------------------------------------------------------
				; obsluha serioveho rozhrania
serial:	jnb	lock,$+4	; skontroluj zamok
	reti
	clr	spe		; zhod vlajku programming enable
sdecode:
	acall 	srcv		; prijmi 1. bajt
	cjne 	a,#0ach,$+5	; a dekoduj ho
	ajmp 	sdecode_l0
	cjne 	a,#20h,$+5
	ajmp 	sbyteread
	cjne 	a,#40h,$+5
	ajmp 	sbytewrite
	cjne 	a,#24h,$+5
	ajmp 	slockread
	cjne 	a,#28h,$+5
	ajmp 	ssignread
	cjne 	a,#30h,$+5
	ajmp 	spageread
	cjne 	a,#50h,$+5
	ajmp 	spagewrite
	ajmp 	sterm		; nebol rozpoznany, skonci
sdecode_l0:
	acall 	srcv		; prijmi 2. bajt
	mov 	r0,a		; a zalohuj ho, moze obsahovat data
	cjne 	a,#53h,$+5	
	ajmp 	senableprog
	anl 	a,#11111100b	
	cjne 	a,#0e0h,$+5
	ajmp 	slockwrite
	anl 	a,#11100000b	
	cjne 	a,#80h,$+5
	ajmp 	serasechip
	ajmp 	sterm		; nebol rozpoznany, skonci
sterm_p2:
	pop	acc		; zahod 2 bajty navratovej adresy
	pop	acc		
sterm:	pop	acc
	pop	acc
	mov	a,#low task
	push	acc
	mov	a,#high task
	push	acc
	setb	green		; zhasni zelenu a cervenu led
	setb	red
	reti
	
senableprog:			; programming enable
	setb	spe		; nastav priznak programming enable
	acall	srcv		; prijmi 3. bajt
	mov	a,#01101001b
	acall	ssend		; posli 4. bajt
	ajmp	sdecode

serasechip:			; chip erase
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	clr	green		; zasviet cervenu led a zelenu led
	clr	red
	acall	srcv		; prijmi 3.
	acall	srcv		; a 4. bajt
	mov	dptr,#0		; zmaz 4 kib fram
	acall	vwrite_open	; otvor model
serasechip_l0:
	mov	a,#0ffh		; vymazany bajt
	acall	vwrite_byte	; zapis bajt do modelu
	inc	dptr		; inkrementuj adresu
	mov	a,dph
	cjne	a,#10h,serasechip_l0
	acall	vwrite_close	; zatvor model
	mov	a,vchange	; zaznamenaj zmenu
	setb	acc.0
	mov	vchange,a
	ajmp	sdecode	
	
sbyteread:			; read program memory (byte mode)
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	acall	srcv		; prijmi 2. bajt (upper address byte)
	anl	a,#0fh		; vymaskuj nahodne bity
	mov	dph,a
	acall	srcv		; prijmi 3. bajt (lower address byte)
	mov	dpl,a
	acall	vread
	acall	ssend		; posli 4. bajt (data)
	ajmp	sdecode	

sbytewrite:			; write program memory (byte mode)
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	clr	green		; zasviet cervenu led a zelenu led
	clr	red
	acall	srcv		; prijmi 2. bajt (upper address byte) 
	anl	a,#0fh		; vymaskuj nahodne bity
	mov	dph,a
	acall	srcv		; prijmi 3. bajt (lower address byte)
	mov	dpl,a
	acall	srcv		; prijmi 4. bajt (data)
	acall	vwrite
	mov	a,vchange	; zaznamenaj zmenu
	setb	acc.1
	mov	vchange,a
	ajmp	sdecode

slockwrite:			; write lock bits
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	clr	green		; zasviet cervenu led a zelenu led
	clr	red
	acall	srcv		; prijmi 3.
	acall	srcv		; a 4. bajt
	mov	a,r0		; vyber 2. bajt zo zalohy
	anl	a,#03h		; vymaskuj nahodne bity
	mov	r0,a
	mov	a,vlocks	; nastav prislusny lock bit
	cjne	r0,#1,$+5
	setb	acc.2
	cjne	r0,#2,$+5
	setb	acc.3
	cjne	r0,#3,$+5
	setb	acc.4
	mov	vlocks,a
	mov	a,vchange	; zaznamenaj zmenu
	setb	acc.2
	mov	vchange,a
	ajmp	sdecode
	
slockread:			; read lock bits
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	acall	srcv		; prijmi 2.
	acall	srcv		; a 3. bajt
	mov	a,vlocks
	acall	ssend		; posli 4. bajt (lock bits)
	ajmp	sdecode	
	
ssignread:			; read signature bytes
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	acall	srcv		; prijmi 2. bajt (upper address)
	mov	r0,a
	acall	srcv		; prijmi 3. bajt (lower address)
	jnz	ssignread_l0	; ak nie je 0, ignoruj upper address
	mov	a,r0
	anl	a,#0fh	
	mov	dptr,#vsign
	movc	a,@a+dptr
ssignread_l0:
	acall	ssend		; posli 4. bajt (signature byte)
	ajmp	sdecode

spageread:			; read program memory (page mode)
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	acall	srcv		; prijmi 2. bajt (upper address)
	anl	a,#0fh		; vymaskuj nahodne bity
	mov	dph,a
	mov	dpl,#0
spageread_l0:	
	acall	vread
	acall	ssend		; posli 0. az 255. datovy bajt
	inc	dpl
	mov	a,dpl
	cjne	a,#0,spageread_l0
	ajmp	sdecode
	
spagewrite:			; write program memory (page mode)
	jb	spe,$+5		; skontroluj programming enable
	ajmp	sterm
	clr	green		; zasviet cervenu led a zelenu led
	clr	red
	acall	srcv		; prijmi 2. bajt (upper address)
	anl	a,#0fh		; vymaskuj nahodne bity
	mov	dph,a
	mov	dpl,#0
spagewrite_l0:	
	acall	srcv		; prijmi 0. az 255. datovy bajt
	acall	vwrite
	inc	dpl
	mov	a,dpl
	cjne	a,#0,spagewrite_l0
	mov	a,vchange	; zaznamenaj zmenu
	setb	acc.1
	mov	vchange,a
	ajmp	sdecode

				; prijem bajtu od programatoru
srcv:	mov	r1,#8		; prijmi 8 bitov
srcv_l0:
	jnb	rst,$+5		; kontroluj rst
	ajmp	sterm_p2	
	jb	sck,$-5		; cakaj na sck = 0	
	jnb	rst,$+5
	ajmp	sterm_p2
	jnb	sck,$-5		; cakaj na sck = 1
	mov	c,mosi		; prijmi bit
	rlc	a
	jnb	rst,$+5
	ajmp	sterm_p2
	jb	sck,$-5		; cakaj na sck = 0
	djnz	r1,srcv_l0
	ret

				; odoslanie bajtu programatoru			
ssend:	mov	r1,#8		; posli 8 bitov
ssend_l0:
	jnb	rst,$+5
	ajmp	sterm_p2
	jb	sck,$-5		; cakaj na sck = 0	
	jnb	rst,$+5
	ajmp	sterm_p2
	jnb	sck,$-5		; cakaj na sck = 1
	rlc	a	
	mov	miso,c		; posli bit
	jnb	rst,$+5
	ajmp	sterm_p2
	jb	sck,$-5		; cakaj na sck = 0
	djnz	r1,ssend_l0
	ret

; ----------------------------------------------------------------------
				; obsluha casovaca 0 pre pwm
rstpwm:	jb	rstsw,rstpwm_low
	setb	rstsw		; rst = 12 v
	mov	tl0,#low (0ffffh - volt)
	mov	th0,#high (0ffffh - volt)
	reti
rstpwm_low:
	clr	rstsw		; rst = 0 v
	mov	tl0,#low (0ffffh - period + volt)
	mov	th0,#high (0ffffh - period + volt)
	reti

				; rst = 0 v
rst0v:	clr	et0		; zakaz prerusenie od casovaca 0
	clr	rstsw		; rst = 0 v
	jmp	rstv_exit
				; rst = 5 v
rst5v:	setb	et0		; povol prerusenie od casovaca 0
	setb	tf0		; vyvolaj obsluhu casovaca 0
	;ajmp	$		; nekonecne cakanie pre odladenie generovania
				; napatia 5 v
	jmp	rstv_exit
				; rst = 12 v
rst12v:	clr	et0		; zakaz prerusenie od casovaca 0
	setb	rstsw		; rst = 12 v
rstv_exit:			; cakaj na ustalenie rst napatia
	mov	r2,#20
rstv_exit_loop:
	clr	tf1		
	mov	tl1,#0
	mov	th1,#0
	jnb	tf1,$		; ok
	djnz	r2,rstv_exit_loop
	ret

; ----------------------------------------------------------------------
button:	jnb	lock,$+4	; skontroluj zamok
	reti
	setb	lock		; zamkni model
	mov	r0,#3		; zober 3 vzorky
button_noise:
	clr	tf1		; po 5 ms
	mov	tl1,#low (65535 - 10000)
	mov	th1,#high (65535 - 10000)
	jnb	tf1,$
	jnb	btn,$+6
	clr	lock
	reti	
	djnz	r0,button_noise	
	mov	r0,#30		; hranicny cas 700 ms
button_wait:
	clr	tf1
	mov	tl1,#low (65535 - 50000)
	mov	th1,#high (65535 - 50000)
				; detekovane kratke stlacenie
	jb	btn,button_short
	jnb	tf1,$-3
	djnz	r0,button_wait
	ajmp	button_long	; detekovane dlhe stlacenie
	
button_short:			; kratke stlacenie
	cpl	up		; prepni smer synchronizacie
	cpl	down
	ajmp	button_exit	; skonci
	
button_long:			; dlhe stlacenie
				; reaguj podla smeru synchronizacie
	jnb	up,button_upload
	jnb	down,button_download
button_upload:			; at89cx501 do prevodniku
	clr	green		; led do aktivneho stavu
	clr	red
	acall	pcoderead	; precitaj pamat programu
	setb	red		; zasviet zelenu led
	ajmp	button_exit	; skonci
button_download:		; prevodnik do at89cx501
	clr	green		; led do aktivneho stavu
	clr	red
	acall	perasechip	; zamaz at89cx501
	acall	pcodewrite	; zapis data
	jnc	button_download_l0
	setb	green		; zapis neuspesny, zasviet cervenu led
	ajmp	button_exit	; a skonci
button_download_l0:
	acall	plockwrite	; zapis lock bity
	setb	red		; zapis uspesny, zasviet zelenu led
	ajmp	button_exit	; a skonci
	
button_exit:			; cakaj na pustenie tlacidla
	mov	r0,#10		; zober 10 vzoriek
button_exit_l0:
	clr	tf1		; po 5 ms
	mov	tl1,#low (65535 - 10000)
	mov	th1,#high (65535 - 10000)
	jnb	tf1,$
	jnb	btn,button_exit	; ak je detekovane stlacenie, znovu
	djnz	r0,button_exit_l0
	clr	lock		; odomkni model
	reti

; ----------------------------------------------------------------------
				; vypinacia sekvencia
poff:	clr	xtal		; xtal = 0 v
	acall	rst0v		; rst = 0 v
	clr	vccsw		; vypni napajanie
	ret

pcodewrite:			; naprogramovanie pamate at89cx051
	setb	vccsw		; zapni napajanie
	setb	prog		; prog = 5 v
	acall	rst5v		; rst = 5 v
	clr	m0		; mod
	setb	m1
	setb	m2		; ok
	mov	dptr,#0		; nastav fram adresu
	clr	f0		; nabeh rst na 12 v len pre 1. bajt
pcodewrite_l0:
	acall	vread		; precitaj bajt z modelu
	mov	pdata,a		; posli bajt at89cx051
	jb	f0,$+7
	acall	rst12v		; rst = 12 v
	setb	f0		; len pre prvy bajt
	clr	prog		; 1 us prog pulz
	nop
	setb	prog		; ok
	clr	tf1		; cakaj 2 ms na skoncenie zapisu
	mov	tl1,#low (65535 - 4000)
	mov	th1,#high (65535 - 4000)
	jnb	tf1,$	
	setb	xtal		; zvys adresu at89cx501
	clr	xtal
	inc	dptr		; zvys adresu modelu
	mov	a,dph		; skontroluj adresu
	cjne	a,#vmargin,pcodewrite_l0
pcodeverify:			; kontrola pamate at89cx051
	acall	rst5v		; rst = 5 v
	setb	prog		; prog = 5 v
	clr	m0		; mod
	clr	m1
	setb	m2		; ok
	mov	dptr,#0		; zaklad adresy modelu
pcodeverify_l0:
	acall	vread		; precitaj byte z modelu
	xrl	a,pdata		; a porovnaj z at89cx501
				; ak acc != 0, chyba
	jnz	pcodeverify_error
	setb	xtal		; zvys adresu at89cx501
	clr	xtal
	inc	dptr		; zvys adresu modelu
	mov	a,dph		; skontroluj adresu
	cjne	a,#vmargin,pcodeverify_l0
	acall	poff		; vypinacia sekvencia
	clr	c		; zhod vlajku chyby
	ret
pcodeverify_error:
	acall	poff		; vypinacia sekvencia
	setb	c		; nastav vlajku chyby
	ret
	
pcoderead:			; citanie pamate at89cx051
	mov	dptr,#0		; zmaz 4 kib fram
	acall	vwrite_open	; otvor model
pcoderead_l1:
	mov	a,#0ffh		; vymazany bajt
	acall	vwrite_byte	; zapis bajt do modelu
	inc	dptr		; inkrementuj adresu
	mov	a,dph
	cjne	a,#10h,pcoderead_l1
	acall	vwrite_close	; zatvor model	
	setb	vccsw		; zapni napajanie
	acall	rst5v		; rst = 5 v
	setb	prog		; prog = 5 v
	mov	pdata,#0ffh	; pdata ako vstupy
	clr	m0		; mod
	clr	m1
	setb	m2		; ok
	mov	dptr,#0		; zaklad adresy modelu
pcoderead_l0:
	mov	a,pdata		; precitaj data
	acall	vwrite		; zapis do modelu
	setb	xtal		; zvys adresu at89cx501
	clr	xtal
	inc	dptr		; zvys adresu modelu
	mov	a,dph		; skontroluj adresu
	cjne	a,#vmargin,pcoderead_l0
	acall	poff		; vypinacia sekvencia
	ret	
	
plockwrite:			; zapis lock bitov at89cx501
	mov	a,vlocks
	jnb	acc.2,$+7	; test 1. lock bitu
	setb	m2		; nastav prislusny mod
	acall	plockwrite_l0	; a zapis
	jnb	acc.3,$+7	; test 2. lock bitu
	clr	m2		; nastav prislusny mod
	acall	plockwrite_l0	; a zapis
	ret	
plockwrite_l0:
	setb	vccsw		; zapni napajanie
	setb	prog		; prog = 5 v
	acall	rst5v		; rst = 5 v
	setb	m0		; mod
	setb	m1
	acall	rst12v		; rst = 12 v
	clr	prog		; 1 us prog pulz
	nop
	setb	prog		; ok
	clr	tf1		; cakaj na skoncenie zapisu
	mov	tl1,#low (65535 - 4000)
	mov	th1,#high (65535 - 4000)
	jnb	tf1,$	
	acall	poff		; vypinacia sekvencia
	ret	
	
perasechip:			; zmazanie pamate at89cx501
	setb	vccsw		; zapni napajanie
	acall	rst5v		; rst = 5 v
	setb	prog		; prog = 5 v
	setb	m0		; nastav mod
	clr	m1
	clr	m2		; ok
	acall	rst12v		; rst = 12 v
	clr	prog		; prog pulz 10 ms
	clr	tf1
	mov	tl1,#low (65535 - 20000)
	mov	th1,#high (65535 - 20000)
	jnb	tf1,$
	setb	prog		; ok
	acall	poff		; vypinacia sekvencia
	ret

; ----------------------------------------------------------------------
vwrite:	mov	b,a		; zapis 1 bajt do fram
	acall	vwrite_open
	mov	a,b
	acall	vwrite_byte
	acall	vwrite_close	; ok
	ret

vwrite_open:			; otvorenie fram pre zapis
	clr	frwp		; povol zapis	
	clr	frsda		; start
	clr	frscl		; adresa zariadenia
	mov	a,#10100000b
	acall	frsend
	mov	a,dph		; vrchny bajt adresy
	acall	frsend	
	mov	a,dpl		; spodny bajt adresy	
	acall	frsend
	ret			
vwrite_byte:			; zapis bajtu do fram
	acall	frsend
	ret
vwrite_close:			; zatvorenie fram
	setb	frscl		; stop
	setb	frsda
	setb	frwp		; zakaz zapis
	ret

frsend:	mov	frerr,#2	; pocet opakovani pri chybe
	mov	frct,#8		; posli 8 bitov
	mov	frtmp,a		; zalohuj data
frsend_l0:	
	rlc	a
	mov	frsda,c		; acc.7 na sda
	setb	frscl		; zapis
	clr	frscl
	djnz	frct,frsend_l0	; dalsi bit
	setb	frsda		; ack
	setb	frscl
	mov	c,frsda		; precitaj ack
	clr	frscl
	jc	frsend_retry	; vyhodnot ack
	ret			; zapis prebehol uspesne, skonci
frsend_retry:			; chyba zapisu
	djnz	frerr,$+5
	ajmp	fatal		; pocet pokusov vycerpany, fatalna chyba
	mov	frct,#8		; posli 8 bitov
	mov	a,frtmp		; obnov data zo zalohy
	ajmp	frsend_l0	; a znovu
	
vread:	acall	vwrite_open	; precitaj 1 bajt z fram
	setb	frwp		; zakaz zapis
	setb	frscl		; start
	clr	frsda
	clr	frscl
	mov	a,#10100001b	; adresa zariadenia
	acall	frsend
	mov	frct,#8		; prijmi 8 bitov
vread_l0:
	mov	c,frsda		; zober bit z sda
	rlc	a
	setb	frscl		; vypytaj dalsi bit
	clr	frscl
	djnz	frct,vread_l0
	setb	frsda		; no ack
	setb	frscl
	clr	frscl		; ok
	setb	frscl		; stop
	setb	frsda
	ret	
	
; ----------------------------------------------------------------------
	; neopravitelna chyba
fatal:	clr	ea		; zakaz vsetky prerusenia
	setb	green		; zhasni vsetky led
	setb	up
	setb	down
	setb	red
fatal_blink:
	mov	r0,#25		; blikaj cervenou led s periodou 0.5 s
	cpl	red
fatal_wait:
	clr	tf1
	mov	tl1,#low (65535 - 40000)
	mov	th1,#high (65535 - 40000)
	jnb	tf1,$
	djnz	r0,fatal_wait
	ajmp	fatal_blink	; cakaj do resetu

	end
