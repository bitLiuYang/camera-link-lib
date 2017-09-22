-------------------------------------------------------------------------------
-- File       : CLinkTxWrapper.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-09-19
-- Last update: 2017-09-21
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
use work.SsiPkg.all;
use work.CLinkPkg.all;

entity CLinkTxWrapper is
   generic (
      TPD_G           : time                 := 1 ns;
      DEFAULT_CLINK_G : boolean              := true;  -- false = 1.25Gb/s, true = 2.5Gb/s
      LANE_G          : integer range 0 to 7 := 0);
   port (
      -- System Interface
      sysClk      : in  sl;
      sysRst      : in  sl;
      -- GT Interface (txClk domain)      
      txClk       : in  sl;
      txRst       : in  sl;
      txData      : out slv(15 downto 0);
      txCtrl      : out slv(1 downto 0);
      -- EVR Interface (evrClk domain)
      evrClk      : in  sl;
      evrRst      : in  sl;
      evrTrig     : in  sl;
      -- DMA Interface (sysClk domain)
      serRxMaster : in  AxiStreamMasterType;
      serRxSlave  : out AxiStreamSlaveType;
      -- Configuration and Status (sysClk domain)
      txStatus    : out CLinkTxStatusType;
      config      : in  CLinkConfigType);
end CLinkTxWrapper;

architecture mapping of CLinkTxWrapper is

   signal master : AxiStreamMasterType;
   signal slave  : AxiStreamSlaveType;

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
         SLAVE_AXI_CONFIG_G  => ssiAxiStreamConfig(4),  -- 32-bit interface
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
         CLK_RATE_INT_G => ite(DEFAULT_CLINK_G, 125000000, 62500000),
         LANE_G         => LANE_G)
      port map (
         -- System Clock and Reset
         systemReset          => sysRst,
         pciClk               => sysClk,
         -- GT Interface (txClk domain)
         txClk                => txClk,
         txRst                => txRst,
         txData               => txData,
         txCtrl               => txCtrl,
         -- EVR Interface (evrClk)
         evrClk               => evrClk,
         evrRst               => evrRst,
         evrToCl_trigger      => evrTrig,
         -- Control (sysClk domain)
         pciToCl_pack16       => config.pack16,
         pciToCl_trgPolarity  => config.trgPolarity,
         pciToCl_trgCC        => config.trgCC,
         pciToCl_serBaud      => config.serBaud,
         -- Serial RX  (sysClk domain)
         pciToCl_serFifoWrEn  => master.tValid,
         pciToCl_serFifoWr    => master.tData(7 downto 0),
         clToPci_serFifoAFull => slave.tReady);

   Sync_txRst : entity work.Synchronizer
      port map (
         clk     => sysClk,
         dataIn  => txRst,
         dataOut => txStatus.txRst);

end mapping;
