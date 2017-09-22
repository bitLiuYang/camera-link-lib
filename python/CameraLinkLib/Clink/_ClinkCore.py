#!/usr/bin/env python
#-----------------------------------------------------------------------------
# Title      : PyRogue AMC Carrier Cryo Demo Board Application
#-----------------------------------------------------------------------------
# File       : ClinkCore.py
# Created    : 2017-04-03
#-----------------------------------------------------------------------------
# Description:
# PyRogue AMC Carrier Cryo Demo Board Application
#-----------------------------------------------------------------------------
# This file is part of the rogue software platform. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the rogue software platform, including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

import pyrogue as pr
import pyrogue.simulation
import rogue.hardware.data

from DataLib.DataDev import *
from CameraLinkLib.Clink import *
from LclsTimingCore.TimingFrameRx import *
from surf.xilinx import *

class ClinkCore(pr.Device):
    def __init__(   self,       
            name        = "ClinkCore",
            description = "ClinkCore",
            **kwargs):
        super().__init__(name=name, description=description, **kwargs)
        
        self.add(pr.RemoteVariable( 
            name         = "CLinkEnable",
            description  = "CLinkEnable",
            offset       = 0x00,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RW",
        ))      
        
        self.add(pr.RemoteVariable( 
            name         = "TrgPolarity",
            description  = "TrgPolarity",
            offset       = 0x04,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RW",
        ))    

        self.add(pr.RemoteVariable( 
            name         = "Pack16",
            description  = "Pack16",
            offset       = 0x08,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RW",
        ))       

        self.add(pr.RemoteVariable( 
            name         = "TrgCC",
            description  = "TrgCC",
            offset       = 0x0C,
            bitSize      = 2,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RW",
        ))     

        self.add(pr.RemoteVariable( 
            name         = "NumTrains",
            description  = "NumTrains",
            offset       = 0x10,
            bitSize      = 32,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RW",
        ))   

        self.add(pr.RemoteVariable( 
            name         = "NumCycles",
            description  = "NumCycles",
            offset       = 0x14,
            bitSize      = 32,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RW",
        ))       

        self.add(pr.RemoteVariable( 
            name         = "SerBaud",
            description  = "SerBaud",
            offset       = 0x18,
            bitSize      = 32,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RW",
        ))   

        self.add(pr.RemoteVariable( 
            name         = "RxRstStatus",
            description  = "RxRstStatus",
            offset       = 0x40,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        ))     

        self.add(pr.RemoteVariable( 
            name         = "EvrRstStatus",
            description  = "EvrRstStatus",
            offset       = 0x44,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        ))       

        self.add(pr.RemoteVariable( 
            name         = "LinkStatus",
            description  = "LinkStatus",
            offset       = 0x48,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        ))       

        self.add(pr.RemoteVariable( 
            name         = "CLinkLock",
            description  = "CLinkLock",
            offset       = 0x4C,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        ))   

        self.add(pr.RemoteVariable( 
            name         = "TrgCount",
            description  = "TrgCount",
            offset       = 0x50,
            bitSize      = 32,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        ))           

        self.add(pr.RemoteVariable( 
            name         = "TrgToFrameDly",
            description  = "TrgToFrameDly",
            offset       = 0x54,
            bitSize      = 32,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        ))    

        self.add(pr.RemoteVariable( 
            name         = "FrameCount",
            description  = "FrameCount",
            offset       = 0x58,
            bitSize      = 32,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        )) 

        self.add(pr.RemoteVariable( 
            name         = "FrameRate",
            description  = "FrameRate",
            offset       = 0x5C,
            bitSize      = 32,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        ))

        self.add(pr.RemoteVariable( 
            name         = "RxClkFreq",
            description  = "RxClkFreq",
            offset       = 0x60,
            bitSize      = 32,
            bitOffset    = 0,
            units        = 'Hz',
            base         = pr.UInt,
            mode         = "RO",
        ))  

        self.add(pr.RemoteVariable( 
            name         = "EvrClkFreq",
            description  = "EvrClkFreq",
            offset       = 0x64,
            bitSize      = 32,
            bitOffset    = 0,
            units        = 'Hz',
            base         = pr.UInt,
            mode         = "RO",
        ))          
        
        self.add(pr.RemoteVariable( 
            name         = "TxRstStatus",
            description  = "TxRstStatus",
            offset       = 0x80,
            bitSize      = 1,
            bitOffset    = 0,
            base         = pr.UInt,
            mode         = "RO",
        )) 

        self.add(pr.RemoteVariable( 
            name         = "TxClkFreq",
            description  = "TxClkFreq",
            offset       = 0x84,
            bitSize      = 32,
            bitOffset    = 0,
            units        = 'Hz',
            base         = pr.UInt,
            mode         = "RO",
        ))         
        