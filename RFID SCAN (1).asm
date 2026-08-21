;******************************************************************************
;  MSP430FR69x Demo - RFID 
;
;   Kidus Abbay, Aiden Buchanan
;   April 2026
;******************************************************************************
    ;-------------------------------------------------------------------------------
                .cdecls C,LIST,"msp430.h"       ; Include device header file
    ;-------------------------------------------------------------------------------
                .def    RESET                   ; Export program entry-point to
                                                ; make it known to linker.

    ;--- MFRC522 Register Map (all addresses are 6-bit; shifted left 1 in protocol) ---
CommandReg      .equ    0x01                    ; Starts/stops command execution
ComIEnReg       .equ    0x02                    ; Enable/disable interrupt request bits
ComIrqReg       .equ    0x04                    ; Interrupt request bits
ErrorReg        .equ    0x06                    ; Error bits
FIFODataReg     .equ    0x09                    ; In/out of 64-byte FIFO buffer
FIFOLevelReg    .equ    0x0A                    ; Number of bytes in FIFO
ControlReg      .equ    0x0C                    ; Miscellaneous control bits
BitFramingReg   .equ    0x0D                    ; Bit-oriented frames
CollReg         .equ    0x0E                    ; Collision register
ModeReg         .equ    0x11                    ; General mode for transmitting/receiving
TxModeReg       .equ    0x12                    ; Data rate during transmission
RxModeReg       .equ    0x13                    ; Data rate during reception
TxControlReg    .equ    0x14                    ; Antenna driver pins
TxASKReg        .equ    0x15                    ; Force 100% ASK modulation
ModWidthReg     .equ    0x24                    ; Miller modulation width
TModeReg        .equ    0x2A                    ; Timer settings
TPrescalerReg   .equ    0x2B                    ; Timer prescaler
TReloadRegH     .equ    0x2C                    ; Timer reload high byte
TReloadRegL     .equ    0x2D                    ; Timer reload low byte
VersionReg      .equ    0x37                    ; Software version

                .bss    tag_storage, 10         ; INDENT REQUIRED: 4 bytes tag, 4 bytes passcode, 2 flags
; Offsets for clarity
tag_data_ptr    .equ    0
passcode_ptr    .equ    4
tag_valid_f     .equ    8
passcode_set_f  .equ    9

delay           .macro  count
                mov     #count, R15
                dec     R15
                jnz     $-2
                .endm

CS_HIGH         .macro
                bis.b   #BIT5, &P1OUT
                .endm

CS_LOW          .macro
                bic.b   #BIT5, &P1OUT
                .endm

rfid_write      .macro  address, data
                mov.b   #address, R15
                mov.b   data, R14
                call    #rfid_write_sr
                .endm

rfid_read       .macro  address, dst
                mov.b   #address, R15
                call    #rfid_read_sr
                mov.b   &UCB1RXBUF, dst
                .endm

bic_reg         .macro  address, mask
                rfid_read   address, R14
                bic.b       mask, R14
                rfid_write  address, R14
                .endm

bis_reg         .macro  address, mask
                rfid_read   address, R14
                bis.b       mask, R14
                rfid_write  address, R14
                .endm

    ;-------------------------------------------------------------------------------
                .global _main
                .global __STACK_END
                .sect   .stack

                .text
                .retain
                .retainrefs

_main
RESET           mov.w   #__STACK_END,SP          ; Initialize stackpointer
StopWDT         mov.w   #WDTPW+WDTHOLD,&WDTCTL   ; Stop watchdog timer

SetupGPIO       bic.b   #BIT0,&P1OUT             ; red LED
                bis.b   #BIT0,&P1DIR

                bic.b   #BIT7,&P9OUT             ; green LED
                bis.b   #BIT7,&P9DIR

                bis.b   #BIT5+BIT3, &P1DIR
                bic.b   #BIT0+BIT1,&P3SEL1
                bis.b   #BIT0+BIT1,&P3SEL0
                bis.b   #BIT7, &P4SEL1
                bic.b   #BIT7, &P4SEL0

                bis.b   #BIT5,&P1OUT
                bis.b   #BIT3,&P1OUT

                bic.b   #BIT1,&P1DIR             ; left button
                bis.b   #BIT1,&P1REN             ; pull resistor
                bis.b   #BIT1,&P1OUT             ; pull up

                mov.w   #UCSWRST,&UCB1CTLW0
                bis.w   #UCCKPH+UCMSB+UCSYNC+UCMST+UCSSEL__SMCLK,&UCB1CTLW0
                mov.w   #2,&UCB1BRW
                bic.w   #UCSWRST,&UCB1CTLW0

UnlockGPIO      bic.w   #LOCKLPM5,&PM5CTL0       ; Disable the GPIO power-on default
                                                 ; high-impedance mode to activate
                                                 ; previously configured port settings

                                                 
                mov.b   #0, &tag_storage+tag_valid_f       ; clear tag valid flag
                mov.b   #0, &tag_storage+passcode_set_f    ; clear passcode set flag

Mainloop:
                rfid_write  CommandReg, #0x0F    ; Reset the chip
                delay       50000                ; wait a little bit!

                ; Write default values to registers
                rfid_write  TxModeReg,      #0x00
                rfid_write  RxModeReg,      #0x00
                rfid_write  ModWidthReg,    #0x26
                rfid_write  TModeReg,       #0x80
                rfid_write  TPrescalerReg,  #0xA9
                rfid_write  TReloadRegH,    #0x03
                rfid_write  TReloadRegL,    #0xE8
                rfid_write  TxASKReg,       #0x40
                rfid_write  ModeReg,        #0x3D

                bis_reg     TxControlReg, #0x03

ReadLoop:
                mov.b       #0, &tag_storage+tag_valid_f   ; clear valid tag flag

                ; Flush and send REQA (0x26, 7-bit short frame)
                rfid_write  CommandReg,     #0x00   ; idle
                rfid_write  ComIrqReg,      #0x7F   ; clear IRQ flags
                rfid_write  FIFOLevelReg,   #0x80   ; flush FIFO
                rfid_write  BitFramingReg,  #0x07   ; 7-bit last byte
                rfid_write  FIFODataReg,    #0x26   ; REQA
                rfid_write  CommandReg,     #0x0C   ; Transceive

                ; Set StartSend
                bis_reg     BitFramingReg, #0x80

                ; Wait for RX Interrupt flag or Timeoutt Interrupt  flag
WaitRX          rfid_read   ComIrqReg, R13
                bit.b       #0x21, R13
                jz          WaitRX               ; Keep waiting until timeout or RX
                bit.b       #0x01, R13           ; Is timeout?
                jnz         ReadLoop             ; Try again

                ; Anticollision registers and intialize FIFO to read
                rfid_write  CommandReg,     #0x00
                rfid_write  ComIrqReg,      #0x7F
                rfid_write  FIFOLevelReg,   #0x80
                rfid_write  BitFramingReg,  #0x00
                rfid_write  FIFODataReg,    #0x93
                rfid_write  FIFODataReg,    #0x20
                rfid_write  CommandReg,     #0x0C

                bis_reg     BitFramingReg, #0x80

                ; Wait for RX Interrupt flag or Timeout Interrupt  flag
WaitRX1         rfid_read   ComIrqReg, R13
                bit.b       #0x21, R13
                jz          WaitRX1              ; Keep waiting until timeout or RX
                bit.b       #0x01, R13           ; Is timeout?
                jnz         ReadLoop             ; Try again

                ; Read 4 UID bytes from FIFO
                rfid_read   FIFODataReg, R4
                rfid_read   FIFODataReg, R5
                rfid_read   FIFODataReg, R6
                rfid_read   FIFODataReg, R7
                rfid_write  CommandReg, #0x00    ; idle the device

                ; save uid bytes
                mov.b       R4, tag_storage+tag_data_ptr+0
                mov.b       R5, tag_storage+tag_data_ptr+1
                mov.b       R6, tag_storage+tag_data_ptr+2
                mov.b       R7, tag_storage+tag_data_ptr+3
                mov.b       #1, &tag_storage+tag_valid_f 

                bit.b       #BIT1, &P1IN                  ; check  left button
                jnz         cmpID                       ; if not pressed, skip to compare

                ; save new passcode
                mov.w       #0, R10        
SaveLoop:       mov.b       tag_storage(R10), tag_storage+passcode_ptr(R10) ; copy byte
                inc.w       R10                           ; move to next byte
                cmp.w       #4, R10                       ; did we do all 4?
                jne         SaveLoop                      ; if no, keep looping

                mov.b       #1, &tag_storage+passcode_set_f ; mark passcode as set
                
                ; blink green led
                bic.b       #BIT0, &P1OUT 
                bic.b       #BIT7, &P9OUT
                mov.w       #4, R11                       ; loop 4 times
                xor.b       #BIT7, &P9OUT                 ; toggle green led
                delay       30000                         ; wait
                dec.w       R11                           ; decrement R11
                jnz         $-16 

wait            bit.b       #BIT1, &P1IN                  ; check if button is still held
                jz          wait          
                delay       20000       
                jmp         ReadLoop     

cmpID:
                cmp.b       #1, &tag_storage+passcode_set_f ; do we have a passcode?
                jne         ReadLoop       

                mov.w       #0, R10         
CompareLoop:    mov.b       tag_storage(R10), R13         ; load tag byte
                cmp.b       tag_storage+passcode_ptr(R10), R13 ; compare to passcode byte
                jne         mismatch  
                inc.w       R10                           ; next byte
                cmp.w       #4, R10                       ; did we check all 4?
                jne         CompareLoop                   ; if no, keep checking

                ; tag match
                bic.b       #BIT0, &P1OUT                 ; turn off leds
                bic.b       #BIT7, &P9OUT    
                mov.w       #4, R11                       ; loop 4 times 
                xor.b       #BIT7, &P9OUT                 ; toggle green led
                delay       30000                         ; wait 
                dec.w       R11                           ; count down 
                jnz         $-16
                jmp         ReadLoop

                ; tag  not match
mismatch        bic.b       #BIT7, &P9OUT                 ; turn off leds
                bic.b       #BIT0, &P1OUT 
                mov.w       #4, R11                       ; loop 4 times
                xor.b       #BIT0, &P1OUT                 ; toggle red led
                delay       30000                         ; wait
                dec.w       R11                           ; count down
                jnz         $-14
                jmp         ReadLoop        

    ;------------------------------------------------------------------------------
    ;           Subroutines
    ;------------------------------------------------------------------------------
    ;  Pass in address on R15, and data on R14
rfid_write_sr:
                CS_LOW                            ; Pull CS low
                rla.b       R15                   ; load address, shift to right spot
                call        #spi_byte             ; tell device what address
                mov.b       R14, R15              ; load data
                call        #spi_byte             ; write data to that address
                CS_HIGH                           ; Pull CS High (End of transmission)
                ret

    ;  Pass in address on R15, pass out data received on UCB1RXBUF
rfid_read_sr:
                CS_LOW                            ; Pull CS low
                rla.b       R15                   ; load address, shift to right spot
                bis.b       #BIT7, R15            ; specify reading
                call        #spi_byte             ; tell device what address
                mov.b       #0, R15               ; send dummy word of 00
                call        #spi_byte             ; receive byte of data
                CS_HIGH                           ; Pull CS High (End of transmission)
                ret

    ; Pass in data to send on R15, data received is on UCB1RXBUF
spi_byte:                                         ; R15=byte to send, result in UCB1RXBUF
spiT1           bit.w       #UCTXIFG, &UCB1IFG
                jz          spiT1
                mov.b       R15, &UCB1TXBUF
spiT2           bit.w       #UCBUSY, &UCB1STATW
                jnz         spiT2
                ret

    ;------------------------------------------------------------------------------
    ;           Interrupt Vectors
    ;------------------------------------------------------------------------------
                .sect       ".reset"              ; MSP430 RESET Vector
                .short      RESET                 ;
                .end