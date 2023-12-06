module KeyVNA

import Sockets

export
    connect,
    disconnect,
    identify,
    clearStatus,

    setPowerLevel,
    setCalibration,
    setAveraging,
    setFrequencies,
    setSweepPoints,
    setIFBandwidth,
    setMeasurement,
    setFormat2Log,
    setFastSweep,
    setupFromFile,

    getBufferSize,
    refreshBuffer,
    clearBuffer,
    isBlocked,

    triggerContinuous,
    triggerHold,
    triggerSingle,

    saveS2P,
    getFrequencies,
    getSweepTime,
    getTrace,
    storeTraceInMemory,
    getTraceFromMemory,
    getTraceCatalog,
    deleteTrace,
    deleteAllTraces,

    instrumentSimplifiedSetup,

    VNAParameters



### Private functions ###
# They are not beeing exported

"""
    send(socket::TCPSocket, msg::String)

Send `msg` to the TCP socket `socket`.

Can be used to send any SCPI command directly to the VNA.
"""
function send(socket::Sockets.TCPSocket, msg::String)
    Sockets.write(socket, codeunits(msg))
end

"""
    recv(socket::TCPSocket)

Receive and return all buffered bytes from `socket`.
If none are available, wait.
Returns a `Vector{UInt8}`.
"""
function recv(socket::Sockets.TCPSocket)
    refreshBuffer(socket)

    return readavailable(socket)
end

"""
    recv(socket::TCPSocket, nb::Integer)

Receive and return `nb` number of bytes from `socket`.
Returns a `Vector{UInt8}`.
"""
function recv(socket::Sockets.TCPSocket,nb::Integer)
    refreshBuffer(socket)

    return read(socket,nb)
end

function async_reader(io::IO, timeout_sec)::Channel
    ch = Channel(1)
    task = @async begin
        reader_task = current_task()

        function timeout_cb(timer)
            put!(ch, :timeout)
            Base.throwto(reader_task, InterruptException())
        end

        timeout = Timer(timeout_cb, timeout_sec)
        data = String(readavailable(io))
        timeout_sec > 0 && close(timeout) # Cancel the timeout
        put!(ch, data)
    end

    bind(ch, task)

    return ch
end

### End private functions ###


### Connection ###

"""
    connect(host; port=5025)

Establish a TCP connection to the VNA with IP address `host`.
Return a `TCPSocket` if succesful and `nothing` if not.
"""
function connect(host; port=5025)
    try
        socket = Sockets.connect(host,port)

        refreshBuffer(socket)

        return socket

    catch e
        error("Failed to connect to host.\n"*e.msg)

        return nothing
    end
end

"""
    disconnect(socket)

Closes the TCP connection `socket`.
"""
function disconnect(socket::Sockets.TCPSocket)
    Sockets.close(socket)

    return nothing
end

"""
    identify(socket)

"""
function identify(socket::Sockets.TCPSocket)
    send(socket,"*IDN?\n")

    return nothing
end

"""
    clearStatus(socket)

"""
function clearStatus(socket::Sockets.TCPSocket)
    send(socket,"*CLS\n")

    return nothing
end


### Setup ###

"""
    setPowerLevel(socket::TCPSocket, power::Integer)

Set the power level, of the VNA specified by `socket`, to `power` dBm.
"""
function setPowerLevel(socket::Sockets.TCPSocket,power::Integer)
    if power > 14
        error("Power threshold reached. Must be less than 14 dBm.")
    end

    send(socket, "SOURce:POWer:LEVel:IMMediate:AMPLitude "*string(power)*"\n")

    return nothing
end

"""
    setCalibration(socket::TCPSocket ,calName::String)

Set the calibration file, of the VNA specified by `socket`, to `calName`
"""
function setCalibration(socket::Sockets.TCPSocket, calName::String)
    send(socket, "SENSe:CORRection:CSET:ACTivate \""*string(calName)*"\",1\n")

    return
end

"""
    setAveraging(socket::TCPSocket, state::Bool; counts::Int=50)

TODO
"""
function setAveraging(socket::Sockets.TCPSocket,state::Bool; counts::Int=50)
    if counts <= 0
        error("Count number must be positive.")
    end

    send(socket, "SENSe:AVERage:STATe "*(state ? "ON\n" : "OFF\n"))

    if state
        send(socket, "SENSe:AVERage:COUNt "*string(counts)*"\n")
    end

    return
end

"""
    setFrequencies(socket::TCPSocket, center::Float64, span::Float64)

Set frequency band, of the VNA specified by `socket`.
The band is given by the `center` frequency and the `span`.
The bounds are then given by `center` ± `span`/2.
"""
function setFrequencies(socket::Sockets.TCPSocket,center::Float64,span::Float64)
    if !(10e6 <= center <= 43.5e9)
        error("Center frequency must be between 10 MHz and 43.5 GHz.")
    elseif !(0 <= span <= min(abs(center-10e6),abs(center-43.5)))
        error("Span reaches out of 10 MHz to 43.5 GHz bandwidth.")
    end

    send(socket, "SENS:FREQ:CENTer "*string(center)*";SPAN "*string(span)*"\n")

    return
end

"""
    setSweepPoints(socket::TCPSocket, points::Integer)

Set number of sweep points, of the VNA specified by `socket`.
"""
function setSweepPoints(socket::Sockets.TCPSocket, points::Integer)
    if points <= 0
        error("Must use at least one sweep point.")
    end

    send(socket, "SENSe1:SWEep:POINts "*string(points)*"\n")

    return
end

"""
    setIFBandwidth(socket::TCPSocket, bandwidth::Integer)

Set IF bandwidth, of the VNA specified by `socket`.
"""
function setIFBandwidth(socket::Sockets.TCPSocket, bandwidth::Integer)
    if bandwidth <= 0
        error("Resolution must be greater that 0.")
    end

    send(socket, "SENSe1:BANDwidth:RESolution "*string(bandwidth)*"\n")

    return
end

"""
    setMeasurement(socket::TCPSocket, name::String)

Set wich measurement, of the VNA specified by `socket`, to use.

# name
The string has to be in a certain format `"CH<n>_S<p>_<t>"``, with:
- `n`: Channel number
- `p`: Scattering parameter
- `t`: trace number

For example the String `"CH1_S11_1"` selects Channel 1, the parameter S11
and the trace 1.
"""
function setMeasurement(socket::Sockets.TCPSocket, name::String)
    send(socket, "CALCulate:PARameter:SELect '"*name*"'\n")

    return
end

"""
    setFormat2Log(socket::TCPSocket)

Set the format of the VNA display to logarithmic scale.
"""
function setFormat2Log(socket::Sockets.TCPSocket)
    send(socket, "CALCulate:MEASure:FORMat MLOGarithmic\n")

    return
end

"""
    setFastSweep(socket::TCPSocket, fast::Bool)

Enable Fast Sweep mode.
"""
function setFastSweep(socket::Sockets.TCPSocket, fast::Bool)
    if fast
        send(socket,"SENSe:SWEep:SPEed FAST\n")
    else
        send(socket,"SENSe:SWEep:SPEed NORMal\n")
    end

    return
end

"""
    setupFromFile(socket::TCPSocket,file::String)

Set up the VNA specified by `socket` according to the settings specified
in `file`.

TODO: For more information see ...
"""
function setupFromFile(socket::Sockets.TCPSocket,file::String)
    for line in readlines(file)
        if line[1] == '#'
            continue
        end
        
        l = split(line,':')
        
        if l[1] == "PWLV"
            setPowerLevel(socket,parse(Int,l[2]))
        elseif l[1] == "AVRG"
            if parse(Bool,l[2])
                setAveraging(socket,true; counts=parse(Int,l[3]))
            else
                setAveraging(socket,false)
            end
        elseif l[1] == "FREQ"
            if length(l) == 3
                setFrequencies(socket,parse(Float64,l[2]),parse(Float64,l[3]))
            elseif length(l) == 4
                f1 = parse(Float64,l[2]); f2 = parse(Float64,l[3])
                setFrequencies(socket,(f1+f2)/2,f2-f1)
            end
        elseif l[1] == "SWPP"
            setSweepPoints(socket,Int64(parse(Float64,l[2])))
        elseif l[1] == "IFBW"
            setIFBandwidth(socket,Int64(parse(Float64,l[2])))
        elseif l[1] == "FRMT"
            if l[2] == "log"
                setFormat2Log(socket)
            end
        elseif l[1] == "MSRM"
            setMeasurement(socket,String(l[2]))
        elseif l[1] == "CALB"
            c = String(l[2])

            if c[1] != '{'
                c = "{"*c
            end

            if c[end] != '}'
                c = c*"}"
            end
            
            setCalibration(socket,c)
        end
    end
end


### Buffer ###

function getBufferSize(socket::Sockets.TCPSocket)
    return socket.buffer.size
end

function refreshBuffer(socket::Sockets.TCPSocket)
    @async eof(socket)

    return
end

function clearBuffer(socket::Sockets.TCPSocket)
    socket.buffer.size = 0
    socket.buffer.ptr = 1

    return
end

function isBlocked(socket::Sockets.TCPSocket)
    refreshBuffer(socket)

    return getBufferSize(socket) == 0
end


### Trigger ###

"""
    triggerContinuous(socket::TCPSocket)

Set the trigger of the VNA to continous.
"""
function triggerContinuous(socket::Sockets.TCPSocket)
    send(socket, "SENse:SWEep:MODE HOLD\n")

    return
end

"""
    triggerHold(socket::TCPSocket)

Set the trigger of the VNA to hold.
"""
function triggerHold(socket::Sockets.TCPSocket)
    send(socket, "SENse:SWEep:MODE CONTinuous\n")

    return
end

"""
    triggerSingle(socket::TCPSocket)

Trigger the VNA once.
"""
function triggerSingle(socket::Sockets.TCPSocket)
    send(socket, "SENse:SWEep:MODE SINGle\n")

    return
end


### Data ###

"""
    saveS2P(socket::TCPSocket, fileURL::String)

Save the measurement as a S2P file `fileUrl` onto the VNA internal harddrive.

Note, that the file is not beeing saved on the VNA and not the device, where
this function is being called.
The file can then be transfered manually.
"""
function saveS2P(socket::Sockets.TCPSocket, fileURL::String)
    send(socket, "MMEMory:STORe "*string(fileURL)*"\n")

    return
end

"""
    getFrequencies(socket::TCPSocket)

Return all the actual sweep points as a `Vector{Float64}`.

The sweep points are the frequencies at which the scattering parameter is
measured during a sweep. They are specified by the number of sweeppoints and the
frequency range.

See also [`setSweepPoints`](@ref), [`setFrequencies`](@ref).
"""
function getFrequencies(socket::Sockets.TCPSocket)
    try
        clearBuffer(socket)

        send(socket,"CALCulate:PARameter:SELect 'CH1_S11_1'\n") # Select the Channel and Measurement Parameter S11
        send(socket,"FORMat:DATA REAL,64\n") # Set the return type to a 64 bit Float
        send(socket,"FORMat:BORDer SWAPPed;*OPC?\n") # Swap the byte order and wait for the completion of the commands
        send(socket,"CALCulate:X:VALues?\n") # Read the frequency points
        # Returns
        # 1 Byte: Block Data Delimiter '#'
        # 1 Byte: n := number of nigits for the Number of data bytes in ASCII (between 1 and 9)
        # n Bytes: N := number of data bytes to read in ASCII
        # N Bytes: data
        # 1 Byte: End of line character 0x0A to indicate the end of the data block

        # Wait for the Block Data Delimiter '#'
        while recv(socket,1)[begin] != 0x23 end

        numofdigitstoread = Int(recv(socket,1))

        numofbytes = Int(recv(socket, numofdigitstoread))

        bytes = recv(socket, numofbytes)

        data = reinterpret(Float64, bytes)

        hanginglinefeed = recv(socket,1)
        if hanginglinefeed[begin] != 0x0A
            error("End of Line Character expected to indicate end of data block")
        end

        send(socket,"FORMat:DATA ASCii,0;*OPC?\n") # Set the return type back to ASCII

        return data
    catch e
        println(e)
        error("Oepsie woepsie, something wrong uwu.")
    end
end

"""
    getSweepTime(socket::TCPSocket)

Returns the time the VNA takes for the sweep.
"""
function getSweepTime(socket::Sockets.TCPSocket)
    clearBuffer(socket)
    send(socket, "SENSe:SWEep:TIME?\n")
    bytes = recv(socket)
    return Float64(bytes)
end

"""
    complexFromTrace(data::Vector{Float64})

Takes the raw `data`` returned by the VNA and returns a `Vector{ComplexF64}`.

The VNA returns a `Vector{Float64}`, where the each complex number is
represented by two successive `Float64`, where the first is the real part and the second
the imaginary.
"""
function complexFromTrace(data::Vector{Float64})
    d = zeros(ComplexF64,div(length(data),2))

    @views d += data[1:2:end]
    @views d += data[2:2:end]*im
end

# function getTrace(socket::Sockets.TCPSocket; waittime=0,set=false)
#     # clearBuffer(socket)

#     if set
#         send(socket, "FORMat:DATA REAL,64\n") # Set the return type to a 64 bit Float
#         send(socket, "FORMat:BORDer SWAPPed;*OPC?\n") # Swap the byte order and wait for the completion of the commands
#         send(socket, "CALCulate1:PARameter:SELect 'CH1_S11_1'\n")
#     end
    
#     send(socket, "SENSe:SWEep:MODE SINGLe;*OPC?\n")
#     send(socket, "CALCulate1:DATA? SDATA\n") # Read the S11 parameter Data
#     # Returns
#     # 1 Byte: Block Data Delimiter '#'
#     # 1 Byte: n := number of nigits for the Number of data bytes in ASCII (between 1 and 9)
#     # n Bytes: N := number of data bytes to read in ASCII
#     # N Bytes: data
#     # 1 Byte: End of line character 0x0A to indicate the end of the data block

#     # Wait for the Block Data Delimiter '#'
#     while recv(socket,1)[begin] != 0x23 end

#     numofdigitstoread = Int(recv(socket,1))

#     numofbytes = Int(recv(socket, numofdigitstoread))

#     bytes = recv(socket, numofbytes)

#     data = reinterpret(Float64, bytes)

#     hanginglinefeed = recv(socket,1)
#     if hanginglinefeed[begin] != 0x0A
#         error("End of Line Character expected to indicate end of data block")
#     end

#     return complexFromTrace(Vector(data))
# end

import Core: Int, Float64

Core.Int(data::Array{UInt8}) = parse(Int, String(data))
Core.Float64(data::Array{UInt8}) = parse(Float64, String(data))


"""
    getTrace(socket::TCPSocket)

Performs a sweep and returns a `Vector{ComplexF64}` of the scattering parameter.

Each element corresponds the the scattering parameter at the frequency given by
the element of [`getFrequencies`](@ref) with the same index.
"""
function getTrace(socket::Sockets.TCPSocket)
    clearBuffer(socket)

    send(socket, "FORMat:DATA REAL,64\n") # Set the return type to a 64 bit Float
    send(socket, "FORMat:BORDer SWAPPed;*OPC?\n") # Swap the byte order and wait for the completion of the commands
    send(socket, "CALCulate1:PARameter:SELect 'CH1_S11_1'\n")
    send(socket, "SENSe:SWEep:MODE SINGLe;*OPC?\n")
    send(socket, "CALCulate1:DATA? SDATA\n") # Read the S11 parameter Data
    # Returns
    # 1 Byte: Block Data Delimiter '#'
    # 1 Byte: n := number of nigits for the Number of data bytes in ASCII (between 1 and 9)
    # n Bytes: N := number of data bytes to read in ASCII
    # N Bytes: data
    # 1 Byte: End of line character 0x0A to indicate the end of the data block

    # Wait for the Block Data Delimiter '#'
    while recv(socket,1)[begin] != 0x23 end

    numofdigitstoread = Int(recv(socket,1))

    numofbytes = Int(recv(socket, numofdigitstoread))

    bytes = recv(socket, numofbytes)

    data = reinterpret(Float64, bytes)

    hanginglinefeed = recv(socket,1)
    if hanginglinefeed[begin] != 0x0A
        error("End of Line Character expected to indicate end of data block")
    end

    return complexFromTrace(Vector(data))
end

"""
    storeTraceInMemory(socket::TCPSocket, mnum::Integer)

Perform a sweep and store the trace in the memory of the VNA.

`mnum` must be a unique integer. It is used to store and identify
multiple traces at the same time.
If a trace with the same `mnum` already exists, the VNA will throw an error and
the trace is not stored.
Existing traces can only be overridden if the it is deleted first.
The trace is stored as a measurement called `"data_<mnum>"` on the VNA.
The prefix `"data_"` is used to distinguish the stored traces from any other
created by the VNA itself.

See also [`deleteTrace`](@ref), [`deleteAllTraces`](@ref) and [`getTraceFromMemory`](@ref).
"""
function storeTraceInMemory(socket::Sockets.TCPSocket, mnum::Integer)
    send(socket, "CALCulate1:PARameter:DEFine:EXTended 'data_"*string(mnum)*"','S11'\n")
    send(socket, "CALCulate1:PARameter:SELect 'data_"*string(mnum)*"'\n")
    send(socket, "SENSe:SWEep:MODE SINGLe;*OPC?\n")  # Set the trigger to Single and wait for completion
    send(socket, "CALCulate1:MATH:MEMorize;*OPC?\n")
end

"""
    getTraceFromMemory(socket::TCPSocket, mnum::Integer; delete=true)

Returns the trace stored in the memory specified by `mnum`.

See also [`getTrace`](@ref), [`deleteTrace`](@ref) and [`deleteAllTraces`](@ref).
"""
function getTraceFromMemory(socket::Sockets.TCPSocket, mnum::Integer; delete=true)
    clearBuffer(vna)

    send(socket, "FORMat:DATA REAL,64\n") # Set the return type to a 64 bit Float
    send(socket, "FORMat:BORDer SWAPPed;*OPC?\n") # Swap the byte order and wait for the completion of the commands
    send(socket, "CALCulate1:PARameter:SELect 'data_"*string(mnum)*"'\n")
    send(socket, "CALCulate1:DATA? SMEM\n") # Read the S11 parameter Data
    # Returns
    # 1 Byte: Block Data Delimiter '#'
    # 1 Byte: n := number of nigits for the Number of data bytes in ASCII (between 1 and 9)
    # n Bytes: N := number of data bytes to read in ASCII
    # N Bytes: data
    # 1 Byte: End of line character 0x0A to indicate the end of the data block

    # Wait for the Block Data Delimiter '#'
    while recv(socket,1)[begin] != 0x23 end

    numofdigitstoread = Int(recv(socket,1))

    numofbytes = Int(recv(socket, numofdigitstoread))

    bytes = recv(socket, numofbytes)

    data = reinterpret(Float64, bytes)

    hanginglinefeed = recv(socket,1)
    if hanginglinefeed[begin] != 0x0A
        error("End of Line Character expected to indicate end of data block")
    end

    if delete send(socket,"CALCulate:PARameter:DELete 'data_"*string(mnum)*"'\n") end

    return complexFromTrace(Vector(data))
end

"""
    getTraceCatalog(socket::TCPSocket)

Returns a list as a `String`, with all traces stored in the VNA.
Not only those, that are created by [`storeTraceInMemory`](@ref).
"""
function getTraceCatalog(socket::Sockets.TCPSocket)
    send(socket,"CALCulate:PARameter:CATalog?\n")
    data = recv(vna)
    return String(data)
end

"""
    deleteTrace(socket::TCPSocket, mnum::Integer)

Delete the trace with the identifier `mnum`.
"""
function deleteTrace(socket::Sockets.TCPSocket, mnum::Integer)
    send(socket,"CALCulate:PARameter:DELete 'data_"*string(mnum)*"'\n")
end

"""
    deleteAllTraces(socket::TCPSocket)

Delete all traces, which were created by [`storeTraceInMemory`](@ref).
"""
function deleteAllTraces(socket::Sockets.TCPSocket)
    send(socket,"CALCulate:PARameter:CATalog?\n")
    data = recv(vna)
    catalog = split(String(data), ',')
    
    pattern = r"data_\d+"
    
    for s in catalog
        m = match(pattern, s)
        if m !== nothing
            send(socket,"CALCulate:PARameter:DELete '"*m.match*"'\n")
        end
    end

    return
end


# function getTrace(socket::Sockets.TCPSocket,n::Int64; waittime=0,set=false,nfreqs=128)
#     ref = zeros(ComplexF64,nfreqs)

#     if n == 1
#         return getTrace(socket; waittime=waittime,set=set)
#     end
    
#     if set
#         clearBuffer(vna)

#         send(socket, "FORMat:DATA REAL,64\n") # Set the return type to a 64 bit Float
#         send(socket, "FORMat:BORDer SWAPPed;*OPC?\n") # Swap the byte order and wait for the completion of the commands
#         send(socket, "CALCulate1:PARameter:SELect 'CH1_S11_1'\n")
#     end

#     for i in 1:n
#         clearBuffer(vna)

#         send(socket, "SENSe:SWEep:MODE SINGLe;*OPC?\n")
#         send(socket, "CALC:DATA? SDATA\n") 

#         while recv(socket,1)[begin] != 0x23 end

#         numofdigitstoread = Int(recv(socket,1))
#         numofbytes = Int(recv(socket, numofdigitstoread))
#         bytes = recv(socket, numofbytes)
#         data = reinterpret(Float64, bytes)
#         hanginglinefeed = recv(socket,1)
        
#         if hanginglinefeed[begin] != 0x0A
#             error("End of Line Character expected to indicate end of data block")
#         end

#         if i == n
#             return ref/n
#         else
#             ref += complexFromTrace(Vector(data))
#         end
#     end
# end


# function getTraceM(socket::Sockets.TCPSocket; waittime=0,set=false)
#     clearBuffer(vna)

#     if set
#         send(socket, "FORMat:DATA REAL,64\n") # Set the return type to a 64 bit Float
#         send(socket, "FORMat:BORDer SWAPPed;*OPC?\n") # Swap the byte order and wait for the completion of the commands
#         send(socket, "CALCulate1:PARameter:SELect 'CH1_S11_1'\n")
#     end

#     send(socket, "SENSe:SWEep:MODE SINGLe;*OPC?\n")
#     send(socket, "CALC:DATA? FDATA\n") 

#     while recv(socket,1)[begin] != 0x23 end

#     numofdigitstoread = Int(recv(socket,1))
#     numofbytes = Int(recv(socket, numofdigitstoread))
#     bytes = recv(socket, numofbytes)
#     data = reinterpret(Float64, bytes)
#     hanginglinefeed = recv(socket,1)

#     if hanginglinefeed[begin] != 0x0A
#         error("End of Line Character expected to indicate end of data block")
#     end

#     return complexFromTrace(Vector(data))
# end

# function getTraceM(socket::Sockets.TCPSocket,n::Int64; waittime=0,set=false,nfreqs=128)
#     ref = zeros(ComplexF64,div(nfreqs,2))

#     if n == 1
#         return getTraceM(socket; waittime=waittime,set=set)
#     end
    
#     if set
#         clearBuffer(vna)

#         send(socket, "FORMat:DATA REAL,64\n") # Set the return type to a 64 bit Float
#         send(socket, "FORMat:BORDer SWAPPed;*OPC?\n") # Swap the byte order and wait for the completion of the commands
#         send(socket, "CALCulate1:PARameter:SELect 'CH1_S11_1'\n")
#     end

#     for i in 1:n
#         clearBuffer(vna)

#         send(socket, "SENSe:SWEep:MODE SINGLe;*OPC?\n")
#         send(socket, "CALC:DATA? FDATA\n") 

#         while recv(socket,1)[begin] != 0x23 end

#         numofdigitstoread = Int(recv(socket,1))
#         numofbytes = Int(recv(socket, numofdigitstoread))
#         bytes = recv(socket, numofbytes)
#         data = reinterpret(Float64, bytes)
#         hanginglinefeed = recv(socket,1)
        
#         if hanginglinefeed[begin] != 0x0A
#             error("End of Line Character expected to indicate end of data block")
#         end

#         if i == n
#             return ref/n
#         else
#             ref += complexFromTrace(Vector(data))
#         end
#     end
# end

# # function getTraceG(socket::Sockets.TCPSocket,n::Int64; waittime=0,set::Bool=false)
# function getTraceG(socket::Sockets.TCPSocket; waittime=0)
#     clearBuffer(vna)
    
#     send(socket, "CALCulate1:PARameter:SELect 'CH1_S11_1'\n")
#     send(socket, "SENSe:SWEep:MODE GROups;*OPC?\n")
#     send(socket, "CALCulate1:DATA? SDATA\n")

#     sleep(waittime)
    
#     while recv(socket,1)[begin] != 0x23 end

#     numofdigitstoread = Int(recv(socket,1))

#     numofbytes = Int(recv(socket, numofdigitstoread))

#     bytes = recv(socket, numofbytes)

#     data = reinterpret(Float64, bytes)

#     hanginglinefeed = recv(socket,1)
#     if hanginglinefeed[begin] != 0x0A
#         error("End of Line Character expected to indicate end of data block")
#     end

#     return complexFromTrace(Vector(data))
# end

# combined functions for convenience

function instrumentErrCheck(socket::Sockets.TCPSocket)
    try
        erroutclear = false
        noerrresult = codeunits("NO ERROR")

        i = 0

        while !erroutclear
            i += 1

            send(socket, "SYST:ERR?\n")

            errqueryresults = take!(socket)

            print("Error query results = "*string(Char.(errqueryresults)...))

            erroutclear = occursin(noerrresult,uppercase(errqueryresults))

            if i == 100
                println("Error check timeout.")
                break
            end
        end
    catch e
        println("Send failed.")
        close(socket)
    end
end

"""
    instrumentSimplifiedSetup(socket::Sockets.TCPSocket; <keyword arguments>)

Change basic settings of the VNA specified by `socket`.
Returns struct `VNAParameters`.

# Keyword Arguments
- `calName::String = cals[:c3GHz]`: Name of the calibration to use
- `power::Int = -20`: Power level (dBm)
- `center::Float64 = 20.025e9`: Center of the frequency band (Hz)
- `span::Float64 = 50e6`: Span of the frequency band (Hz)
- `ifbandwidth::Int = Int(5e6)`: IF Bandwidth (Hz)
- `sweepPoints::Int = 101` Number of sweep points in frequency band
- `fastSweep::Bool = true`: Enable Fast Sweep mode
- `measurement::String = "CH1_S11_1"`: Set which Channel, Parameter and Trace to measure
"""
function instrumentSimplifiedSetup(socket::Sockets.TCPSocket;
        calName::String = cals[:c3GHz],
        power::Int = -20,
        center::Float64 = 20.025e9,
        span::Float64 = 50e6,
        ifbandwidth::Int = Int(5e6),
        sweepPoints::Int = 101,
        fastSweep::Bool = true,
        measurement::String = "CH1_S11_1"
    )

    setCalibration(socket,calName)
    setPowerLevel(socket,power)
    setAveraging(socket,false)
    setFrequencies(socket,center,span)
    setSweepPoints(socket,sweepPoints)
    setIFBandwidth(socket,ifbandwidth)
    setFormat2Log(socket)
    setFastSweep(socket, true)
    sweepTime = getSweepTime(socket)

    return VNAParameters(
        calName,
        power,
        center,
        span,
        ifbandwidth,
        sweepPoints,
        sweepTime,
        fastSweep
    )
end

"""
    VNAParameters

This struct is used to store some important VNA settings and is returned by
[`instrumentSimplifiedSetup`](@ref).

The fields are:
- `calName::String` Calibration label
- `power::Integer` Power level
- `center::Float64` Frequency center
- `span::Float64` Frequency span
- `ifbandwidth::Integer` IF bandwidth
- `sweepPoints::Integer` Sweep points
- `sweepTime::Float64` Sweep time
- `fastSweep::Bool` Fast sweep
"""
struct VNAParameters
    calName::String
    power::Integer
    center::Float64
    span::Float64
    ifbandwidth::Integer
    sweepPoints::Integer
    sweepTime::Float64
    fastSweep::Bool
end

end
