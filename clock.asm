	include "P16F690.inc"
	list p=16F690
	__CONFIG _INTRC_OSC_NOCLKOUT & _CP_OFF & _CPD_OFF & _FCMEN_OFF & _IESO_OFF & _BOR_OFF & _MCLRE_OFF & _WDT_OFF & _PWRTE_ON

;***** VARIABLE DEFINITIONS
delay_counter	EQU		0x70	; 
command_msb		EQU		0x71	; MSB of command to be sent on SPI bus.
command_lsb		EQU		0x72	; LSB of command to be sent on SPI bus.
last_input		EQU		0x73	; State of the input switches last time they were checked.
increment_arg	EQU		0x74	; Value to be incremented by increment_ functions.
second			EQU		0x20	; Current second in 2 digit 4-bit BCD.
minute			EQU		0x21	; Current minute in 2 digit 4-bit BCD.
hour			EQU		0x22	; Current hour in 2 digit 4-bit BCD.

;***** CONSTANT DEFINITIONS
DELAY_LOOPS		EQU		0xFF	; Number of loops through delay loop.
ENABLE			EQU		PORTB	; Port used for SPI enable lines.
MAX_E			EQU		5		; Bit used for MAX7219 Enable line.
CLOCK_E			EQU		7		; Bit used for DS1305 Enable line.
BUTTON			EQU		PORTA	; Port used for buttons to set time.
HOUR_B			EQU		2		; Bit used for hour button.
MINUTE_B		EQU		5		; Bit used for minute button.
SECOND_B		EQU		4		; Bit used for second button.

;***** DS1305 COMMANDS
READ_SECOND		EQU		0x00
READ_MINUTE		EQU		0x01
READ_HOUR		EQU		0x02
WRITE_SECOND	EQU		0x80
WRITE_MINUTE	EQU		0x81
WRITE_HOUR		EQU		0x82

main
	; Set 31kHz oscillator.
	BANKSEL	OSCCON
	bcf		OSCCON, 0x04
	bcf		OSCCON, 0x05
	bcf		OSCCON, 0x06

	; Disable A/D Converter
	BANKSEL ANSEL
	clrf	ANSEL
	clrf	ANSELH			; Deactivate A/D Converter

	; Enable SSP Module for SPI.
	BANKSEL	SSPCON
	movlw	0x20
	movwf	SSPCON
	BANKSEL SSPSTAT
	movlw	0xC0
	movwf	SSPSTAT

	; Set PORTB to output enable signals to peripherals.
	bsf		STATUS, RP0
	bsf		STATUS, RP1		; Bank 3
	movlw	0x10
	movwf	TRISB			; Set PORTB to output except PORTB<4> (SSPSDI).
	clrf	TRISC			; Set PORTC to output. (PORTC<7> is also SSPSDO).
	bcf		STATUS, RP0		; Bank 2
	clrf	PORTB			; Set port B to all 0s

	bsf		ENABLE, MAX_E	; Set MAX7219 enable high (since MAX7219 enable is active low).
	bcf		ENABLE, CLOCK_E	; Set CS1305 enable low (since DS1305 enable is active high).

	; Enable PORT A/B pull up resistors.
	BANKSEL OPTION_REG
	bcf		OPTION_REG, 0x07

	; Enable pull-up resistors for input switches.
	BANKSEL	WPUA
	movlw	0x34
	movwf	WPUA

	; Set PORT A as input.
	BANKSEL	TRISA
	movlw	0x34
	movwf	TRISA

	; Set last_input to show all buttons not-pressed. (all ones)
	movlw	0x34
	movwf	last_input

	; Send initilization commands to devices.

	; Set MAX7219 to normal operation
	movlw	0x0c
	movwf	command_msb
	movlw	0x01
	movwf	command_lsb
	call	send_to_max

	; Set MAX7219 to scan digits 0 through 5 inclusive.
	movlw	0x0b
	movwf	command_msb
	movlw	0x05
	movwf	command_lsb
	call	send_to_max

	; Set MAX7219 to full intensity
	movlw	0x0a
	movwf	command_msb
	movlw	0x0f
	movwf	command_lsb
	call	send_to_max

	; Set MAX7219 to decode digits 0 through 5 inclusive.
	movlw	0x09
	movwf	command_msb
	movlw	0x3f
	movwf	command_lsb
	call	send_to_max

	; Ensure write protect bit is clear on DS1305
	movlw	0x8f
	movwf	command_msb
	movlw	0x00
	movwf	command_lsb
	call	send_to_clock

	; Enable oscillator on DS1305
	movlw	0x8f
	movwf	command_msb
	movlw	0x00
	movwf	command_lsb
	call	send_to_clock


main_loop
	; Check if second button is pressed.
	BANKSEL BUTTON
	btfss	BUTTON, SECOND_B	
	call	reset_seconds		; If second button is pressed, call reset_seconds.

	; Check if minute button is pressed.
	BANKSEL BUTTON
	btfsc	last_input, MINUTE_B	; If the minute button was not pressed last time (last_input)
	btfsc	BUTTON, MINUTE_B		; AND minute button is pressed now THEN increment the minute.
	goto	after_check_minute		; Otherwise, skip over the code to increment the minute.
	movlw	READ_MINUTE
	movwf	command_msb
	call	recv_from_clock			; Read current minute from DS1305
	movf	command_lsb, W
	movwf	increment_arg	
	call 	increment_minute		; Increment the current minute mod 60
	movf	increment_arg, W
	movwf	command_lsb
	movlw	WRITE_MINUTE
	movwf	command_msb
	call	send_to_clock			; Write incremented minute to DS1305
after_check_minute

	; Check if hour button is pressed
	BANKSEL BUTTON
	btfsc	last_input, HOUR_B	; If the hour button was not pressed last time (last_input)
	btfsc	BUTTON, HOUR_B		; AND hour button is pressed now THEN increment the hour.
	goto	after_check_hour	; Otherwise, skip over the code to increment the hour.
	movlw	READ_HOUR					
	movwf	command_msb
	call	recv_from_clock		; Read current hour from DS1305
	movf	command_lsb, W
	movwf	increment_arg	
	call 	increment_hour		; Increment the current hour mod 24
	movf	increment_arg, W
	movwf	command_lsb
	movlw	WRITE_HOUR
	movwf	command_msb
	call	send_to_clock		; Write incremented hour to DS1305
after_check_hour

	; Save current state of buttons to last_input.
	BANKSEL	BUTTON
	movf	BUTTON, W
	movwf	last_input

	; Read current time from DS1305.
	call	read_time

	; Set digit 0 on display (10 Hour).
	movlw	0x01
	movwf	command_msb
	swapf	hour, w
	andlw	0x0f
	movwf	command_lsb
	call	send_to_max

	; Set digit 1 on the display (Hour).
	movlw	0x02
	movwf	command_msb
	movf	hour, w
	andlw	0x0f
	movwf	command_lsb
	call 	send_to_max

	; Set digit 2 on display (10 Minute).
	movlw	0x03
	movwf	command_msb
	swapf	minute, w
	andlw	0x0f
	movwf	command_lsb
	call	send_to_max

	; Set digit 3 on the display (Minute).
	movlw	0x04
	movwf	command_msb
	movf	minute, w
	andlw	0x0f
	movwf	command_lsb
	call 	send_to_max

	; Set digit 4 on display (10 Second).
	movlw	0x05
	movwf	command_msb
	swapf	second, w
	andlw	0x0f
	movwf	command_lsb
	call	send_to_max

	; Set digit 5 on the display (Second).
	movlw	0x06
	movwf	command_msb
	movf	second, w
	andlw	0x0f
	movwf	command_lsb
	call 	send_to_max

	; Repeat.
	goto	main_loop

halt_loop
	goto halt_loop			; Stop doing anything.

; Function that sends the 2-byte command in
; command_msb and command_lsb to the MAX7219.
send_to_max
	BANKSEL	ENABLE
	bcf		ENABLE, MAX_E	; Enable MAX7219
	
	; Send MSB
	BANKSEL	SSPBUF
	movf	command_msb, W	; Move command to W
	movwf	SSPBUF			; Move command to SSPBUF
	call	wait_ssp		; Wait until SSPBUF is ready.
	BANKSEL	SSPBUF
	movf	SSPBUF, W		; Discard received data.

	; Send LSB
	BANKSEL	SSPBUF
	movf	command_lsb, W	; Move command to W
	movwf	SSPBUF			; Move command to SPPBUF
	call	wait_ssp		; Wait until SSPBUF is ready.
	BANKSEL	SSPBUF
	movf	SSPBUF, W		; Discard received data.

	BANKSEL	ENABLE
	bsf		ENABLE, MAX_E	; Latch data in MAX7219

	return

; Function that writes the byte command_lsb
; to the address command_msb in the DS1305.
send_to_clock

	BANKSEL	ENABLE
	bsf		ENABLE, CLOCK_E	; Enable DS1305

	movf	command_msb, W	; Move address to W
	movwf	SSPBUF			; Move address to SSPBUF
	call	wait_ssp		; Wait until SSPBUF is ready.
	BANKSEL	SSPBUF
	movf	SSPBUF, W		; Discard received data.

	; Send LSB
	BANKSEL	SSPBUF
	movf	command_lsb, W	; Move data to W
	movwf	SSPBUF			; Move data to SPPBUF
	call	wait_ssp		; Wait until SSPBUF is ready.
	BANKSEL	SSPBUF
	movf	SSPBUF, W		; Discard received data.

	BANKSEL ENABLE
	bcf		ENABLE, CLOCK_E	; Latch data in DS1305

	return

; Function that reads the byte at address command_msb
; in the DS1305 and stores it in command_lsb.
recv_from_clock

	BANKSEL	ENABLE
	bsf		ENABLE, CLOCK_E	; Enable DS1305

	movf	command_msb, W	; Move address to W
	movwf	SSPBUF			; Move address to SSPBUF
	call	wait_ssp		; Wait until SSPBUF is ready.
	BANKSEL	SSPBUF
	movf	SSPBUF, W		; Discard received data.

	; Send LSB
	BANKSEL	SSPBUF
	movlw	0x00			; Move zeros to W
	movwf	SSPBUF			; Move zeros to SPPBUF
	call	wait_ssp		; Wait until SSPBUF is ready.
	BANKSEL	SSPBUF
	movf	SSPBUF, W		; Move received data to W.
	movwf	command_lsb		; Store it in command_lsb.

	BANKSEL ENABLE
	bcf		ENABLE, CLOCK_E	; Finished with DS1305

	return

; Function that reads the time from the DS1305 and stores it in:
; second, minute, and hour.

read_time
	BANKSEL	ENABLE
	bsf		ENABLE, CLOCK_E	; Enable DS1305

	; Send starting address to DS1305.
	movlw	0
	movwf	SSPBUF
	call	wait_ssp
	BANKSEL	SSPBUF
	movf	SSPBUF, W

	; Get the current seconds. (Address 0)
	movlw	0
	movwf	SSPBUF
	call	wait_ssp
	BANKSEL	SSPBUF
	movf	SSPBUF, W
	movwf	second	

	; Get the current minutes. (Address 1)
	movlw	0
	movwf	SSPBUF
	call	wait_ssp
	BANKSEL	SSPBUF
	movf	SSPBUF, W
	movwf	minute

	; Get the current hours. (Address 2)
	movlw	0
	movwf	SSPBUF
	call	wait_ssp
	BANKSEL	SSPBUF
	movf	SSPBUF, W
	movwf	hour

	BANKSEL	ENABLE
	bcf		ENABLE, CLOCK_E	; Finished with DS1305

	return	

; Resets the seconds to 0 on the DS1305.
reset_seconds
	movlw	WRITE_SECOND
	movwf	command_msb
	movlw	0
	movwf	command_lsb
	call	send_to_clock
	return

; Increments a BCD value mod 0x24. (Result will be between 0x00 and 0x23)
; Assumes the input is a BCD less than 0x24.
increment_hour
	call	increment_bcd			; Increment the value
	movf	increment_arg, W		; Copy the result to W
	sublw	0x24					; Subtract 0x24 from the incremented number.
	btfss	STATUS, Z				; if the result is not zero:
	return							; return the original result.
	movlw	0						; Otherwise, return 0 (= 24 mod 24)
	movwf	increment_arg
	return

; Increments a BCD value mod 0x60. (Result will be between 0x00 and 0x59)
; Assumes the input is a BCD less than 0x60.
increment_minute
	call	increment_bcd			; Increment the value
	movf	increment_arg, W		; Copy the result to W
	sublw	0x60					; Subtract 0x60 from the incremented number.
	btfss	STATUS, Z				; if the result is not zero:
	return							; return the original result.
	movlw	0						; Otherwise, return 0 (= 60 mod 60)
	movwf	increment_arg
	return

; Increments a 2 digit BCD value (8 bits).
; Assumes the input is a BCD less than 0x99.
increment_bcd
	incf	increment_arg, F		; Increment the value in increment_arg.
	btfsc	increment_arg, 0x01		; If either bit 0x01
	btfss	increment_arg, 0x03		; OR bit 0x03 are not set then return
	return							; Otherwise, the ones digit is 0xA. so:
	movf	increment_arg, W
	andlw	0xf0					; Zero the ones digit.
	addlw	0x10					; Increment the tens digit.
	movwf	increment_arg
	return

; Wait for SSPBUF
wait_ssp
	bsf		STATUS, RP0
	bcf		STATUS, RP1		; Bank 1
	btfss	SSPSTAT, BF		; Is the SSPBUF register available?
	goto	wait_ssp		; No: Continue waiting.
	return					; Yes: Return.

; Delay loop
delay
	movlw	DELAY_LOOPS
	movwf	delay_counter
delay_loop_start
	nop
	nop

	decfsz	delay_counter, f
	goto	delay_loop_start
	return

	end