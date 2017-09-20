-------------------------------------------------------------------------------
-- File       : CLinkRxWrapper.vhd
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

entity CLinkRxWrapper is
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
      rxClk           : in  sl;
      rxData          : in  slv(15 downto 0);
      rxCtrl          : in  slv(1 downto 0);
      rxDecErr        : in  slv(1 downto 0);
      rxDispErr       : in  slv(1 downto 0);
      -- EVR Interface (evrClk domain)
      evrClk          : in  sl;
      evrTrig         : in  sl;
      evrTimeStamp    : in  slv(63 downto 0);
      -- DMA Interfaces (sysClk domain)
      camDataMaster   : out AxiStreamMasterType;
      camDataSlave    : in  AxiStreamSlaveType
      serTxMaster     : out AxiStreamMasterType;
      serTxSlave      : in  AxiStreamSlaveType
      -- AXI-Lite Register Interface (sysClk domain)
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end CLinkRxWrapper;

architecture rtl of CLinkRxWrapper is

   type RegType is record
      pack16         : sl;
      trgPolarity    : sl;
      enable         : sl;
      numTrains      : slv(31 downto 0);
      numCycles      : slv(31 downto 0);
      serBaud        : slv(31 downto 0);
      axilReadSlave  : AxiLiteReadSlaveType;
      axilWriteSlave : AxiLiteWriteSlaveType;
   end record;

   constant REG_INIT_C : RegType := (
      pack16         => '0',
      trgPolarity    => '0',
      enable         => '0',
      numTrains      => toSlv(512, 32),
      numCycles      => toSlv(1536, 32),
      serBaud        => toSlv(57600, 32),
      axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal serTxMaster : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;

   signal linkStatus    : sl;
   signal cLinkLock     : sl;
   signal trgCount      : slv(31 downto 0);
   signal trgToFrameDly : slv(31 downto 0);
   signal frameCount    : slv(31 downto 0);
   signal frameRate     : slv(31 downto 0);

   signal linkStatusSync    : sl;
   signal cLinkLockSync     : sl;
   signal trgCountSync      : slv(31 downto 0);
   signal trgToFrameDlySync : slv(31 downto 0);
   signal frameCountSync    : slv(31 downto 0);
   signal frameRateSync     : slv(31 downto 0);

begin

   U_CLinkRx : entity work.CLinkRx
      generic map (
         TPD_G          => TPD_G,
         CLK_RATE_INT_G => ite(DEFAULT_CLINK_G, 250000000, 125000000),
         LANE_G         => LANE_G)
      port map (
         -- System Clock and Reset
         systemReset         => sysRst,
         pciClk              => sysClk,
         -- GT Interface (rxClk domain)
         rxClk               => rxClk,
         rxData              => rxData,
         rxCtrl              => rxCtrl,
         rxDecErr            => rxDecErr,
         rxDispErr           => rxDispErr,
         -- EVR Interface (evrClk)
         evrClk              => evrClk,
         evrToCl_trigger     => evrTrig,
         evrToCl_seconds     => evrTimeStamp(63 downto 32),
         evrToCl_nanosec     => evrTimeStamp(31 downto 0),
         -- Control (sysClk domain)
         pciToCl_pack16      => r.pack16,
         pciToCl_trgPolarity => r.trgPolarity,
         pciToCl_enable      => r.enable,
         pciToCl_numTrains   => r.numTrains,
         pciToCl_numCycles   => r.numCycles,
         pciToCl_serBaud     => r.serBaud,
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

   Sync_linkStatus : entity work.Synchronizer
      port map (
         clk     => sysClk,
         dataIn  => linkStatus,
         dataOut => linkStatusSync);

   Sync_cLinkLock : entity work.Synchronizer
      port map (
         clk     => sysClk,
         dataIn  => cLinkLock,
         dataOut => cLinkLockSync);

   Sync_trgCount : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => trgCount,
         rd_clk => sysClk,
         dout   => trgCountSync);

   Sync_trgToFrameDly : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => trgToFrameDly,
         rd_clk => sysClk,
         dout   => trgToFrameDlySync);

   Sync_frameCount : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => frameCount,
         rd_clk => sysClk,
         dout   => frameCountSync);

   Sync_frameRate : entity work.SynchronizerFifo
      generic map(
         DATA_WIDTH_G => 32)
      port map(
         wr_clk => rxClk,
         din    => frameRate,
         rd_clk => sysClk,
         dout   => frameRateSync);

   --------------------- 
   -- AXI Lite Interface
   --------------------- 
   comb : process (axilReadMaster, axilWriteMaster, cLinkLockSync,
                   frameCountSync, frameRateSync, linkStatusSync, r, sysRst,
                   trgCountSync, trgToFrameDlySync) is
      variable v      : RegType;
      variable regCon : AxiLiteEndPointType;
   begin
      -- Latch the current value
      v := r;

      -- Determine the transaction type
      axiSlaveWaitTxn(regCon, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      -- Map the read registers
      axiSlaveRegister(regCon, x"00", 0, v.numTrains);
      axiSlaveRegister(regCon, x"04", 0, v.numCycles);
      axiSlaveRegister(regCon, x"08", 0, v.serBaud);

      axiSlaveRegister(regCon, x"10", 0, v.enable);
      axiSlaveRegister(regCon, x"10", 1, v.pack16);
      axiSlaveRegister(regCon, x"10", 2, v.trgPolarity);

      axiSlaveRegisterR(regCon, x"80", 0, trgCountSync);
      axiSlaveRegisterR(regCon, x"84", 0, trgToFrameDlySync);
      axiSlaveRegisterR(regCon, x"88", 0, frameCountSync);
      axiSlaveRegisterR(regCon, x"8C", 0, frameRateSync);

      axiSlaveRegisterR(regCon, x"90", 0, linkStatusSync);
      axiSlaveRegisterR(regCon, x"90", 1, cLinkLockSync);

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
