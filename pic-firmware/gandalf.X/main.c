// Gandalf miner

#include <stdint.h>
#include <stdio.h>
#include <xc.h>
#include <plib.h>

// PIC32MX220F032B Configuration Bit Settings

// DEVCFG3
// USERID = No Setting
#pragma config PMDL1WAY = OFF           // Peripheral Module Disable Configuration (Allow multiple reconfigurations)
#pragma config IOL1WAY = OFF            // Peripheral Pin Select Configuration (Allow multiple reconfigurations)
#pragma config FUSBIDIO = ON            // USB USID Selection (Controlled by the USB Module)
#pragma config FVBUSONIO = ON           // USB VBUS ON Selection (Controlled by USB Module)

// DEVCFG2
#pragma config FPLLIDIV = DIV_2         // PLL Input Divider (2x Divider)
#pragma config FPLLMUL = MUL_20         // PLL Multiplier (20x Multiplier)
#pragma config UPLLIDIV = DIV_12        // USB PLL Input Divider (12x Divider)
#pragma config UPLLEN = OFF             // USB PLL Enable (Disabled and Bypassed)
#pragma config FPLLODIV = DIV_2         // System PLL Output Clock Divider (PLL Divide by 2)

// DEVCFG1
#pragma config FNOSC = PRI              // Oscillator Selection Bits (Primary Osc (XT,HS,EC))
#pragma config FSOSCEN = OFF            // Secondary Oscillator Enable (Disabled)
#pragma config IESO = OFF               // Internal/External Switch Over (Disabled)
#pragma config POSCMOD = EC             // Primary Oscillator Configuration (External clock mode)
#pragma config OSCIOFNC = ON            // CLKO Output Signal Active on the OSCO Pin (Enabled)
#pragma config FPBDIV = DIV_1           // Peripheral Clock Divisor (Pb_Clk is Sys_Clk/1)
#pragma config FCKSM = CSDCMD           // Clock Switching and Monitor Selection (Clock Switch Disable, FSCM Disabled)
#pragma config WDTPS = PS1048576        // Watchdog Timer Postscaler (1:1048576)
#pragma config WINDIS = OFF             // Watchdog Timer Window Enable (Watchdog Timer is in Non-Window Mode)
#pragma config FWDTEN = OFF             // Watchdog Timer Enable (WDT Disabled (SWDTEN Bit Controls))
#pragma config FWDTWINSZ = WISZ_25      // Watchdog Timer Window Size (Window Size is 25%)

// DEVCFG0
#pragma config JTAGEN = OFF             // JTAG Enable (JTAG Disabled)
#pragma config ICESEL = ICS_PGx3        // ICE/ICD Comm Channel Select (Communicate on PGEC3/PGED3)
#pragma config PWP = OFF                // Program Flash Write Protect (Disable)
#pragma config BWP = OFF                // Boot Flash Write Protect bit (Protection Disabled)
#pragma config CP = OFF                 // Code Protect (Protection Disabled)

#define GetSystemClock()       (25000000ul)
#define GetPeripheralClock()    (GetSystemClock())
#define CORE_TICK_RATE (GetSystemClock() / 2 / 1000) // 1mS
#define BaudRate   115200

volatile unsigned long gmscount;
volatile uint16_t blinker = 0;

#define RX_FIFO_SIZE 16
volatile uint8_t rxFifoReadIndex = 0;
volatile uint8_t rxFifoWriteIndex = 0;
volatile uint8_t rxFifo[RX_FIFO_SIZE];

#define SPI_FIFO_SIZE 8
volatile uint8_t spiFifoReadIndex = 0;
volatile uint8_t spiFifoWriteIndex = 0;
volatile uint32_t spiFifo[SPI_FIFO_SIZE];

void delay(unsigned long msdelay) {
	unsigned long startTime = gmscount;
	while (gmscount - startTime < msdelay);
}

int write(int handle, void *buffer, unsigned int len) {
	int i;
	if (!buffer || (len == 0)) return 0;
	for (i = 0; i < len; i++) {
		while (!UARTTransmitterIsReady(UART1));
		UARTSendDataByte(UART1, ((char*) buffer)[i]);
	}
	return len;
}

// UART 1 interrupt handler, set at priority level 1
void __ISR(_UART1_VECTOR, ipl1) IntUart1Handler(void) {
	// test overrun flag, which has to be cleared in software
	if (U1STA & UART_OVERRUN_ERROR) {
		U1STACLR = UART_OVERRUN_ERROR;
	} else {
		// test if a byte was received
		if (INTGetFlag(INT_SOURCE_UART_RX(UART1))) {
			rxFifo[rxFifoWriteIndex] = UARTGetDataByte(UART1);
			rxFifoWriteIndex = (rxFifoWriteIndex + 1) & (RX_FIFO_SIZE - 1);
		}
	}

	// clear all UART1 interrupt request flags
	INTClearFlag(INT_SOURCE_UART(UART1));
}

// core timer interrupt handler, set at priority level 2
void __ISR(_CORE_TIMER_VECTOR, ipl2) CoreTimerHandler(void) {
	gmscount++;
	blinker++;
	UpdateCoreTimer(CORE_TICK_RATE);
	mCTClearIntFlag();
}

// SPI 2 interrupt handler, set at priority level 3
void __ISR(_SPI_2_VECTOR, ipl3) _SPI2Handler(void) {
	// clear overflow condition, if set
	SpiChnGetRov(SPI_CHANNEL2, TRUE);

	// save data to FIFO, if received
	if (SpiChnDataRdy(SPI_CHANNEL2)) {
		spiFifo[spiFifoWriteIndex] = SpiChnReadC(SPI_CHANNEL2);
		spiFifoWriteIndex = (spiFifoWriteIndex + 1) & (SPI_FIFO_SIZE - 1);
	}
	
	// clear all SPI2 interrupt request flags
	INTClearFlag(INT_SOURCE_SPI(SPI_CHANNEL2));
}

static void initSpi() {
	// configure SPI2
	SpiChnClose(SPI_CHANNEL2);
	SpiChnOpen(SPI_CHANNEL2, SPI_OPEN_SLVEN | SPI_OPEN_MODE32 | SPI_OPEN_CKP_HIGH | SPI_OPEN_DISSDO, 4);

	// configure SPI2 RX interrupt
	INTSetVectorPriority(INT_VECTOR_SPI(SPI_CHANNEL2), INT_PRIORITY_LEVEL_3);
	INTSetVectorSubPriority(INT_VECTOR_SPI(SPI_CHANNEL2), INT_SUB_PRIORITY_LEVEL_0);
	INTEnable(INT_SOURCE_SPI_RX(SPI_CHANNEL2), INT_ENABLED);
}

static void setAvalonReset(int flag) {
	if (flag) {
		mPORTBSetBits(BIT_1);
	} else {
		mPORTBClearBits(BIT_1);
	}
}

static void setAvalonConfigP(int flag) {
	if (flag) {
		mPORTASetBits(BIT_4);
	} else {
		mPORTAClearBits(BIT_4);
	}
}

static void setAvalonConfigN(int flag) {
	if (flag) {
		mPORTBSetBits(BIT_0);
	} else {
		mPORTBClearBits(BIT_0);
	}
}

static void bitDelay() {
	volatile int i;
	for (i = 0; i < 30; i++) {
		asm("nop");
	}
}

static void avalonSend(uint8_t data) {
	int i;
	for (i = 0; i < 4; i++) {
		setAvalonConfigP(0);
		setAvalonConfigN(0);
		bitDelay();
		if (data & 1) {
			setAvalonConfigP(1);
		} else {
			setAvalonConfigN(1);
		}
		data >>= 1;
		bitDelay();
	}
	bitDelay();
}

static void avalonSendIdle() {
	setAvalonConfigP(1);
	setAvalonConfigN(1);
}

main() {
	SYSTEMConfig(GetSystemClock(), SYS_CFG_WAIT_STATES | SYS_CFG_PCACHE);
	OpenCoreTimer(CORE_TICK_RATE);
	mConfigIntCoreTimer((CT_INT_ON | CT_INT_PRIOR_2 | CT_INT_SUB_PRIOR_0));
	INTEnableSystemMultiVectoredInt();

	// Avalon reset
	mPORTBClearBits(BIT_1);
	mPORTBSetPinsDigitalOut(BIT_1);

	// Avalon config P
	mPORTASetBits(BIT_4);
	mPORTASetPinsDigitalOut(BIT_4);

	// Avalon config N
	mPORTBSetBits(BIT_0);
	mPORTBSetPinsDigitalOut(BIT_0);

	// LED
	mPORTBClearBits(BIT_4);
	mPORTBSetPinsDigitalOut(BIT_4);

	// UART2 TX
	mPORTBSetBits(BIT_3);
	mPORTBSetPinsDigitalOut(BIT_3);

	// UART2 RX
	mPORTBSetPinsDigitalIn(BIT_13);

	// SPI SCK
	mPORTBSetPinsDigitalIn(BIT_15);

	// SPI RX
	mPORTBSetPinsDigitalIn(BIT_2);

	// pin mapping
	PPSUnLock;
	PPSOutput(1, RPB3, U1TX);
	PPSInput(3, U1RX, RPB13);
	PPSInput(3, SDI2, RPB2);
	PPSLock;

	// configure UART1
	UARTConfigure(UART1, UART_ENABLE_PINS_TX_RX_ONLY);
	UARTSetLineControl(UART1, UART_DATA_SIZE_8_BITS | UART_PARITY_NONE | UART_STOP_BITS_1);
	UARTSetDataRate(UART1, GetPeripheralClock(), BaudRate);
	UARTEnable(UART1, UART_ENABLE_FLAGS(UART_PERIPHERAL | UART_RX | UART_TX));

	// configure UART1 RX interrupt
	INTSetVectorPriority(INT_VECTOR_UART(UART1), INT_PRIORITY_LEVEL_1);
	INTSetVectorSubPriority(INT_VECTOR_UART(UART1), INT_SUB_PRIORITY_LEVEL_0);
	INTEnable(INT_SOURCE_UART_RX(UART1), INT_ENABLED);
	INTEnable(INT_SOURCE_UART_ERROR(UART1), INT_ENABLED);

	delay(20);
	initSpi();

	// show startup message
	/*
	delay(20);
	printf("\nGandalf Miner V0.1\n");
	delay(20);
	*/

	// command loop
	while (1) {
		if (blinker > 500) {
			// LED blinking
			blinker -= 500;
			PORTToggleBits(IOPORT_B, BIT_4);
		}

		// eval command
		if (rxFifoReadIndex != rxFifoWriteIndex) {
			uint8_t data = rxFifo[rxFifoReadIndex];
			rxFifoReadIndex = (rxFifoReadIndex + 1) & (RX_FIFO_SIZE - 1);
			switch (data >> 4) {
				case 0:
					avalonSend(data & 0xf);
					break;
				case 1:
					avalonSendIdle();
					break;
				case 2:
					setAvalonReset(data & 1);
					if ((data & 1) == 0) initSpi();
					break;
			}
		}

		// send received SPI data
		if (spiFifoReadIndex != spiFifoWriteIndex) {
			uint32_t data = spiFifo[spiFifoReadIndex];
			spiFifoReadIndex = (spiFifoReadIndex + 1) & (SPI_FIFO_SIZE - 1);
			int i;
			for (i = 0; i < 32; i++) {
				while (!UARTTransmitterIsReady(UART1));
				if (data & 0x80000000) {
					UARTSendDataByte(UART1, 1);
				} else {
					UARTSendDataByte(UART1, 0);
				}
				data <<= 1;
			}
		}
	}
}
