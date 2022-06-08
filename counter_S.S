	.data
counter:	.quad 0 # Counter of which pins to light (mod 16)
GPIO:		.quad 0 # Calculated adress of program
	.text
	.global setup
	.global interrupt

interrupt:
	pushq %rax # Value of counter for the mod function
	pushq %rdx # The modulu value
	pushq %rsi # 
	pushq %rcx # Binary representation active pin
	pushq %rdi # Input for the pinOn/pinOff subrutin calls

	# increase the value of counter mod 16
	movq counter, %rax
	inc %rax
	movq $0, %rdx
	movq $16, %rsi
	divq %rsi # %rax mod 16 -> %rdx
	movq %rdx, counter

	# Update the pins
	movq $0b1000, %rcx
	movq $1, %rdi
	interrupt_iloop:
	cmp $4, %rdi
	jg interrupt_end

	# (counter mod 16) & (ob1000 >> current_pin)
	movq %rdx, %rsi # Keep the modulu value intact
	andq %rcx, %rsi
	cmp $0, %rsi
	jg interrupt_pinOn
	# Else
	jmp interrupt_pinOff

	interrupt_iloop_iter:
	inc %rdi
	shrq $1, %rcx
	jmp interrupt_iloop


	# Calls to pinOn/pinOff with a jump to return before the iteration
	interrupt_pinOn:
	# param: rdi
	call pinOn
	jmp interrupt_iloop_iter
	
	interrupt_pinOff:
	# param: rdi
	call pinOff
	jmp interrupt_iloop_iter

	interrupt_end:
	popq %rdi
	popq %rcx
	popq %rsi
	popq %rdx
	popq %rax
	ret

setup:
	pushq %rdi
	
	# Update address of GPIO
	call getAdress

	# Set all pins to 0
	movq $0, %rdi
	setup_rloop:
	cmp $4, %rdi
	jg setup_rloop_end

	# Param rdi
	call pinOff

	inc %rdi
	jmp setup_rloop

	setup_rloop_end:
	# set pin 0 to input
	# param rdi
	movq $0, %rdi
	call pinInput

	# set pin 1-4 to output
	inc %rdi
	setup_oloop:
	cmp $4, %rdi
	jg setup_end

	# param rdi
	call pinOutput

	inc %rdi
	jmp setup_oloop

	setup_end:
	popq %rdi
	ret


getAdress:
# int gpio_addr = ((0x60 << 16) | (0xFFFF & 0x1000) | (~(0x9E) & 0xFF));
	pushq %rsi



	movq $0x601061, %rsi
	movq %rsi, GPIO

	popq %rsi
	ret

pinOutput: # param: %rdi
# *(short*)gpio_addr |= (0x2 << 6) << ((4-GPIO_NR)*2);
	pushq %rdi # The input
	pushq %rax # Segments of HL (helper)
	pushq %rsi # HL
	pushq %rdx # The address of GPIO
	pushq %rcx # Imminate value

	# (0x2 << 6) = rsi
	movq $0x2, %rsi
	shlq $6, %rsi

	# ((4-GPIO_NR)*2) = rax
	movq $4, %rax
	subq %rdi, %rax
	movq $2, %rcx
	mulq %rcx

	# rsi << rax = rsi = HL
	movq %rax, %rcx # rax (aka dl) to rcx (aka cl)
	shlq %cl, %rsi

	# (*short)gpio_addr = rdx
	movq GPIO, %rdx

	# *(short*)gpio_addr = *(short*)gpio_addr | HL
	orq %rsi, (%rdx)

	popq %rcx
	popq %rdx
	popq %rsi
	popq %rax
	popq %rdi
	ret

pinInput: # param: %rdi
# *(short*)gpio_addr + (GPIO_NR/8) |= 0x3 << ((((3-GPIO_NR)*2) % 8)+8);
	pushq %rdi # input
	pushq %rax # HL
	pushq %rcx # Bitshift helper
	pushq %rsi # Temp helper
	pushq %rdx # mod result
	pushq %r8 # VL

	# VL: r8 + rax
	movq GPIO, %r8		# r8 = *((short*)GPIO)
	movq %rdi, %rax		# rax = rdi
	movq $0, %rdx		# rdx = 0
	movq $8, %rsi
	divq %rsi			# rax = rax / rsi(8)
	addq %rax, %r8	# r8 = rax + r8 = VL

	# HL: rsi << rax
	movq $3, %rax		# rax = 3
	subq %rdi, %rax		# rax - rdi
	movq $2, %rsi
	mulq %rsi			# rax *= 2
	movq $0, %rdx		# set up mod
	movq $8, %rsi		# rsi = 8
	divq %rsi			# rdx = rax mod rsi
	addq $8, %rdx		# rdx += 8
	movq $0x3, %rax		# rax = 0x3
	movq %rdx, %rcx		# rcx = rdx
	shlq %cl, %rax		# rax << cl (8lsb of rcx) (has to be cl)

	# VL |= HL
	orq %rax, (%r8)

	popq %r8
	popq %rdx
	popq %rsi
	popq %rcx
	popq %rax
	popq %rdi
	ret

pinOn: # param: %rdi
# *(int*)gpio_addr + 3 |= ((0x3 << 4)+1) << (8*(GPIO_NR-1));
	pushq %rdi # Input
	pushq %rcx # Bitshift helper
	pushq %rax # Mul helper
	pushq %r8 # local adress of GPIO
	pushq %rsi # Result of RHS
	pushq %rdx

	# LHS
	movq GPIO, %r8
	addq $3, %r8

	# RHS
	# ((0x3 << 4) + 1)
	movq $0x3, %rsi
	shlq $4, %rsi
	inc %rsi
	# (8*(GPIO_NR-1))
	movq %rdi, %rax
	dec %rax
	movq $8, %rcx
	mulq %rcx			# rax = rax*rcx
	movq %rax, %rcx
	# Combine to LHS
	shlq %cl, %rsi

	orq %rsi, (%r8)

	popq %rdx
	popq %rsi
	popq %r8
	popq %rax
	popq %rcx
	popq %rdi
	ret

pinOff: # param: %rdi
# *(int*)gpio_addr + 3 &= ~(0xCF << (8*(GPIO_NR-1)));
	pushq %rdi # Input
	pushq %rax # Mul helper
	pushq %rcx # Bitshift helper
	pushq %rsi # Local adress of GPIO
	pushq %rdx # temp variable

	# LHS
	movq GPIO, %rsi
	addq $3, %rsi
	# RHS
	movq %rdi, %rax
	dec %rax
	movq $8, %rdx
	mulq %rdx 			# rax = rdx * rax
	movq %rax, %rcx		# Val goes into rcx / cl, for bitshift prep
	movq $0xCF, %rax
	shlq %cl, %rax
	notq %rax

	andq %rax, (%rsi)

	popq %rdx
	popq %rsi
	popq %rcx
	popq %rax
	popq %rdi
	ret