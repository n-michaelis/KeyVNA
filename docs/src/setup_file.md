# Setup file

To make it easier and more reliable to setup the VNA, the settings
can be stored in a `.txt` file.
For now, only a handful of the most basic settings, are implemented.
But it can be extended easily.

For more information on all the settings see the [documentation](https://rfmw.em.keysight.com/wireless/helpfiles/e5080a/programming/gp-ib_command_finder/scpi_command_tree.htm) for the SCPI protocoll provided by Keysight. Note that this is a general SCPI documentation and therefore not every command may be implemented on your specific Device.

The settings can then be loaded using the function [`setupFromFile`](@ref).

## Syntax

Each settings corresponds to a 4 uppercase letter identifier `ID` (eg. `PWLV`). After the identifier comes a `:`, followed by the value `VAL`. Multiple values are also possible by seperating them by another `:` (parsed as an tuple).
Depending on the setting, the value is interpreted as a different type (`String`, `Integer`, etc.).
It is the users responsibility to ensure the correct type is given.

```txt
# A single valued setting
<ID>:<VAL> # another comment

# A double valued setting
<ID>:<VAL1>:<VAL2>
```

Each setting must be on a seperate line.

Everything after a `#` is a comment and ignored by the parser.

## Implemented settings

The following table gives a overview over every settings implemented up to date.

| Setting | ID | Value Type | Unit |
| :--- | :---: | :---: | :---: |
| Powerlevel | `PWLV` | `Integer` | ``dBm`` |
| Frequency Band (Center, Span) | `FREQ` | `Tuple{Float}` | ``Hz`` |
| IF Bandwidth | `IFBW` | `Float` | ``Hz`` |
| Sweeppoints | `SWPP` | `Integer` | |
| Calibration | `CALB` | `String` | |
| Measurement | `MSRM` | `String` | |
| Display Format | `FRMT` | `String` | |
| Averaging | `AVRG` | `Bool` | |

>[!NOTE]
>The calibration string is a label given to each calibration stored on the VNA.


## Example

Below is a simple example of a setup file.

```txt
PWLV:9
FREQ:20.00e9:3e9
SWPP:128
IFBW:100e3
CALB:{483B25B2-6FE9-483E-8A93-0527B8D277E2}
MSRM:CH1_S11_1
```