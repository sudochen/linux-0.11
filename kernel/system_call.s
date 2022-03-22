/*
 *  linux/kernel/system_call.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  system_call.s  contains the system-call low-level handling routines.
 * This also contains the timer-interrupt handler, as some of the code is
 * the same. The hd- and flopppy-interrupts are also here.
 *
 * NOTE: This code handles signal-recognition, which happens every time
 * after a timer-interrupt and after each system call. Ordinary interrupts
 * don't handle signal-recognition, as that would clutter them up totally
 * unnecessarily.
 *
 * Stack layout in 'ret_from_system_call':
 *
 *	 0(%esp) - %eax
 *	 4(%esp) - %ebx
 *	 8(%esp) - %ecx
 *	 C(%esp) - %edx
 *	10(%esp) - %fs
 *	14(%esp) - %es
 *	18(%esp) - %ds
 *	1C(%esp) - %eip
 *	20(%esp) - %cs
 *	24(%esp) - %eflags
 *	28(%esp) - %oldesp
 *	2C(%esp) - %oldss
 */

SIG_CHLD	= 17

EAX		= 0x00
EBX		= 0x04
ECX		= 0x08
EDX		= 0x0C
FS		= 0x10
ES		= 0x14
DS		= 0x18
EIP		= 0x1C
CS		= 0x20
EFLAGS		= 0x24
OLDESP		= 0x28
OLDSS		= 0x2C

state	= 0		# these are offsets into the task-struct.
counter	= 4
priority = 8
signal	= 12
sigaction = 16		# MUST be 16 (=len of sigaction)
blocked = (33*16)
stack_top = (33*16+4)

# offsets within sigaction
sa_handler = 0
sa_mask = 4
sa_flags = 8
sa_restorer = 12

nr_system_calls = 72

/*
 * Ok, I get parallel printer interrupts while using the floppy for some
 * strange reason. Urgel. Now I just ignore them.
 */
.globl system_call,sys_fork,timer_interrupt,sys_execve
.globl hd_interrupt,floppy_interrupt,parallel_interrupt
.globl device_not_available, coprocessor_error
.globl switch_to, first_return_from_kernel

.align 2
bad_sys_call:
	movl $-1,%eax
	iret
.align 2
reschedule:
	pushl $ret_from_sys_call
	jmp schedule

.align 2
system_call:
	cmpl $nr_system_calls-1,%eax    # �ж�ϵͳ���ú��Ƿ�Ϸ�
	ja bad_sys_call                 # ������ɺϷ�������bad_sys_call��������eax����Ϊ-1,��Ϊ����ֵ
	push %ds
	push %es
	push %fs                        # �����ѡ���ӵ����ݣ�CS��IP��ִ��INTָ��ʱ���Ѿ�ѹ��ջ�У�IRETʱ�ָ�
	pushl %edx
	pushl %ecx		                # push %ebx,%ecx,%edx as parameters
	pushl %ebx		                # to the system call
	movl $0x10,%edx		            # set up ds,es to kernel space, ����
	mov %dx,%ds                     # �������ݶ�Ϊ�ں����ݶ�
	mov %dx,%es                     # ���ø��Ӷ�Ϊ�ں����ݶΣ� �������ִ��INTָ��ʱ�Ѿ�������
	movl $0x17,%edx		            # fs points to local data space
	mov %dx,%fs                     # ����FSΪ�û���ѡ����
	call *sys_call_table(,%eax,4)   # call��ַsys_call_table + eax * 4, ������sys_fork���򣬴�ʱ�Ὣ��һ��ָ���EIP��ջ
	pushl %eax                      # ����ֵ�����eax��
	movl current,%eax               # ȡ��ǰ����ָ������eax��
	cmpl $0,state(%eax)		        # state 
	jne reschedule                  # ���state������0���������µ��ȳ���
	cmpl $0,counter(%eax)		    # counter�����������״̬����ʱ��Ƭ������Ҳִ�е��ó���
	je reschedule
ret_from_sys_call:
	movl current,%eax		        # task[0] cannot have signals
	cmpl task,%eax                  # �ж��ǲ�������0��������������3�����У�����0��ִ���źŴ���
	je 3f
	cmpw $0x0f,CS(%esp)		        # was old code segment supervisor ? ����ǵ��������ں˳���Ҳ�������źŴ���
	jne 3f
	cmpw $0x17,OLDSS(%esp)		    # was stack segment = 0x17 ?  ���ԭ��ջҲ���ں�Ҳ�˳�
	jne 3f
	movl signal(%eax),%ebx          # ȡ�ź�λͼ
	movl blocked(%eax),%ecx         # ȡ�ź�����λͼ
	notl %ecx                       # �ź�����λͼȡ��
	andl %ebx,%ecx                  # ����ź�λͼ
	bsfl %ecx,%ecx                  # ���Ϊ0���ʾû���źŴ���
	je 3f                           #   
	btrl %ecx,%ebx
	movl %ebx,signal(%eax)          # �ź�
	incl %ecx
	pushl %ecx
	call do_signal                  # �����źŴ�����
	popl %eax
3:	popl %eax
	popl %ebx
	popl %ecx
	popl %edx
	pop %fs
	pop %es
	pop %ds
	iret

.align 2
coprocessor_error:
	push %ds
	push %es
	push %fs
	pushl %edx
	pushl %ecx
	pushl %ebx
	pushl %eax
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax
	mov %ax,%fs
	pushl $ret_from_sys_call
	jmp math_error

.align 2
switch_to:
    pushl %ebp
    movl %esp,%ebp
    pushl %ecx
    pushl %ebx
    pushl %eax
    movl 8(%ebp),%ebx
    cmpl %ebx,current
    je 1f
    # switch_to PCB
    movl %ebx,%eax
	xchgl %eax,current
    # rewrite TSS pointer
    movl tss,%ecx
    addl $4096,%ebx
    movl %ebx,4(%ecx)
    # switch_to system core stack
    movl %esp,stack_top(%eax)
    movl 8(%ebp),%ebx
    movl stack_top(%ebx),%esp
    # switch_to LDT
	movl 12(%ebp), %ecx
    lldt %cx
    movl $0x17,%ecx
	mov %cx,%fs
    # nonsense
    cmpl %eax,last_task_used_math 
    jne 1f
    clts
1:    
    popl %eax
    popl %ebx
    popl %ecx
    popl %ebp
    ret

.align 2
first_return_from_kernel: 
    popl %edx
    popl %edi
    popl %esi
    pop %gs
    pop %fs
    pop %es
    pop %ds
    iret

.align 2
device_not_available:
	push %ds
	push %es
	push %fs
	pushl %edx
	pushl %ecx
	pushl %ebx
	pushl %eax
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax
	mov %ax,%fs
	pushl $ret_from_sys_call
	clts				            # clear TS so that we can use math
	movl %cr0,%eax
	testl $0x4,%eax			        # EM (math emulation bit)
	je math_state_restore
	pushl %ebp
	pushl %esi
	pushl %edi
	call math_emulate
	popl %edi
	popl %esi
	popl %ebp
	ret

.align 2
timer_interrupt:
	push %ds		                # save ds,es and put kernel data space
	push %es		                # into them. %fs is used by _system_call
	push %fs
	pushl %edx		                # we save %eax,%ecx,%edx as gcc doesn't
	pushl %ecx		                # save those across function calls. %ebx
	pushl %ebx		                # is saved as we use that in ret_sys_call
	pushl %eax                      # ���ϱ��ָ��ּĴ�������Ϊ����������ret_from_sys_call�����Ҫ����һ��ջ
	movl $0x10,%eax                 # �ں����ݶ�
	mov %ax,%ds                     # ds����Ϊ�ں����ݶ�
	mov %ax,%es                     # es����Ϊ�ں����ݶ�
	movl $0x17,%eax                 #
	mov %ax,%fs                     # fs����Ϊ�û����ݶ�
	incl jiffies                    # ����jiffies����
	movb $0x20,%al		            # EOI to interrupt controller #1�������ж�ָ��
	outb %al,$0x20                  #
	movl CS(%esp),%eax              # �Ӷ�ջ��ȡ��CS��ֵ
	andl $3,%eax		            # %eax is CPL (0 or 3, 0=supervisor)
	pushl %eax                      # eax��Ϊ������ջ
	call do_timer		            # 'do_timer(long CPL)' does everything from
	addl $4,%esp		            # task switching to accounting ... �ָ�����
	jmp ret_from_sys_call

.align 2
sys_execve:
	lea EIP(%esp),%eax              # ȡϵͳ���÷��ص�ַ�ĵ�ַ
	pushl %eax                      # ��ϵͳ���÷��ص�ַ�ĵ�ַ��ջ��Ϊ��һ������
	call do_execve                  # ִ��do_execve����
	addl $4,%esp                    # �޸�ջ
	ret                             # ����

.align 2
sys_fork:
	call find_empty_process         # Ѱ��һ���յ�task_struct
	testl %eax,%eax                 # ����eax�Ǹ�������0������Ǹ�������0������ת��1���
	js 1f
	push %gs                        # push gs esi edi ebpûʲôʵ����˼��ֻ���뽫��ǰ���жϵ��û����̵�������Ϊ�������ݵ�copy_process��
	pushl %esi
	pushl %edi
	pushl %ebp
	pushl %eax                      # eax�ǽ��̺ţ�Ҳ����find_empty_process�ķ���ֵ��Ϊ������±�
	call copy_process               # ��ջ��Ϊʲô������20, �Ҳ²�Ӧ��push %gsҲ��ռ��4���ֽڣ�ֻ�Ǹߵ�ַ������Ч
	addl $20,%esp                   # ��ԭջָ��, ��Ϊǰ��ͨ��ջ������copy_process�Ĳ���
1:	ret                             # �ӳ��򷵻�

hd_interrupt:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax
	mov %ax,%fs
	movb $0x20,%al
	outb %al,$0xA0		# EOI to interrupt controller #1
	jmp 1f			    # give port chance to breathe
1:	jmp 1f
1:	xorl %edx,%edx
	xchgl do_hd,%edx
	testl %edx,%edx
	jne 1f
	movl $unexpected_hd_interrupt,%edx
1:	outb %al,$0x20
	call *%edx		    # "interesting" way of handling intr.
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret

floppy_interrupt:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax
	mov %ax,%fs
	movb $0x20,%al
	outb %al,$0x20		# EOI to interrupt controller #1
	xorl %eax,%eax
	xchgl do_floppy,%eax
	testl %eax,%eax
	jne 1f
	movl $unexpected_floppy_interrupt,%eax
1:	call *%eax		    # "interesting" way of handling intr.
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret

parallel_interrupt:
	pushl %eax
	movb $0x20,%al
	outb %al,$0x20
	popl %eax
	iret
	
