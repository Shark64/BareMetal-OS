; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2014 Return Infinity -- see LICENSE.TXT
;
; INIT_NET
; =============================================================================

align 16
db 'DEBUG: INIT_NET '
align 16


init_net:
	mov rsi, networkmsg
	call os_output

	; Search for a supported NIC
	xor ebx, ebx			; Clear the Bus number
	xor ecx, ecx			; Clear the Device/Slot number
	mov edx, 2			; Register 2 for Class code/Subclass
	xor r8, r8

init_net_probe_next:
	call os_pci_read_reg
	shr eax, 16			; Move the Class/Subclass code to AX
	cmp eax, 0x0200			; Network Controller (02) / Ethernet (00)
	je init_net_probe_find_driver	; Found a Network Controller... now search for a driver
	add ecx, 1
	lea r9d, [ebx+1]
	cmp ecx, 256			; Maximum 256 devices/functions per bus
	cmove ecx, r8d			; reset ecx if > 256
	cmove ebx, r9d			; and increment ebx
	cmp r9d, 256
	jle init_net_probe_next
	jmp init_net_probe_not_found


init_net_probe_find_driver:
	xor edx, edx				; Register 0 for Device/Vendor ID
	call os_pci_read_reg			; Read the Device/Vendor ID from the PCI device
	mov r8d, eax				; Save the Device/Vendor ID in R8D
	mov rsi, NIC_DeviceVendor_ID
	lodsd					; Load a driver ID - Low half must be 0xFFFF
init_net_probe_find_next_driver:
	mov edx, eax				; Save the driver ID
init_net_probe_find_next_device:
	lodsd					; Load a device and vendor ID from our list of supported NICs
	test eax, eax				; 0x00000000 means we have reached the end of the list
	jz init_net_probe_not_found		; No suported NIC found
	cmp ax, 0xFFFF				; New driver ID?
	je init_net_probe_find_next_driver	; We found the next driver type
	cmp eax, r8d
	jl init_net_probe_find_next_device	; Check the next device

init_net_probe_found:
	cmp edx, 0x8254FFFF
	je init_net_probe_found_i8254x
	cmp edx, 0x8169FFFF
	jne init_net_probe_not_found

init_net_probe_found_rtl8169:
	call os_net_rtl8169_init
	mov rdi, os_net_transmit
	mov rax, os_net_rtl8169_transmit
	mov [rdi], rax
	mov rax, os_net_rtl8169_poll
	mov [rdi+8], rax
	mov rax, os_net_rtl8169_ack_int
	mov [rdi+16], rax
	jmp init_net_probe_found_finish

init_net_probe_found_i8254x:
	call os_net_i8254x_init
	mov rdi, os_net_transmit
	mov rax, os_net_i8254x_transmit
	mov [rdi], rax
	mov rax, os_net_i8254x_poll
	mov [rdi+8], rax
	mov rax, os_net_i8254x_ack_int
	mov [rdi+16], rax
	jmp init_net_probe_found_finish

init_net_probe_found_finish:
	movzx eax, byte [os_NetIRQ]

;	push rax			; Save the IRQ
	lea edi, [eax+0x20]
	mov rax, network
	call create_gate
;	pop rax				; Restore the IRQ

	; Enable the Network IRQ in the PIC 
	; IRQ value 0-7 set to zero bit 0-7 in 0x21 and value 8-15 set to zero bit 0-7 in 0xa1
	xor eax, eax
	xor edx, edx
	in al, 0x21				; low byte target 0x21
	movzx ebx, al
	mov al, [os_NetIRQ]
	mov dl, 0x21				; Use the low byte pic
	cmp al, 8
	jl os_net_irq_init_low
	sub al, 8				; IRQ 8-16
	movzx edi,  ax
	in al, 0xA1				; High byte target 0xA1
	movzx ebx, al
	mov eax, edi
	mov dx, 0xA1				; Use the high byte pic
os_net_irq_init_low:
	movzx ecx, al
	mov al, 1
	shl eax, cl
	not eax
	and eax, ebx
	out dx, al
	mov al, 1
;	mov rcx, rax
;	add rax, 0x20
;	bts rax, 13			; 1=Low active
;	bts rax, 15			; 1=Level sensitive
;	call ioapic_entry_write

	mov  [os_NetEnabled], al	; A supported NIC was found. Signal to the OS that networking is enabled
	call os_ethernet_ack_int	; Call the driver function to acknowledge the interrupt internally

	mov cl, 6
	mov rsi, os_NetMAC
nextbyte:
	lodsb
	call os_debug_dump_al
	sub cl, 1
	jnz nextbyte
	mov rsi, closebracketmsg
	call os_output
	ret
	
init_net_probe_not_found:
	mov rsi, namsg
	call os_output
	mov rsi, closebracketmsg
	call os_output
	ret


; =============================================================================
; EOF
