# Methods

## Index

```@index
```

## Structs

```@docs
VNAParameters
```

## Functions

```@docs
connect
```

>[!NOTE]
>`nothing` is a return type used in Julia for indicating, that it is intended to return nothing.

```@docs
disconnect
identify
clearStatus

KeyVNA.send
KeyVNA.recv

instrumentSimplifiedSetup
setPowerLevel
setCalibration
setFrequencies
setSweepPoints
setIFBandwidth
setMeasurement
setFormat2Log
setFastSweep
setAveraging
setupFromFile

triggerContinuous
triggerHold
triggerSingle

saveS2P
getFrequencies
getSweepTime

getTrace
storeTraceInMemory
getTraceFromMemory
getTraceCatalog
deleteTrace
deleteAllTraces

KeyVNA.complexFromTrace
```