; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2014 Return Infinity -- see LICENSE.TXT
;
; PCI Functions. http://wiki.osdev.org/PCI
; =============================================================================

align 16
db 'DEBUG: PCI      '
align 16


; -----------------------------------------------------------------------------
; os_pci_read_reg -- Read a register from a PCI device
;  IN:	BL  = Bus number
;	CL  = Device/Slot/Function number
;	DL  = Register number
; OUT:	EAX = Register information
;	All other registers preserved
os_pci_read_reg:
	mov r8, rdx
	mov r9, rcx
	mov r10 rbx
	
	shl ebx, 16			; Move Bus number to bits 23 - 16
	shl ecx, 8			; Move Device/Slot/Fuction number to bits 15 - 8
	or ebx, ecx
	shl edx, 2
	or ebx, edx
	and ebx, 0x00ffffff		; Clear bits 31 - 24
	or ebx, 0x80000000		; Set bit 31
	mov eax, ebx
	mov dx, PCI_CONFIG_ADDRESS
	out dx, eax
	mov dx, PCI_CONFIG_DATA
	in eax, dx

	mov rbx, r10
	mov rcx, r9
	mov rdx, r8
ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_pci_dump_devices -- Dump all Device and Vendor ID's to the screen
;  IN:	Nothing
; OUT:	Nothing, All registers preserved
; http://pci-ids.ucw.cz/read/PC/ - Online list of Device and Vendor ID's
os_pci_dump_devices:
	push rdx
	push rcx
	push rbx
	push rax

	xor ecx, ecx
	
	bts ecx, 31		; Bit 31 must be set
	xor eax, eax

os_pci_dump_devices_check_next:
	mov eax, ecx
	mov dx, PCI_CONFIG_ADDRESS
	out dx, eax
	mov dx, PCI_CONFIG_DATA
	in eax, dx			; EAX now holds the Device and Vendor ID
	cmp eax, 0xffffffff		; 0xFFFFFFFF means no device present on that Bus and Slot
	je os_pci_dump_devices_nothing_there
	call os_debug_dump_eax		; Print the Device and Vendor ID (DDDDVVVV)
	call os_print_newline
os_pci_dump_devices_nothing_there:
	add ecx, 0x800
	cmp ecx, 0x81000000		; The end has been reached (already looked at 8192 devices)
	jne os_pci_dump_devices_check_next

os_pci_dump_devices_end:
	pop rax
	pop rbx
	pop rcx
	pop rdx
ret
; -----------------------------------------------------------------------------


;Configuration Mechanism One has two IO port rages associated with it.
;The address port (0xcf8-0xcfb) and the data port (0xcfc-0xcff).
;A configuration cycle consists of writing to the address port to specify which device and register you want to access and then reading or writing the data to the data port.

PCI_CONFIG_ADDRESS	EQU	0x0CF8
PCI_CONFIG_DATA		EQU	0x0CFC

;ddress dd 10000000000000000000000000000000b
;          /\     /\      /\   /\ /\    /\
;        E    Res    Bus    Dev  F  Reg   0
; Bits
; 31		Enable bit = set to 1
; 30 - 24	Reserved = set to 0
; 23 - 16	Bus number = 256 options
; 15 - 11	Device/Slot number = 32 options
; 10 - 8	Function number = will leave at 0 (8 options)
; 7 - 2		Register number = will leave at 0 (64 options) 64 x 4 bytes = 256 bytes worth of accessible registers
; 1 - 0		Set to 0


; =============================================================================
; EOF
