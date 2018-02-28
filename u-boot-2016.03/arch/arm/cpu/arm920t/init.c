/* NAND FLASH控制器 */
#define NFCONF (*((volatile unsigned long *)0x4E000000))
#define NFCONT (*((volatile unsigned long *)0x4E000004))
#define NFCMMD (*((volatile unsigned char *)0x4E000008))
#define NFADDR (*((volatile unsigned char *)0x4E00000C))
#define NFDATA (*((volatile unsigned char *)0x4E000010))
#define NFSTAT (*((volatile unsigned char *)0x4E000020))

/* CLK */
#define CLKDIVN  (*(volatile unsigned long *)0x4C000014)
#define MPLLCON  (*(volatile unsigned long *)0x4C000004) 

/* SDRAM */
#define BWSCON    (*(volatile unsigned long *)0x48000000) 
#define BANKCON4  (*(volatile unsigned long *)0x48000014) 
#define BANKCON6  (*(volatile unsigned long *)0x4800001c) 
#define REFRESH   (*(volatile unsigned long *)0x48000024) 
#define BANKSIZE  (*(volatile unsigned long *)0x48000028) 
#define MRSRB6    (*(volatile unsigned long *)0x4800002c)

void init_clock(void)
{
    //Mpll = 400M
    MPLLCON = (0x5c<<12) | (1<<4) | 1;
    //FCLK 400M HCLK 100M PCLK 50M
    CLKDIVN = 2<<1 | 1<<0;
    __asm__(
        "mrc  p15,0,r0,c1,c0,0\n" 
        "orr  r0,r0,#0xc0000000\n"
        "mcr  p15,0,r0,c1,c0,0\n" 
    );
}

void init_sdram(void)
{
    #if 1
    BWSCON   = 0x22011110;
    BANKCON4 = 0x00000740;
    BANKCON6 = 0x00018005;
    REFRESH  = 0x008C04F4;
    BANKSIZE = 0x000000B1;
    MRSRB6   = 0x30;
    #else
    BWSCON   = 1<<25 | 1<<16;
    BANKCON4 = 0x00000740;
    BANKCON6 = 1<<16 | 1<<15 | 1;
    REFRESH  = (1<<23) + 1268;
    BANKSIZE = 1<<7 | 1<<4 | 1;
    MRSRB6   = 0x30;
    #endif
}

void clear_bss(void)
{
    extern int __bss_start, __bss_end;
    int *p = &__bss_start;
    
    for (; p < &__bss_end; p++)
    {    
        *p = 0;
    }
}

static void nand_latency(void)
{
    int i=100;
    while(i--);
}

static void nand_is_ready(void)
{
    //bit 0 : 1 不忙了
    while(! (NFSTAT & 1));
}

static void nand_write_addr(unsigned int addr)
{
    int col, page;
    col = addr % 2048;
    page = addr / 2048;
    
    NFADDR = col & 0xff;            /* Column Address A0~A7 */
    nand_latency();        
    NFADDR = (col >> 8) & 0x0f;     /* Column Address A8~A11 */
    nand_latency();
    NFADDR = page & 0xff;            /* Row Address A12~A19 */
    nand_latency();
    NFADDR = (page >> 8) & 0xff;    /* Row Address A20~A27 */
    nand_latency();
    NFADDR = (page >> 16) & 0x03;    /* Row Address A28~A29 */
    nand_latency();
}

static unsigned char nand_read_char(void)
{
    //只保留8个bit
    return NFDATA & 0xff;
}

static void nand_cmd(unsigned char cmd)
{
    NFCMMD = cmd;
    nand_latency();
}

static void nand_select_chip(void)
{
    //1bit : 0 选中
    NFCONT &= ~(1<<1);
}

static void nand_deselect_chip(void)
{
    //1bit : 1 选中
    NFCONT |= (1<<1);
}

static void nand_reset(void)
{
    nand_select_chip();
    nand_cmd(0xff);
    nand_deselect_chip();
}

void nand_init_ll(void)
{    
    //TACLS 3.3v 时 12ns
    #define TACLS   0
    //12ns
    #define TWRPH0  1
    //5ns
    #define TWRPH1  0
    NFCONF = TACLS<<12 | TWRPH0<<8 |  TWRPH1<<4;
    /* 4 ECC
     * 1 CE 先不选中，用的时候在选中
     * 0 启动 flash controller
     */
    NFCONT = 1<<4 | 1<<1 | 1;
    nand_reset();
}

static void nand_read(unsigned int addr, unsigned char *buf, int len)
{
    //选中
    nand_select_chip();
    //j 地址可能不是从0对齐开始读的
    unsigned int i = addr,j = addr % 2048;
    for(; i<(addr + len);)
    {
        //读命令
        nand_cmd(0x00);
        nand_is_ready();
        
        //发送地址
        nand_write_addr(i);
        nand_is_ready();
    
        //在次发出读命令
        nand_cmd(0x30);
        nand_is_ready();
        //读2K
        for(; j<2048; j++)
        {
            *buf = nand_read_char();
            buf++;
            i++;
        }
        j=0;
        nand_latency();
    }
    //取消选中
    nand_deselect_chip();
}

static int boot_is_nor(void)
{
    //利用 NOR 不能写的特点判断
    volatile unsigned int *p = (volatile unsigned int *)0;
    unsigned int val;
    val = *p;
    *p = 0x12345678;
    if(0x12345678 == *p)
    {
        *p = val;
        return 0;
    }
    return 1;
}

//片内4K 的程序要复制到链接SDRAM中去
void copy_code_to_sdram(unsigned char *src,unsigned char *dst,int len)
{
    int i = 0;
    if(boot_is_nor())
    {
        while(i < len)
        {
            dst[i] = src[i];
            i++;
        }
    }
    else
    {
        nand_read((int)src, dst, len);
    }
}

