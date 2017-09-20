-------------------------------------------------------------------------------
-- File       : CLinkTxWrapper.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-09-19
-- Last update: 2017-09-20
-------------------------------------------------------------------------------
-- Description: 
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
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.AxiLitePkg.all;

entity CLinkTxWrapper is
   generic (
      TPD_G            : time                 := 1 ns;
      DEFAULT_CLINK_G  : boolean              := true;  -- false = 1.25Gb/s, true = 2.5Gb/s
      LANE_G           : integer range 0 to 7 := 0
      AXI_ERROR_RESP_G : slv(1 downto 0)      := AXI_RESP_DECERR_C);
   port (
      -- System Interface
      sysClk          : in  sl;
      sysRst          : in  sl;
      -- GT Interface (rxClk domain)      
      txClk           : in  sl;
      txData          : out slv(15 downto 0);
      txCtrl          : out slv(1 downto 0);
      -- EVR Interface (evrClk domain)
      evrClk          : in  sl;
      evrTrig         : in  sl;
      -- DMA Interface (sysClk domain)
      serRxMaster     : in  AxiStreamMasterType;
      serRxSlave      : out AxiStreamSlaveType;
      -- AXI-Lite Register Interface (sysClk domain)
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end CLinkTxWrapper;

architecture rtl of CLinkTxWrapper is

   type RegType is record
      pack16         : sl;
      trgPolarity    : sl;
      trgCC          : slv(1 downto 0);
      serBaud        : slv(31 downto 0);
      axilReadSlave  : AxiLiteReadSlaveType;
      axilWriteSlave : AxiLiteWriteSlaveType;
   end record;

   constant REG_INIT_C : RegType := (
      pack16         => '0',
      trgPolarity    => '0',
      trgCC          => (others => '0'),
      serBaud        => toSlv(57600, 32),
      axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal serRxMaster : AxiStreamMasterType;
   signal serRxSlave  : AxiStreamSlaveType

begin

   U_Fifo : entity work.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         INT_PIPE_STAGES_G   => 1,
         PIPE_STAGES_G       => 1,
         SLAVE_READY_EN_G    => true,
         VALID_THOLD_G       => 1,
         -- FIFO configurations
         BRAM_EN_G           => true,
         USE_BUILT_IN_G      => false,
         GEN_SYNC_FIFO_G     => true,
         CASCADE_SIZE_G      => 1,
         FIFO_ADDR_WIDTH_G   => 9,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  =>  ssiAxiStreamConfig(4),  -- 32-bit interface
         MASTER_AXI_CONFIG_G => ssiAxiStreamConfig(1))  -- 8-bit interface   
      port map (
         -- Slave Port
         sAxisClk    => sysClk,
         sAxisRst    => sysRst,
         sAxisMaster => serRxMaster,
         sAxisSlave  => serRxSlave,
         -- Master Port
         mAxisClk    => sysClk,
         mAxisRst    => sysRst,
         mAxisMaster => master,
         mAxisSlave  => slave);

   U_CLinkTx : entity work.CLinkTx
      generic map (
         TPD_G          => TPD_G,
         CLK_RATE_INT_G => ite(DEFAULT_CLINK_G, 250000000, 125000000),
         LANE_G         => LANE_G)
      port map (
         -- System Clock and Reset
         systemReset          => sysRst,
         pciClk               => sysClk,
         -- GT Interface (txClk domain)
         txClk                => txClk,
         txData               => txData,
         txCtrl               => txCtrl,
         -- EVR Interface (evrClk)
         evrClk               => evrClk,
         evrToCl_trigger      => evrTrig,
         -- Control (sysClk domain)
         pciToCl_pack16       => r.pack16,
         pciToCl_trgPolarity  => r.trgPolarity,
         pciToCl_trgCC        => r.trgCC,
         pciToCl_serBaud      => r.serBaud,
         -- Serial RX  (sysClk domain)
         pciToCl_serFifoWrEn  => master.tValid,
         pciToCl_serFifoWr    => master.tData(7 downto 0),
         clToPci_serFifoAFull => slave.tReady);

   --------------------- 
   -- AXI Lite Interface
   --------------------- 
   comb : process (axilReadMaster, axilWriteMaster, r, sysRst) is
      variable v      : RegType;
      variable regCon : AxiLiteEndPointType;
   begin
      -- Latch the current value
      v := r;

      -- Determine the transaction type
      axiSlaveWaitTxn(regCon, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      -- Map the read registers
      axiSlaveRegister(regCon, x"00", 0, v.trgCC);
      axiSlaveRegister(regCon, x"04", 0, v.serBaud);

      axiSlaveRegister(regCon, x"10", 1, v.pack16);
      axiSlaveRegister(regCon, x"10", 2, v.trgPolarity);

      -- Closeout the transaction
      axiSlaveDefault(regCon, v.axilWriteSlave, v.axilReadSlave, AXI_ERROR_RESP_G);

      -- Synchronous Reset
      if (sysRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

      -- Outputs
      axilWriteSlave <= r.axilWriteSlave;
      axilReadSlave  <= r.axilReadSlave;

   end process comb;

   seq : process (sysClk) is
   begin
      if (rising_edge(sysClk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

end rtl;
