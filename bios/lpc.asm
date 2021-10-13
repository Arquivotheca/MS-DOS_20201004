        PAGE    ,132
        TITLE   'Power Control Transient Portion'

;-----------------------------------------------------------------------------
;       Power control transient module for POWER.EXE
;
;       This file contains the transient code used to turn power
;       monitoring on and off from the command line.
;
;       Microsoft Confidential
;       Copyright (C) 1991 Microsoft Corporation 
;       All Rights Reserved.
;
; This code is bound to the device driver image of POWER.EXE.  This
; transient program can be used to turn power control on and off.
; POWER has the following options:
;
;       POWER [ADV | STD |OFF |SOUND |/?]
;               ADV   - Monitors applications and devices
;               STD   - Monitors devices only
;		OFF   - turns off all pw. management
;               SOUND - activate speaker during idle (debug version only) - toggle
;               /? - print help message
;
; MODIFICATIONS:
;	M004	9/5/91	NSM	power status from APM in BL reg. was trashed
;				and so we were skipping call to get and print
;				APM stats. Fixed by storing status and
;				using it whenever we need to look at current
;				POWER status
;	M007	09/11/91 SMR	B#2669. Registered POWER's 2f channels
;					in mult.inc
;	M009	09/11/91 SMR	Build non-debug version.
;
;  	M010	09/12/91 SMR	PWR_API returns 0 in AX instead of no carry flag
;				in case of no error
;	M011	09/17/91 NSM	PWR_API returns the version no in AX for the
;				install_chk call and so we shouldn't chk for
;				AX==0 for install-chk call.
;	M087	09/23/91 NSM	Install_chk returns 504d in BX and not 4d50
;				B#2756
;
;	M089	09/25/91 NSM	UI changes.	
;
;	M092	10/18/91 NSM	B#2872(5.1) Clear out BH
;				(correction for a typo: xor was entered as or)
;-----------------------------------------------------------------------------

Trans_Code      segment word public 'CODE'
Trans_Code      ends

Trans_Data      segment word public 'DATA'
Trans_Data      ends

Trans_Stack     segment para stack 'STACK'
        db      512 dup (?)
Trans_Stack     ends

break		macro		; satisfy mult.inc & pdb.inc		; M009
		endm							; M009

include		mult.inc				; M007
include         power.inc
include         pdb.inc

; DOS calls used
EXIT            equ     4Ch
OUT_STRING      equ     09h
OUT_CHAR        equ     02h

Trans_Data      segment
include         powermsg.inc

psp             dw      0,0             ; stores our PSP address 

digit_buf       db      8 dup (0)       ; stores chars generated by get_dec

idle_data	IDLE_INFO	<>

pow_status	db	0		; M004 ; to store current POWER
					; enabled/disabled state

Trans_Data      ends

Trans_Code      segment
        assume  cs:Trans_Code, ds:nothing, es:nothing

        extrn   get_dec:near, uldiv:near, lmul:near        
        
start:
        public  start
        mov     ax,Trans_Data
        mov     ds,ax                   ; set up data segment
        assume  ds:Trans_Data

        mov     [psp]+2,es              ; save our PSP address for later
        
; look at the command line and determine what we are supposed to be
; doing.  

        les     bx,dword ptr [psp]      ; recover our PSP address
        lea     di,es:[bx].PDB_TAIL
        cmp     es:[bx].PDB_TAIL,0      ; is there a command line?
	je	not_help		; no tail; go display stats
look_at_tail:
	inc	di			; skip the first blank in tail

clear_spaces:
        cmp     es:byte ptr [bx+di],' ' ; scan past any spaces
        jne     get_command_option      ; not a space, load it and check it
        inc     di
        jmp     short clear_spaces      ; assume we will stop on CR terminator

get_command_option:
        mov     ax,es:word ptr [bx+di]  ; get start of command line,
        cmp     ax,'?/'                 ; looks like /?
	jne	not_help
	jmp	display_help

not_help:

; We've established this is not /?.  Now check for other options        
; before proceeding, detect the presence of POWER by power detect call

	push	bx
	mov	ax,(MultPWR_API*256)+00h; POWER detect mult.call ; M007
	int	2fh
	cmp	ax,(MultPWR_API*256)+00h; MultAPI code unchanged ? ; M011
	jnz	chk_signature		; M011
to_open_fail:
	jmp	open_failed
chk_signature:
	cmp	bx,504dh		; M087 signature correct ?
	jne	to_open_fail

IFDEF	DEBUG
	push	di
        lea     dx,rev_msg      	; Display current rev. no & date
        mov     ah,OUT_STRING		;
        int     21h                     
	pop	di
ENDIF
	pop	bx

        mov     ax,es:word ptr [bx+di]  ; get start of command line,

        cmp     al,13                   ; is it the CR terminator?
        je      display_info            ; yes, just go display status
	cmp	al,0			; no tail at all
	je	display_info		; just display status

        or      ax,2020h                ; map to lower case -- this is a
                                        ; command line, so don't need lang.
                                        ; independence
; M089 BEGIN - UI changes

        cmp     ax,'da'                 ; turning on?
        je      turn_on_all
	cmp	ax,'ts'			; Standard ?
	je	turn_on_FW
        cmp     ax,'fo'                 ; looks like OFF?
        je      turn_off                ; 

; M089 END

IFDEF      DEBUG           ; only active in debug version
        cmp     ax,'os'                 ; looks like SOUND?
        jne     bad_command             ; none of the above, parameter error

; User requests we toggle control of speaker on at idle
	mov	ax,(MultPWR_API*256)+02h; change allocation strategy ; M007
	mov	bl,80h			; special value for SOUND toggle
	int	2fh
        jmp     short display_info      ; go show current state

bad_command:

ENDIF

; User provided an invalid command line

        lea     dx,bad_command_msg      ; scold the user
        jmp     err_exit

turn_on_all:        ; User requested power control be activated
	mov	bl,3			; set both F/W and S/W
;
change_pw_state:			; issue mult.int to turn on/off PW mgmt.
	mov	bh,1			; set  power state
	mov	al,I2F_PW_GET_SET_PWSTATE
	mov	ah,MultPWR_API		; M007
	int	2fh
        jmp     short display_info

turn_on_FW:
	mov	bl,2			; turn on only F/W
	jmp	short change_pw_state
	

turn_off:       ; User requests power control be deactivated
	xor	bl,bl		; turn off all pw mgmt
	jmp	short change_pw_state
	
        
display_info:   ; Print current state and idle stats
	mov	al,I2F_PW_GET_SET_PWSTATE
	mov	ah,MultPWR_API		; M007
	mov	bx,0			; get pw state
	int	2fh
	or	ax, ax			; M010
	jz	chk_status		; M010
	jmp	stats_failed		; error in get pw state ? just quit
chk_status:
	mov	[pow_status],bl		; M004
        lea     dx,power_stat1_msg      ; Display current POWER status
        mov     ah,OUT_STRING		; Whether "ON/OFF/NOAPP"
        int     21h                     

	or	bl,bl			; all pow.mgmt off ?
        lea     dx,power_off_msg         ; assume power control is off
	jz	got_msg			
	cmp	bl,2
	lea	dx,power_allon_msg
	jne	got_msg
	lea	dx,power_noid_msg
got_msg:
        mov     ah,OUT_STRING		
        int     21h                     
	lea	dx,power_stat2_msg	; complete the above stat msg
        mov     ah,OUT_STRING		
        int     21h                     

; Compute percentage of time idle if idle detection is on
	test	[pow_status],1		;M004; is idle detection on ?
	jz	Print_APM_Stats
        lea     dx,cpu_idle_msg1
        mov     ah,OUT_STRING
        int     21h

	lea	si,idle_data
	mov	cx,size IDLE_INFO
	mov	al,I2F_PW_GET_STATS
	mov	ah,MultPWR_API		; M007
	mov	bx,PW_GET_IDLE_STATS	; get only idle detection stats
	int	2fh			; get stats
	or	ax, ax			; M010
	jnz	stats_failed		; M010

	lea	bx,idle_data
        push    word ptr [bx].CPU_IDLE_TIME+2
        push    word ptr [bx].CPU_IDLE_TIME   ; get total idle time
        xor     ax,ax
        push    ax
        mov     ax,100
        push    ax
        call    lmul                    ; returns result in DX:AX
        add     sp,8
        push    word ptr [bx].CPU_ON_TIME+2
        push    word ptr [bx].CPU_ON_TIME
        push    dx
        push    ax
        call    uldiv                   ; returns result in DX:AX
        add     sp,8

	call	calc_and_print_no
        
        lea     dx,cpu_idle_msg2
        mov     ah,OUT_STRING
        int     21h

Print_APM_Stats:
IFDEF	INCL_APM
	test	[pow_status],2		;M004; is APM enabled ?
	jz	good_exit		; no, all stats display over
	call	Display_APM_Stats
ENDIF
	

good_exit:      ; And exit

        xor     al,al
        mov     ah,EXIT
        int     21h


; Help message display

display_help:
        lea     dx,help_text
        mov     ah,OUT_STRING
        int     21h
        jmp     short good_exit


; Various error exits

open_failed:
        
        lea     dx,open_failed_msg
        jmp     short err_exit

stats_failed:
        lea     dx,stats_failed_msg
err_exit:
        mov     ah,OUT_STRING
        int     21h                     ; display error message
        mov     ah,EXIT
        mov     al,1                    ; signal error on exit 
        int     21h                     

; END OF Main (of transient POWER.EXE)

calc_and_print_no	proc	near
;dx:ax = no to print
;
        lea     di,digit_buf
        call    get_dec                 ; convert result to ASCII

        mov     ah,OUT_CHAR
        lea     bx,digit_buf

next_digit:
        mov     dl,[bx]                 ; reached end of string?
        or      dl,dl
        jz      capn_end              ; yes, go wrap up
        int     21h                     ; print the character
        inc     bx                      ; point to next char in string
        jmp     short next_digit
capn_end:
	ret

calc_and_print_no	endp

IFDEF	INCL_APM

batt_stat_table	label	word
	dw	battery_high
	dw	battery_low
	dw	battery_critical
	dw	battery_charging

;***************************************** Display_APM_Stats
; display APM statistics (ACLine status, Battery status and battery life)
;

Display_APM_Stats	proc	near
	mov	ax,530ah		; get power status
	mov	bx,1
	int	15h			;
	jc	APM_stats_End
	push	cx
	push	bx
	cmp	bh,-1
	je	go_chk_batt_stat
        lea     dx,ACLine_Stat1
        mov     ah,OUT_STRING
        int     21h
	pop	bx
	push	bx
        lea     dx,AC_Offline_str
	or	bh,bh
	je	go_print_acstat
	lea	dx,AC_Online_str
go_print_acstat:
        mov     ah,OUT_STRING
        int     21h
        lea     dx,ACLine_Stat2
        mov     ah,OUT_STRING
        int     21h

go_chk_batt_stat:
	pop	bx
	cmp	bl,-1
	je	go_print_batt_life
	xor	bh,bh		; M092
	push	bx
	lea	dx,battery_status1
        mov     ah,OUT_STRING
        int     21h
	pop	bx
	shl	bx,1		; word offset
	mov	dx,cs:batt_stat_table[bx]
        mov     ah,OUT_STRING
        int     21h

	lea	dx,battery_status2
        mov     ah,OUT_STRING
        int     21h

go_print_batt_life:
	pop	cx
	cmp	cl,-1
	je	APM_stats_End
	mov	ax,cx
	xor	ah,ah
	push	ax
	lea	dx,battery_life_str1
        mov     ah,OUT_STRING
        int     21h
	pop	ax
	xor	dx,dx
	call	calc_and_print_no
	lea	dx,battery_life_str2
        mov     ah,OUT_STRING
        int     21h
APM_stats_END:
	ret

Display_APM_Stats	endp

ENDIF

Trans_Code      ends

        end     start

