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

    VNAParameters



### Private functions ###
# They are not beeing exported

function send(socket::Sockets.TCPSocket ,msg::String)
    Sockets.write(socket, codeunits(msg))
end

function recv(socket::Sockets.TCPSocket)
    refreshBuffer(socket)

    return readavailable(socket)
end

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


### Connection ###

function connect(; host=nothing, port=5025)
    if isnothing(host)
        error("No IP given")
    end

    try
        socket = Sockets.connect(host,port)

        refreshBuffer(socket)

        return socket

    catch e
        error("Failed to connect to host.\n"*e.msg)

        return nothing
    end
end

function disconnect(socket::Sockets.TCPSocket)
    Sockets.close(socket)

    return
end

function identify(socket::Sockets.TCPSocket)
    send(socket,"*IDN?\n")

    return
end

function clearStatus(socket::Sockets.TCPSocket)
    send(socket,"*CLS\n")

    return
end


### Setup ###

function setPowerLevel(socket::Sockets.TCPSocket,power::Integer)
    if power > 14
        error("Power threshold reached. Must be less than 14 dBm.")
    end

    send(socket, "SOURce:POWer:LEVel:IMMediate:AMPLitude "*string(power)*"\n")

    return
end

function setCalibration(socket::Sockets.TCPSocket,calName::String)
    send(socket, "SENSe:CORRection:CSET:ACTivate \""*string(calName)*"\",1\n")

    return
end

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

function setFrequencies(socket::Sockets.TCPSocket,center::Float64,span::Float64)
    if !(10e6 <= center <= 43.5e9)
        error("Center frequency must be between 10 MHz and 43.5 GHz.")
    elseif !(0 <= span <= min(abs(center-10e6),abs(center-43.5)))
        error("Span reaches out of 10 MHz to 43.5 GHz bandwidth.")
    end

    send(socket, "SENS:FREQ:CENTer "*string(center)*";SPAN "*string(span)*"\n")

    return
end

function setSweepPoints(socket::Sockets.TCPSocket, points::Integer)
    if points <= 0
        error("Must use at least one sweep point.")
    end

    send(socket, "SENSe1:SWEep:POINts "*string(points)*"\n")

    return
end

function setIFBandwidth(socket::Sockets.TCPSocket, bandwidth::Integer)
    if bandwidth <= 0
        error("Resolution must be greater that 0.")
    end

    send(socket, "SENSe1:BANDwidth:RESolution "*string(bandwidth)*"\n")

    return
end

function setMeasurement(socket::Sockets.TCPSocket, name::String)
    send(socket, "CALCulate:PARameter:SELect '"*name*"'\n")

    return
end

function setFormat2Log(socket::Sockets.TCPSocket)
    send(socket, "CALCulate:MEASure:FORMat MLOGarithmic\n")

    return
end

function setFastSweep(socket::Sockets.TCPSocket, fast::Bool)
    if fast
        send(socket,"SENSe:SWEep:SPEed FAST\n")
    else
        send(socket,"SENSe:SWEep:SPEed NORMal\n")
    end

    return
end

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

function triggerContinuous(socket::Sockets.TCPSocket)
    send(socket, "SENse:SWEep:MODE HOLD\n")

    return
end

function triggerHold(socket::Sockets.TCPSocket)
    send(socket, "SENse:SWEep:MODE CONTinuous\n")

    return
end

function triggerSingle(socket::Sockets.TCPSocket)
    send(socket, "SENse:SWEep:MODE SINGle\n")

    return
end


### Data ###

function saveS2P(socket::Sockets.TCPSocket, fileURL::String)
    send(socket, "MMEMory:STORe "*string(fileURL)*"\n")

    return
end

function getFrequencies(socket::Sockets.TCPSocket; waittime=0)
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

        sleep(waittime)

        send(socket,"FORMat:DATA ASCii,0;*OPC?\n") # Set the return type back to ASCII

        return data
    catch e
        println(e)
        error("Oepsie woepsie, something wrong uwu.")
    end
end

function getSweepTime(socket::Sockets.TCPSocket)
    clearBuffer(socket)
    send(socket, "SENSe:SWEep:TIME?\n")
    bytes = recv(socket)
    return Float64(bytes)
end

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

function getTrace(socket::Sockets.TCPSocket; waittime=0)
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

function storeTraceInMemory(socket::Sockets.TCPSocket, mnum::Integer)
    send(socket, "CALCulate1:PARameter:DEFine:EXTended 'data_"*string(mnum)*"','S11'\n")
    send(socket, "CALCulate1:PARameter:SELect 'data_"*string(mnum)*"'\n")
    send(socket, "SENSe:SWEep:MODE SINGLe;*OPC?\n")  # Set the trigger to Single and wait for completion
    send(socket, "CALCulate1:MATH:MEMorize;*OPC?\n")
end

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

function getTraceCatalog(socket::Sockets.TCPSocket)
    send(socket,"CALCulate:PARameter:CATalog?\n")
    data = recv(vna)
    return String(data)
end

function deleteTrace(socket::Sockets.TCPSocket, mnum::Integer)
    send(socket,"CALCulate:PARameter:DELete 'data_"*string(mnum)*"'\n")
end

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

cals = Dict{Symbol,String}(
    :c3GHz => "{AAE0FD65-EEA1-4D1A-95EE-06B3FFCB32B7}",
    :c300MHz => "{AC488992-4AB2-4EB5-9D23-34EF8774902F}",
    :c3GHz_NEW => "{2D2A1B51-D3C2-4613-98CC-884561BE4A57}",
    :c3GHz_9dB => "{483B25B2-6FE9-483E-8A93-0527B8D277E2}"
)

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
