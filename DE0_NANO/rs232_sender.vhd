-- Copyright (c) 2014 Frank Buss (fb@frank-buss.de)
-- See license.txt for license
--
-- RS232 sender with generic baudrate and 8N1 mode.
--
-- Set 'data' to the byte you want to send and 'start' to 1 for one clock cycle.
-- 'busy' is 1 while the byte is transfered

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rs232_sender is
  generic(
    system_speed,  -- clock frequency, in Hz
    baudrate: integer);  -- baudrate, in bps
  port(
    clock: in std_logic;
    data: in unsigned(7 downto 0);
    start: in std_logic;
    busy: out std_logic;
    tx: out std_logic);  -- RS232 transmit pin
end entity rs232_sender;

architecture rtl of rs232_sender is
  constant max_counter: natural := system_speed / baudrate;
  
  type state_type is (
    wait_for_start,
    send_start_bit,
    send_bits,
    send_stop_bit);

  signal state: state_type := wait_for_start;

  signal baudrate_counter: natural range 0 to max_counter := 0;
  
  signal bit_counter: natural range 0 to 7 := 0;
  signal shift_register: unsigned(7 downto 0) := (others => '0');

begin

  update: process(clock)
  begin
    if rising_edge(clock) then
        case state is
          -- wait until start
          when wait_for_start =>
            if start = '1' then
              state <= send_start_bit;
              baudrate_counter <= max_counter - 1;
              tx <= '0';
              shift_register <= data;
            else
              tx <= '1';
            end if;
          when send_start_bit =>
            if baudrate_counter = 0 then
              state <= send_bits;
              baudrate_counter <= max_counter - 1;
              tx <= shift_register(0);
              bit_counter <= 7;
            else
              baudrate_counter <= baudrate_counter - 1;
            end if;
          when send_bits =>
            if baudrate_counter = 0 then
              if bit_counter = 0 then
                state <= send_stop_bit;
                tx <= '1';
              else
                tx <= shift_register(1);
                shift_register <= shift_right(shift_register, 1);
                bit_counter <= bit_counter - 1;
              end if;
              baudrate_counter <= max_counter - 1;
            else
              baudrate_counter <= baudrate_counter - 1;
            end if;
          when send_stop_bit =>
            if baudrate_counter = 0 then
              state <= wait_for_start;
            else
              baudrate_counter <= baudrate_counter - 1;
            end if;
        end case;
    end if;
  end process;

  busy <= '1' when start = '1' or state /= wait_for_start else '0';

end architecture rtl;
