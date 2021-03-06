;-----------------------------------------------------------------------------
; Input/Output basic routines
;-----------------------------------------------------------------------------

file_not_found                  db "file not found", 0

; the location of the root directory on the disk is from 0x5800 to 0xA000

; the starting LBA sector of the root directory is sector 44 (byte 0x5800 / 512 = 44)
root_dir_starting_sector        dw 44

; the root directory is 36 sectors long (18 432 bytes long)
root_dir_sectors_amount         dw 36

; the location of the first FAT on the disk is from 0x0800 to 0x2FFF

; the starting LBA sector of the FAT is sector 4 (byte 0x0800 / 512 = 4)
fat_starting_sector             dw 4

; the fat is 17 sectors long
fat_sectors_amount              dw 17

; used for har drive sectors LBA/CHS conversions

; the disk has 63 sectors per track
sectors_per_track               dw 63

; the disk has 16 heads to read/write data
heads_amount                    dw 16

; there are 576 entries into the root directory
; FIXME: #50 check why and fix it if necessary (usually 512 entries only)
root_dir_entries                dw 576

; the filename length (including extension) is 11 characters
filename_length                 dw 11

; the size of bytes into one directory entry is 32 bytes long
root_dir_entry_size             dw 32

; file first cluster into a root directory entry is at byte 26
root_entry_file_first_cluster   dw 26

; the first data sector on disk is the sector 80
; (the first byte is at 0xA000, so 0xA000 / 512 = 80)
first_data_sector               dw 80

; the first entries of the FAT must be ignored;
; there are three reserved entries on the FAT
; TODO: #33 it should be 2 and not 3
fat_reserved_entries            dw 3

; every cluster on disk is 4 sectors long (check boot sector BPB values)
; (default value generated by `mkfs.vfat -v -F16` from makefile)
sectors_per_cluster             dw 4

;-----------------------------------------------------------------------------
; Displays every character from the given address, until 0 is found
;-----------------------------------------------------------------------------
; DS: data segment of the content to display
; SI: byte offset of the character to display (the first one at the first call)
;-----------------------------------------------------------------------------
print:

    ; move DS:SI content into AL and increment SI,
    ; AL contains the current character, SI points to the next character
    lodsb

    ; ends the function if the current character is 0
    or al, al          ; is al = 0 ? (end of the string)
    jz print_end       ; if al = 0, ends the process (OR returns 0 if both operands are 0)

    ; print the character stored into AL on screen
    mov ah, 0x0E       ; the function to write one character is 0x0E
    int 0x10           ; call the video interrupt
    jmp print          ; jump to the beginning of the loop to write following characters

    print_end:
        ret

;-----------------------------------------------------------------------------
; Loads the FAT16 root directory from the hard disk to 0x0A000 - 0x0E800
;-----------------------------------------------------------------------------

load_root:

    ; the root directory is loaded at 0x0A000 (0x0A00:0x0000)
    mov bx, 0x0A00
    mov es, bx
    xor bx, bx

    ; the first sector to read is the first root directory sector
    mov ax, word [root_dir_starting_sector]

    ; the amount of sectors to read is the root directory sectors amount
    mov cx, [root_dir_sectors_amount]

    call read_sectors
    ret

;-----------------------------------------------------------------------------
; Loads the FAT16 first FAT from the hard disk to 0x0E800 - 0x10FFF
;-----------------------------------------------------------------------------

load_fat:

    ; the FAT is loaded at 0x0E800, right after the root directory (0x0E80:0x0000)
    mov bx, 0x0E80
    mov es, bx
    xor bx, bx

    ; the first sector to read is the first FAT sector
    mov ax, word [fat_starting_sector]

    ; the amount of sectors to read is the FAT sectors amount
    mov cx, word [fat_sectors_amount]

    call read_sectors
    ret

;-----------------------------------------------------------------------------
; Reads sector(s) on the disk and loads it in memory at the expected location
;-----------------------------------------------------------------------------
; AX: LBA sector to read
; CX: number of sector(s) to read
; ES:BX: memory location where sectors are written
;-----------------------------------------------------------------------------

read_sectors:

    ; bx, cx and dx are used for CHS calculation, but they also contain
    ; the number of sectors to read and the memory location to fill
    ; used after the computation, so we push them on the stack
    push dx
    push bx
    push cx

    ; calculate the absolute sector
    ; -> sector = (logical sector % sectors per track) + 1
    xor dx, dx                      ; div [word] actually takes the dividend from dx and ax,
                                    ; (dx for high bits and ax for low bits),
                                    ; we only want to considere the ax content,
                                    ; so all the dx bits are set to 0
    div word [sectors_per_track]    ; div [word] stores the result into ax and rest into dx
                                    ; so now dx = (logical sector % sectors per track) and
                                    ; ax = (logical sector / sectors per track)
    inc dx                          ; increment dx, so now dx = (logical sector % sectors per track) + 1
    ; the CHS sector is now into dx

    ; the dx register is used for the head and the track calculation,
    ; so we store the sector into the bx register,
    ; that won't be used into the next computations
    mov bx, dx

    ; calculate the absolute head and absolute track
    ; -> head = (logical sector / sectors per track) % number of heads
    ; -> cylinder = (logical sector / sectors per track) / number of heads
    xor dx, dx                      ; same reason as for the CHS sector calculation just before
    div word [heads_amount]
    ; the CHS cylinder is now into ax, the CHS head is now into dx

    ; read the sectors
    mov ch, al                      ; ch stores the cylinder number, currently stored into ax

    pop ax                          ; al stores the amount of sectors to read, currently stored into the stack
    mov ah, 0x02                    ; ah stores the function to read sectors (0x02)

    mov cl, bl                      ; cl stores the sector number to read for bit from 0 to 5,
                                    ; currently stored into bx;

                                    ; NOTE: bits 6 and 7 are bits 8 and 9 of the cylinder number,
                                    ; we just dont considere this constraint at all in that case,
                                    ; this code is not supposed to manipulate high cylinder numbers

    pop bx                          ; es:bx contains the address where sectors must be written,
                                    ; the offset is currently on the stack

    mov dh, dl                      ; dh stores the head number, currently stored into dx
                                    ; (so we can simply ignore dh content and replace it by dl)
    mov dl, 0x80                    ; unit to use (0x80 for hard drive, less for floppy)
    int 0x13

    pop dx                          ; dx has been pushed previously
    ret

;-----------------------------------------------------------------------------
; load a given file into memory, the name of the file to search from the root
; directory is located at DS:SI, the location where the file has to be written
; into the memory is ES:BX.
;-----------------------------------------------------------------------------
; DS: data segment of the file name to find
; SI: the address of the string of the file name to find (DS:SI)
; ES:BX: location where the whole file must be loaded
;-----------------------------------------------------------------------------

load_file:

        ; push on the stack the functions arguments required later
        ; but stored for now into registers required right now
        push bx
        push es
        push di

        ; set ES:DI to the root directory location (0x0A00:0x0000)
        ; in order to read one by one the root directory entries
        ; in order to find the searched file
        mov bx, 0x0A00
        mov es, bx
        mov di, 0x0000

        ; the maximum amount of iterations over the root directory entries
        ; is equal to the amount of root directory entries (576)
        mov cx, word [root_dir_entries]

    .SEARCH_FILE_LOOP

        ; push cx and di on stack as they are modified by rep cmpsb
        ; during the searched file name and root entry file name comparison
        push cx
        push di
        push si

        ; check if the current root directory entry file name
        ; is the same as the searched file
        ; (compare the 11 characters one by one between ES:DI and DS:SI)
        mov cx, word [filename_length]  ; there are 11 characters to compare,
                                        ; cx must be equal to the amount of comparisons
                                        ; for rep cmpsb
        rep cmpsb                       ; repeat 11 times (cx times) comparison between es:di
                                        ; and ds:si by incrementing SI and DI everytime
        je .FOUND_FILE                  ; the two strings are equal, the file is found

        ; get back di and cx from the stack, they are used for the loop that checks
        ; the root directory entries one by one
        pop si
        pop di
        pop cx

        ; di is now equal to the address of the previous compared root entry filename character;
        ; we add to it 32 bytes in order to point on the first character of the filename
        ; of the next root entry
        add di, word [root_dir_entry_size]

        ; repeat the search file process, decrement cx by 1,
        ; does not jump back and continues if cx == 0
        ; (that means every root directory entry has been browsed)
        loop .SEARCH_FILE_LOOP

        ; the file has not been found, an error message is displayed
        ; and the system is halted
        ;
        ; NOTE: as the system is directly halted, we do not clear the stack content
        mov si, file_not_found
        call print
        hlt

    .FOUND_FILE

        ; in order to keep the stack balanced, the values pushed for the file search
        ; (at SEARCH_FILE_LOOP) are removed from the stack
        pop si
        pop di
        pop cx
        ; di now contains the first byte of the found file root entry

        ; add to the di offset the number of bytes to bypass
        ; in order to point on the file first sector
        ; (26 bytes after the entry starts)
        add di, word [root_entry_file_first_cluster]

        ; data from the root directory has to be read,
        ; so the current ds address is pushed on stack temporarily
        push ds

        ; read the position of the first sector of the file from the root directory,
        ; (the root directory is loaded at 0xA000:0x0000)
        mov bx, 0x0A00
        mov ds, bx
        mov dx, word [di]
        ; dx now contains the file first sector position on disk

        ; get back the current data segment from the stack
        pop ds

        ; get back the location where the file has to be loaded in memory
        ; these values were pushed at the very beginning of the function
        ; as their registers were used for computations
        pop di
        pop es
        pop bx

    .LOAD_FILE

        ; FIXME: #58 for refactoring purposes, this section is only able to read one sector
        ; from the disk. Instead, it should iterate over all the sectors of the file
        ; until the file is fully loaded.

        ; keep track of the file first sector index (from the beginning of the data area index),
        ; as we need to apply some calculations on this value in order to find the sector
        ; to read from the beginning of the disk
        mov ax, dx

        ; the FAT contains some initial sectors that are not considered when loading a file
        ; when iterating over a file cluster (there are three initial FAT entries to ignore)
        sub ax, word [fat_reserved_entries]  ; remove the three initial FAT entries

        ; we want to find the absolute sector to read, as one cluster contains four sectors,
        ; then we have to multiply the cluster index by the sectors amount per cluster

        ; IMPORTANT: mul stores its result in dx:ax, we ignore dx, so this code does
        ; not work when high values are computed...
        push dx                             ; dx is modified by mul and we want to keep its value
        mul word [sectors_per_cluster]      ; multiply ax and stores the result in dx:ax
        pop dx                              ; get back dx (cluster index)

        ; the data area starts at the sector 80, so it is necessary to add 80
        ; to the cluster value as this value is relative to the beginning of the data area
        add ax, word [first_data_sector]     ; the first data sector is at sector 80 on disk
        ; ax now contains the logical sector to read
        ; (required as an input of read_sectors)

        ; we load one cluster at a time (one cluster is 4 sectors long on disk)
        mov cx, word [sectors_per_cluster]

        call read_sectors

        ; check if others clusters have to be loaded,
        ; the FAT content must be read

        push ds     ; temporary change the data segment in order to read the FAT
        push bx     ; bx contains the offset where to load the file,
                    ; and its content is going to be modified in the following computations

        ; the FAT is loaded at 0x0E800,
        ; right after the root directory (0x0E80:0x0000)
        mov bx, 0x0E80
        mov ds, bx

        ; get back the current cluster index and find its value from the FAT
        ; (in order to know if the file is finished or if another cluster
        ; has to be loaded)
        mov ax, dx
        mov bx, 2
        mul bx
        mov bx, ax
        mov dx, word [bx]

        pop bx
        pop ds      ; get back previous data segment and loading offset

        ; one cluster has been loaded and bx contains the offset to the beginning of that cluster,
        ; every cluster is four sectors long (2048 bytes), so if another cluster has to be loaded
        ; for the current file, then it has to be loaded 2048 bytes after
        add bx, 2048

        ; check if the cluster is the end of the file
        cmp dx, 0xFFFF
        jne .LOAD_FILE

        ret
