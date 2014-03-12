.code16 #use 16bit
.text #code segment start

SYSSIZE = 0x3000
SETUPLEN = 4				# nr of setup-sectors
BOOTSEG  = 0x07c0			# original address of boot-sector
INITSEG  = 0x9000			# we move boot here - out of the way
SETUPSEG = 0x9020			# setup starts here
SYSSEG   = 0x1000			# system loaded at 0x10000 (65536).
ENDSEG   = SYSSEG + SYSSIZE		# where to stop loading

# ROOT_DEV: 0x000 - same type of floppy as boot.
#			0x301 - first partition on first drive etc
ROOT_DEV = 0x306

	movw %cs, %ax #cs:ip was initialized by BOIS instruction 'jmpi 0, 0x07c0'
	movw %ax, %ds #initialize ds, es and ss with cs
	movw %ax, %es

	movw $BOOTSEG, %ax
	movw %ax, %ds
	movw $INITSEG, %ax
	movw %ax, %es
	movw $256, %cx
	xor %si, %si
	xor %di, %di
	rep
	movsw
	ljmp $INITSEG, $go
go:
	movw %cs, %ax
	movw %ax, %ds
	movw %ax, %es
# put stack at 0x9ff00
	movw %ax, %ss
	movw $0xFF00, %sp	# arbitrary value >> 512

load_setup:
	movw $0x0000, %dx	# DL = drive 0, DH = head 0
	movw $0x0002, %cx	# CL = sector 2, CH = track 0
	movw $0x0200, %bx	# address = 512, in INITSEG
	movw $0x0200+SETUPLEN, %ax	# servie 2, nr of sectors
	int $0x13			# read it
	jnc ok_load_setup	# ok - continue
	movw $0x0000, %dx	
	movw $0x0000, %ax	#reset the diskette
	int $0x13
	jmp load_setup

ok_load_setup:
	
# Get disk drive parameters, specificlly nr of sectors/track

	movb $0x00, %dl	# DL = drive index
	movw $0x0800, %ax	# AH = service number
	int $0x13	# return CX[0:5] = nr of sectors per track
				# CX[6:7][8:15] = nr of cylinders
				# es has changed
	movb $0x00, %ch	# clear CH because only nr of sectors per stack
					# will be needed. CX[6:7] is zero in floppy.
	movw %cx, %cs:sectors	# save nr of sectors per stack
	movw $INITSEG, %ax
	movw %ax, %es

# Print some message

	movb $0x03, %ah	# read cursor pos (AH = function number)
	xor %bh, %bh	# BH = page number
	int $0x10		# return (DH = row, DL = column
					# CH = cursor start line CL = cursor bottom line)

	movw $24, %cx	# number of characters in string
	movw $0x0007, %bx	# BH = page number BL = attribute if string 
						# contains only characters (bit 1 of AL = 0)
	movw $msg1, %bp	# ES:BP points to string to be printed
	movw $0x1301, %ax	# AH = function number
						# AL = write mode:
						# bit 0:update cursor after writing
						# bit 1:string contains attribute
	int $0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

	movw $SYSSEG, %ax
	movw %ax, %es	# segment of 0x10000
	call read_it
	call kill_motor

# After that we check which root-device to use. if the device is
# defined (!= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.

	movw %cs:root_dev, %ax
	cmp $0, %ax
	jne root_defined
	movw %cs:sectors, %bx
	movw $0x0208, %ax	# /dev/ps0 - 1.2Mb
	cmp $15, %bx
	je root_defined
	movw $0x021c, %ax	# /dev/PS0 - 1.44Mb
	cmp $18, %bx
	je root_defined
undef_root:
	jmp undef_root
root_defined:
	movw %ax, %cs:root_dev

# after that (everything loaded), we jump to 
# the setup-routine loaded directly after
# the bootblock:

	ljmp $SETUPSEG, $0x0

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in: es - starting address segment (normally 0x1000)
#
sread: .word 1+SETUPLEN	# sectors read of current track
head: .word 0	# current head
track: .word 0	# current track

read_it:
	movw %es, %ax
	test $0x0fff, %ax
die :
	jne die	# es must be at 64kB boundary

	xor %bx, %bx	# bx is starting addresss within segment
rp_read:
	movw %es, %ax
	cmp $ENDSEG, %ax	# have we loaded all yet?
	jb	ok1_read
	ret
ok1_read:
	movw %cs:sectors, %ax
	subw sread, %ax	# nr of sectors in the track have not been read.
	movw %ax, %cx	
	shlw $9, %cx		# nr of Bytes = nr of sectors * 512
	addw %bx, %cx	# end address
	jnc ok2_read	# is out of 64kB boundary
	je ok2_read
	xor %ax, %ax	# 0 = 64kB mod 2^16
	subw %bx, %ax	# free memory size in current segment
	shrw $9, %ax		# nr of sectors can be read in current segment
ok2_read:
	call read_track
	movw %ax, %cx
	add sread, %ax	# nr of sectors which have been read in the track 
	cmp %cs:sectors, %ax
	jne ok3_read	# have we read all sectors in the track?
	movw $1, %ax
	subw head, %ax
	jne ok4_read	# Is current head zero?
	incw track		# current head = 1, so increase track
ok4_read:
	movw %ax, head	# set current head = 1 if current head = 0
					# set current head = 0 if current head = 1 
	xor %ax, %ax	# reset sectors have been read in the track
ok3_read:	# continue reading sectors in the track
	movw %ax, sread	# update sread after read_track
	shlw $9, %cx	
	addw %cx, %bx	# update offset(BX) in the segment
	jnc rp_read		# is out of 64kB boundary
	movw %es, %ax
	addw $0x1000, %ax
	movw %ax, %es	# increase segment base address(ES) by 64kB
	xor %bx, %bx	# reset the offset(BX)
	jmp rp_read

read_track:
	push %ax
	push %bx
	push %cx
	push %dx
	movw track, %dx
	movw sread, %cx
	inc %cx
	movb %dl, %ch	# CH = track, CL = sector
	movw head, %dx
	movb %dl, %dh
	movb $0, %dl
	and $0x0100, %dx	# DH = head, DL = drive
						# make sure only drive 0, head 0/1 will be read
	movb $2, %ah	# AH = service nr, AL = nr of sectors to be read
	int $0x13
	jc bad_rt
	pop %dx
	pop %cx
	pop %bx
	pop %ax
	ret
bad_rt:
	xor %ax, %ax
	xor %dx, %dx
	int $0x13
	pop %dx
	pop %cx
	pop %bx
	pop %ax
	jmp read_track
	
# This procedure turns off the floppy drive motor, so
# that we enter the kernel in a known state, and
# don't have to worry about it later.

kill_motor:
	push %dx
	movw $0x3f2, %dx
	movb $0, %al
	outb %al, %dx
	pop %dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.org 508
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

