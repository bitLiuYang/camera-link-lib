-------------------------------------------------------------------------------
-- File       : CLinkRxWrapper.vhd
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
use work.CLinkPkg.all;

entity CLinkRxWrapper is
   generic (
      TPD_G           : time                 := 1 ns;
      DEFAULT_CLINK_G : boolean              := true;  -- false = 1.25Gb/s, true = 2.5Gb/s
      LANE_G          : integer range 0 to 7 := 0);
   port (
      -- System Interface
      sysClk        : in  sl;
      sysRst        : in  sl;
      -- GT Interface (rxClk domain)
      rxClk         : in  sl;
      rxRst         : in  sl;
      rxData        : in  slv(15 downto 0);
      rxCtrl        : in  slv(1 downto 0);
      rxDecErr      : in  slv(1 downto 0);
      rxDispErr     : in  slv(1 downto 0);
      -- EVR Interface (evrClk domain)
      evrClk        : in  sl;
      evrRst        : in  sl;
      evrTrig       : in  sl;
      evrTimeStamp  : in  slv(63 downto 0);
      -- DMA Interfaces (sysClk domain)
      camDataMaster : out AxiStreamMasterType;
      camDataSlave  : in  AxiStreamSlaveType;
      serTxMaster   : out AxiStreamMasterType;
      serTxSlave    : in  AxiStreamSlaveType;
      -- Configuration and Status (sysClk domain)
      rxStatus      : out CLinkRxStatusType;
      config        : in  CLinkConfigType);
end CLinkRxWrapper;

architecture rtl of CLinkRxWrapper is

   signal master : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;

   signal linkStatus    : sl;
   signal cLinkLock     : sl;
   signal trgCount      : slv(31 downto 0);
   signal trgToFrameDly : slv(31 downto 0);
   signal frameCount    : slv(31 downto 0);
   signal frameRate     : slv(31 downto 0);

begin

   U_CLinkRx : entity work.CLinkRx
      generic map (
         TPD_G          => TPD_G,
         CLK_RATE_INT_G => ite(DEFAULT_CLINK_G, 125000000, 62500000),
         LANE_G         => LANE_G)
      port map (
         -- System Clock and Reset
         systemReset         => sysRst,
         pciClk              => sysClk,
         -- GT Interface (rxClk domain)
         rxClk               => rxClk,
         rxRst               => rxRst,
         rxData              => rxData,
         rxCtrl              => rxCtrl,
         rxDecErr            => rxDecErr,
         rxDispErr           => rxDispErr,
         -- EVR Interface (evrClk)
         evrClk              => evrClk,
         evrRst              => evrRst,
         evrToCl_trigger     => evrTrig,
         evrToCl_seconds     => evrTimeStamp(63 downto 32),
         evrToCl_nanosec     => evrTimeStamp(31 downto 0),
         -- Control (sysClk domain)
         pciToCl_pack16      => config.pack16,
         pciToCl_trgPolarity => config.trgPolarity,
         pciToCl_enable      => config.enable,
         pciToCl_numTrains   => config.numTrains,
         pciToCl_numCycles   => config.numCycles,
         pciToCl_serBaud     => config.serBaud,
         pciToCl_SerFifoRdEn => serTxSlave.tReady,
         -- Status  (rxClk domain)
         linkStatus          => linkStatus,
         cLinkLock           => cLinkLock,
         trgCount            => trgCount,
         trgToFrameDly       => trgToFrameDly,
         frameCount          => frameCount,
         frameRate           => frameRate,
         -- Serial TX  (sysClk domain)
         serTfgValid         => master.tValid,
         serTfgByte          => master.tData(7 downto 0),
         -- DMA Interface (dmaClk domain)
         dmaClk              => sysClk,
         dmaRst              => sysRst,
         dmaStreamMaster     => camDataMaster,
         dmaStreamSlave      => camDataSlave);

   master.tLast <= '1';                 -- always last
   master.tKeep <= x"0001";             -- 1 byte at a time
   master.tStrb <= x"0001";             -- 1 byte at a time
   serTxMaster  <= master;

   Sync_rxRst : entity work.Synchronizer
      port map (
         clk     => sysClk,
         dataIn  => rxRst,
         dataOut => rxStatus.rxRst);

   Sync_evrRst : entity work.Synchronizer
      port map (
         clk     => sysClk,
         dataIn  => evrRst,
         dataOut => rxStatus.evrRst);

   Sync_linkStatus : entity work.Synchronizer
      port map (
         clk     => sysClk,
         dataIn  => linkStatus,
         dataOut => rxStatus.linkStatus);

   Sync_cLinkLock : entity work.Synchronizer
      port map (
         clk     => sysClk,
         dataIn  => cLinkLock,
         dataOut => rxStatus.cLinkLock);

   Sync_trgCount : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => trgCount,
         rd_clk => sysClk,
         dout   => rxStatus.trgCount);

   Sync_trgToFrameDly : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => trgToFrameDly,
         rd_clk => sysClk,
         dout   => rxStatus.trgToFrameDly);

   Sync_frameCount : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => frameCount,
         rd_clk => sysClk,
         dout   => rxStatus.frameCount);

   Sync_frameRate : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => frameRate,
         rd_clk => sysClk,
         dout   => rxStatus.frameRate);

end rtl;
