-- Copyright (c) 2014 Frank Buss (fb@frank-buss.de)
-- See license.txt for license
--
-- Avalon sender.
--
-- Set 'data' to the byte you want to send and 'start' to 1 for one clock cycle.
-- 'busy' is 1 while the byte is transfered

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity avalon_sender is
  generic(
    system_speed: integer);  -- clock frequency, in Hz, must be multiple of 8 MHz
  port(
    clock: in std_logic;
    data: in unsigned(3 downto 0);
    start: in std_logic;
    set_idle: in std_logic;
    busy: out std_logic;
    tx_p: out std_logic;
    tx_n: out std_logic);
end entity avalon_sender;

architecture rtl of avalon_sender is
  constant baudrate: natural := 4e6;
  constant max_counter: natural := system_speed / baudrate;
  
  type state_type is (
    wait_for_start,
    send_bit_start,
    send_bit);

  signal state: state_type := wait_for_start;

  signal baudrate_counter: natural range 0 to max_counter := 0;
  
  signal bit_counter: natural range 0 to 4 := 0;
  signal shift_register: unsigned(3 downto 0) := (others => '0');

begin

  update: process(clock)

  begin
    if rising_edge(clock) then
        case state is
          -- wait until start
          when wait_for_start =>
            if start = '1' then
              state <= send_bit_start;
              baudrate_counter <= 0;
              shift_register <= data;
              bit_counter <= 4;
            end if;
				if set_idle = '1' then
					tx_p <= '1';
					tx_n <= '1';
				end if;

			when send_bit_start =>
            if baudrate_counter = 0 then
              if bit_counter = 0 then
                state <= wait_for_start;
              else
                tx_p <= '0';
			       tx_n <= '0';
                state <= send_bit;
                baudrate_counter <= max_counter / 2 - 1;
				  end if;
				else
              baudrate_counter <= baudrate_counter - 1;
            end if;

			when send_bit =>
            if baudrate_counter = 0 then
					if shift_register(0) = '1' then
                tx_p <= '1';
				   else
                tx_n <= '1';
					end if;
               baudrate_counter <= max_counter / 2 - 1;
               state <= send_bit_start;
               shift_register <= shift_right(shift_register, 1);
               bit_counter <= bit_counter - 1;
            else
               baudrate_counter <= baudrate_counter - 1;
            end if;

        end case;
    end if;
  end process;
  
  busy <= '1' when start = '1' or state /= wait_for_start else '0';
  
end architecture rtl;
