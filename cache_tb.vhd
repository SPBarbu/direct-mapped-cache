library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_tb is
end cache_tb;

architecture behavior of cache_tb is

component cache is
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
end component;

component memory is 
GENERIC(
    ram_size : INTEGER := 32768;
    mem_delay : time := 10 ns;
    clock_period : time := 1 ns
);
PORT (
    clock: IN STD_LOGIC;
    writedata: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
    address: IN INTEGER RANGE 0 TO ram_size-1;
    memwrite: IN STD_LOGIC;
    memread: IN STD_LOGIC;
    readdata: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
    waitrequest: OUT STD_LOGIC
);
end component;
	
-- test signals 
signal reset : std_logic := '0';
signal clk : std_logic := '0';
constant clk_period : time := 1 ns;

signal s_addr : std_logic_vector (31 downto 0);
signal s_read : std_logic;
signal s_readdata : std_logic_vector (31 downto 0);
signal s_write : std_logic;
signal s_writedata : std_logic_vector (31 downto 0);
signal s_waitrequest : std_logic;

signal m_addr : integer range 0 to 2147483647;
signal m_read : std_logic;
signal m_readdata : std_logic_vector (7 downto 0);
signal m_write : std_logic;
signal m_writedata : std_logic_vector (7 downto 0);
signal m_waitrequest : std_logic; 

begin

-- Connect the components which we instantiated above to their
-- respective signals.
dut: cache 
port map(
    clock => clk,
    reset => reset,

    s_addr => s_addr,
    s_read => s_read,
    s_readdata => s_readdata,
    s_write => s_write,
    s_writedata => s_writedata,
    s_waitrequest => s_waitrequest,

    m_addr => m_addr,
    m_read => m_read,
    m_readdata => m_readdata,
    m_write => m_write,
    m_writedata => m_writedata,
    m_waitrequest => m_waitrequest
);

MEM : memory
port map (
    clock => clk,
    writedata => m_writedata,
    address => m_addr,
    memwrite => m_write,
    memread => m_read,
    readdata => m_readdata,
    waitrequest => m_waitrequest
);
				

clk_process : process
begin
  clk <= '0';
  wait for clk_period/2;
  clk <= '1';
  wait for clk_period/2;
end process;

test_process : process
begin
  s_write <= '0';
  s_read <= '0';
  
  reset <= '1';
  wait for clk_period;
  reset <= '0';
  wait for clk_period;
  
  report "Test 1: Populating cache.  Either non-valid block or valid, but hit miss. (0000, 0001, 0010, 0100, 0110)";
	s_addr <= "11111111111111111111111111111111";
	s_read <= '1';
	s_write <= '0';
	wait until falling_edge(s_waitrequest);
	assert s_readdata = X"FFFEFDFC" report "Unsuccessful read" severity error;
	s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	
	report "Test 2: Reading valid block, cache hit (0101, 0111)";
	s_addr <= "00000000000000000111111111111000"; -- same block as test 1 but 3rd word rather than 4th
	s_read <= '1';
	s_write <= '0';
	wait until falling_edge(s_waitrequest);
	assert s_readdata = X"FBFAF9F8" report "Unsuccessfully populated" severity error;
	s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	
	report "Test 3: Writing to cache on a populate block, valid cache hit(1101, 1111)";
	s_addr <= "11111111111111111111111111111000"; -- same block as test 2
	s_read <= '0';
	s_write <= '1';
	s_writedata <=  X"FFFFFFFF";
	wait until falling_edge(s_waitrequest);
	s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	s_read <= '1';
	s_write <= '0';
	wait until falling_edge(s_waitrequest);
	assert s_readdata = X"FFFFFFFF" report "Unsuccessful write" severity error;
  s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	
	report "Test 4: Reading dirty block on cache miss. Writing back to memory. (0011, 1011)";
	s_addr <= "11111111111111111011111111111000"; -- same index as test3 so know it's dirty, but different tag so hit miss
	s_read <= '1';
	s_write <= '0';
	wait until falling_edge(s_waitrequest);
	assert s_readdata = X"FBFAF9F8" report "Unsuccessful read" severity error;
	s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	s_addr <= "11111111111111111111111111111000"; -- bring back previous data so know it was saved  to memory
	s_read <= '1';
	s_write <= '0';
	wait until falling_edge(s_waitrequest);
	assert s_readdata = X"FFFFFFFF" report "Unsuccessfully saved to memory" severity error;
	s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	
	report "Test 5: Populating before writing. Either non-valid block or valid, but hit miss and not dirty. (1000, 1001, 1010, 1100, 1110)";
	s_addr <= "11111111111111111111111111101100";
	s_read <= '0';
	s_write <= '1';
	s_writedata <=  X"FFFFFFFF";
	wait until falling_edge(s_waitrequest);
	assert s_readdata = X"FFFFFFFF" report "Unsuccessful write" severity error;
  s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	s_addr <= "11111111111111111111111111101000"; -- same block as before but 3rd word rather than 4th
	s_read <= '1';
	s_write <= '0';
	wait until falling_edge(s_waitrequest);
	assert s_readdata = "11101011111010101110100111101000" report "Unsuccessfully populated" severity error;
  s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	
	reset <= '1';
  wait for clk_period;
  reset <= '0';
  wait for clk_period;
  
  report "Test 6: Testing reset";
	s_addr <= "11111111111111111111111111101100";
	s_read <= '1';
	s_write <= '0';
	wait until falling_edge(s_waitrequest);
	assert s_readdata = "11101111111011101110110111101100" report "Unsuccessful read" severity error;
	s_write <= '0';
  s_read <= '0';
	wait until rising_edge(s_waitrequest);
	
	report "Confirming all tests have ran";
	wait;
end process;
	
end;