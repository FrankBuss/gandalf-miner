library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use work.all;

entity main is
	port (
		CLOCK_50: in std_logic;
		GPIO_1: inout std_logic_vector(33 downto 0);
		LED: inout std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of main is
	constant system_speed: natural := 64e6;
	constant baudrate: natural := 115200;

	signal clock64: std_logic := '0';
	signal clock25_latch: std_logic := '0';

	signal rs232_sender_data: unsigned(7 downto 0);
	signal rs232_sender_start: std_logic;
	signal rs232_sender_busy: std_logic;
	signal rs232_receiver_data: unsigned(7 downto 0);
	signal rs232_receiver_received: std_logic;

	signal fifo_data: std_logic_vector(7 downto 0);
	signal fifo_rdreq: std_logic := '0';
	signal fifo_wrreq: std_logic := '0';
	signal fifo_empty: std_logic;
	signal fifo_q: std_logic_vector(7 downto 0);
	
	signal avalon_sender_data: unsigned(3 downto 0);
	signal avalon_sender_start: std_logic;
	signal avalon_sender_set_idle: std_logic;
	signal avalon_sender_busy: std_logic;
	signal avalon_receiver_data: std_logic;
	signal avalon_receiver_received: std_logic;
	
	signal avalon_reset: std_logic := '0';

	signal debugOut: std_logic_vector(3 downto 0);

begin

	pll: clock
	port map (
		areset => '0',
		inclk0 => CLOCK_50,
		c0 => clock64,
		locked => open
	);

	rs232_sender_inst: entity rs232_sender
	generic map(system_speed, baudrate)
	port map(
		clock => clock64,
		data => rs232_sender_data,
		start => rs232_sender_start,
		busy => rs232_sender_busy,
		tx => GPIO_1(32));

	rs232_receiver_inst: entity rs232_receiver
	generic map(system_speed, baudrate)
	port map(
		clock => clock64,
		data => rs232_receiver_data,
		received => rs232_receiver_received,
		rx => GPIO_1(30));

	fifo_inst: entity fifo
	port map(
		clock => clock64,
		data => fifo_data,
		rdreq => fifo_rdreq,
		wrreq => fifo_wrreq,
		empty => fifo_empty,
		q => fifo_q);

	avalon_sender_inst: entity avalon_sender
	generic map(system_speed)
	port map(
		clock => clock64,
		data => avalon_sender_data,
		start => avalon_sender_start,
		set_idle => avalon_sender_set_idle,
		busy => avalon_sender_busy,
		tx_p => GPIO_1(21),
		tx_n => GPIO_1(19));

	avalon_receiver_inst: entity avalon_receiver
	generic map(system_speed)
	port map(
		clock => clock64,
		data => avalon_receiver_data,
		received => avalon_receiver_received,
		rx_p => GPIO_1(15),
		rx_n => GPIO_1(13));

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			-- generate 25 MHz output
			clock25_latch <= not clock25_latch;
			GPIO_1(23) <= clock25_latch;
		end if;
	end process;

	process(clock64)
	begin
		if rising_edge(clock64) then
			fifo_rdreq <= '0';
			fifo_wrreq <= '0';
			avalon_sender_start <= '0';
			avalon_sender_set_idle <= '0';
			
			-- evalute command
			if rs232_receiver_received = '1' then
				case rs232_receiver_data(7 downto 4) is
					when x"0" =>
						avalon_sender_data <= rs232_receiver_data(3 downto 0);
						avalon_sender_start <= '1';
					
					when x"1" =>
						avalon_sender_set_idle <= '1';
					
					when x"2" =>
						avalon_reset <= rs232_receiver_data(0);
					
					when others => null;
				end case;
				
			end if;
			
			-- store report bits in FIFO
			if avalon_receiver_received = '1' then
				fifo_data <= "0000000" & avalon_receiver_data;
				fifo_wrreq <= '1';
			end if;
				
			-- send FIFO to RS232
			rs232_sender_start <= '0';
			if rs232_sender_busy = '0' and fifo_empty = '0' then
				rs232_sender_data <= unsigned(fifo_q);
				rs232_sender_start <= '1';
				fifo_rdreq <= '1';
			end if;
			
			-- Avalon reset
			GPIO_1(17) <= avalon_reset;

			LED(0) <= rs232_sender_busy;
			LED(7 downto 1) <= std_logic_vector(rs232_receiver_data(7 downto 1));
			
			GPIO_1(11) <= GPIO_1(15);
			GPIO_1(9) <= GPIO_1(13);

			GPIO_1(7) <= debugOut(0);
			GPIO_1(5) <= debugOut(1);
			GPIO_1(3) <= debugOut(2);
			GPIO_1(1) <= fifo_empty;  -- dbg 3
			GPIO_1(0) <= rs232_sender_busy;  -- dbg 4
			
		end if;
	end process;

end architecture;
