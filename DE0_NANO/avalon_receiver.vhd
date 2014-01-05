-- Copyright (c) 2014 Frank Buss (fb@frank-buss.de)
-- See license.txt for license
--
-- Avalon receiver.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.all;

entity avalon_receiver is
  generic(system_speed: integer);  -- clock frequency, in Hz, must be multiple of 32 MHz, min 64 MHz
  port(
    clock: in std_logic;
    data: out std_logic;
    received: out std_logic;
    rx_p: in std_logic;
    rx_n: in std_logic);
end entity avalon_receiver;

architecture rtl of avalon_receiver is
  constant sample_max: natural := system_speed / 32e6;
  
  signal wait_for_start: boolean := true;
  signal sample_counter: natural range 0 to sample_max := 0;
  signal p_latch: std_logic_vector(1 downto 0);
  signal n_latch: std_logic_vector(1 downto 0);

begin

	update: process(clock)
	begin
		if rising_edge(clock) then
			received <= '0';
			if sample_counter = 0 then
				p_latch <= p_latch(0) & rx_p;
				n_latch <= n_latch(0) & rx_n;
				sample_counter <= sample_max - 1;
				if wait_for_start then
					if p_latch = "00" and n_latch = "00" then
						wait_for_start <= false;
					end if;
				else
					if p_latch = "11" or n_latch = "11" then
						if p_latch = "11" then
							data <= '1';
						else
							data <= '0';
						end if;
						received <= '1';
						wait_for_start <= true;
					end if;
				end if;
			else
				sample_counter <= sample_counter - 1;
			end if;
		end if;

	end process;

end architecture rtl;
