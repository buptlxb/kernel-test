.code16 # use bit
.text   # code segment start

	movw %cs, %ax    # cs:ip was initialized by bois instruction 'jmpi 0, 0x07c0'
	movw %ax, %ds    # initialize ds, es and ss with cs
	movw %ax, %es
	movw %ax, %ss
	movw $0x7c00, %sp    # allocate stack, get ready for call
	call disp_msg   # call the function of display message
inf:
	jmp inf # infinite loop to see the result

disp_msg:
	movb $0x03, %ah	# read cursor pos (AH = function number)
	xor %bh, %bh	# BH = page number
	int $0x10		# return (DH = row, DL = column
					# CH = cursor start line CL = cursor bottom line)

	movw len, %cx	# number of characters in string
	movw $0x000c, %bx	# BH = page number BL = attribute if string 
						# contains only characters (bit 1 of AL = 0)
	movw $msg, %bp	# ES:BP points to string to be printed
	movw $0x1301, %ax	# AH = function number
						# AL = write mode:
						# bit 0:update cursor after writing
						# bit 1:string contains attribute
	int $0x10
	ret

msg:
	.byte 13, 10
	.ascii "Hello, OS World!"
	.byte 13, 10, 13, 10
len:
	.int . - msg
	.org 510    #fill the blank
	.word 0xaa55    #maybe a magic number
