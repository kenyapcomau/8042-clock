;
; If debug == 1 then time constants are lowered for faster simulation
; Also port 2 low nybble is virtually used to simulate buttons because
; s48 simulator has no commands to change interrupt and test input "pins"
;
.equ	debug,		0

; 8042 7 segment clock

; This code is under MIT license. Ken Yap

;;;;;;;;;;;;;;;;;;;;;;;;;;

.ifdef	.__.CPU.		; if we are using as8048 this is defined
.8041
.area	CODE	(ABS)
.endif	; .__.CPU.

; if 1 a blink program will be executed instead
.equ	blinktest,	0

; 0 = mains frequency input on I pin, 1 = free running, no mains input
.equ	intxtal,	1	; MCU clock

; 0 = driving multiplexed display, 1 = using TM1637 serial display
.equ	tm1637,		1

; 0 = no brightness control, 1 = both buttons = cycle brightness
.equ	brightcontrol,	1

; 0 = 0 bit turns on, 1 = 1 bit turns on segment, direct drive only
.equ	highison,	1	; using 7406 inverting buffer

; timing information.
; clk / 5 -- ale (osc / 15). "provided continuously" (pin 11)
; ale / 32 -- "normal" timer rate (osc / 480).
; set timer count, tick = period x timerdiv

.if	debug == 1
.if	blinktest == 1
.else				; but only if not blink program
.equ	timerdiv,	3	; speed up simulation
.endif	; blink
.else
.equ	timerdiv,	100	; 250 Hz with 12.000 MHz crystal
;.equ	timerdiv,	100	; 200 Hz with 9.600 MHz crystal
;.equ	timerdiv,	64	; 200 Hz with 6.144 MHz crystal
;.equ	timerdiv,	50	; 250 Hz with 6.000 MHz crystal
;.equ	timerdiv,	44	; 240 Hz with 5.0688 MHz crystal
;.equ	timerdiv,	40	; 256 Hz with 4.9152 MHz crystal
;.equ	timerdiv,	32	; 240 Hz with 3.6864 MHz crystal
.endif	; debug
.equ	tcount,		-timerdiv

.equ	scanfreq,	250	; resulting scan frequency, see above

; these are in 1/100ths of second, multiply by scanfreq to get counts
.equ	depmin,		scanfreq*10/100	; down 1/10th s to register
.equ	rptthresh,	scanfreq*50/100	; repeat kicks in at 1/2 s
.equ	rptperiod,	scanfreq*25/100	; repeat 4 times / second

; number of digits to scan, always 4 for this clock
; note: we always store 6 digits of time
.equ	scancnt,	4

; p1.0 thru p1.7 drive segments when driving with edge triggered latch
; p2.0 thru p2.3 are used in debug mode in simulator, not physically
; p2.4 thru p2.7 drive digits when driving directly. or TM1637
; t0 set minutes
; t1 set hours
; both change brightness
.equ	p21,		0x02
.equ	p22,		0x04
.equ	p22rmask,	~p22
.equ	p23,		0x08
.equ	p23rmask,	~p23
.equ	swmask,		p23|p22

.if	tm1637 == 1
;
; for driving TM1637 based display with 2 lines
;
.equ	data1mask,	0x80	; p2.7
.equ	data0mask,	~data1mask&0xff
.equ	clk1mask,	0x40	; p2.6
.equ	clk0mask,	~clk1mask&0xff
.equ	colon1mask,	0x80	; colon is top bit

; 0 = no blink on p2.5, 1 = blink, used for verification when TM1637 used
.equ	blinkp25,	1
.equ	blink1mask,	0x20	; p2.5
.equ	blink0mask,	~blink1mask
.equ	minbright,	0x88	; 1/16th brightness
.equ	maxbright,	0x8f	; 14/16 brightness (why not full?)
.equ	defbright,	(maxbright+minbright)/2
.else
.equ	minbright,	0x0	; min brightness
.equ	maxbright,	0x7	; full brightness
.equ	defbright,	(maxbright+minbright)/2
.endif	; tm1637

; scan digit storage (6 digits)
; sds1 seconds 1's digit
; sds2 seconds 10's digit
; sdm1 minutes 1's digit
; sdm2 minutes 10's digit
; sdh1 hours 1's digit
; sdh2 hours 10's digit

.equ	sds1,		0x20
.equ	sds2,		0x21
.equ	sdm1,		0x22
.equ	sdm2,		0x23
.equ	sdh1,		0x24
.equ	sdh2,		0x25

; current display digit storage
.equ	scand,		0x26
.equ	currbright,	0x27

.if	scancnt == 4
.equ	scanbase,	sdm1
.else
.equ	scanbase,	sds1
.endif	; scancnt

.equ	swstate,	0x28	; previous state of switches
.equ	swtent,		0x29	; tentative state of switches
.equ	swmin,		0x2a	; count of how long state has been stable
.equ	mrepeat,	0x2c	; repeat counter for minutes up
.equ	hrepeat,	0x2d	; repeat counter for hours up
.equ	brightthresh,	0x2e	; store point at which display turns off

; saved PSW for checking previous F0
.equ	savepsw,	0x2f

.equ	clockoff,	0x30	; put clock values at top of RAM

.equ	sr,		0+clockoff
.equ	sra,		1+clockoff
.equ	mr,		2+clockoff
.equ	mra,		3+clockoff
.equ	hr,		4+clockoff
.equ	hra,		5+clockoff

.equ	tickcounter,	0x3e

.if	debug == 1
.equ	counthz,	2	; speed up simulation
.else
.equ	counthz,	50	; "mains" frequency, must suit scanfreq
.endif	; debug

; divide tick to get mains frequency
.if	debug == 1
.equ	counttick,	2	; speed up simulation
.else
.equ	counttick,	scanfreq/counthz	; should be integer
.endif	; debug

; location doubles as powerfail indicator
.equ	powerfail,	0x3e

.equ	hzcounter,	0x3f

.equ	colonplace,	2	; hours serves colon

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; reset vector 
	.org	0
.if	blinktest == 1
	jmp	blink
.else
	jmp	ticktock
.endif	; blinktest

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; external interrupt vector (pin 6) not used
	.org	3
	dis	i
	retr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; timer interrupt vector
; scan order is from msd to lsd
; scancnt == 6 -- hours minutes seconds
; scancnt == 4 -- hours minutes
; r7 saved a to restore on retr
; r6 digit index 0-3
; r5 saved low nybble of p2
; r4 colon state in high bit
	.org	7
	sel	rb1
	mov	r7, a		; save a
	mov	a, #tcount	; restart timer
	mov	t, a
	strt	t
.if	tm1637 == 1
				; no interrupt work, TM1637 handles display
.else
	anl	p1, #0x00	; turn off all segments
; work out if we need to turn on colon
	mov	r0, #hzcounter
	mov	a, @r0
	add	a, #256-(counthz/2)
.ifdef	mains
	jc	firsthalf	; in first half of second
	mov	r0, #powerfail	; make colon 3/4 second on before buttons used
	add	a, @r0
firsthalf:
.endif	; mains
; C means in first half of second or first 3/4 if buttons not used yet
	mov	r0, #scand
	mov	a, @r0
	dec	a
	mov	@r0, a
	jnz	nextdigit	; if zero, restore our count
	mov	@r0, #scancnt
nextdigit:
.if	scancnt == 4
	anl	a, #0x03	; restrict to 0-3
.else
	anl	a, #0x07	; restrict to 0-7
.endif	; scancnt
	mov	r6, a		; save digit index
	xrl	a, #colonplace
	jz	colonhere
	clr	c		; colon not on this digit
colonhere:
	clr	a
	rrc	a		; a7 <- C
.if	highison == 1
.else
	cpl	a
.endif	; highison
	mov	r4,a		; save colon
	in	a, p2		; get p2 state
	anl	a, #0x0f	; low nybble
	orl	a, #0xf0
	mov	r5, a		; save
	mov	a, r6		; retrieve digit index
	add	a, #digit2mask-page3
	movp3	a, @a
	anl	a, r5		; preserve low nybble
	outl	p2, a
	mov	a, r6		; retrieve digit index
	add	a, #scanbase	; index into the 7 segment storage
	mov	r0, a
	mov	a, @r0
.if	highison == 1
	orl	a, r4		; r4 contains 0x0 or 0x80
.else
	anl	a, r4		; r4 contains 0xff or 0x7f
.endif	; highison
	outl	p1, a		; output digit
.endif	; tm1637
	mov	a, r7		; restore a
	retr

; switch handling
; t0 low is set minutes, hold to start, then hold to repeat
; t1 low is set hours, hold to start, then hold to repeat
; convert to bitmask to easily detect change
; use p2.2 and p2.3 to emulate for debugging
switch:
.if	debug == 1
	in	a, p2
.else
	mov	a, #0xff
	jt0	not0
	anl	a, #p22rmask
not0:
	jt1	not1
	anl	a, #p23rmask
not1:
.endif	; debug
	anl	a, #swmask	; isolate switch bits
	mov	r7, a		; save a copy
	mov	r0, #swtent
	xrl	a, @r0		; compare against last state
	mov	r0, #swmin
	jz	swnochange
	mov	@r0, #depmin	; reload timer
	mov	r0, #swtent
	mov	a, r7
	mov	@r0, a		; save current switch state
	ret
swnochange:
	mov	a, @r0		; check timer
	jz	swaction
	dec	a
	mov	@r0, a
	ret
swaction:
.if	brightcontrol == 1
	call	incbright
	jc	swactioned	; both buttons were down, just brightness
.endif	; brightcontrol
	call	incmin
	call	inchour
swactioned:
.ifdef	mains
	mov	r0, #powerfail	; button was clicked
	mov	@r0, #0
.endif	; mains
	mov	r0, #swtent
	mov	a, @r0
	mov	r0, #swstate
	mov	@r0, a
	ret

incmin:
	mov	r0, #swtent
	mov	a, @r0
	jb2	noincmin	; first time through?
	mov	r0, #swstate
	mov	a, @r0
	jb2	inc1min
	mov	r0, #mrepeat
	mov	a, @r0
	jz	minwaitover
	dec	a
	mov	@r0, a
	ret
minwaitover:
	mov	r0, #mrepeat
	mov	@r0, #rptperiod
inc1min:
	mov	r0, #mr
	mov	a, @r0
	inc	a
	mov	@r0, a
	add 	a, #196		; test for 60 minute overflow
	jnc 	mindone
	mov	@r0, #0		; yep overflow, reset to zero and update display
mindone:
	mov	r0, #sr
	mov	@r0, #0
	call 	updatedisplay
	ret
noincmin:
	mov	r0, #mrepeat
	mov	@r0, #rptthresh
	ret

inchour:
	mov	r0, #swtent
	mov	a, @r0
	jb3	noinchour	; first time through?
	mov	r0, #swstate
	mov	a, @r0
	jb3	inc1hour
	mov	r0, #hrepeat
	mov	a, @r0
	jz	hourwaitover
	dec	a
	mov	@r0, a
	ret
hourwaitover:
	mov	r0, #hrepeat
	mov	@r0, #rptperiod
inc1hour:
	mov	r0, #hr
	mov	a, @r0
	inc	a
	mov	@r0, a
	add 	a, #232
	jnc 	hourdone
	mov	@r0, #0		; yep overflow, reset to zero and update display
hourdone:
	call 	updatedisplay
	ret
noinchour:
	mov	r0, #hrepeat
	mov	@r0, #rptthresh
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	.org	0x100
ticktock:
	clr	f0		; zero some registers and other cold boot stuff
	sel	rb0
.if	tm1637 == 1
.else
	mov 	r0, #scand	; set up digit scan parameters
	mov 	@r0, #scancnt
.endif	; tm1637
	mov	a, #0xff
	outl	p2, a		; p2 is all input
	anl	a, #swmask	; isolate switch bits
	mov	r0, #swstate
	mov	@r0, a
	mov	r0, #swtent
	mov	@r0, a
	mov	r0, #swmin	; preset switch depression counts
	mov	@r0, #depmin
	mov	r0, #mrepeat	; and repeat thresholds
	mov	@r0, #rptthresh
	mov	r0, #hrepeat
	mov	@r0, #rptthresh
; set 12:34:56 as initial data
	mov	r0, #sr
	mov	@r0, #56
	mov	r0, #mr
	mov	@r0, #34
	mov	r0, #hr
	mov	@r0, #12
.if	brightcontrol == 1
	mov	r0, #currbright
	mov	a, #defbright
	mov	@r0, a
	call	setbright
.endif	; brightcontrol
	call	updatedisplay
.ifdef	mains
	mov	r0, #powerfail
	mov	@r0, #counthz/4	; so colon blink is asymmetric on power up
	mov	a, psw		; initialise saved psw
	mov	r0, #savepsw
	mov	@r0, a
.endif	; mains
	mov	r0, #tickcounter
	mov	@r0, #counttick
	mov	r0, #hzcounter
	mov	@r0, #counthz
	mov	a, #tcount	; setup timer and enable its interrupt
	mov	t, a
	strt	t
	en	tcnti

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; main loop
workloop:
	jtf	ticked
.if	tm1637 == 1
.else
.if	brightcontrol == 1	; PWM method
	mov	r0, #brightthresh
	mov	a, t
	add	a, @r0
	jb7	leaveon
.if	highison == 1
	anl	p1, #0x00
.else
	orl	p1, #0xff
.endif	; highison
leaveon:
.endif	; brightcontrol
.endif	; tm1637
	jmp	workloop	; wait until tick is up
ticked:
	call	tickhandler
	jnc	noadv
	call	incsec
	call	updatedisplay
.if	tm1637 == 1
.if	blinkp25 == 1
	orl	p2, #blink1mask	; turn off blink
.endif	; blinkp25
.endif	; tm1637
noadv:
	call	switch
	jmp	workloop

; called once per tick
tickhandler:
	clr	c
	clr	f0
.ifdef	mains
.if	debug == 1
	in	a, p2		; simulate mains frequency with p21 on simulator
	anl	a, #p21
	jz	intlow
.else
	jni	intlow
.endif	; debug
	mov	r0, #savepsw
	mov	a, psw		; save f0 state
	mov	@r0, a		; f0 is !I
	ret
intlow:
	cpl	f0		; f0 is !I
	mov	r0, #savepsw	; was f0 previously 0?
	mov	a, @r0
	jb5	igntick		; transition already seen
	mov	a, psw		; save f0 state to turn on
	mov	@r0, a
.endif	; mains
	mov	r0, #tickcounter
	mov	a, @r0
	dec	a
	mov	@r0, a
	jnz	igntick		; tick to 1/Hz-th
	mov	@r0, #counttick
.if	tm1637 == 1
	mov	r0, #hzcounter
	mov	a, @r0
	xrl	a, #counthz/2	; halfway through second?
	jnz	nocolon
	mov	r0, #sdm1+colonplace
	mov	a, @r0
	orl	a, #colon1mask
	mov	@r0, a		; modify digit register but will only last 1/2 s
	call	updatetm1637
.if	blinkp25 == 1
	anl	p2, #blink0mask	; pull low to turn on
.endif	; blinkp25
nocolon:
.endif	; tm1637
	mov	r0, #hzcounter
	mov	a, @r0
	dec	a
	mov	@r0, a
	jnz	igntick
	mov	@r0, #counthz	; reinitialise Hz counter
	cpl	c		; set carry if second up
igntick:
	ret

; increment second and carry to minute and hour on overflow
incsec:
	mov 	r0, #sr
	mov	a, @r0
	inc	a
	mov	@r0, a
	add 	a, #196
	jnc 	noover
	mov	@r0, #0		; reset secs to 0
	mov	r0, #mr
	mov	a, @r0
	inc	a
	mov	@r0, a
	add	a, #196
	jnc	noover
	mov	@r0, #0		; reset mins to 0
	mov	r0, #hr
	mov	a, @r0
	inc	a
	mov	@r0, a
	add	a, #232
	jnc	noover
	mov	@r0, #0		; reset hours to 0
noover:
	ret

; convert binary values to segment patterns
updatedisplay:
	mov 	r1, #sr
	mov	a, @r1
	mov 	r1, #sds1
	call	byte2segment
	mov	r1, #mr
	mov 	a, @r1
	mov 	r1, #sdm1
	call	byte2segment
	mov	r1, #hr
	mov 	a, @r1
	mov 	r1, #sdh1
	call	byte2segment
.if	tm1637 == 1
	jmp	updatetm1637
.else
	ret
.endif	; tm1637

	.org	0x200

page2:
;
; TM1637 handling routines translated from C code at
; https://blog.3d-logic.com/2015/01/21/arduino-and-the-tm1637-4-digit-seven-segment-display/
;
.if	tm1637 == 1
updatetm1637:
	call	startxfer
	mov	a, #0x40
	call	writebyte
	call	stopxfer
	call	startxfer
	mov	a, #0xc0
	call	writebyte
	mov	r0, #sdh2
	mov	a, @r0
	call	writebyte
	mov	r0, #sdh1
	mov	a, @r0
	call	writebyte
	mov	r0, #sdm2
	mov	a, @r0
	call	writebyte
	mov	r0, #sdm1
	mov	a, @r0
	call	writebyte
	call	stopxfer
	ret

;
; Byte to write in A, destructive
;
writebyte:
.if	debug == 1		; don't actually write anything
.else
	mov	r6, #8
writebit:
	anl	p2, #clk0mask
	call	fiveus
	rrc	a
	jc	useor
	anl	p2, #data0mask	; turn bit off
	jmp	wrotebit
useor:
	orl	p2, #data1mask	; turn bit on
wrotebit:
	call	fiveus
	orl	p2, #clk1mask
	call	fiveus
	djnz	r6, writebit

	anl	p2, #clk0mask
	call	fiveus
	orl	p2, #data1mask
	orl	p2, #clk1mask
	call	fiveus
	in	a, p2
.endif	; debug
	ret			; ack in A

startxfer:
	orl	p2, #clk1mask
	orl	p2, #data1mask
	call	fiveus
	anl	p2, #data0mask
	anl	p2, #clk0mask
	call	fiveus
	ret

stopxfer:
	anl	p2, #clk0mask
	anl	p2, #data0mask
	call	fiveus
	orl	p2, #clk1mask
	orl	p2, #data1mask
	call	fiveus
	ret

; The call and return should take at least 5 us

fiveus:
	ret

setbright:
	call	startxfer	; desired brightness in a
	call	writebyte
	call	stopxfer
	ret

.else

setbright:
	mov	r0, #currbright
	mov	a, @r0
	add	a, #brighttable-page2
	movp	a, @a
	mov	r0, #brightthresh
	mov	@r0, a
	ret

.endif	; tm1637

.if	brightcontrol == 1
incbright:
	clr	c
	mov	r0, #swtent
	mov	a, @r0
	jnz	noincbright	; both buttons down?
	mov	r0, #swstate
	mov	a, @r0
	jz	nosingle	; buttons still down?
	mov	r0, #currbright	; one or both were up so first time
	mov	a, @r0
	xrl	a, #maxbright	; wrap around to minimum
	jnz	incbright1
	mov	a, #minbright
	mov	@r0, a
	jmp	setbright1
incbright1:
	mov	a, @r0
	inc	a
	mov	@r0, a
setbright1:
	call	setbright
nosingle:			; don't trigger any single actions
	clr	c
	cpl	c
noincbright:
	ret

.if	tm1637 == 1
.else
brighttable:			; only for direct drive
	.db	timerdiv-timerdiv/16
	.db	timerdiv-(timerdiv*2)/16
	.db	timerdiv-(timerdiv*4)/16
	.db	timerdiv-(timerdiv*11)/16
	.db	timerdiv-(timerdiv*12)/16
	.db	timerdiv-(timerdiv*13)/16
	.db	timerdiv-(timerdiv*14)/16
	.db	timerdiv-timerdiv
.endif	; tm1637

.endif	; brightcontrol

.if	blinktest == 1
;
; short program to check chip works
;
.equ	p25on,		0xdf
.equ	p25off,		0xff
.equ	delaycount,	scanfreq/2

blink:
	mov	a, #p25on
	outl	p2, a
	call	delay500ms
	mov	a, #p25off
	outl	p2, a
	call	delay500ms
	jmp	blink

delay500ms:
	mov	r0, #delaycount
another4ms:
	mov	a, #tcount	; restart timer
	mov	t, a
	strt	t
busy4ms:
	jtf	done4ms
	jmp	busy4ms
done4ms:
	stop	tcnt
	djnz	r0, another4ms
	ret
.endif	; blinktest

;
; Tables and lookup routines
;
	.org	0x300

page3:

; BCD lookup table
; movp3 a, @a reads this table entry into accumulator.
; Must org this at "page 3" (1 "page" is 256 bytes)
; We could use the double-dabble algorithm
; but we are not short of ROM storage, we can spare 61 bytes
	.db	0
	.db 	1
	.db	2
	.db	3
	.db	4
	.db	5
	.db	6
	.db	7
	.db	8
	.db	9
	.db	0x10	; bcd ten.
	.db	0x11
	.db	0x12
	.db	0x13
	.db	0x14
	.db	0x15
	.db	0x16
	.db	0x17
	.db	0x18
	.db	0x19
	.db	0x20	; bcd twenty. etc...
	.db	0x21
	.db	0x22
	.db	0x23
	.db	0x24
	.db	0x25
	.db	0x26
	.db	0x27
	.db	0x28
	.db	0x29
	.db	0x30
	.db	0x31
	.db	0x32
	.db	0x33
	.db	0x34
	.db	0x35
	.db	0x36
	.db	0x37
	.db	0x38
	.db	0x39
	.db	0x40
	.db	0x41
	.db	0x42
	.db	0x43
	.db	0x44
	.db	0x45
	.db	0x46
	.db	0x47
	.db	0x48
	.db	0x49
	.db	0x50
	.db	0x51
	.db	0x52
	.db	0x53
	.db	0x54
	.db	0x55
	.db	0x56
	.db	0x57
	.db	0x58
	.db	0x59
	.db	0x60	; for leap seconds

; font table. (beware of 8048 movp "page" limitation)
; 1's for lit segment since this turns on cathodes
; MSB=colon LSB=a
; entries for 10-15 are for blanking
; second half of each table is for 6 segments, add 16 to get there

dfont:
.if	highison == 1
	.db	0x3f	; 0
	.db	0x06	; 1
	.db	0x5b
	.db	0x4f
	.db	0x66
	.db	0x6d
	.db	0x7d
	.db	0x07
	.db	0x7f
	.db	0x6f
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
.else
	.db	~0x3f	; 0
	.db	~0x06	; 1
	.db	~0x5b
	.db	~0x4f
	.db	~0x66
	.db	~0x6d
	.db	~0x7d
	.db	~0x07
	.db	~0x7f
	.db	~0x6f
	.db	~0x00
	.db	~0x00
	.db	~0x00
	.db	~0x00
	.db	~0x00
	.db	~0x00
.endif	; highison

; convert byte to 7 segment
; a - input, r1 -> 2 byte storage

byte2segment:
	movp3 	a, @a		; convert from binary to bcd
	mov 	r7, a		; save converted bcd digits
	anl 	a, #0xf		; get units
	add 	a, #dfont-page3	; index into font table
	movp3 	a, @a		; grab font for this digit
	mov 	@r1, a		; save it
	inc	r1
	mov 	a, r7		; restore bcd digits
	swap 	a
	anl 	a, #0xf
	add 	a, #dfont-page3	; index into font table
	movp3 	a, @a		; grab font for this digit
	mov 	@r1, a		; save it
	ret

.if	tm1637 == 1		; not needed for external display
.else
; convert digit number 0-3 to for port 2 high nybble
digit2mask:
	.db	~0x10		; p2.4 is min
	.db	~0x20		; p2.5 is 10 min
	.db	~0x40		; p2.6 is hour
	.db	~0x80		; p2.7 is 10 hour
	.db	~0x00		; just in case scancnt == 6 in future
	.db	~0x00
	.db	~0x00
	.db	~0x00
.endif	; tm1637

ident:
	.db	0x0
	.db	0x4b, 0x65, 0x6e
	.db	0x20
	.db	0x59, 0x61, 0x70
	.db	0x20
	.db	0x32, 0x30	; 20
	.db	0x31, 0x39	; 19
	.db	0x0

; end
