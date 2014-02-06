; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2014 Return Infinity -- see LICENSE.TXT
;
; SMP Functions
; =============================================================================

align 16
db 'DEBUG: SMP      '
align 16


; -----------------------------------------------------------------------------
; os_smp_reset -- Resets a CPU Core
;  IN:	AL = CPU #
; OUT:	Nothing. All registers preserved.
; Note:	This code resets an AP
;	For setup use only.
os_smp_reset:
	mov r10, rax

	mov r8 [os_LocalAPICAddress]
	shl eax, 24		; AL holds the CPU #, shift left 24 bits to get it into 31:24, 23:0 are reserved
	mov [r8+0x0310], eax	; Write to the high bits first
	xor eax, eax		; Clear EAX, namely bits 31:24
	mov al, 0x81		; Execute interrupt 0x81
	mov [r8+0x0300], eax	; Then write to the low bits

	mov rax, r10
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_wakeup -- Wake up a CPU Core
;  IN:	AL = CPU #
; OUT:	Nothing. All registers preserved.
os_smp_wakeup:
	mov r10, rax

	mov r8, [os_LocalAPICAddress]
	shl eax, 24		; AL holds the CPU #, shift left 24 bits to get it into 31:24, 23:0 are reserved
	mov [r8+0x0310], eax	; Write to the high bits first
	xor eax, eax		; Clear EAX, namely bits 31:24
	mov al, 0x80		; Execute interrupt 0x80
	mov [r8+0x0300], eax	; Then write to the low bits

	mov rax, r10
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_wakeup_all -- Wake up all CPU Cores
;  IN:	Nothing.
; OUT:	Nothing. All registers preserved.
os_smp_wakeup_all:
	mov r9, rax
	mov r8, [os_LocalAPICAddress]
	xor eax, eax
	mov [r8+0x0310], eax	; Write to the high bits first
	mov eax, 0x000C0080	; Execute interrupt 0x80
	mov [r8+0x0300], eax	; Then write to the low bits

	mov rax, r9
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_get_id -- Returns the APIC ID of the CPU that ran this function
;  IN:	Nothing
; OUT:	RAX = CPU's APIC ID number, All other registers perserved.
os_smp_get_id:

	mov r9, [os_LocalAPICAddress]
	mov eax, [r9+0x23]	; APIC ID is stored in bits 31:24

	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_enqueue -- Add a workload to the processing queue
;  IN:	RAX = Address of code to execute
;	RSI = Variable
; OUT:	Nothing
os_smp_enqueue:
	mov  r9, rdi
	mov r10, rsi
	mov r11, rcx
	mov r12, rbx
	mov r15, rax

os_smp_enqueue_spin:
;	bt word [os_QueueLock], 0	; Check if the mutex is free
;	jc os_smp_enqueue_spin		; If not check it again
;	lock bts word [os_QueueLock], 0	; The mutex was free, lock the bus. Try to grab the mutex
;	jc os_smp_enqueue_spin		; Jump if we were unsuccessful

	xor ecx, ecx
	mov cl, 1
	xor eax, eax
	lock cmpxchg cl, [os_QueueLock]
	jz mutex_free
	pause
	jmp os_smp_dequeue_spin

mutex_free:
	movzx edx, word [os_QueueLen]	; aka cpuqueuemax
	mov rdi, cpuqueue
	movzx ecx, word [cpuqueuefinish]
	mov eax, ecx
	shl ecx, 4			; Quickly multiply RCX by 16
	add rdi, rcx
	cmp edx, 256
	je os_smp_enqueue_fail


	mov [rdi], r15				; Store the code address from RAX
	mov [rdi+8], rsi			; Store the variable

	add edx 1
	inc eax
	xor ebx, ebx
	mov [os_QueueLen], dx
	cmp ax, [cpuqueuemax]
	cmove ecx, ebx

os_smp_enqueue_end:
	mov [cpuqueuefinish], ax
	mov [os_QueueLock], bx		; Release the lock
	mov r8, [os_LocalAPICAddress]
	mov rbx, r12
	mov rcx, r11
	mov rsi, r10
	mov rdi, r9
	xor eax, eax
	mov [r8+0x0310], eax	; Write to the high bits first
	mov eax, 0x000C0080	; Execute interrupt 0x80
	mov [r8+0x0300], eax	; Then write to the low bits
	mov rax, r15
	clc				; Carry clear for success
	ret

os_smp_enqueue_fail:
	xor eax, eax
	mov [os_QueueLock], ax	; Release the lock
	mov rax, r15
	mov rbx, r12
	mov rcx, r11
	mov rsi, r10
	mov rdi, r9
	stc				; Carry set for failure (Queue full)
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_dequeue -- Dequeue a workload from the processing queue
;  IN:	Nothing
; OUT:	RAX = Address of code to execute (Set to 0 if queue is empty)
;	RDI = Variable
os_smp_dequeue:
	mov  r9, rsi
	mov r10, rcx
	mov r11, rbx
	mov r12, rdx

os_smp_dequeue_spin:
;	bt word [os_QueueLock], 0	; Check if the mutex is free
;	jc os_smp_dequeue_spin		; If not check it again
;	lock bts word [os_QueueLock], 0	; The mutex was free, lock the bus. Try to grab the mutex
;	jc os_smp_dequeue_spin		; Jump if we were unsuccessful

	xor ecx, ecx
	mov cl, 1
	xor eax, eax
	lock cmpxchg cl, [os_QueueLock]
	jz mutex_free
	pause
	jmp os_smp_dequeue_spin

mutex_free:
	mov rsi, cpuqueue
	movzx ebx, word [os_QueueLen]
	cmp eax, ebx
	je os_smp_dequeue_fail

	movzx ecx, word [cpuqueuestart]
	mov edx, ecx
	shl ecx, 4			; Quickly multiply RCX by 16
	add rsi, rcx

	mov rax, [rsi]				; Load the code address into RAX
	mov rdi, [rsi+8]			; Load the variable

	dec ebx
	xor r8d, r8d
	inc edx
	cmp edx, [cpuqueuemax]
	cmove edx, r8d			; We wrap around	

os_smp_dequeue_end:
	mov word [cpuqueuestart], dx
	xor edx, edx
	mov [os_QueueLock], dx
	mov rcx, r10
	mov rsi, r9
	mov r11, rbx
	mov r12, rdx
	clc				; If we got here then ok
	ret

os_smp_dequeue_fail:
	xor eax, eax
	mov [os_QueueLock], ax
	mov rcx, r10
        mov rsi, r9
        mov r11, rbx
        mov r12, rdx

	stc
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_run -- Call the code address stored in RAX
;  IN:	RAX = Address of code to execute
; OUT:	Nothing
os_smp_run:
	call rax			; Run the code
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_queuelen -- Returns the number of items in the processing queue
;  IN:	Nothing
; OUT:	RAX = number of items in processing queue
os_smp_queuelen:
	movzx eax, word [os_QueueLen]
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_numcores -- Returns the number of cores in this computer
;  IN:	Nothing
; OUT:	RAX = number of cores in this computer
os_smp_numcores:
	movzx eax, word [os_NumCores]
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_wait -- Wait until all other CPU Cores are finished processing
;  IN:	Nothing
; OUT:	Nothing. All registers preserved.
os_smp_wait:
	push rsi
	push rcx
	push rbx
	push rax

	mov r9, [os_LocalAPICAddress] ; get_id
        mov ebx, [r9+0x23]
	xor eax, eax
	xor edx, edx
	mov ecx, 256
	mov rsi, cpustatus

checkit:
	movzx eax, byte [rsi]
	cmp rbx, rcx		; Check to see if it is looking at itself
	sete dl
				; Check the Present bit (bit 0)
				; Check the Ready/Busy bit (bit 1)
	test eax, 3
	setnz al 
	lea r8, [rsi+1]
	or dl, al
	cmovz rsi, r8
	dec rcx
	jnz checkit

	pop rax
	pop rbx
	pop rcx
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_lock -- Attempt to lock a mutex
;  IN:	RAX = Address of lock variable
; OUT:	Nothing. All registers preserved.
os_smp_lock:
	mov r8, rdi
	mov r9, rcx
	mov rdi, rax
	xor ecx, ecx
	mov cl, 1
	xor eax, eax
	lock cmpxchg [rdi], cl
	jz mutex_free
	pause
	jmp os_smp_lock

mutex_free:
	mov rax, rdi
	mov rdi, r8
	mov rcx, r9

	setc
	ret			; Lock acquired. Return to the caller
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_smp_unlock -- Unlock a mutex
;  IN:	RAX = Address of lock variable
; OUT:	Nothing. All registers preserved.
os_smp_unlock:
	mov r8, rbx
	xor ebx, ebx
	mov [rax], bx	; Release the lock (Bit 0 cleared to 0)
	mov rbx, r8
	ret			; Lock released. Return to the caller
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
