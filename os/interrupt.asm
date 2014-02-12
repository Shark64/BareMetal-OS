; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2014 Return Infinity -- see LICENSE.TXT
;
; Interrupts
; =============================================================================

align 16
db 'DEBUG: INTERRUPT'
align 16


; -----------------------------------------------------------------------------
; Default exception handler
exception_gate:
	mov rsi, int_string00
	call os_output
	mov rsi, exc_string
	call os_output
	jmp $				; Hang
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Default interrupt handler
align 16
interrupt_gate:				; handler for all other interrupts
	iretq				; It was an undefined interrupt so return to caller
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Keyboard interrupt. IRQ 0x01, INT 0x21
; This IRQ runs whenever there is input on the keyboard
align 16
keyboard:
	mov  r8,  rdi
	mov  r9,  rbx
	mov  r10, rax
	mov  r11, rcx

	xor eax, eax
	xor edi, edi
	xor ebx, ebx
	
	in al, 0x60			; Get the scancode from the keyboard
	cmp al, 0x01
	je reboot
	cmp al, 0x2A			; Left Shift Make
	setz dl
	cmp al, 0x36			; Right Shift Make
	setz bl
	or ebx,edx
	cmp al, 0xAA			; Left Shift Break
	setz dl
	cmp al, 0xB6			; Right Shift Break
	setz cl
	or ecx, edx
	or ecx, ebx 			
	jnz keyboard_shift
	test al, 0x80
	jnz keyboard_done
	movzx ecx, byte [key_shift]
	mov rbx, keylayoutlower
	mov rdi, keylayoutupper
	test ecx,ecx
	cmovz rbx,rdi

keyboard_processkey:			; Convert the scancode
	movzx byte ecx, [rbx+rax]
	mov [key], cl
	
keyboard_done:
	mov al, 0x20			; Acknowledge the IRQ
	out 0x20, al
	call os_smp_wakeup_all		; A terrible hack

	mov rcx, r11
	mov rax, r10
	mov rbx, r9
	mov rdi, r8
	iretq

keyboard_shift:
	test ebx, ebx
	cmovz ecx, ebx
	mov byte [key_shift], cl
	jmp keyboard_done

; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Cascade interrupt. IRQ 0x02, INT 0x22
cascade:
	mov r8, rax
	
	xor eax, eax
	mov al, 0x20			; Acknowledge the IRQ
	out 0x20, al

	mov rax, r8
	iretq
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Real-time clock interrupt. IRQ 0x08, INT 0x28
; Currently this IRQ runs 8 times per second (As defined in init_64.asm)
; The supervisor lives here
align 16
rtc:
	mov r8, rax

	cld				; Clear direction flag
	xor eax, eax			; Clear EAX
	lea r9,  [eax+1]
	add r9, [os_ClockCounter]	; 64-bit counter started at bootup

	cmp al, [os_show_sysstatus]
	je rtc_end
	call system_status		; Show System Status information on screen

rtc_end:
	mov [os_ClockCounter}, r9
	mov al, 0x0C			; Select RTC register C
	out 0x70, al			; Port 0x70 is the RTC index, and 0x71 is the RTC data
	in al, 0x71			; Read the value in register C
	mov al, 0x20			; Acknowledge the IRQ
	out 0xA0, al
	out 0x20, al

	mov rax, r8
	iretq
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Network interrupt.
align 16
network:
	push rdi
	push rsi
	push rcx
	push rax

	cld				; Clear direction flag
	call os_ethernet_ack_int	; Call the driver function to acknowledge the interrupt internally

	test eax, 129				; RX bit set
	jz network_end
	test eax, 1				; TX bit set (caused the IRQ?)
	jnz network_tx			; If so then jump past RX section
network_rx_as_well:
	mov byte [os_NetActivity_RX], 1
	mov rdi, os_EthernetBuffer	; Raw packet is copied here
	push rdi
	add rdi, 2
	call os_ethernet_rx_from_interrupt
	pop rdi
	mov rax, rcx
	stosw				; Store the size of the packet
	cmp qword [os_NetworkCallback], 0	; Is it valid?
	je network_end			; If not then bail out.

	; We could do a 'call [os_NetworkCallback]' here but that would not be ideal.
	; A defective callback would hang the system if it never returned back to the
	; interrupt handler. Instead, we modify the stack so that the callback is
	; executed after the interrupt handler has finished. Once the callback has
	; finished, the execution flow will pick up back in the program.
	mov rcx, [os_NetworkCallback]	; RCX stores the callback address
	mov rsi, rsp			; Copy the current stack pointer to RSI
	sub rsp, 8			; Subtract 8 since we will copy 8 registers
	mov rdi, rsp			; Copy the 'new' stack pointer to RDI
	lodsq				; RAX
	stosq
	lodsq				; RCX
	stosq
	lodsq				; RSI
	stosq
	lodsq				; RDI
	stosq
	lodsq				; RIP
	xchg rax, rcx
	stosq				; Callback address
	lodsq				; CS
	stosq
	lodsq				; Flags
	stosq
	lodsq				; RSP
	sub rax, 8
	stosq
	lodsq				; SS
	stosq
	xchg rax, rcx
	stosq				; Original program address
	jmp network_end

network_tx:
	mov byte [os_NetActivity_TX], 1
	test eax, 128
	jnz network_rx_as_well

network_end:
	mov al, 0x20			; Acknowledge the IRQ on the PIC(s)
	cmp byte [os_NetIRQ], 8
	jl network_ack_only_low		; If the network IRQ is less than 8 then the other PIC does not need to be ack'ed
	out 0xA0, al
network_ack_only_low:
	out 0x20, al

	pop rax
	pop rcx
	pop rsi
	pop rdi
	iretq
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; A simple interrupt that just acknowledges an IPI. Useful for getting an AP past a 'hlt' in the code.
align 16
ap_wakeup:
	mov r8, rdi
	mov r9, rax

	mov rdi, [os_LocalAPICAddress]	; Acknowledge the IPI
	xor eax, eax
	mov [rdi+0xB0], eax

	mov rax, r9
	mov rdi, r8
	iretq				; Return from the IPI.
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Resets a CPU to execute ap_clear
align 16
ap_reset:
	mov eax, ap_clear		; Set RAX to the address of ap_clear
	mov [rsp], rax			; Overwrite the return address on the CPU's stack
	mov rdi, [os_LocalAPICAddress]	; Acknowledge the IPI
	xor eax, eax
	mov [rdi+0xB0], eax
	iretq				; Return from the IPI. CPU will execute code at ap_clear
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; CPU Exception Gates
align 16
exception_gate_00:
	push rax
	mov al, 0x00
	jmp exception_gate_main

align 16
exception_gate_01:
	push rax
	mov al, 0x01
	jmp exception_gate_main

align 16
exception_gate_02:
	push rax
	mov al, 0x02
	jmp exception_gate_main

align 16
exception_gate_03:
	push rax
	mov al, 0x03
	jmp exception_gate_main

align 16
exception_gate_04:
	push rax
	mov al, 0x04
	jmp exception_gate_main

align 16
exception_gate_05:
	push rax
	mov al, 0x05
	jmp exception_gate_main

align 16
exception_gate_06:
	push rax
	mov al, 0x06
	jmp exception_gate_main

align 16
exception_gate_07:
	push rax
	mov al, 0x07
	jmp exception_gate_main

align 16
exception_gate_08:
	push rax
	mov al, 0x08
	jmp exception_gate_main

align 16
exception_gate_09:
	push rax
	mov al, 0x09
	jmp exception_gate_main

align 16
exception_gate_10:
	push rax
	mov al, 0x0A
	jmp exception_gate_main

align 16
exception_gate_11:
	push rax
	mov al, 0x0B
	jmp exception_gate_main

align 16
exception_gate_12:
	push rax
	mov al, 0x0C
	jmp exception_gate_main

align 16
exception_gate_13:
	push rax
	mov al, 0x0D
	jmp exception_gate_main

align 16
exception_gate_14:
	push rax
	mov al, 0x0E
	jmp exception_gate_main

align 16
exception_gate_15:
	push rax
	mov al, 0x0F
	jmp exception_gate_main

align 16
exception_gate_16:
	push rax
	mov al, 0x10
	jmp exception_gate_main

align 16
exception_gate_17:
	push rax
	mov al, 0x11
	jmp exception_gate_main

align 16
exception_gate_18:
	push rax
	mov al, 0x12
	jmp exception_gate_main

align 16
exception_gate_19:
	push rax
	mov al, 0x13
	jmp exception_gate_main

align 16
exception_gate_main:
	push rbx
	push rdi
	push rsi
	push rax				; Save RAX since os_smp_get_id clobers it
	call os_print_newline
	mov rsi, int_string00
	call os_output
	call os_smp_get_id		; Get the local CPU ID and print it
	mov rdi, os_temp_string
	mov rsi, rdi
	call os_int_to_string
	call os_output
	mov rsi, int_string01
	call os_output
	mov rsi, exc_string00
	pop rax
	movzx eax, al			; Clear out everything in RAX except for AL
	push rax
	mov bl, 32			; Length of each message
	mul bl				; AX = AL x BL
	add rsi, rax			; Use the value in RAX as an offset to get to the right message
	pop rax
	mov bl, 0x0F
	call os_output
	call os_print_newline
	pop rsi
	pop rdi
	pop rbx
	pop rax
	call os_print_newline
	call os_debug_dump_reg
	mov rsi, rip_string
	call os_output
	push rax
	mov rax, [rsp+0x08] 		; RIP of caller
	call os_debug_dump_rax
	pop rax
	call os_print_newline
	push rax
	push rcx
	push rsi
	mov rsi, stack_string
	call os_output
	mov rsi, rsp
	add rsi, 0x18
	mov rcx, 4
next_stack:
	lodsq
	call os_debug_dump_rax
	mov al, ' '
	call os_output_char
;	call os_print_char
;	call os_print_char
;	call os_print_char
	loop next_stack
	call os_print_newline
	pop rsi
	pop rcx
	pop rax
;	jmp $				; For debugging
	call init_memory_map
	jmp ap_clear			; jump to AP clear code


int_string00 db 'BareMetal OS - CPU ', 0
int_string01 db ' - Interrupt ', 0
; Strings for the error messages
exc_string db 'Unknown Fatal Exception!', 0
exc_string00 db '00 - Divide Error (#DE)        ', 0
exc_string01 db '01 - Debug (#DB)               ', 0
exc_string02 db '02 - NMI Interrupt             ', 0
exc_string03 db '03 - Breakpoint (#BP)          ', 0
exc_string04 db '04 - Overflow (#OF)            ', 0
exc_string05 db '05 - BOUND Range Exceeded (#BR)', 0
exc_string06 db '06 - Invalid Opcode (#UD)      ', 0
exc_string07 db '07 - Device Not Available (#NM)', 0
exc_string08 db '08 - Double Fault (#DF)        ', 0
exc_string09 db '09 - Coprocessor Segment Over  ', 0	; No longer generated on new CPU's
exc_string10 db '10 - Invalid TSS (#TS)         ', 0
exc_string11 db '11 - Segment Not Present (#NP) ', 0
exc_string12 db '12 - Stack Fault (#SS)         ', 0
exc_string13 db '13 - General Protection (#GP)  ', 0
exc_string14 db '14 - Page-Fault (#PF)          ', 0
exc_string15 db '15 - Undefined                 ', 0
exc_string16 db '16 - x87 FPU Error (#MF)       ', 0
exc_string17 db '17 - Alignment Check (#AC)     ', 0
exc_string18 db '18 - Machine-Check (#MC)       ', 0
exc_string19 db '19 - SIMD Floating-Point (#XM) ', 0
rip_string db ' IP:', 0
stack_string db ' ST:', 0



; =============================================================================
; EOF
