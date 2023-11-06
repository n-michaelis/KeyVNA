# KeyVNA

KeyVNA is an API for Keysight Vector Network Analyzers. Based on the SCPI protocoll.

### Installation

Clone into directory of choice.
Include the module with:
```julia
include("src/KeyVNA.jl")
import .KeyVNA
```


### Example usage

A simple example on how to use the Package.
Connecting to the VNA and performing a sweep.

```julia
import KeyVNA

# Connect to the VNA using the IP
vna = KeyVNA.connect("127.0.0.1")

# Perform a single trace
# Returns the scattering parameter for each frequency point as a
# Vector{ComplexF64}
data = KeyVNA.getTrace(vna)

# Returns the frequency points
freq = KeyVNA.getFrequencies(vna)
```
