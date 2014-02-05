; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2014 Return Infinity -- see LICENSE.TXT
;
; INIT_64
; =============================================================================

align 16
db 'DEBUG: INIT_64  '
align 16


init_64:
	; Make sure that memory range 0x110000 - 0x200000 is cleared
	mov edi, os_SystemVariables
	mov ecx, 122880            ; Clear 960 KiB
	xor eax, eax
	rep stosq                  ; Store rax to [rdi], rcx - 1, rdi + 8, if rcx > 0 then do it again

	mov word [os_Screen_Rows], 25
	mov word [os_Screen_Cols], 80
	cmp eax, [0x5080]
	je nographics
	call init_screen
nographics:
	xor eax, eax
	mov [os_Screen_Cursor_Row], eax
	call os_screen_clear		; Clear screen and display cursor

	; Display CPU information
	movzx eax, [os_Screen_Rows]
	sub eax, 5
	mov dword [os_Screen_Cursor_Row], eax
	mov rsi, cpumsg
	call os_output
	movzx eax, word [0x5012]
	mov rdi, os_temp_string
	mov rsi, rdi
	call os_int_to_string
	call os_output
	mov rsi, coresmsg
	call os_output
	movzx eax, word [0x5010]
	mov rdi, os_temp_string
	mov rsi, rdi
	call os_int_to_string
	call os_output
	mov rsi, mhzmsg
	call os_output

	xor edi, edi 			; Create the 64-bit IDT (at linear address 0x0000000000000000) as defined by Pure64

	; Create exception gate stubs (Pure64 has already set the correct gate markers)
	xor ecx, ecx
	mov cl, 32
	mov rax, exception_gate
make_exception_gate_stubs:
	call create_gate
	inc rdi
	dec rcx
	jnz make_exception_gate_stubs

	; Create interrupt gate stubs (Pure64 has already set the correct gate markers)
	mov rcx, 256-32
	mov rax, interrupt_gate
make_interrupt_gate_stubs:
	call create_gate
	inc rdi
	dec rcx
	jnz make_interrupt_gate_stubs

	; Set up the exception gates for all of the CPU exceptions
	xor ecx, ecx
	mov cl, 20
	xor rdi, rdi
	mov rax, exception_gate_00
make_exception_gates:
	call create_gate
	inc edi	
	add eax, 16			; The exception gates are aligned at 16 bytes
	dec rcx 
	jnz make_exception_gates

	; Set up the IRQ handlers (Network IRQ handler is configured in init_net)
	mov edi, 0x21
	mov rax, keyboard
	call create_gate
	add edi, 1
	mov rax, cascade
	call create_gate
	add edi, 6
	mov rax, rtc
	call create_gate
	mov edi, 0x80
	mov rax, ap_wakeup
	call create_gate
	add edi, 1
	mov rax, ap_reset
	call create_gate

	; Set up RTC
	; Rate defines how often the RTC interrupt is triggered
	; Rate is a 4-bit value from 1 to 15. 1 = 32768Hz, 6 = 1024Hz, 15 = 2Hz
	; RTC value must stay at 32.768KHz or the computer will not keep the correct time
	; http://wiki.osdev.org/RTC
rtc_poll:
	xor eax, eax
	mov al, 0x0A			; Status Register A
	out 0x70, al
	in al, 0x71
	test al, 0x80			; Is there an update in process?
	jne rtc_poll			; If so then keep polling
	mov al, 0x0A			; Status Register A
	out 0x70, al
	mov al, 00101101b		; RTC@32.768KHz (0010), Rate@8Hz (1101)
	out 0x71, al
	mov al, 0x0B			; Status Register B
	out 0x70, al			; Select the address
	in al, 0x71			; Read the current settings
	movzx ebx, al
	mov al, 0x0B			; Status Register B
	out 0x70, al			; Select the address
	bts ebx, 6			; Set Periodic(6)
	mov eax, ebx
	out 0x71, al			; Write the new settings
	mov al, 0x0C			; Acknowledge the RTC
	out 0x70, al
	in al, 0x71

	; Set color palette
	xor eax, eax
	mov dx, 0x03C8			; DAC Address Write Mode Register
	out dx, al
	mov dx, 0x03C9			; DAC Data Register
	xor ebx, ebx
	xor ecx, ecx
	mov bl, 16			; 16 lines
nextline:
	mov cl, 16			; 16 colors
	mov rsi, palette
nexttritone:
	mov eax, [rsi]
	out dx, al
	shr eax, 8
	out dx, al
	shr eax, 8
	out dx, al
	add rsi, 3
	dec ecx
	jnz nexttritone
	dec ebx
	jnz nextline			; Set the next 16 colors to the same
	xor eax, eax
	mov al, 0x14			; Fix for color 6
	mov edx, 0x03c8			; DAC Address Write Mode Register
	out dx, al
	mov dx, 0x03c9			; DAC Data Register
	mov rsi, palette
	add rsi, 18
	mov eax, [rsi+18]
	out dx, al
	shl eax, 8
	out dx, al
	shl eax, 8
	out dx, al

	xor eax, eax
	xor ebx, ebx
	xor ecx, ecx
	; Grab data from Pure64's infomap
	mov ebx, [0x5008]		; Load the BSP ID
					; Save it to EBX
	mov rsi, 0x5012
	mov eax, [0x5012]		; Load the number of activated cores
	movzx ecx, ax			; Save it to CX
	mov esi, 0x5060
	mov rax, [rsi]
	mov [os_LocalAPICAddress], rax
	mov rax, [rsi+8]
	mov [os_IOAPICAddress], rax

;	mov rsi, 0x5012
	mov eax, [rsi-0x4e]
	mov [os_NumCores], ax

	mov rsi, 0x5020
	mov eax, [0x5020]
	mov [os_MemAmount], eax		; In MiB's

	mov rax, [0x5040]
	mov [os_HPETAddress], rax

	; Build the OS memory table
	call init_memory_map

	; Initialize all AP's to run our reset code. Skip the BSP
	xor eax, eax
	mov esi, 0x5100	; Location in memory of the Pure64 CPU data
next_ap:
	test ecx, ecx
	jz no_more_aps
	lodsb				; Load the CPU APIC ID
	cmp al, bl
	je skip_ap
	call os_smp_reset		; Reset the CPU
skip_ap:
	dec ecx
	jmp next_ap

no_more_aps:

	; Display memory information
	mov rsi, memmsg
	call os_output
	mov eax, [os_MemAmount]		; In MiB's
	mov rdi, os_temp_string
	mov rsi, rdi
	call os_int_to_string
	call os_output
	mov rsi, mibmsg
	call os_output

	; Enable specific interrupts
	xor eax, eax
	in al, 0x21
	mov al, 11111001b		; Enable Cascade, Keyboard
	out 0x21, al
	in al, 0xA1
	mov al, 11111110b		; Enable RTC
	out 0xA1, al

	ret

; create_gate
; rax = address of handler
; rdi = gate # to configure
create_gate:
	mov r8, rdi
	mov r9, rax

	shl r8, 4			; quickly multiply rdi by 16
	mov [r8], ax			; store the low word (15..0)
	shr rax, 16
					; skip the gate marker
	mov [r8+6], ax			; store the high word (31..16)
	shr rax, 16
	mov [r8+8], eax			; store the high dword (63..32)

	mov rax, r9
	ret


init_memory_map:			; Build the OS memory table
	push rax
	push rcx
	push rdi

	; Build a fresh memory map for the system
	mov rdi, os_MemoryMap
	movzx ecx, word [os_MemAmount]
	shr ecx, 1			; Divide actual memory by 2
	xor eax, eax
	mov al, 1
	rep stosb
	mov rdi, os_MemoryMap
	inc eax
	mov [rdi], al			; Mark the first 2 MiB as in use (by Kernel and system buffers)
;	stosb				; As well as the second 2 MiB (by loaded application)
	; The CLI should take care of the Application memory

	; Allocate memory for CPU stacks (2 MiB's for each core)
	movzx ecx, word [os_NumCores]	; Get the amount of cores in the system
	call os_mem_allocate		; Allocate a page for each core
	test rcx, rcx			; os_mem_allocate returns 0 on failure
	jz system_failure
	add rax, 2097152
	mov [os_StackBase], rax		; Store the Stack base address

	pop rdi
	pop rcx
	pop rax
	ret


system_failure:
	mov rsi, memory_message
	call os_output
system_failure_hang:
	hlt
	jmp system_failure_hang
	ret


; -----------------------------------------------------------------------------
init_screen:
	mov rax, [0x5080]		; VIDEO_BASE
	mov esi, 0x5080
	mov ecx, eax			; 0 extend to 64bit
	mov [os_VideoBase], rcx

	shr rax, 32			; VIDEO_X
	mov [os_VideoX], ax		; ex: 1024
	movzx r8d, ax
	
	xor edx, edx
	movzx ecx, byte [font_width]
	div cx
	mov [os_Screen_Cols], ax

	mov eax, [rsi+8]		; VIDEO_Y
	mov [os_VideoY], ax		; ex: 768
	movzx r9d, ax
	xor edx, edx
	movzx ecx, byte [font_height]
	mov r10d, ecx			; Save font_height
	div cx
	mov [os_Screen_Rows], ax

	shr eax, 24				; VIDEO_DEPTH
	mov [os_VideoDepth], al
	mov r11d, r8d				; Save VIDEO_X
	imul r8d, r9d
	mov [os_Screen_Pixels], r8d
	movzx ecx, byte [os_VideoDepth]
	shr ecx, 3
	mov r12d, ecx				; Save VideoDepth
	imul ecx, r8d
	mov [os_Screen_Bytes], ecx

	imul r10d, r11d
	mov ecx, r12d
	imul ecx, r10d
	mov dword [os_Screen_Row_2], ecx
	xor ecx, ecx
	mov cl, 1
	mov eax, 0x00FFFFFF
	mov [os_Font_Color], eax

	mov [os_VideoEnabled], cl

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
