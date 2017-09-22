-------------------------------------------------------------------------------
-- File       : CLinkPkg.vhd
-- Created    : 2017-08-22
-- Last update: 2017-09-22
-------------------------------------------------------------------------------
-- Description: CLink Package
-------------------------------------------------------------------------------
-- This file is part of 'axi-pcie-core'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'axi-pcie-core', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

use work.StdRtlPkg.all;

package CLinkPkg is

   constant IDLE_STRING_C : slv(495 downto 0) := x"45524242524120474D45524120464E4B4C4941204552414D20435259544F5241424F4C415220544F52414C45434541434C204E41494F4154204E4143534C";

   type CLinkConfigType is record
      enable      : sl;
      trgPolarity : sl;
      pack16      : sl;
      trgCC       : slv(1 downto 0);
      numTrains   : slv(31 downto 0);
      numCycles   : slv(31 downto 0);
      serBaud     : slv(31 downto 0);
   end record;
   constant CLINK_CONFIG_INIT_C : CLinkConfigType := (
      enable      => '0',
      trgPolarity => '0',
      pack16      => '0',
      trgCC       => (others => '0'),
      numTrains   => toSlv(512, 32),
      numCycles   => toSlv(1536, 32),
      serBaud     => toSlv(57600, 32));

   type CLinkRxStatusType is record
      rxRst         : sl;
      evrRst        : sl;
      linkStatus    : sl;
      cLinkLock     : sl;
      trgCount      : slv(31 downto 0);
      trgToFrameDly : slv(31 downto 0);
      frameCount    : slv(31 downto 0);
      frameRate     : slv(31 downto 0);
      rxClkFreq     : slv(31 downto 0);
      evrClkFreq    : slv(31 downto 0);
   end record;

   type CLinkTxStatusType is record
      txRst     : sl;
      txClkFreq : slv(31 downto 0);
   end record;

end package CLinkPkg;

