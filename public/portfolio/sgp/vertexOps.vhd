-------------------------------------------------------------------------
-- MP-5 Adaptation
--Greg Gholson, Michael Patterson, Travis Munn
-------------------------------------------------------------------------

-- vertexOps.vhd
-------------------------------------------------------------------------
-- DESCRIPTION: This file contains an implementation of the vertex  
-- transformation processing stage of the 3D rendering pipeline. 
--
-- NOTES:
-- 02/04/11 by MAS::Design created.
-------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.SGP_config.all;

entity vertexOps is
      generic(BUS_ADDRESS : integer);
     port (clk100  : in std_logic;
               rst         : in std_logic;

             -- Connections to the hostBus
              hostBusMaster  : in hostBusMaster_t;
              hostBusSlave   : out hostBusSlave_a(0 to 1);
              
              -- Uppipe connection for the vertex data
             pipeFrontData  : in pipeFrontData_t;
              upPipeStall    : out std_logic;
              
              -- Downpipe connection for the pixelOps
              pipeVertexData : out assemblyData_t;
              downPipeStall  : in std_logic;
              
              -- View port dims
              viewPort_left   : out signed(31 downto 0);
              viewPort_right  : out signed(31 downto 0);
              viewPort_top    : out signed(31 downto 0);
              viewPort_bottom : out signed(31 downto 0);
              
              packetError    : out std_logic);
end vertexOps;


architecture mixed of vertexOps is

    -- hostBus interface
    component hostBusinterface
        generic (BUS_ADDRESS : integer);
        port (clk : in  std_logic;
                rst : in  std_logic;
              
                -- Bus interface
                hostBusMaster         : in hostBusMaster_t;
                hostBusSlave        : out hostBusSlave_t;
              
                -- User interface
                instrFIFORead        : out instrFIFORead_t;
                instrFIFOReadEn      : in std_logic;
                unitStall            : in std_logic);
    end component;
    
    -- check packet ID
    component packetIDCheck
            port( clk    : in std_logic;
                    rst   : in std_logic;
                    weEn  : in std_logic;
                    packetID : in unsigned(31 downto 0);
                    error    : out std_logic;
                    counterValue : out unsigned(31 downto 0));
    end component;
    
    
    -- Stack memory for modelview and projection matrix
    component matrixStack
        port (clka    : in std_logic;
                  wea        : in std_logic_vector(0 downto 0);
              addra    : in std_logic_vector(9 downto 0);
              dina    : in std_logic_vector(63 downto 0);
              douta    : out std_logic_vector(63 downto 0);
              clkb    : in std_logic;
              web        : in std_logic_vector(0 downto 0);
              addrb    : in std_logic_vector(9 downto 0);
              dinb    : in std_logic_vector(63 downto 0);
              doutb    : out std_logic_vector(63 downto 0));
   end component;
    
    -- Matrix Multiply Units (2 64-bit multipliers)
    component matrixMult is
    Port ( clk100 : in  std_logic;
           rst     : in  std_logic;
              
              -- Pipeline control signals
              unitfull           : out std_logic;
              wrEnable             : in std_logic;
              output_valid     : out std_logic;
              downStreamFull    : in std_logic;
              
              -- Input values
              input_vertex_data : in pipeFrontData_t;
              matrix                    : in matrix_t;
              
              -- Resulting coordinate value
              output_vertex_data : out pipeFrontData_t;
              
              packetError    : out std_logic);
    end component;
    
    -- Perspective Division unit
    component perspectiveDivision is
      Port ( clk100 : in  std_logic;
            rst     : in  std_logic;
              
               -- Pipeline control signals
               unitfull           : out std_logic;
               wrEnable             : in std_logic;
               output_valid     : out std_logic;
               downStreamFull    : in std_logic;
              
               -- Input values
               input_vertex_data : in pipeFrontData_t;
              
               -- Resulting coordinate value
               output_vertex_data : out pipeFrontData_t;
                
                packetError    : out std_logic);
    end component;
    
    component vertexAssemblyTag is
          generic(BUS_ADDRESS : integer);
          port (    clk    : in std_logic;
                    rst    : in std_logic;
                    
                    -- Connections to the hostBus
                    hostBusMaster  : in hostBusMaster_t;
                    hostBusSlave   : out hostBusSlave_t;
                    
                    -- Pipeline control signals
                    unitfull           : out std_logic;
                    wrEnable         : in std_logic;
                    output_valid     : out std_logic;
                    downStreamFull    : in std_logic;
                    
                    -- Vertex in/out data
                    input_vertex_data  : in pipeFrontData_t;
                    output_vertex_data : out assemblyData_t;
                    
                    packetError    : out std_logic);
    end component;
    
    component vertexClipping is
        port (    clk    : in std_logic;
                    rst    : in std_logic;
                    
                    -- Pipeline control signals
                    unitfull           : out std_logic;
                    wrEnable         : in std_logic;
                    output_valid     : out std_logic;
                    output_clipped : out std_logic;
                    downStreamFull    : in std_logic;
                    
                    -- Vertex in/out data
                    input_vertex_data  : in assemblyData_t;
                    output_vertex_data : out assemblyData_t);
    end component;
    
    -- Viewport multiplier for XY coords
    component viewPortMultXY
        port (    clk    : in std_logic;
                    a        : in std_logic_vector(63 downto 0);
                    b        : in std_logic_vector(11 downto 0);
                    ce        : in std_logic;
                    p        : out std_logic_vector(75 downto 0));
    end component;

    -- Viewport multiplier for Z coord
    component viewPortMultZ
        port (    clk    : in std_logic;
                    a        : in std_logic_vector(63 downto 0);
                    b        : in std_logic_vector(24 downto 0);
                    ce        : in std_logic;
                    p        : out std_logic_vector(88 downto 0));
    end component;

    
    -- Constants
    constant FIX_ONE    : signed(63 downto 0) := x"0000000100000000";

    -- Matrix array data structures
    type viewport_t          is array( 7 downto 0) of unsigned(31 downto 0);
    
    type viewPortShift_t  is array( 6 downto 0) of std_logic_vector(36 downto 0);
    
    -- State machine data structure
    type VERT_STATE_M is (IDLE, PUSHMATRIX, POPMATRIX, DECODE, SETMATRIX, LOADIDENTITY);
  
    -- State machine signals
    signal curState, curState_d1, nextState    : VERT_STATE_M;
    
    -- Signals to interface with the hostBus. 
    signal instrFIFORead     : instrFIFORead_t;
    signal instrFIFOReadEn   : std_logic;
   signal hostBusStall      : std_logic;
    
    -- opcode reg
    signal opCode                : unsigned(7 downto 0);

    -- Memory Stack Signals
    signal stack_we_en        : std_logic_vector(0 downto 0);    -- Write enable to stack memory
    signal s_bramAddress_a    : unsigned(9 downto 0);             -- port a address wire
    signal s_bramAddress_b    : unsigned(9 downto 0);                -- port b address wire
    signal s_saveMatrix_a    : fixed_t;                                -- port a write data wire
    signal s_savematrix_b    : fixed_t;                                -- port b write data wire
    signal loadMatrix_a        : std_logic_vector(63 downto 0);    -- port a read data
    signal loadMatrix_b        : std_logic_vector(63 downto 0);    -- port b read data
    
    -- registers to store matrix addresses for push/pop
    signal r_stackAddressModelView_a        : unsigned(9 downto 0);
    signal r_stackAddressModelView_b        : unsigned(9 downto 0);
    signal r_stackAddressProj_a            : unsigned(9 downto 0);
    signal r_stackAddressProj_b            : unsigned(9 downto 0);
    signal s_stackAddress_a                 : unsigned(9 downto 0);
    signal s_stackAddress_b                    : unsigned(9 downto 0);
    
    -- Count the number of stack cycles
    signal stackCount                            : unsigned(5 downto 0);
    signal r_stackCount                        : unsigned(5 downto 0);
    signal pushPopDone                        : std_logic;

    -- Model view and Projection matrix signals
    signal r_modelView        : matrix_t;
    signal r_projection        : matrix_t;
    
    -- viewport signals
    signal r_viewport            : viewport_t;
    signal r_viewport4neg   : signed(31 downto 0);
    signal ox, oy           : unsigned(63 downto 0);
    signal z1, z2                : fixed_t;
    
    -- Load new matrix signals
    signal r_num32matrixPackets     : unsigned(18 downto 0);    -- Number of packets for setting a matrix
    signal r_setCount                  : unsigned(18 downto 0);    -- Number of receaved packets for setting a matrix
    signal setCount                    : unsigned(18 downto 0);    -- Wire signal for counting packets
    signal setDone                        : std_logic;
    
    -- Count the number of vertex into pipeline and out of pipeline
    signal vertexCounter                : unsigned(7 downto 0);
    signal vertexCounter2            : unsigned(7 downto 0);
    signal pipeVertexDataValid        : std_logic;
    
    -- Pipeline wires
    signal projectionMatrixFull    : std_logic;
    signal modelViewVertex            : pipeFrontData_t;
    
    signal viewPortFull                : std_logic;
    signal projectionVertex            : pipeFrontData_t;
    
    signal perspectiveDividerFull : std_logic;
    signal normalizedVertex            : pipeFrontData_t;
    
    signal assemblyFull                : std_logic;
    signal assemblyVertex            : assemblyData_t;
    
    signal clippingFull                : std_logic;
    signal clippingVertex            : assemblyData_t;
    
    --viewport pipe signals
    signal viewportX, viewportY    : std_logic_vector(75 downto 0);
    signal viewportZ                    : std_logic_vector(88 downto 0);
    signal viewPortShiftReg            : viewPortShift_t;
    signal stdLogicVectorX, stdLogicVectorY            : std_logic_vector(63 downto 0);
    signal stdLogicVectorZ            : std_logic_vector(63 downto 0);
    signal ce_viewport                : std_logic;
    
    signal packetError_model, packetError_proj, packetError_div, packetError_assm : std_logic;
    signal packetError_fifo : std_logic;
    
    signal output_clipped : std_logic;

begin

   -- Connect the vertexOps module to the hostBus
    u_hostBusinterface: hostBusinterface
      generic map(BUS_ADDRESS      => BUS_ADDRESS)
        port map(clk                => clk100,
                   rst                => rst,
              
                   -- Bus interface
                   hostBusMaster          => hostBusMaster,
                   hostBusSlave         => hostBusSlave(0),
              
                   -- User interface
                   instrFIFORead         => instrFIFORead,
                   instrFIFOReadEn       => instrFIFOReadEn,
                   unitStall             => hostBusStall);
                    
    -- stall the hostBus when not in idle or Setting matrix (needs bus data)
    hostBusStall <= '0' when (curState = IDLE) and (vertexCounter=0) and (vertexCounter2=0) else
                         '1';
    
    -- Read instructions when the state is idle or setting a matrix (needs instructions)
    -- Also don't read the next instruction the following cycle after getting a start signal
    instrFIFOReadEn <= '1' when curState = SETMATRIX else
                             not hostBusStall and not instrFIFORead.start;
    
    -- This process stores the opcode from the last instruction
    P1: process(rst, clk100)
    begin
        if(rst='1') then
            opCode <= (others => '0');
        elsif(rising_edge(clk100)) then
           
            -- If the start bit from the FIFO is high, then we have a new instruction.
            -- The opcode is defined as bits 11 downto 4 of a new instruction data packet.
            if(instrFIFORead.start = '1') then         
                opCode <= unsigned(instrFIFORead.packet(11 downto 4));
            end if;

        end if;
    end process;   
    
    -- Count number of input vertex and sub output vertex
    process(clk100, rst) 
    begin
        if(rst='1') then
            vertexCounter <= (others=>'0');
        elsif(rising_edge(clk100)) then
            if(pipeFrontData.valid='1' and normalizedVertex.valid='0') then
                vertexCounter <= vertexCounter+1;
            elsif(pipeFrontData.valid='0' and normalizedVertex.valid='1') then
                vertexCounter <= vertexCounter-1;
            end if;
        end if;
    end process;
    
    process(clk100, rst) 
    begin
        if(rst='1') then
            vertexCounter2 <= (others=>'0');
        elsif(rising_edge(clk100)) then
            if(assemblyVertex.valid='1' and pipeVertexDataValid='0' and output_clipped='0') then
                vertexCounter2 <= vertexCounter2+1;
            elsif(assemblyVertex.valid='0' and pipeVertexDataValid='1' and output_clipped='0') then
                vertexCounter2 <= vertexCounter2-1;
            elsif(assemblyVertex.valid='0' and pipeVertexDataValid='0' and output_clipped='1') then
                vertexCounter2 <= vertexCounter2-1;
            elsif(assemblyVertex.valid='0' and pipeVertexDataValid='1' and output_clipped='1') then
                vertexCounter2 <= vertexCounter2-2;
            elsif(assemblyVertex.valid='1' and pipeVertexDataValid='1' and output_clipped='1') then
                vertexCounter2 <= vertexCounter2-1;
            end if;
        end if;
    end process;
    
    
    
    
    --=========================================================================
    -- Matix stack operations
    --=========================================================================
    
--    Memory address layout for model view and projection matrix
--    ---------------------
--    | Model View Matrix | <- 0    
--    |        ||         |
--    |        || (23)    |
--    |        ||         |
--    |        \/         |
--    |                   | 
--    |        /\         |
--    |        || (2)     |
--    | Projection Matrix | <- 1023
--    ---------------------
    
    -- block ram memory for stack
u_matrixStackMemory : matrixStack
   port map (clka     => clk100,
             wea         => stack_we_en,
             addra     => std_logic_vector(s_bramAddress_a),
             dina     => std_logic_vector(s_saveMatrix_a),
             douta     => loadMatrix_a,
             clkb     => clk100,
             web         => stack_we_en,
             addrb     => std_logic_vector(s_bramAddress_b),
             dinb     => std_logic_vector(s_saveMatrix_b),
             doutb     => loadMatrix_b);
                
    -- Assign addresses
    s_bramAddress_a <= r_stackAddressModelView_a when opCode(3 downto 0) = 0 else        -- When in modelview
                             r_stackAddressProj_a;                                                        -- else projection
    s_bramAddress_b <= r_stackAddressModelView_b when opCode(3 downto 0) = 0 else        -- When in modelview
                             r_stackAddressProj_b;                                                        -- else projection
            
    -- Write to the stack memory when in PUSHMATRIX state
    stack_we_en(0) <= '1' when curState = PUSHMATRIX else
                           '0';
    
    -- Data to write to the blockRam port A
    -- 2 level mux, first mux between projection and modelview
    --                  second mux the correct entry in matrix
    process(opcode, stackCount, r_modelView, r_projection)
    begin
        case opcode(3 downto 0) is
            when x"0" =>
                case r_stackCount is
                    when "000000" => s_saveMatrix_a <= r_modelView(0); s_saveMatrix_b <= r_modelView(1);
                    when "000001" => s_saveMatrix_a <= r_modelView(2); s_saveMatrix_b <= r_modelView(3);
                    when "000010" => s_saveMatrix_a <= r_modelView(4); s_saveMatrix_b <= r_modelView(5);
                    when "000011" => s_saveMatrix_a <= r_modelView(6); s_saveMatrix_b <= r_modelView(7);
                    when "000100" => s_saveMatrix_a <= r_modelView(8); s_saveMatrix_b <= r_modelView(9);
                    when "000101" => s_saveMatrix_a <= r_modelView(10); s_saveMatrix_b <= r_modelView(11);
                    when "000110" => s_saveMatrix_a <= r_modelView(12); s_saveMatrix_b <= r_modelView(13);
                    when "000111" => s_saveMatrix_a <= r_modelView(14); s_saveMatrix_b <= r_modelView(15);
                    when others => s_saveMatrix_a <= (others=>'0'); s_saveMatrix_b <= (others=>'0');
                end case;
            when x"1" =>
                case r_stackCount is
                    when "000000" => s_saveMatrix_a <= r_projection(0); s_saveMatrix_b <= r_projection(1);
                    when "000001" => s_saveMatrix_a <= r_projection(2); s_saveMatrix_b <= r_projection(3);
                    when "000010" => s_saveMatrix_a <= r_projection(4); s_saveMatrix_b <= r_projection(5);
                    when "000011" => s_saveMatrix_a <= r_projection(6); s_saveMatrix_b <= r_projection(7);
                    when "000100" => s_saveMatrix_a <= r_projection(8); s_saveMatrix_b <= r_projection(9);
                    when "000101" => s_saveMatrix_a <= r_projection(10); s_saveMatrix_b <= r_projection(11);
                    when "000110" => s_saveMatrix_a <= r_projection(12); s_saveMatrix_b <= r_projection(13);
                    when "000111" => s_saveMatrix_a <= r_projection(14); s_saveMatrix_b <= r_projection(15);
                    when others => s_saveMatrix_a <= (others=>'0'); s_saveMatrix_b <= (others=>'0');
                end case;
            when others =>
                s_saveMatrix_a <= (others=>'0');
                s_saveMatrix_b <= (others=>'0');
        end case;
    end process;
                
   -- compute the next stack address                
    process(rst, curState, opCode, r_stackAddressModelView_a, r_stackAddressModelView_b, r_stackAddressProj_a, r_stackAddressProj_b)
    begin
        if(rst='1') then
            s_stackAddress_a <= (others=>'0');
            s_stackAddress_b <= (others=>'0');
            
        -- If we are pushing a matrix
        elsif(curState = PUSHMATRIX) then
        
            -- If we are pushing the modelView Matrix
            -- Take the reg stack address value and add 2. output is a wire not a reg!
            if(opCode(3 downto 0) = 0) then
                s_stackAddress_a <= r_stackAddressModelView_a + 2;
                s_stackAddress_b <= r_stackAddressModelView_b + 2;
                
            -- If we are pushing the projection Matrix. Sub since the addresses move down
            -- as we fill up the blockRam.  See fig above
            elsif(opCode(3 downto 0) = 1) then
                s_stackAddress_a <= r_stackAddressProj_a - 2;
                s_stackAddress_b <= r_stackAddressProj_b - 2;
            
            -- do nothing on a bad signal
            else
                s_stackAddress_a <= (others=>'0');
                s_stackAddress_b <= (others=>'0');
            end if;
            
        -- If we are poping a matrix
        elsif(curState = POPMATRIX) then
        
            -- If we are poping the modelView Matrix
            if(opCode(3 downto 0) = 0) then
                s_stackAddress_a <= r_stackAddressModelView_a - 2;
                s_stackAddress_b <= r_stackAddressModelView_b - 2;
                
            -- If we are poping the projection Matrix
            elsif(opCode(3 downto 0) = 1) then
                s_stackAddress_a <= r_stackAddressProj_a + 2;
                s_stackAddress_b <= r_stackAddressProj_b + 2;
            
            -- do nothing on a bad signal
            else
                s_stackAddress_a <= (others=>'0');
                s_stackAddress_b <= (others=>'0');
            end if;
            
        -- do nothing on other states
        else
            s_stackAddress_a <= (others=>'0');
            s_stackAddress_b <= (others=>'0');
        end if;
    end process;
    
    -- Register the new stack addresses (2 regs per matrix mode, one for each port)
    -- r_* are the regs and s_* is just a wire signal
    process(clk100, rst)
    begin
        if(rst='1') then
            -- Set to default Values
            -- Modelview starts at 0&1
            r_stackAddressModelView_a <= "0000000000";
            r_stackAddressModelView_b <= "0000000001";
            
            -- Projection starts at top and works down
            r_stackAddressProj_a <= "1111111111";
            r_stackAddressProj_b <= "1111111110";
        elsif(rising_edge(clk100)) then
            if( (curState = PUSHMATRIX) or ((curState = POPMATRIX) and (stackCount < 9)) ) then
                -- if we are editing the modelView matrix
                if(opCode(3 downto 0) = 0) then
                    r_stackAddressModelView_a <= s_stackAddress_a;
                    r_stackAddressModelView_b <= s_stackAddress_b ;
                    
                -- if we are editing the projection matrix
                elsif(opCode(3 downto 0) = 1) then
                    r_stackAddressProj_a <= s_stackAddress_a;
                    r_stackAddressProj_b <= s_stackAddress_b;
                end if;
            end if;
        end if;
    end process;
    
    -- Count the number of stack operations
    -- No reg in this processes only wires
    process(rst, curState, r_stackCount)
    begin
        if(rst='1') then
            stackCount <= (others=>'0');
        else
            -- If we are pushing or poping a matrix stack
            if((curState = PUSHMATRIX) or (curState = POPMATRIX)) then
                -- Take reg value for stackCount and add one
                stackCount <= r_stackCount + 1;
            else
                stackCount <= r_stackCount;
            end if;
        end if;
    end process;
    
    -- reg the stack count wire signal
    process(clk100, rst)
    begin
        if(rst='1') then
            r_stackCount <= (others=>'0');
        elsif(rising_edge(clk100)) then
            -- If start of a new instr. Set reg value to zero
            if(instrFIFORead.start = '1') then
                r_stackCount <= (others=>'0');
                
            -- Register the stackCount wire
            else
                r_stackCount <= stackCount;
            end if;
        end if;
    end process;
    
    -- Set the pushPopDone signal
    process(rst, stackCount)
    begin
        if(rst='1') then
            pushPopDone <= '0';
        elsif(curState = PUSHMATRIX) then
            -- If we have written 8 cycles to memory (8*2=16 values since dual ported)
            -- We are done
            if(stackCount >= 8) then
                pushPopDone <= '1';
            else
                pushPopDone <='0';
            end if;
        elsif(curState = POPMATRIX) then
        
            -- If we have read 8 cycles from memory + the one additional cycle to register
            -- the first address for reading, we are done.
            if(stackCount >= 9) then
                pushPopDone <= '1';
            else
                pushPopDone <='0';
            end if;
        else
            pushPopDone <= '0';
        end if;
    end process;
    
    --=========================================================================
    -- Load new matrix data (Misc control signals)
    --=========================================================================
    
    -- Count the number of incomming packets
    r_num32matrixPackets <= (others=>'0') when rst='1' else
                                    unsigned(instrFIFORead.packet(30 downto 12)) when rising_edge(clk100) and instrFIFORead.start='1';
    
    -- Count the number of packets receaved, output is a wire not a reg
    process(rst, curState, instrFIFORead.valid, r_setCount)
    begin
        if(rst='1') then
            setCount <= (others=>'0');
            
        -- If we are loading a new matrix and the input packet is valid
        elsif((curState = SETMATRIX) and (instrFIFORead.valid='1')) then
            -- Output signal is register value pluss one
            setCount <= r_setCount + 1;
        else
            -- No change to register value on output signal
            setCount <= r_setCount;
        end if;
    end process;
    
    -- Register setCount wire
    process(rst, clk100)
    begin
        if(rst='1') then
            r_setCount <= (others=>'0');
        elsif(rising_edge(clk100)) then
            -- If in idle state
            if(curState=IDLE) then
                -- Reset the number of receaved packets for loading a matrix to zero
                r_setCount <= (others=>'0');
            else
                -- Save the setCount wire as the new reg value
                r_setCount <= setCount;
            end if;
        end if;
    end process;
    
    -- set done flag for loading matrix when we have seen all the packets
    process(rst, setCount, r_num32matrixPackets)
    begin
        if(rst='1') then
            setDone <= '0';
        -- Done when setCount is equal to the number of packets sent from the PC.
        elsif(setCount = r_num32matrixPackets) then
            setDone <= '1';
        else
            setDone <= '0';
        end if;
    end process;
    
    --=========================================================================
    -- Set viewport entry data sent from PC.
    -- Shift Registers are used for storing the array of viewport data
    -- All 32 bit packets are stored in viewport 0 for every valid packet,
    -- the viewport array will shift.  viewport(0) -> viewport(1) etc..
    --=========================================================================
    
    ox(63 downto 32) <= ('0' & r_viewport(5)(31 downto 1)) + r_viewport(7);
    ox(31 downto 0) <= (others=>'0');
    oy(63 downto 32) <= 1023-(('0' & r_viewport(4)(31 downto 1)) + r_viewport(6));
    oy(31 downto 0) <= (others=>'0');
    z1 <= (signed(r_viewport(3)) & signed(r_viewport(2))) - (signed(r_viewport(1)) & signed(r_viewport(0))); --(f-n);
    z2 <= (signed(r_viewport(3)) & signed(r_viewport(2))) + (signed(r_viewport(1)) & signed(r_viewport(0))); --(f+n);
     
    process(clk100, rst)
    begin
        if(rst='1') then
            r_viewport(0) <= (others=>'0');        -- Reset value to zero
        elsif(rising_edge(clk100)) then
            -- If loading new data and the packet is valid
            if ((curState = SETMATRIX) and (instrFIFORead.valid='1')) then
                -- If the new data is for viewport
                if(opCode(3 downto 0) = 3) then
                    -- Assign receaved data to viewport(0)
                    r_viewport(0) <= unsigned(instrFIFORead.packet);
                end if;
            end if;
        end if;
    end process;
                
-- Shift Registers for viewport
shiftViewport: for i in 1 to 7 generate
        process(clk100, rst)
        begin
            if(rst='1') then
                r_viewport(i) <= (others=>'0');        -- Reset all values to zero
            elsif(rising_edge(clk100)) then
                -- If we are setting new data to one of the vertex states and we have a valid packet
                if ((curState = SETMATRIX) and (instrFIFORead.valid='1')) then
                    -- If the data is for viewport
                    if(opCode(3 downto 0) = 3) then
                        -- Shift all viewport data over one.
                        -- Last entry falls out
                        r_viewport(i)  <= r_viewport(i-1);
                    end if;
                end if;
            end if;
        end process;
end generate shiftViewport;
                
r_viewport4neg <= signed(not(r_viewport(4))) + 1 ;

viewPort_left <= signed(r_viewport(7));
viewPort_right <= signed(r_viewport(7) + r_viewport(5)-1);
viewPort_bottom <= signed(1023 - r_viewport(6));
viewPort_top <= signed(1023 - (r_viewport(6) + r_viewport(4)-1));


                
    --=========================================================================
    -- Set modelview/projection entry data sent from PC.
    -- Shift Registers are used for storing the array of modelview data
    -- All 32 bit packets are stored in modelview 0(31 downto 0). For every valid packet,
    -- the modelview array will shift.  modelview(0)(31 downto 0) -> modelview(0)(63 downto 32)
    -- modelview(0)(63 downto 32) -> modelview(1)(31 downto 0) etc...
    --=========================================================================        
                
    -- Set first entries in modelview or projectoin matrix
    process(clk100,rst)
    begin
        if(rst='1') then
            r_modelview(0)  <= FIX_ONE;
            r_projection(0) <= FIX_ONE;

        elsif(rising_edge(clk100)) then
        
            -- If we are resetting a matrix to the identity matrix
            if(curState = LOADIDENTITY) then
            
                -- If we are working with modelview
                if (opCode(3 downto 0) = 0) then
                    r_modelview(0) <= FIX_ONE;
                    
                -- Else if working with projection
                elsif(opCode(3 downto 0) = 1) then
                    r_projection(0) <= FIX_ONE;
                end if;
                
            -- If we are setting the matrix from the PC and have a valid packet
            elsif ((curState = SETMATRIX) and (instrFIFORead.valid='1')) then
        
                -- If modelview
                if(opCode(3 downto 0) = 0) then
                    -- Set new value and shift
                    r_modelview(0)(31 downto 0)  <= signed(instrFIFORead.packet);
                    r_modelview(0)(63 downto 32) <= r_modelview(0)(31 downto 0);
                    
                -- If projection
                elsif(opCode(3 downto 0) = 1) then
                    -- Set new value and shift
                    r_projection(0)(31 downto 0)  <= signed(instrFIFORead.packet);
                    r_projection(0)(63 downto 32) <= r_projection(0)(31 downto 0);
                end if;
                
            -- If we are poping a matrix of the stack
            -- and if the value comming out of block ram is the 0 entry
            elsif ((curState_d1 = POPMATRIX) and (r_stackCount=9)) then
                -- If modelview
                if(opCode(3 downto 0) = 0) then
                    -- Set new value from block ram
                    r_modelview(0)  <= signed(loadMatrix_a);
                    
                -- If projection
                elsif(opCode(3 downto 0) = 1) then
                    -- Set new value from block ram
                    r_projection(0) <= signed(loadMatrix_a);
                end if;
            end if;
        end if;
    end process;
    

    -- Shift the entire model view or projectio matrix to make room for new entry values
shiftMatrix: for i in 1 to 15 generate
        process(clk100, rst)
        begin
            if(rst='1') then
                -- Reset both matrix to identity matrix
                if((i=5) or (i=10) or (i=15)) then
                    r_modelview(i)  <= FIX_ONE;
                    r_projection(i) <= FIX_ONE;
                else
                    r_modelview(i)  <= (others=>'0');
                    r_projection(i) <= (others=>'0');
                end if;
            elsif( rising_edge(clk100)) then
                
                -- If we are setting one of the matrix to identity matrix
                if(curState = LOADIDENTITY) then
                
                    -- If we are setting modelview to identity
                    if (opCode(3 downto 0) = 0) then
                        if((i=5) or (i=10) or (i=15)) then
                            r_modelview(i)  <= FIX_ONE;
                        else
                            r_modelview(i)  <= (others=>'0');
                        end if;
                        
                    -- If we are setting the projection to identity
                    elsif(opCode(3 downto 0) = 1) then
                        if((i=5) or (i=10) or (i=15)) then
                            r_projection(i) <= FIX_ONE;
                        else
                            r_projection(i) <= (others=>'0');
                        end if;
                    end if;
            
                -- if we are setting a matrix and it is time to shift the entire matrix
                -- AKA if  we have a valid 32 bit packet from host
                elsif((curState=SETMATRIX) and (instrFIFORead.valid='1')) then
                
                    -- If modelview is changing
                    if(opcode(3 downto 0)=0) then
                        -- Shift
                        r_modelview(i)(31 downto 0)  <= r_modelview(i-1)(63 downto 32);
                        r_modelview(i)(63 downto 32) <= r_modelview(i)(31 downto 0);
                        
                    -- If projection is changing
                    elsif(opCode(3 downto 0) = 1) then
                        r_projection(i)(31 downto 0)  <= r_projection(i-1)(63 downto 32);
                        r_projection(i)(63 downto 32) <= r_projection(i)(31 downto 0);
                    end if;
                    
                -- If we are poping a matrix of the stack
                -- and if the value comming out of block ram is the i entry
                elsif ((curState_d1 = POPMATRIX)) then
                    
                    -- if i is odd, we load from port b
                    if( (i=1) or (i=3) or (i=5) or (i=7) or (i=9) or (i=11) or (i=13) or (i=15) ) then
                    
                        -- If stackCount has the ith data
                        if(r_stackCount = ((8-((i+1)/2))+2)) then --i*(-0.5)+8.5) then
                            -- If modelview
                            if(opCode(3 downto 0) = 0) then
                                -- Set new value from block ram
                                r_modelview(i)  <= signed(loadMatrix_b);
                    
                            -- If projection
                            elsif(opCode(3 downto 0) = 1) then
                                -- Set new value from block ram
                                r_projection(i) <= signed(loadMatrix_b);
                            end if;    
                        end if;
                        
                    -- else i is even and we load from port a
                    else
                        -- If stackCount has the ith data
                        if(r_stackCount = ((8-(i/2))+1)) then
                            -- If modelview
                            if(opCode(3 downto 0) = 0) then
                                -- Set new value from block ram
                                r_modelview(i)  <= signed(loadMatrix_a);
                    
                            -- If projection
                            elsif(opCode(3 downto 0) = 1) then
                                -- Set new value from block ram
                                r_projection(i) <= signed(loadMatrix_a);
                            end if;    
                        end if;
                    end if;
                end if;
            end if;
        end process;
        
 end generate shiftMatrix;
    

    --=========================================================================
    -- Vertex Pipe
    --=========================================================================
    
    u_modelViewMult: matrixMult
      port map( clk100     => clk100,
                    rst         => rst,
              
                   -- Pipeline control signals
                   unitfull            => upPipeStall,
                    wrEnable             => pipeFrontData.valid,
                   output_valid     => open,
                   downStreamFull    => projectionMatrixFull,
              
                   -- Input values
                   input_vertex_data => pipeFrontData,
                   matrix                    => r_modelview,
              
                   -- Resulting coordinate value
                   output_vertex_data => modelViewVertex,
                     
                     packetError => packetError_model);
    
    
    u_projectionMult: matrixMult
       port map( clk100     => clk100,
                    rst         => rst,
              
                   -- Pipeline control signals
                   unitfull            => projectionMatrixFull,
                    wrEnable             => modelViewVertex.valid,
                   output_valid     => open,    
                   downStreamFull    => perspectiveDividerFull,
              
                   -- Input values
                   input_vertex_data => modelViewVertex,
                   matrix                    => r_projection,
              
                   -- Resulting coordinate value
                   output_vertex_data => projectionVertex,
                     
                     packetError => packetError_proj);
                  
    u_perspectiveDivision: perspectiveDivision
       port map( clk100        => clk100,
                     rst            => rst,
                    
                     -- Pipeline control signals
                   unitfull            => perspectiveDividerFull,
                    wrEnable             => projectionVertex.valid,
                   output_valid     => open,    
                   downStreamFull    => assemblyFull,
              
                   -- Input values
                   input_vertex_data => projectionVertex,
              
                   -- Resulting coordinate value
                   output_vertex_data => normalizedVertex,
                     
                     packetError => packetError_div);
                  
    
u_checkID: packetIDCheck
      port map( clk       => clk100,
                    rst      => rst,
                    weEn     => normalizedVertex.valid,
                    packetID => normalizedVertex.packetID,
                    error    => packetError_fifo,
                    counterValue => open);
    
    
    -- Assembly
    u_assemblyTag: vertexAssemblyTag
      generic map(BUS_ADDRESS => ASSEMBLE_BUS_ADDRESS)
      port map(    clk    => clk100,
                    rst    => rst,
                    
                    -- Connections to the hostBus
                    hostBusMaster  => hostBusMaster,
                    hostBusSlave   => hostBusSlave(1),
                    
                    -- Pipeline control signals
                    unitfull           => assemblyFull,
                    wrEnable         => normalizedVertex.valid,
                    output_valid     => open,
                    downStreamFull    => clippingFull,
                    
                    -- Vertex in/out data
                    input_vertex_data  => normalizedVertex,
                    output_vertex_data => assemblyVertex,
                    
                    packetError => packetError_assm);
                    
                    packetError <= packetError_fifo or packetError_model or packetError_proj or packetError_div or packetError_assm;


   u_clipping: vertexClipping
      port map(    clk    => clk100,
                    rst    => rst,
                    
                    -- Pipeline control signals
                    unitfull           => clippingFull,
                    wrEnable         => assemblyVertex.valid,
                    output_valid     => open,
                    output_clipped => output_clipped,
                    downStreamFull    => viewPortFull,
                    
                    -- Vertex in/out data
                    input_vertex_data  => assemblyVertex,
                    output_vertex_data => clippingVertex);
    
    
    ce_viewport <= not downPipeStall;
    
   u_viewportXMult: viewPortMultXY
      port map (clk => clk100,
                a     => std_logic_vector(clippingVertex.vertex.pos.x),
                b     => std_logic_vector(r_viewport(5)(12 downto 1)),                     --(11 downto 0)
                     ce     => ce_viewport,
                p    => viewportX);    -- Q32.32 * Q12.0 = Q44.32 = 76bits
    
   u_viewportYMult: viewPortMultXY
      port map (clk => clk100,
                a     => std_logic_vector(clippingVertex.vertex.pos.y),
                b     => std_logic_vector(r_viewport4neg(12 downto 1)),                     --(11 downto 0)
                     ce     => ce_viewport,
                p    => viewportY);    -- Q32.32 * Q12.0 = Q44.32 = 76bits
        
    -- Q32.32 * Q1.24
   u_viewportZMult: viewPortMultZ
      port map (clk => clk100,
                a     => std_logic_vector(clippingVertex.vertex.pos.z),
                b     => std_logic_vector(z1(33 downto 9)),     -- Q2.23/2 = Q1.24 // with no actual shift                --(31 downto 0)
                     ce     => ce_viewport,
                p    => viewportZ);    -- Q33.56 = 89bits
            
        -- Shift register for valid and colors
        viewPortShiftReg(0) <=  (others=>'0') when rst='1' else
                                        std_logic_vector(clippingVertex.assembly) & std_logic_vector(clippingVertex.vertex.color) & clippingVertex.valid when rising_edge(clk100) and downPipeStall='0';
                                        
        viewPortFull <= viewPortShiftReg(0)(0) or downPipeStall;
                                        
   shiftRegViewPorts: for i in 1 to 6 generate
          viewPortShiftReg(i) <= (others=>'0') when rst='1' else
                                            viewPortShiftReg(i-1) when rising_edge(clk100) and downPipeStall='0';
   end generate shiftRegViewPorts;
        
        assert (viewportX(75 downto 64) = b"000000000000") or (viewportX(75 downto 64) = b"111111111111")  report "Error verteX truncation in vertexOps" severity ERROR;    
        assert (viewportY(75 downto 64) = b"000000000000") or (viewportY(75 downto 64) = b"111111111111")  report "Error verteY truncation in vertexOps" severity ERROR;    
        stdLogicVectorX <= viewportX(63 downto 0);
        stdLogicVectorY <= viewportY(63 downto 0);

        --Q33.56 = 89bits
        stdLogicVectorZ <= viewportZ(87 downto 24); 
        
        pipeVertexData.vertex.color <= color_t(viewPortShiftReg(5)(32 downto 1));
        pipeVertexData.assembly <= unsigned(viewPortShiftReg(5)(36 downto 33));
        pipeVertexData.vertex.pos.x <= fixed_t( signed(stdLogicVectorX) + signed(Ox));
        pipeVertexData.vertex.pos.y <= fixed_t( signed(stdLogicVectorY) + signed(Oy));
        pipeVertexData.vertex.pos.z <= fixed_t( signed(stdLogicVectorZ) + signed(Z2(63) & Z2(63 downto 1)));
        pipeVertexData.vertex.pos.w <= fixed_t(FIX_ONE);
        pipeVertexData.valid <= viewPortShiftReg(5)(0);
        pipeVertexDataValid <= viewPortShiftReg(5)(0);
        
   --=========================================================================
    -- State machine Processor
    --=========================================================================
    
    process(clk100, rst)
    begin
        if(rst='1') then
            curState <= IDLE;
        elsif(rising_edge(clk100)) then
            curState <= nextState;
            curState_d1 <= curState;
        end if;
    end process;
    
    process(curState, rst, instrFIFORead.start, opCode, setDone, pushPopDone)
    begin
        if(rst='1') then
            nextState <= IDLE;
        else
            -- Set the default nextState to current state
            nextState <= curState;
            
            case curState is
               when IDLE =>
                    -- If we have the start of a new packet do decode
                    if(instrFIFORead.start = '1') then
                        nextState <= DECODE;
                    end if;
                when DECODE =>
                    -- What type of inst are we doing?
                    case opCode(7 downto 4) is 
                        when "0001" =>
                            nextState <= SETMATRIX;
                        when "0010" =>
                            nextState <= PUSHMATRIX;
                        when "0100" =>
                            nextState <= POPMATRIX;
                        when "1000" =>
                            nextState <= LOADIDENTITY;
                        when others =>
                            nextState <= IDLE;
                    end case;
                when LOADIDENTITY =>
                    nextState <= IDLE;
                when POPMATRIX =>
                    if(pushPopDone = '1') then
                        nextState <= IDLE;
                    end if;
                when PUSHMATRIX =>
                    if(pushPopDone = '1') then
                        nextState <= IDLE;
                    end if;
                when SETMATRIX =>
                    if(setDone = '1') then
                        nextState <= IDLE;
                    end if;
                when others =>
                    nextState <= IDLE;
            end case;
        end if;
    end process;


end mixed;