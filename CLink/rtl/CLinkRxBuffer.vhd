-------------------------------------------------------------------------------
-- Title      : Camera link receive buffer
-------------------------------------------------------------------------------
-- File       : CLinkRxBuffer.vhd
-- Created    : 2017-08-22
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- This file is part of 'SLAC PGP Gen3 Card'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC PGP Gen3 Card', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.SsiPkg.all;
use work.Pgp2bPkg.all;

entity CLinkRxBuffer is 
   generic (
      TPD_G            : time := 1 ns;
      CASCADE_SIZE_G   : natural;
      SLAVE_READY_EN_G : boolean;
      LANE_G           : natural);
   port (
      seconds         : in  Slv(31 downto 0);
      nanosec         : in  Slv(31 downto 0);
      trgToFrameDly   : in  Slv(31 downto 0);
      frameCount      : in  Slv(31 downto 0);
      frameRate       : in  Slv(31 downto 0);

      -- 16-bit Streaming RX Interface
      rx16Master      : in  AxiStreamMasterType;
      rx16Slave       : out AxiStreamSlaveType;
      -- 32-bit Streaming TX Interface for DMA
      dmaClk          : in  sl;
      dmaRst          : in  sl;
      dmaStreamMaster : out AxiStreamMasterType;
      dmaStreamSlave  : in  AxiStreamSlaveType;
      -- FIFO Overflow Error Strobe
      fifoError       : out sl;
      -- Global Signals
      clk             : in  sl;
      rst             : in  sl);
end CLinkRxBuffer;

architecture rtl of CLinkRxBuffer is

   constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(4);  -- 32-bit interface

   type StateType is (
      NEW_DATA_S,
      WR_HDR1_S,
      WR_HDR2_S,
      WR_HDR3_S,
      WR_FIRST_S);    

   type RegType is record
      fifoError  : sl;
      tData0     : Slv(31 downto 0);
      rx32Slave  : AxiStreamSlaveType;
      tx32Master : AxiStreamMasterType;
      state      : StateType;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      fifoError  => '0',
      tData0     => (others => '0'),
      rx32Slave  => AXI_STREAM_SLAVE_INIT_C,
      tx32Master => AXI_STREAM_MASTER_INIT_C,
      state      => NEW_DATA_S);

   signal r          : RegType := REG_INIT_C;
   signal rin        : RegType;

   signal rx32Master : AxiStreamMasterType;
   signal rx32Slave  : AxiStreamSlaveType;

   signal tx32Slave  : AxiStreamSlaveType;
   signal axis16Ctrl : AxiStreamCtrlType;
   
begin
   
   FIFO_RX : entity work.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         INT_PIPE_STAGES_G   => 1,
         PIPE_STAGES_G       => 1,
         SLAVE_READY_EN_G    => SLAVE_READY_EN_G,
         VALID_THOLD_G       => 1,
         -- FIFO configurations
         BRAM_EN_G           => true,
         XIL_DEVICE_G        => "7SERIES",
         USE_BUILT_IN_G      => false,
         GEN_SYNC_FIFO_G     => true,
         ALTERA_SYN_G        => false,
         ALTERA_RAM_G        => "M9K",
         CASCADE_SIZE_G      => CASCADE_SIZE_G,
         FIFO_ADDR_WIDTH_G   => 10,
         FIFO_FIXED_THRESH_G => true,
         FIFO_PAUSE_THRESH_G => 512,
         CASCADE_PAUSE_SEL_G => (CASCADE_SIZE_G-1),
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => SSI_PGP2B_CONFIG_C,
         MASTER_AXI_CONFIG_G => AXIS_CONFIG_C)        
      port map (
         -- Slave Port
         sAxisClk    => clk,
         sAxisRst    => rst,
         sAxisMaster => rx16Master,
         sAxisSlave  => rx16Slave,
         sAxisCtrl   => axis16Ctrl,
         -- Master Port
         mAxisClk    => clk,
         mAxisRst    => rst,
         mAxisMaster => rx32Master,
         mAxisSlave  => rx32Slave);  

   FIFO_TX : entity work.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         INT_PIPE_STAGES_G   => 1,
         PIPE_STAGES_G       => 1,
         SLAVE_READY_EN_G    => true,
         VALID_THOLD_G       => 1,
         -- FIFO configurations
         BRAM_EN_G           => false,
         USE_BUILT_IN_G      => false,
         GEN_SYNC_FIFO_G     => false,
         CASCADE_SIZE_G      => 1,
         FIFO_ADDR_WIDTH_G   => 4,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => AXIS_CONFIG_C,
         MASTER_AXI_CONFIG_G => AXIS_CONFIG_C)      
      port map (
         -- Slave Port
         sAxisClk    => clk,
         sAxisRst    => rst,
         sAxisMaster => r.tx32Master,
         sAxisSlave  => tx32Slave,
         -- Master Port
         mAxisClk    => dmaClk,
         mAxisRst    => dmaRst,
         mAxisMaster => dmaStreamMaster,
         mAxisSlave  => dmaStreamSlave);        

   comb : process (axis16Ctrl, r, rst, rx32Master, tx32Slave, frameRate, trgToFrameDly, frameCount, seconds, nanosec) is
      variable v : RegType;
   begin
      -- Latch the current value
      v                := r;

      -- Add registers to help with timing
      v.fifoError      := axis16Ctrl.overflow;

      -- Reset strobing signals
      v.rx32Slave.tReady := '0';

      -- Update tValid register
      if (tx32Slave.tReady = '1') then
         v.tx32Master.tValid := '0';
         v.tx32Master.tLast  := '0';
         v.tx32Master.tUser  := (others => '0');
         v.tx32Master.tDest  := toSlv(0, 8);
      end if;

      case r.state is
         -----------------------------------------------------------------------
         when NEW_DATA_S =>
            -- Check if need to and can move data
            if (rx32Master.tValid = '1') and (v.tx32Master.tValid = '0') then
               if (ssiGetUserSof(AXIS_CONFIG_C, rx32Master) = '1') then   -- SOF
                  ssiSetUserSof(AXIS_CONFIG_C, v.tx32Master, '1');
                  v.tx32Master.tData(31 downto 29) := toSlv(LANE_G, 3);

                  if ( frameRate < 1024 ) then
                  v.tx32Master.tData(28 downto 19) := frameRate(9 downto 0);
                  else
                  v.tx32Master.tData(28 downto 19) := (others => '1');
                  end if;

                  if ( trgToFrameDly < X"80000" ) then
                  v.tx32Master.tData(18 downto  0) := trgToFrameDly(18 downto 0);
                  else
                  v.tx32Master.tData(18 downto  0) := (others => '1');
                  end if;

                  v.tx32Master.tValid              := '1';

                  v.tData0                         := rx32Master.tData(31 downto 0);

                  v.state                          := WR_HDR1_S;
               else                                           -- accept the data
                  v.tx32Master       := rx32Master;             -- write to FIFO
                  v.rx32Slave.tReady := '1';               -- ready for new data
               end if;
            end if;
         -----------------------------------------------------------------------
         when WR_HDR1_S =>
            if (v.tx32Master.tValid = '0') then        -- Check if FIFO is ready
               v.tx32Master.tData(31 downto 0) := frameCount;
               v.tx32Master.tValid             := '1';

               v.state                         := WR_HDR2_S;
            end if;
         when WR_HDR2_S =>
            if (v.tx32Master.tValid = '0') then        -- Check if FIFO is ready
               v.tx32Master.tData(31 downto 0) := seconds;
               v.tx32Master.tValid             := '1';

               v.state                         := WR_HDR3_S;
            end if;
         -----------------------------------------------------------------------
         when WR_HDR3_S =>
            if (v.tx32Master.tValid = '0') then        -- Check if FIFO is ready
               v.tx32Master.tData(31 downto 0) := nanosec;
               v.tx32Master.tValid             := '1';

               v.state                         := WR_FIRST_S;
            end if;
         -----------------------------------------------------------------------
         when WR_FIRST_S =>
            if (v.tx32Master.tValid = '0') then        -- Check if FIFO is ready
               v.tx32Master.tData(31 downto 0) := v.tData0;       -- 1st 4 bytes
               v.tx32Master.tValid             := '1';

               v.rx32Slave.tReady              := '1';     -- ready for new data

               v.state                         := NEW_DATA_S;
            end if;
         -----------------------------------------------------------------------
      end case;

      -- Reset
      if (rst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin       <= v;

      -- Outputs
      fifoError <= r.fifoError;
      rx32Slave <= v.rx32Slave;
      
   end process comb;

   seq : process (clk) is
   begin
      if rising_edge(clk) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;

