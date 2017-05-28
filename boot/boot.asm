;-----------------------------------------------------------------------------
; pitiOS bootsector
;-----------------------------------------------------------------------------

; BIOS loads the boot sector at the address 0x7c00 in memory; this is a NASM
; directive indicating that all the variables we use in the program will get
; this additional offset
org 0x7c00

; NASM directive indicating how the code should be generated; the bootloader
; is the one of the first program executed by the machine; at this moment, the
; machine is executing real mode (16 bits) mode (in 80x86 architecture)
bits 16

; this instruction is used to jump to the bootsector block, this is required
; to write this instruction here (3 bytes from offset 0 to 2 included) according
; to FAT16 specifications
jmp reset_hd

; ----------------------------------------------------------------------------
; BIOS Parameter block for FAT16 file system, has to start at the byte 0x3
; ----------------------------------------------------------------------------

db "pitios", 0, 0 ;8 bytes, name of the operating system
dw 512            ;2 bytes, bytes per sector, each one is 512 bytes long
db 1              ; 1 byte, sectors per cluster, it is possible to group
                  ; the sectors by 'cluster', here, we only have one
                  ; sector per cluster
dw 1              ; 2 bytes, reserved sectors, used to calculate the starting
                  ; sector of the first FAT; the boot sector is the only
                  ; sector before the FAT, so the value is 1
db 2              ; 1 byte, numer of file allocation tables, the prefered
                  ; amout is 2 for backup
dw 512            ; 2 bytes, number of root directory entries (file or
                  ; directories) inside the root directory, the max amount
                  ; is 512 items, this is the recommended value
dw 65535          ; small number of sectors in the volume
                  ; NOTE: for my tests purposes, this amount is simply set
                  ; with an arbitrary value
db 0xf0           ; media descriptor, the value must be 0xf0 for 1.44 Mb
                  ; hd disks
dw 9              ; amount of sectors per FAT, we have 2 FATs of 9 sectors
dw 18             ; sectors per track, used for LBA/CHS conversion, the 
                  ; hd disk contains 18 sectors per track
dw 2              ; number of heads (2 heads on a standard hd disk)
dd 0              ; hidden sectors, the amount of sectors between the first
                  ; sector of the disk and the beginning of the volume
dd 0              ; large number of sector, unused in our case as we use
                  ; the small amount of sectors
db 0x29           ; extended boot signature, must be equal to 0x29 to indicate
                  ; that the next items of the EBPB are set
dd 0xffff         ; serial number, we set the 32 bits to 1, related to the
                  ; hardware, it does not matter for us...

; ----------------------------------------------------------------------------
; Extended BIOS Parameter Block
; ----------------------------------------------------------------------------

db 0              ; drive number, 0 for hd disk
db 0              ; reserved and unused byte
db "NO NAME", 0, 0, 0, 0    ; 11 bytes long volume label string
                  ; TODO: #7 must be equal to NO NAME if the root directory
                  ; entry does not exist. This entry does not exist yet,
                  ; but I will have to change it once I get the root
                  ; directory label entry properties...
db "FAT16", 0, 0, 0 ; 8 bytes long file system name

; fill all the bytes between the end of the OEM and the expected starting byte
; of the boot sector code
times 0x3e - ($-$$) db 0

; ----------------------------------------------------------------------------
; here starts the code part of the booloader (byte 0x3e)
; ----------------------------------------------------------------------------

bootloader:

xor cl,cl ;set cl to 0

; directly jump to the instructions that reset the hd disk
jmp reset_hd

; ----------------------------------------------------------------------------
; basic data of the bootsector (this way to do is special, should be in the
; data sector normally, but this concept does not exist at this moment... :(
; ----------------------------------------------------------------------------

hd_error_msg db "Hard disk error", 0

; ----------------------------------------------------------------------------
; executed when the hd has an error (read/write), displays an error
; message and halt the system
; ----------------------------------------------------------------------------

hd_error:
    xor bx, bx ;set bx to 0
    mov ds, bx ;data segment is equal to 0
    mov si, hd_error_msg ;si is equal to the address where the message starts

    loop:
        lodsb ;load ds:si in al, and increment si (store one letter in al and
              ;jump to the next one
        or al,al ;is al = 0 ? (end of the string)
        jz end ;if al = 0, jump to the end of the sector
        mov ah, 0x0e ;the function to write one character is 0x0e
        int 0x10 ;the video interrupt
        jmp loop ;jump to the beginning of the loop

; ----------------------------------------------------------------------------
; reset the hd disk (force the hd controller to get ready on the
; first sector of the disk)
; ----------------------------------------------------------------------------

reset_hd:
    cmp cl, 3 ;try three attemps only, jump to display an error message if
              ;the function fails more 3 times
    je hd_error
    mov ah, 0 ;init disks function is 0
    mov dl, 0x80 ;first hard disk is 80, second one is 81
    int 0x13 ;disk access interrupt, reset the disk
    inc cl    ;increment the attempts amount
    jb reset_hd ;jump back to the address of the beginning of the action
                     ;if an error occured (cf=1, carry flag)

; ----------------------------------------------------------------------------
; end of the bootloader execution
; ----------------------------------------------------------------------------

end:

; set the processor flaf IF to 0, disable the hardware interrupts, no
; interrupts will be handled from the execution of this instruction
cli

; this instruction halts the execution until an interrupt; interrupts have
; just been disabled, so it intentionnaly hangs the system here
hlt

; the time instruction is used to copy the given byte ('db' for byte) x times
; (times x db byte). We use $ to find the address of the current instruction
; (right after hlt), and $$ refers to the first used address of this code.
; the bootsector must be 512 bytes long exactly, so we fill all the next bytes
; of the program until the byte 510
times 510 - ($-$$) db 0

; the two last bytes of a bootsector are always AA and 55; this is a convention
; to localize the end of the boot sector program
dw 0xaa55
