library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768
);
port(
	clock : in std_logic;
	reset : in std_logic;

	-- Avalon interface --
	s_addr : in std_logic_vector (31 downto 0);
	s_read : in std_logic;
	s_readdata : out std_logic_vector (31 downto 0);
	s_write : in std_logic;
	s_writedata : in std_logic_vector (31 downto 0);
	s_waitrequest : out std_logic;

	m_addr : out integer range 0 to ram_size-1;
	m_read : out std_logic;
	m_readdata : in std_logic_vector (7 downto 0);
	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0);
	m_waitrequest : in std_logic
);
end cache;

architecture arch of cache is

type State_Type is (Waiting, Fetching_mem, Writeback);
type Data_Array_Type is array (0 to 31) of std_logic_vector(127 downto 0);
type Control_Array_Type is array (0 to 31) of std_logic_vector(7 downto 0);--tag(6bits)/dirty(1bit)/valid(1bit)

signal state : State_Type := Waiting;
signal data_array : Data_Array_Type := (others=> (others=>'0'));--initialize to 0 so can print for debugging
signal control_array : Control_Array_Type  := (others=> (others=>'0'));--initialize to 0 so can print for debugging

begin
  
  process(clock, reset) --main logic process
    variable tag : std_logic_vector (5 downto 0);
    variable index : integer range 0 to 31;
    variable word_offset: integer range 0 to 3;
    variable combination : std_logic_vector (3 downto 0);
    variable operation : std_logic;
    variable dirty : std_logic;
    variable valid : std_logic;
    variable hit : std_logic;
    variable count : integer range 0 to 16;
        
    begin
      if (reset = '1') or (now < 1 ps) then -- invalidate control array
        --report "resetting";
        for i in 0 to 31 loop
          control_array(i)(0) <= '0';
        end loop;
      end if;
      if (rising_edge(clock)) then
      s_waitrequest <= '1'; -- default high
      case state is
        when Waiting =>
          --report "Waiting";
          operation := 'U';
          if (s_read = '1') and (s_write = '0') then
            operation := '0';
            tag := s_addr(14 downto 9);
            index := to_integer(unsigned(s_addr(8 downto 4)));
            word_offset := to_integer(unsigned(s_addr(3 downto 2)));
          elsif (s_write = '1') and (s_read = '0') then
            operation := '1';          
            tag := s_addr(14 downto 9);
            index := to_integer(unsigned(s_addr(8 downto 4)));
            word_offset := to_integer(unsigned(s_addr(3 downto 2)));
          else
            operation := 'U';--neither writing nor reading
          end if;
          if control_array(index)(7 downto 2) = tag then --hit?
            hit := '1';
          else
            hit := '0';
          end if;
          dirty := control_array(index)(1);
          valid := control_array(index)(0);
          combination := operation & hit & dirty & valid;
        
          case combination is 
            when "1101" | "1111" => -- successful write cache
              --report "C1";
              data_array (index) (word_offset*32+31 downto word_offset*32) <= s_writedata; -- write data
              control_array (index) (1) <= '1'; -- set dirty
              s_waitrequest <= '0';
              state <= Waiting; -- next state
            when "0101" | "0111" => -- successful read cache
              --report "C2";
              s_readdata <= data_array (index) (word_offset*32+31 downto word_offset*32); -- read data
              s_waitrequest <= '0';
              state <= Waiting; -- next state
            when "0011" | "1011" => -- dirty read/write
              --report "C3";
              count := 0;
              state <= Writeback; -- next state
            when "0000" | "0001" | "0010" | "0100" | "0110" | "1000" | "1001" | "1010" | "1100" | "1110" => -- unsuccessful read/write
              --report "C4";
              count := 0;
              state <= Fetching_mem;
            when others => -- neither read nor write
              --report "C5";
              null;
          end case;
        when Writeback =>
          --report "Writeback" & integer'image(count);
          m_addr <= to_integer(unsigned(std_logic_vector'(control_array(index)(7 downto 2) & std_logic_vector(to_unsigned(index, 5)) & std_logic_vector(to_unsigned(count, 4)))));
          m_writedata <= data_array (index) (8*count+7 downto 8*count);
          m_write <= '1';
          if (m_waitrequest = '0') and (count < 15) then
            count := count + 1;
            m_write <= '0';
          elsif (m_waitrequest = '0') and (count = 15) then
            m_write <= '0';
            count := 0;
            state <= Fetching_mem;
          end if; --else waiting on m_waitrequest
        when Fetching_mem =>
          --report "Fetching_mem" & integer'image(count);
          if count  <= 15 then
            m_addr <= to_integer(unsigned(std_logic_vector'(tag & std_logic_vector(to_unsigned(index, 5)) & std_logic_vector(to_unsigned(count, 4)))));
            m_read <= '1';
          end if;
          if (m_waitrequest = '0') and (count <= 15) then
            data_array (index) (8*count+7 downto 8*count) <= m_readdata;
            --report "m_readdata" & integer'image(to_integer(unsigned(m_readdata)));
            count := count + 1;
            m_read <= '0';
          elsif (count = 16) then -- 16 rather that 15 b/c cant have write then read in same process
            control_array (index) <= control_array (index)(7 downto 2) & "01"; --valid & not dirty data
            control_array (index)(7 downto 2) <= s_addr(14 downto 9);
            if operation = '0' then -- read
              --report "data_array" & integer'image(to_integer(unsigned(data_array (index)(127 downto 96))));
              s_readdata <= data_array(index)(word_offset*32+31 downto word_offset*32); -- read data
            elsif operation = '1' then
              data_array (index) (word_offset*32+31 downto word_offset*32) <= s_writedata; -- write data
              control_array (index) (1) <= '1'; -- set dirty
            end if;
            m_read <= '0';
            s_waitrequest <= '0';
            state <= Waiting;
          end if; --else waiting on m_waitrequest
        when others =>
          null;
      end case;
    end if;
    end process;

end arch;