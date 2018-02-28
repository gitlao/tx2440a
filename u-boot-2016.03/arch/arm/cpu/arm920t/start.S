/*
 *  armboot - Startup Code for ARM920 CPU-core
 *
 *  Copyright (c) 2001	Marius Gr枚ger <mag@sysgo.de>
 *  Copyright (c) 2002	Alex Z眉pke <azu@sysgo.de>
 *  Copyright (c) 2002	Gary Jennejohn <garyj@denx.de>
 *
 * SPDX-License-Identifier:	GPL-2.0+
 */

#include <asm-offsets.h>
#include <common.h>
#include <config.h>

/*
 *************************************************************************
 *
 * Startup Code (called from the ARM reset exception vector)
 *
 * do important init only if we don't start from memory!
 * relocate armboot to ram
 * setup stack
 * jump to second stage
 *
 *************************************************************************
 */

	.globl	reset

reset:
	/*
	 * set the cpu to SVC32 mode
	 */
	mrs	r0, cpsr
	bic	r0, r0, #0x1f
	orr	r0, r0, #0xd3
	msr	cpsr, r0

#if	defined(CONFIG_AT91RM9200DK) || defined(CONFIG_AT91RM9200EK)
	/*
	 * relocate exception table
	 */
	ldr	r0, =_start
	ldr	r1, =0x0
	mov	r2, #16
copyex:
	subs	r2, r2, #1
	ldr	r3, [r0], #4
	str	r3, [r1], #4
	bne	copyex
#endif

#ifdef CONFIG_S3C24X0
	/* turn off the watchdog */

# if defined(CONFIG_S3C2400)
#  define pWTCON	0x15300000
#  define INTMSK	0x14400008	/* Interrupt-Controller base addresses */
#  define CLKDIVN	0x14800014	/* clock divisor register */
#else
#  define pWTCON	0x53000000
#  define INTMSK	0x4A000008	/* Interrupt-Controller base addresses */
#  define INTSUBMSK	0x4A00001C
#  define CLKDIVN	0x4C000014	/* clock divisor register */
# endif

#  define CLK_CTL_BASE	0x4C000000
#  define MDIV_405	0x7f << 12
#  define PSDIV_405	0x21
#  define MDIV_400	0x5c << 12
#  define PSDIV_400	0x21
#  define MDIV_200	0xa1 << 12
#  define PSDIV_200	0x31
#  define UMDIV     0x38 << 12
#  define UPSDIV    0x22

	ldr	r0, =pWTCON
	mov	r1, #0x0
	str	r1, [r0]

	/*
	 * mask all IRQs by setting all bits in the INTMR - default
	 */
	mov	r1, #0xffffffff
	ldr	r0, =INTMSK
	str	r1, [r0]
# if defined(CONFIG_S3C2410)
	ldr	r1, =0x3ff
	ldr	r0, =INTSUBMSK
	str	r1, [r0]
# endif
# if defined(CONFIG_S3C2440)
	ldr	r1, =0x7fff
	ldr	r0, =INTSUBMSK
	str	r1, [r0]
# endif
#if defined(CONFIG_S3C2440)
	/* FCLK:HCLK:PCLK = 1:4:8 */
	ldr	r0, =CLKDIVN
	mov	r1, #5
	str	r1, [r0]
	
	mrc	p15, 0, r1, c1, c0, 0	
	orr	r1, r1, #0xc0000000		
	mcr	p15, 0, r1, c1, c0, 0	

    /* 系统主频设置为405MHZ，USB时钟频率设置为48MHZ*/

    mov r1, #CLK_CTL_BASE
    
    mov r2, #0xFFFFFF
    str r2, [r1]            /* LOCKTIME */
    
#if 1/* 可在board_early_init_f中初始化 */

    /* When you set MPLL&UPLL values, you have to set the UPLL value first and then the MPLL value. 
          (Needs intervals approximately 7 NOP) -- S3C2440A 32-Bit CMOS Microcontroller User's Manual, Revision 1*/

    mov r2, #UMDIV   
    add r2, r2, #UPSDIV  
    str r2, [r1, #0x08]     /* UPLLCON */
/*
    nop
    nop
    nop
    nop
    nop
    nop
    nop
*/
    /* delay 4000 */
    mov r2, #4000 
delay:
    sub r2, r2, #1
    cmp r2, #0
    bne delay

#endif

	mov	r2, #MDIV_405	
	add	r2, r2, #PSDIV_405	
	str	r2, [r1, #0x04]		/* MPLLCON */

#else
	/* FCLK:HCLK:PCLK = 1:2:4 */
	/* default FCLK is 120 MHz ! */
	ldr	r0, =CLKDIVN
	mov	r1, #3
	str	r1, [r0]
	mrc	p15, 0, r1, c1, c0, 0	
	orr	r1, r1, #0xc0000000	
	mcr	p15, 0, r1, c1, c0, 0	
	
	
	mov	r1, #CLK_CTL_BASE	
	mov	r2, #MDIV_200	
	add	r2, r2, #PSDIV_200	
	str	r2, [r1, #0x04]
#endif	
#endif	/* CONFIG_S3C24X0 */

#if 1
	/*
	 * flush v4 I/D caches
	 */
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache */
	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	/*
	 * disable MMU stuff and caches
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002300	@ clear bits 13, 9:8 (--V- --RS)
	bic	r0, r0, #0x00000087	@ clear bits 7, 2:0 (B--- -CAM)
	orr	r0, r0, #0x00000002	@ set bit 1 (A) Align
	orr	r0, r0, #0x00001000	@ set bit 12 (I) I-Cache
	mcr	p15, 0, r0, c1, c0, 0

	/**		
	  * 调用 init.c 中的初始化		
	  * 因为已经初始化好内存 所以 sp 在 顶部 		
	  * 在 NOR 时不能用片内 4K		*/
	ldr sp, =4096
	bl init_sdram
	ldr sp, =0x34000000
	bl nand_init_ll
	/**		
	  * 从 0 地址开始复制 到 SDRAM 中		
	  * 在 smdk2440.h 中定义 #define CONFIG_SYS_TEXT_BASE		
	  * u-boot 的加载地址		*/
	mov r0,#0
	ldr r1, =CONFIG_SYS_TEXT_BASE
	ldr r2, =__bss_start
	sub r2, r2, r1
	bl copy_code_to_sdram
	bl clear_bss
	/* 从片内 4K 跳到 SDRAM 中 bl 不行，要用 ldr pc */	
	ldr pc, =_main
#else
	/*
	 * we do sys-critical inits only at reboot,
	 * not when booting from ram!
	 */
#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	bl	cpu_init_crit
#endif

	bl	_main
#endif

/*------------------------------------------------------------------------------*/

	.globl	c_runtime_cpu_setup
c_runtime_cpu_setup:

	mov	pc, lr

/*
 *************************************************************************
 *
 * CPU_init_critical registers
 *
 * setup important registers
 * setup memory timing
 *
 *************************************************************************
 */


#ifndef CONFIG_SKIP_LOWLEVEL_INIT
cpu_init_crit:
	/*
	 * flush v4 I/D caches
	 */
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache */
	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	/*
	 * disable MMU stuff and caches
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002300	@ clear bits 13, 9:8 (--V- --RS)
	bic	r0, r0, #0x00000087	@ clear bits 7, 2:0 (B--- -CAM)
	orr	r0, r0, #0x00000002	@ set bit 1 (A) Align
	orr	r0, r0, #0x00001000	@ set bit 12 (I) I-Cache
	mcr	p15, 0, r0, c1, c0, 0

	/*
	 * before relocating, we have to setup RAM timing
	 * because memory timing is board-dependend, you will
	 * find a lowlevel_init.S in your board directory.
	 */
	mov	ip, lr

	bl	lowlevel_init

	mov	lr, ip
	mov	pc, lr
#endif /* CONFIG_SKIP_LOWLEVEL_INIT */
