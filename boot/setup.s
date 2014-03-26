.code16

#
#	setup.s		(C) 1991 Linus Torvalds (rewrite by ict-lxb)
#
# setup.s is responsible for getting the system data from the BIOS,
# and putting them into the appropriate places in system memory.
# both setup.s and system has been loaded by the bootblock.
#
# This code asks the bios for memory/disk/other parameters,and
# puts them in a "safe" place: 0x90000-0x901FF, ie where the
# boot-block used to be. It is then up to the protected mode
# system to read them from there before the area is overwritten
# for buffer-blocks.
#
#
# NOTE! These had better be the same as in bootsect.s!

INITSEG  = 0x9000	# we move boot here - out of the way
SYSSEG   = 0x1000	# system loaded at 0x10000 (65536).
SETUPSEG = 0x9020	# this is the current segment

.text

# ok, the read went well so we get current cursor position 
# and save it for posterity.

	movw $INITSEG, %ax	# this is done in bootsect already, but...
	movw %ax, %ds
	movb $0x03, %ah		# read cursor pos
	xor %bh, %bh
	int $0x10			# save it in known place, con_init fetches
	movw %dx, 0	# it from 0x90000

# Get memory size (extended mem, kB)

	movb $0x88, %ah
	int $0x15
	movw %ax, 2

# Get video-card data:
	
	movb $0x0f, %ah
	int $0x10
	movw %bx, 4		# BH = display page
	movw %ax, 6		# AL = video mode, AH = window width

# check for EGA/VGA and some config parameters

	movb $0x12, %ah
	movb $0x10, %bl
	int $0x10
	movw %ax, 8
	movw %bx, 10
	movw %cx, 12

# Get hd0 data

	xor %ax, %ax
	movw %ax, %ds
	lds 0x41*4, %si	# what is this? why is the address?
	movw $INITSEG, %ax
	movw %ax, %es
	movw $0x0080, %di
	movw $0x10, %cx
	rep
	movsb

# Get hd1 data

	xor %ax, %ax
	movw %ax, %ds
	lds 0x46*4, %si	# what is this? why is the address?
	movw $INITSEG, %ax
	movw %ax, %es
	movw $0x0090, %di
	movw $0x10, %cx
	rep
	movsb

# Check that there IS a hd1 :-)

	movw $0x1500, %ax
	movb $0x81, %dl
	int $0x13
	jc no_disk1
	cmp $3, %ah
	je is_disk1
no_disk1:
	movw $INITSEG, %ax
	movw %ax, %es
	movw $0x0090, %di
	movw $0x10, %cx
	xor %ax, %ax
	rep
	stosb
is_disk1:
	
# now we want to move to protected mode ...
	
	cli		# no interrupts allowed

# first, we move the system to its rightful place
	
	xor %ax, %ax
	cld		# 'direction' = 0, 'movs' moves forward

do_move:
	movw %ax, %es		# destination segment
	add $0x1000, %ax
	cmp $0x9000, %ax
	jz end_move
	movw %ax, %ds		# source segment
	xor %di, %di
	xor %si, %si
	movw $0x8000, %cx
	rep
	movsw
	jmp do_move

# then we load the segment descriptors

end_move:
	movw $SETUPSEG, %ax # right, forgot this at first. didn't work :-)
	movw %ax, %ds
	lidt idt_48		# load idt with 0,0
	lgdt gdt_48		# load gdt with whatever appropriate

# that was painless, now we enable A20
	call empty_8042
	movb $0xD1, %al		# command write
	outb %al, $0x64
	call empty_8042
	movb $0xDF, %al		# A20 on
	outb %al, $0x60
	call empty_8042

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.

	movb $0x11, %al		# initialization sequence
	out	%al, $0x20		# send it to 8259A-1
	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2
	out	%al, $0xA0		# and to 8259A-2
	.word	0x00eb,0x00eb
	mov	$0x20, %al		# start of hardware int's (0x20)
	out	%al, $0x21
	.word	0x00eb,0x00eb
	mov	$0x28, %al		# start of hardware int's 2 (0x28)
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0x04, %al		# 8259-1 is master
	out	%al, $0x21
	.word	0x00eb,0x00eb
	mov	$0x02, %al		# 8259-2 is slave
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0x01, %al		# 8086 mode for both
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1
	.word	0x00eb,0x00eb
	mov	$0xFF, %al		# mask off all interrupts for now
	out	%al, $0x21
	.word	0x00eb,0x00eb
	out	%al, $0xA1


# well, that certainly wasn't fun :-(. Hopefully it works, and we don't
# need no steenking BIOS anyway (except for the initial loading :-).
# The BIOS-routine wants lots of unnecessary data, and it's less
# "interesting" anyway. This is how REAL programmers do it.
#
# Well, now's the time to actually move into protected mode. To make
# things as simple as possible, we do no register set-up or anything,
# we let the gnu-compiled 32-bit programs do that. We just jump to
# absolute address 0x00000, in 32-bit protected mode.

	mov	$0x0001, %ax	# protected mode (PE) bit
	lmsw	%ax			# This is it!
	ljmp	$8, $0			# jmp offset 0 of segment 8 (cs)

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	.word	0x00eb,0x00eb
	in	$0x64, %al	# 8042 status port
	test $2, %al	# is input buffer full?
	jnz	empty_8042	# yes - loop
	ret

gdt:
	.word	0,0,0,0		# dummy

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9A00		# code read/exec
	.word	0x00C0		# granularity=4096, 386

	.word	0x07FF		# 8Mb - limit=2047 (2048*4096=8Mb)
	.word	0x0000		# base address=0
	.word	0x9200		# data read/write
	.word	0x00C0		# granularity=4096, 386

idt_48:
	.word	0			# idt limit=0
	.word	0,0			# idt base=0L

gdt_48:
	.word	0x800		# gdt limit=2048, 256 GDT entries
	.word	512+gdt,0x9	# gdt base = 0X9xxxx

.org 2048
